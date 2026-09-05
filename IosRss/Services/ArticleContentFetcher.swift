import Foundation

enum ArticleContentFetcher {
    struct Result {
        let title: String?
        let contentHTML: String
        let textLength: Int
    }
    enum FetchError: LocalizedError {
        case invalidURL, network(String), emptyContent, tooShort
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
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { throw FetchError.invalidURL }
        if let cached = OfflineCache.loadArticleHTML(link: urlString), !cached.isEmpty {
            let len = HTMLUtils.stripTags(cached).count
            if len >= 80 { return Result(title: nil, contentHTML: cached, textLength: len) }
        }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.cachePolicy = .returnCacheDataElseLoad
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch {
            if let cached = OfflineCache.loadArticleHTML(link: urlString), !cached.isEmpty {
                return Result(title: nil, contentHTML: cached, textLength: HTMLUtils.stripTags(cached).count)
            }
            throw FetchError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let cached = OfflineCache.loadArticleHTML(link: urlString), !cached.isEmpty {
                return Result(title: nil, contentHTML: cached, textLength: HTMLUtils.stripTags(cached).count)
            }
            throw FetchError.network("HTTP \(http.statusCode)")
        }
        let html = decodeHTML(data: data) ?? ""
        guard !html.isEmpty else { throw FetchError.emptyContent }
        let extracted = extractArticle(from: html, baseURL: url)
        let plainLen = HTMLUtils.stripTags(extracted.content).count
        if plainLen < 80 { throw FetchError.tooShort }
        OfflineCache.saveArticleHTML(link: urlString, html: extracted.content)
        return Result(title: extracted.title, contentHTML: extracted.content, textLength: plainLen)
    }
    private static func decodeHTML(data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return String(data: data, encoding: .windowsCP1252)
    }
    private struct Extracted { var title: String?; var content: String }
    private static func extractArticle(from html: String, baseURL: URL) -> Extracted {
        var work = html
        for tag in ["script", "style", "noscript", "svg", "iframe", "object", "embed", "form", "nav", "footer", "header", "aside"] {
            work = removeTagBlocks(work, tag: tag)
        }
        work = work.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        let title = extractTitle(from: html)
        if let semantic = extractBySemanticTags(work) {
            let cleaned = cleanContentHTML(semantic, baseURL: baseURL)
            if HTMLUtils.stripTags(cleaned).count >= 120 { return Extracted(title: title, content: cleaned) }
        }
        if let candidate = extractByHeuristics(work) {
            let cleaned = cleanContentHTML(candidate, baseURL: baseURL)
            if HTMLUtils.stripTags(cleaned).count >= 80 { return Extracted(title: title, content: cleaned) }
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
        if let og = matchFirst("<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']", in: html)
            ?? matchFirst("<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:title[\"']", in: html) {
            return HTMLUtils.decodeEntities(og).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let t = matchFirst("<title[^>]*>([\\s\\S]*?)</title>", in: html) {
            return HTMLUtils.decodeEntities(t).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let h1 = matchFirst("<h1[^>]*>([\\s\\S]*?)</h1>", in: html) {
            return HTMLUtils.stripTags(h1).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    private static func extractBySemanticTags(_ html: String) -> String? {
        for tag in ["article", "main"] {
            if let block = extractInnermostBlock(html, tag: tag),
               HTMLUtils.stripTags(block).count >= 120 { return block }
        }
        return nil
    }
    private static func extractByHeuristics(_ html: String) -> String? {
        let pattern = "<(div|section|td)[^>]*(?:class|id)=[\"'][^\"']*(?:article|post|content|entry|story|body|main|text|rich)[^\"']*[\"'][^>]*>([\\s\\S]*?)</\\1>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: (html as NSString).length))
        var best: (score: Double, html: String)?
        for match in matches {
            guard match.numberOfRanges >= 3, let range = Range(match.range(at: 2), in: html) else { continue }
            let block = String(html[range])
            let score = scoreBlock(block)
            if score > (best?.score ?? 0) { best = (score, block) }
        }
        return best?.html
    }
    private static func scoreBlock(_ html: String) -> Double {
        let text = HTMLUtils.stripTags(html)
        let len = Double(text.count)
        guard len > 50 else { return 0 }
        let pCount = countMatches("<p[\\s>]", in: html)
        var score = len * 0.01 + Double(pCount) * 3
        let lower = html.lowercased()
        for bad in ["comment", "share", "related", "sidebar", "footer", "nav", "advert"] {
            if lower.contains(bad) { score *= 0.5 }
        }
        return score
    }
    private static func collectParagraphs(_ html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<p[^>]*>([\\s\\S]*?)</p>", options: .caseInsensitive) else { return [] }
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: (html as NSString).length))
        var result: [String] = []
        for m in matches {
            if m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: html) {
                let text = HTMLUtils.stripTags(String(html[r])).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count >= 40 { result.append(HTMLUtils.decodeEntities(text)) }
            }
        }
        return result
    }
    private static func removeTagBlocks(_ html: String, tag: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "<\(tag)\\b[^>]*/?>", with: "", options: [.regularExpression, .caseInsensitive])
        return result
    }
    private static func extractInnermostBlock(_ html: String, tag: String) -> String? {
        let pattern = "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: (html as NSString).length))
        var best: String?; var bestLen = 0
        for m in matches {
            if m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: html) {
                let block = String(html[r])
                let len = HTMLUtils.stripTags(block).count
                if len > bestLen { bestLen = len; best = block }
            }
        }
        return best
    }
    private static func cleanContentHTML(_ html: String, baseURL: URL) -> String {
        var work = html
        for tag in ["script", "style", "noscript", "iframe", "button", "input"] {
            work = removeTagBlocks(work, tag: tag)
        }
        work = HTMLUtils.decodeEntities(work)
        work = work.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return work.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func matchFirst(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
    private static func countMatches(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
}
