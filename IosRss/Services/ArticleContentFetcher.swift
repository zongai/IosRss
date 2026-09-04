import Foundation

/// 从文章原文页抓取完整正文（启发式 Readability 风格提取）
/// 参考常见 RSS 阅读器：拉取 HTML → 去噪 → 候选区块打分 → 输出干净 HTML
enum ArticleContentFetcher {

    struct Result {
        let title: String?
        let contentHTML: String
        let textLength: Int
    }

    enum FetchError: LocalizedError {
        case invalidURL
        case network(String)
        case emptyContent
        case tooShort

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的文章链接"
            case .network(let msg): return "网络错误：\(msg)"
            case .emptyContent: return "未能提取到正文内容"
            case .tooShort: return "提取到的正文过短，可能被网站拦截"
            }
        }
    }

    /// 抓取并提取全文；优先 OfflineCache 与 URLCache，失败时尽量回退本地 HTML
    static func fetchFullContent(from urlString: String) async throws -> Result {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw FetchError.invalidURL
        }

        // 1) 应用层磁盘缓存（已提取正文）
        if let cached = OfflineCache.loadArticleHTML(link: urlString), !cached.isEmpty {
            let len = HTMLUtils.stripTags(cached).count
            if len >= 80 {
                return Result(title: nil, contentHTML: cached, textLength: len)
            }
        }

        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        // 先尝试网络，必要时再用缓存
        request.cachePolicy = .returnCacheDataElseLoad

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // 2) 网络失败再读一次本地提取结果
            if let cached = OfflineCache.loadArticleHTML(link: urlString), !cached.isEmpty {
                let len = HTMLUtils.stripTags(cached).count
                return Result(title: nil, contentHTML: cached, textLength: len)
            }
            throw FetchError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let cached = OfflineCache.loadArticleHTML(link: urlString), !cached.isEmpty {
                let len = HTMLUtils.stripTags(cached).count
                return Result(title: nil, contentHTML: cached, textLength: len)
            }
            throw FetchError.network("HTTP \(http.statusCode)")
        }

        let html = decodeHTML(data: data) ?? ""
        guard !html.isEmpty else { throw FetchError.emptyContent }

        let extracted = extractArticle(from: html, baseURL: url)
        let plainLen = HTMLUtils.stripTags(extracted.content).count
        if plainLen < 80 {
            throw FetchError.tooShort
        }
        OfflineCache.saveArticleHTML(link: urlString, html: extracted.content)
        return Result(title: extracted.title, contentHTML: extracted.content, textLength: plainLen)
    }

    // MARK: - Encoding

    private static func decodeHTML(data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        // 尝试从 meta charset 推断（简单处理）
        if let probe = String(data: data.prefix(2048), encoding: .isoLatin1),
           let range = probe.range(of: #"charset=["']?([^"'>\s]+)"#, options: .regularExpression) {
            let matched = String(probe[range])
            if matched.lowercased().contains("gb") {
                // GBK / GB2312
                let cfEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                return String(data: data, encoding: String.Encoding(rawValue: cfEnc))
            }
        }
        return String(data: data, encoding: .windowsCP1252)
    }

    // MARK: - Extraction

    private struct Extracted {
        var title: String?
        var content: String
    }

    private static func extractArticle(from html: String, baseURL: URL) -> Extracted {
        var work = html

        // 1. 去掉 script / style / noscript / svg / iframe 等噪声
        let noiseTags = ["script", "style", "noscript", "svg", "iframe", "object", "embed", "form", "nav", "footer", "header", "aside"]
        for tag in noiseTags {
            work = removeTagBlocks(work, tag: tag)
        }
        // 注释
        work = work.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)

        // 2. 标题
        let title = extractTitle(from: html)

        // 3. 优先尝试语义标签 article / main
        if let semantic = extractBySemanticTags(work) {
            let cleaned = cleanContentHTML(semantic, baseURL: baseURL)
            if HTMLUtils.stripTags(cleaned).count >= 120 {
                return Extracted(title: title, content: cleaned)
            }
        }

        // 4. 基于 class/id 启发式找正文容器
        if let candidate = extractByHeuristics(work) {
            let cleaned = cleanContentHTML(candidate, baseURL: baseURL)
            if HTMLUtils.stripTags(cleaned).count >= 80 {
                return Extracted(title: title, content: cleaned)
            }
        }

        // 5. 回退：收集所有 <p> 拼成正文
        let paragraphs = collectParagraphs(work)
        if !paragraphs.isEmpty {
            let joined = paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n")
            return Extracted(title: title, content: cleanContentHTML(joined, baseURL: baseURL))
        }

        // 最后回退：整页去标签后的文本
        let plain = HTMLUtils.stripTags(work)
        return Extracted(title: title, content: "<p>\(plain.prefix(8000))</p>")
    }

    private static func extractTitle(from html: String) -> String? {
        // og:title
        if let og = matchFirst(#"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#, in: html)
            ?? matchFirst(#"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']"#, in: html) {
            return HTMLUtils.decodeEntities(og).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let t = matchFirst(#"<title[^>]*>([\s\S]*?)</title>"#, in: html) {
            return HTMLUtils.decodeEntities(t).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let h1 = matchFirst(#"<h1[^>]*>([\s\S]*?)</h1>"#, in: html) {
            return HTMLUtils.stripTags(h1).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func extractBySemanticTags(_ html: String) -> String? {
        for tag in ["article", "main"] {
            if let block = extractInnermostBlock(html, tag: tag) {
                let textLen = HTMLUtils.stripTags(block).count
                if textLen >= 120 { return block }
            }
        }
        // role="main"
        if let roleMain = matchFirst(#"<[^>]+role=["']main["'][^>]*>([\s\S]*?)</[^>]+>"#, in: html) {
            let textLen = HTMLUtils.stripTags(roleMain).count
            if textLen >= 120 { return roleMain }
        }
        return nil
    }

    private static func extractByHeuristics(_ html: String) -> String? {
        // 找带 content / post / article / entry / story 等 class/id 的 div/section
        let pattern = #"<(div|section|td)[^>]*(?:class|id)=["'][^"']*(?:article|post|content|entry|story|body|main|text|rich)[^"']*["'][^>]*>([\s\S]*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        var best: (score: Double, html: String)?
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let range = Range(match.range(at: 2), in: html) else { continue }
            let block = String(html[range])
            let score = scoreBlock(block)
            if score > (best?.score ?? 0) {
                best = (score, block)
            }
        }
        return best?.html
    }

    /// 给候选区块打分：段落数、逗号、文本长度、链接密度惩罚
    private static func scoreBlock(_ html: String) -> Double {
        let text = HTMLUtils.stripTags(html)
        let len = Double(text.count)
        guard len > 50 else { return 0 }

        let pCount = countMatches(#"<p[\s>]"#, in: html)
        let commaCount = text.filter { $0 == "," || $0 == "，" }.count
        let linkTextLen = extractLinkTextLength(html)
        let linkDensity = len > 0 ? Double(linkTextLen) / len : 1

        var score = len * 0.01
        score += Double(pCount) * 3
        score += Double(commaCount) * 0.5
        // 链接过多视为导航/侧边栏
        if linkDensity > 0.35 { score *= 0.3 }
        else if linkDensity > 0.2 { score *= 0.6 }

        // 负面 class 关键词
        let lower = html.lowercased()
        for bad in ["comment", "share", "related", "recommend", "sidebar", "footer", "nav", "advert", "promo"] {
            if lower.contains(bad) { score *= 0.5 }
        }
        return score
    }

    private static func extractLinkTextLength(_ html: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"<a[^>]*>([\s\S]*?)</a>"#, options: .caseInsensitive) else { return 0 }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var total = 0
        for m in matches {
            if m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: html) {
                total += HTMLUtils.stripTags(String(html[r])).count
            }
        }
        return total
    }

    private static func collectParagraphs(_ html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<p[^>]*>([\s\S]*?)</p>"#, options: .caseInsensitive) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var result: [String] = []
        for m in matches {
            if m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: html) {
                let text = HTMLUtils.stripTags(String(html[r])).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count >= 40 {
                    result.append(HTMLUtils.decodeEntities(text))
                }
            }
        }
        // 取最长的连续段落组（避免页脚碎段落）
        return result
    }

    // MARK: - HTML helpers

    private static func removeTagBlocks(_ html: String, tag: String) -> String {
        var result = html
        // 成对标签
        let pair = #"<\#(tag)\b[^>]*>[\s\S]*?</\#(tag)>"#
        result = result.replacingOccurrences(of: pair, with: "", options: [.regularExpression, .caseInsensitive])
        // 自闭合
        let selfClosing = #"<\#(tag)\b[^>]*/?>"#
        result = result.replacingOccurrences(of: selfClosing, with: "", options: [.regularExpression, .caseInsensitive])
        return result
    }

    private static func extractInnermostBlock(_ html: String, tag: String) -> String? {
        // 取内容最长的匹配
        let pattern = #"<\#(tag)\b[^>]*>([\s\S]*?)</\#(tag)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var best: String?
        var bestLen = 0
        for m in matches {
            if m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: html) {
                let block = String(html[r])
                let len = HTMLUtils.stripTags(block).count
                if len > bestLen {
                    bestLen = len
                    best = block
                }
            }
        }
        return best
    }

    private static func cleanContentHTML(_ html: String, baseURL: URL) -> String {
        var work = html

        // 去掉剩余危险/无用标签，保留结构
        for tag in ["script", "style", "noscript", "iframe", "button", "input", "select", "textarea"] {
            work = removeTagBlocks(work, tag: tag)
        }

        // 相对图片地址转绝对
        work = absolutizeAttributes(work, attr: "src", baseURL: baseURL)
        work = absolutizeAttributes(work, attr: "href", baseURL: baseURL)

        // 常见懒加载：data-src -> src
        work = work.replacingOccurrences(
            of: #"<(img[^>]+)data-src=["']([^"']+)["']"#,
            with: #"<$1src="$2""#,
            options: .regularExpression
        )
        work = work.replacingOccurrences(
            of: #"<(img[^>]+)data-original=["']([^"']+)["']"#,
            with: #"<$1src="$2""#,
            options: .regularExpression
        )

        // 解码实体
        work = HTMLUtils.decodeEntities(work)

        // 压缩多余空白
        work = work.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return work.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func absolutizeAttributes(_ html: String, attr: String, baseURL: URL) -> String {
        let pattern = #"(\#(attr)=["'])([^"']+)(["'])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return html }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed()
        var result = html
        for m in matches {
            guard m.numberOfRanges >= 4,
                  let valRange = Range(m.range(at: 2), in: result),
                  let fullRange = Range(m.range, in: result) else { continue }
            let value = String(result[valRange])
            if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("data:") || value.hasPrefix("#") {
                continue
            }
            if let absolute = URL(string: value, relativeTo: baseURL)?.absoluteString {
                let prefix = String(result[Range(m.range(at: 1), in: result)!])
                let suffix = String(result[Range(m.range(at: 3), in: result)!])
                result.replaceSubrange(fullRange, with: "\(prefix)\(absolute)\(suffix)")
            }
        }
        return result
    }

    private static func matchFirst(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func countMatches(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
}
