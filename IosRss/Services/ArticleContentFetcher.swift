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

    static func fetchFullContent(from urlString: String) async throws -> Result {
        guard let url = NetworkURLPolicy.validate(urlString) else {
            throw FetchError.invalidURL
        }

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
        request.cachePolicy = .returnCacheDataElseLoad

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
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

        var extracted = extractArticle(from: html, baseURL: url)
        var plainLen = HTMLUtils.stripTags(extracted.content).count

        // HTML 启发式过短时，尝试 WordPress REST API（量子位等 WP 站点）
        if plainLen < 400, let wp = await fetchWordPressContent(pageURL: url, pageHTML: html) {
            let wpLen = HTMLUtils.stripTags(wp.content).count
            if wpLen > plainLen {
                extracted = wp
                plainLen = wpLen
            }
        }

        if plainLen < 80 {
            throw FetchError.tooShort
        }
        OfflineCache.saveArticleHTML(link: urlString, html: extracted.content)
        return Result(title: extracted.title, contentHTML: extracted.content, textLength: plainLen)
    }

    // MARK: - WordPress REST fallback

    private static func fetchWordPressContent(pageURL: URL, pageHTML: String) async -> Extracted? {
        var apiURL: URL?
        if let link = matchFirst(#"<link[^>]+type=[\"']application/json[\"'][^>]+href=[\"']([^\"']+)[\"']"#, in: pageHTML)
            ?? matchFirst(#"<link[^>]+href=[\"']([^\"']+)[\"'][^>]+type=[\"']application/json[\"']"#, in: pageHTML) {
            apiURL = URL(string: link)
        }
        if apiURL == nil, let id = matchFirst(#"/wp-json/wp/v2/posts/(\d+)"#, in: pageHTML) {
            if var comps = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
                comps.path = "/wp-json/wp/v2/posts/\(id)"
                comps.query = nil
                comps.fragment = nil
                apiURL = comps.url
            }
        }
        if apiURL == nil {
            let postID = matchFirst(#"[?&]p=(\d+)"#, in: pageURL.absoluteString)
                ?? matchFirst(#"/\d{4}/\d{2}/(\d+)\.html"#, in: pageURL.absoluteString)
            if let postID, var comps = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
                comps.path = "/wp-json/wp/v2/posts/\(postID)"
                comps.query = nil
                comps.fragment = nil
                apiURL = comps.url
            }
        }
        guard let apiURL else { return nil }

        var request = URLRequest(url: apiURL, timeoutInterval: 15)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let contentHTML: String? = {
                if let content = obj["content"] as? [String: Any],
                   let rendered = content["rendered"] as? String { return rendered }
                return nil
            }()
            let title: String? = {
                if let t = obj["title"] as? [String: Any], let rendered = t["rendered"] as? String {
                    return HTMLUtils.stripTags(rendered).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return nil
            }()
            guard let contentHTML, !contentHTML.isEmpty else { return nil }
            let cleaned = cleanContentHTML(contentHTML, baseURL: pageURL)
            let len = HTMLUtils.stripTags(cleaned).count
            guard len >= 120 else { return nil }
            return Extracted(title: title, content: cleaned)
        } catch {
            return nil
        }
    }

    // MARK: - Encoding

    private static func decodeHTML(data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        if let probe = String(data: data.prefix(2048), encoding: .isoLatin1),
           let range = probe.range(of: #"charset=[\"']?([^\"'>\s]+)"#, options: .regularExpression) {
            let matched = String(probe[range])
            if matched.lowercased().contains("gb") {
                let cfEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                return String(data: data, encoding: String.Encoding(rawValue: cfEnc))
            }
        }
        return String(data: data, encoding: .windowsCP1252)
    }

    private struct Extracted {
        var title: String?
        var content: String
    }

    private static func extractArticle(from html: String, baseURL: URL) -> Extracted {
        var work = html
        let noiseTags = ["script", "style", "noscript", "svg", "iframe", "object", "embed", "form", "nav", "footer", "header", "aside"]
        for tag in noiseTags {
            work = removeTagBlocks(work, tag: tag)
        }
        work = work.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)

        let title = extractTitle(from: html)

        // 站点特化：在通用语义标签之前尝试（避免 <article> 只匹配到订阅墙短文）
        if let site = extractByKnownSite(work, host: baseURL.host?.lowercased() ?? "") {
            let cleaned = cleanContentHTML(site, baseURL: baseURL)
            if HTMLUtils.stripTags(cleaned).count >= 200 {
                return Extracted(title: title, content: cleaned)
            }
        }

        if let semantic = extractBySemanticTags(work) {
            let cleaned = cleanContentHTML(semantic, baseURL: baseURL)
            // 语义块若明显短于全文启发式，继续往下试
            let semLen = HTMLUtils.stripTags(cleaned).count
            if semLen >= 800 {
                return Extracted(title: title, content: cleaned)
            }
            if let candidate = extractByHeuristics(work) {
                let cand = cleanContentHTML(candidate, baseURL: baseURL)
                if HTMLUtils.stripTags(cand).count > semLen + 200 {
                    return Extracted(title: title, content: cand)
                }
            }
            if semLen >= 120 {
                return Extracted(title: title, content: cleaned)
            }
        }

        if let candidate = extractByHeuristics(work) {
            let cleaned = cleanContentHTML(candidate, baseURL: baseURL)
            if HTMLUtils.stripTags(cleaned).count >= 80 {
                return Extracted(title: title, content: cleaned)
            }
        }

        let paragraphs = collectParagraphs(work)
        if !paragraphs.isEmpty {
            let joined = paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n")
            return Extracted(title: title, content: cleanContentHTML(joined, baseURL: baseURL))
        }

        let plain = HTMLUtils.stripTags(work)
        return Extracted(title: title, content: "<p>\(plain.prefix(8000))</p>")
    }

    private static func extractTitle(from html: String) -> String? {
        if let og = matchFirst(#"<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']"#, in: html)
            ?? matchFirst(#"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:title[\"']"#, in: html) {
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

    /// 已知站点正文容器（Foreign Affairs 等）
    private static func extractByKnownSite(_ html: String, host: String) -> String? {
        let selectors: [String]
        if host == "foreignaffairs.com" || host.hasSuffix(".foreignaffairs.com") {
            selectors = [
                "article__body-content",
                "article-dropcap--inner",
                "paywall-content",
                "rich-text__inner",
                "article__body"
            ]
        } else {
            selectors = []
        }
        var best: String?
        var bestLen = 0
        for token in selectors {
            let escaped = NSRegularExpression.escapedPattern(for: token)
            let pattern = "<(div|section)([^>]*class=[\"'][^\"']*" + escaped + "[^\"']*[\"'][^>]*)>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges >= 2,
                      let tagRange = Range(match.range(at: 1), in: html),
                      let fullOpen = Range(match.range, in: html) else { continue }
                let tag = String(html[tagRange])
                guard let block = extractBalancedFromOpen(html, openEnd: fullOpen.upperBound, tag: tag) else { continue }
                let len = HTMLUtils.stripTags(block).count
                if len > bestLen {
                    bestLen = len
                    best = block
                }
            }
        }
        return bestLen >= 200 ? best : nil
    }

    private static func extractBySemanticTags(_ html: String) -> String? {

        for tag in ["article", "main"] {
            if let block = extractBalancedTagContent(html, tag: tag) {
                let textLen = HTMLUtils.stripTags(block).count
                if textLen >= 120 { return block }
            }
        }
        if let open = firstMatchRange(#"<([a-zA-Z0-9]+)[^>]*role=[\"']main[\"'][^>]*>"#, in: html),
           let tagName = matchFirst(#"<([a-zA-Z0-9]+)[^>]*role=[\"']main[\"']"#, in: html),
           let block = extractBalancedFromOpen(html, openEnd: open.upperBound, tag: tagName) {
            let textLen = HTMLUtils.stripTags(block).count
            if textLen >= 120 { return block }
        }
        return nil
    }

    private static func extractByHeuristics(_ html: String) -> String? {
        // 平衡标签匹配，避免嵌套 div 被非贪婪正则截断（量子位等站点）
        let openPattern = #"<(div|section|td|article)([^>]*(?:class|id)=[\"'][^\"']*(?:article|post|content|entry|story|body|main|text|rich|detail|dropcap|paywall)[^\"']*[\"'][^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: openPattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        var best: (score: Double, html: String)?
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let tagRange = Range(match.range(at: 1), in: html),
                  let fullOpen = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let openAttrs = Range(match.range(at: 2), in: html).map { String(html[$0]) } ?? ""
            let openLower = openAttrs.lowercased()

            let skipTokens = ["text_box", "picture_text", "sidebar", "related", "recommend",
                              "comment", "share_box", "share_pc", "nav_", "menu", "footer",
                              "breadcrumb", "pagination", "hot-list", "hot_list"]
            if skipTokens.contains(where: { openLower.contains($0) }) { continue }

            guard let block = extractBalancedFromOpen(html, openEnd: fullOpen.upperBound, tag: tag) else { continue }
            let score = scoreBlock(block, openAttrs: openAttrs)
            if score > (best?.score ?? 0) {
                best = (score, block)
            }
        }
        if let best, HTMLUtils.stripTags(best.html).count >= 200 {
            return best.html
        }
        return best.map { HTMLUtils.stripTags($0.html).count >= 120 ? $0.html : nil } ?? nil
    }

    private static func scoreBlock(_ html: String, openAttrs: String = "") -> Double {
        let text = HTMLUtils.stripTags(html)
        let len = Double(text.count)
        guard len > 50 else { return 0 }

        let pCount = countMatches(#"<p[\s>]"#, in: html)
        let commaCount = text.filter { $0 == "," || $0 == "，" }.count
        let linkTextLen = extractLinkTextLength(html)
        let linkDensity = len > 0 ? Double(linkTextLen) / len : 1

        var score = len * 0.01
        score += Double(pCount) * 4
        score += Double(commaCount) * 0.5
        if linkDensity > 0.35 { score *= 0.25 }
        else if linkDensity > 0.2 { score *= 0.55 }

        let lower = (html + " " + openAttrs).lowercased()
        for bad in ["comment", "share", "related", "recommend", "sidebar", "footer", "nav", "advert", "promo", "text_box", "picture_text"] {
            if lower.contains(bad) { score *= 0.4 }
        }
        for good in ["entry-content", "post-content", "article-content", "article_content",
                     "post_content", "single-content", "rich-content", "article-body", "post-body",
                     "article__body", "body-content", "paywall-content", "rich-text", "dropcap"] {
            if openAttrs.lowercased().contains(good) { score *= 2.5; break }
        }
        if openAttrs.lowercased().contains("class=\"article\"")
            || openAttrs.lowercased().contains("class='article'")
            || openAttrs.lowercased().contains(" article ") {
            score *= 1.8
        }
        if len < 400 { score *= 0.5 }
        if len < 200 { score *= 0.4 }
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
        return result
    }

    private static func removeTagBlocks(_ html: String, tag: String) -> String {
        var result = html
        let pair = "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>"
        result = result.replacingOccurrences(of: pair, with: "", options: [.regularExpression, .caseInsensitive])
        let selfClosing = "<\(tag)\\b[^>]*/?>"
        result = result.replacingOccurrences(of: selfClosing, with: "", options: [.regularExpression, .caseInsensitive])
        return result
    }

    private static func extractBalancedTagContent(_ html: String, tag: String) -> String? {
        let openPattern = "<\(tag)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: openPattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        let opens = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var best: String?
        var bestLen = 0
        for open in opens {
            guard let openRange = Range(open.range, in: html) else { continue }
            if let block = extractBalancedFromOpen(html, openEnd: openRange.upperBound, tag: tag) {
                let len = HTMLUtils.stripTags(block).count
                if len > bestLen {
                    bestLen = len
                    best = block
                }
            }
        }
        return best
    }

    private static func extractBalancedFromOpen(_ html: String, openEnd: String.Index, tag: String) -> String? {
        var depth = 1
        let search = String(html[openEnd...])
        let pattern = "<(/?)\(tag)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = search as NSString
        let matches = regex.matches(in: search, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard let full = Range(m.range, in: search),
                  let slashRange = Range(m.range(at: 1), in: search) else { continue }
            let isClose = !search[slashRange].isEmpty
            let token = String(search[full])
            if token.hasSuffix("/>") { continue }
            if isClose {
                depth -= 1
                if depth == 0 {
                    let innerEnd = search.index(search.startIndex, offsetBy: m.range.location)
                    return String(search[search.startIndex..<innerEnd])
                }
            } else {
                depth += 1
            }
        }
        return nil
    }

    private static func firstMatchRange(_ pattern: String, in text: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Range(m.range, in: text)
    }

    private static func cleanContentHTML(_ html: String, baseURL: URL) -> String {
        var work = html
        for tag in ["script", "style", "noscript", "iframe", "button", "input", "select", "textarea"] {
            work = removeTagBlocks(work, tag: tag)
        }
        work = absolutizeAttributes(work, attr: "src", baseURL: baseURL)
        work = absolutizeAttributes(work, attr: "href", baseURL: baseURL)
        work = work.replacingOccurrences(
            of: #"<(img[^>]+)data-src=[\"']([^\"']+)[\"']"#,
            with: #"<$1src=\"$2\""#,
            options: .regularExpression
        )
        work = work.replacingOccurrences(
            of: #"<(img[^>]+)data-original=[\"']([^\"']+)[\"']"#,
            with: #"<$1src=\"$2\""#,
            options: .regularExpression
        )
        work = HTMLUtils.decodeEntities(work)
        work = work.replacingOccurrences(of: #"\n{3,}"# , with: "\n\n", options: .regularExpression)
        return work.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func absolutizeAttributes(_ html: String, attr: String, baseURL: URL) -> String {
        let realPat = "(" + attr + "=[\"'])([^\"']+)([\"'])"
        guard let regex = try? NSRegularExpression(pattern: realPat, options: .caseInsensitive) else { return html }
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
