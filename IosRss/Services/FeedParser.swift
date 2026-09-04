import Foundation

// MARK: - RSS/Atom Feed Parser (regex-based, no XMLParser dependency)

enum FeedParser {
    static func parse(data: Data, feedID: UUID, feedTitle: String) -> [Article] {
        guard let raw = String(data: data, encoding: .utf8) ??
              String(data: data, encoding: .isoLatin1) else { return [] }

        // Detect format
        if raw.contains("<feed") && raw.contains("xmlns") {
            return parseAtom(raw, feedID: feedID, feedTitle: feedTitle)
        } else {
            return parseRSS(raw, feedID: feedID, feedTitle: feedTitle)
        }
    }

    /// 从 RSS/Atom 中提取订阅源名称（channel/feed 的 title）
    static func extractFeedTitle(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) ??
              String(data: data, encoding: .isoLatin1) else { return nil }

        if raw.contains("<feed") && raw.contains("xmlns") {
            // Atom: <feed> 下第一层 <title>，避免用到 entry 里的 title
            if let feedBlock = firstTopLevelBlock(raw, tag: "feed") {
                if let t = extractTag("title", from: feedBlock) {
                    let cleaned = stripHTML(t).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty { return cleaned }
                }
            }
        } else {
            // RSS: 优先 channel 内的 title
            if let channel = firstTopLevelBlock(raw, tag: "channel") {
                if let t = extractTag("title", from: channel) {
                    let cleaned = stripHTML(t).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty { return cleaned }
                }
            }
        }
        return nil
    }

    /// 从 RSS channel 的 link 或 Atom feed 的 href 提取源地址，供 XML 文件导入后刷新使用
    static func extractFeedLink(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) ??
              String(data: data, encoding: .utf16) ??
              String(data: data, encoding: .isoLatin1) else { return nil }

        if raw.contains("<feed") && raw.contains("xmlns") {
            if let feedBlock = firstTopLevelBlock(raw, tag: "feed") {
                let href = extractLinkHref(from: feedBlock)
                if !href.isEmpty { return href.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        } else if let channel = firstTopLevelBlock(raw, tag: "channel") {
            if let link = extractTag("link", from: channel) {
                let cleaned = stripHTML(link).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    /// 从 RSS/Atom 提取源图标：channel image / itunes:image / Atom icon|logo
    static func extractFeedImage(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) ??
              String(data: data, encoding: .isoLatin1) else { return nil }

        // 1) 标准 RSS：任意位置的 <image>…<url>…</url>…</image>（不依赖 channel 截取成功）
        //    示例：
        //    <image>
        //      <url>https://spacenews.com/.../star-32x32.png</url>
        //      <title>SpaceNews</title>
        //      <link>https://spacenews.com/</link>
        //    </image>
        if let url = extractRSSImageURL(from: raw) {
            return url
        }

        // 2) itunes / media 属性式图片
        if let href = extractAttrHref(tagName: "itunes:image", from: raw)
            ?? extractAttrHref(tagName: "media:thumbnail", from: raw)
            ?? extractAttrHref(tagName: "media:content", from: raw) {
            if looksLikeImageURL(href) { return href }
        }

        // 3) Atom icon / logo
        if raw.contains("<feed") {
            let scope = firstTopLevelBlock(raw, tag: "feed") ?? raw
            for tag in ["icon", "logo"] {
                if let v = extractTag(tag, from: scope) {
                    let u = stripHTML(v).trimmingCharacters(in: .whitespacesAndNewlines)
                    if looksLikeImageURL(u) { return u }
                }
            }
        }
        return nil
    }

    /// 在整份 XML 中找第一处 channel 级 <image><url>
    private static func extractRSSImageURL(from raw: String) -> String? {
        // 优先：完整 <image>…</image> 块内的 <url>
        // 用正则直接抓，避免 extractBlocks 在超大 feed / 异常嵌套时漏掉
        let patterns = [
            #"<image\\b[^>]*>[\\s\\S]*?<url[^>]*>\\s*([^<]+?)\\s*</url>"#,
            #"<image>\\s*<url>\\s*([^<]+?)\\s*</url>"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
               let range = Range(match.range(at: 1), in: raw) {
                let u = stripHTML(String(raw[range])).trimmingCharacters(in: .whitespacesAndNewlines)
                // 跳过条目里偶发的非图标大图：channel 图标通常较小路径或明确是站点图
                if looksLikeImageURL(u) { return u }
            }
        }
        // 退路：extractBlocks
        if let imageBlock = extractBlocks(from: raw, tag: "image").first,
           let url = extractTag("url", from: imageBlock) {
            let u = stripHTML(url).trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeImageURL(u) { return u }
        }
        return nil
    }

    /// 解析出图标 URL：优先 XML 内 image，否则用站点 favicon 服务
    static func resolveFaviconURL(from data: Data, feedURL: String) -> String? {
        if let fromFeed = extractFeedImage(from: data), !fromFeed.isEmpty {
            return absoluteURL(fromFeed, relativeTo: feedURL)
        }
        return siteFaviconURL(for: feedURL)
    }

    /// 站点 favicon：优先 DuckDuckGo（国内相对可访问），再试站点根路径 /favicon.ico
    static func siteFaviconURL(for feedURL: String) -> String? {
        let host: String? = {
            if let h = URL(string: feedURL)?.host, !h.isEmpty { return h }
            var s = feedURL
            if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
            if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
            return s.isEmpty ? nil : s
        }()
        guard let host, !host.isEmpty else { return nil }
        // DuckDuckGo icons 服务，不依赖 Google
        return "https://icons.duckduckgo.com/ip3/\(host).ico"
    }

    private static func looksLikeImageURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ("&" + "amp;"), with: "&")
            .lowercased()
        guard t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("/") else { return false }
        return true
    }

    private static func absoluteURL(_ maybeRelative: String, relativeTo base: String) -> String {
        var t = maybeRelative.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: ("&" + "amp;"), with: "&")
        if t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") {
            return t
        }
        if let baseURL = URL(string: base), let resolved = URL(string: t, relativeTo: baseURL) {
            return resolved.absoluteURL.absoluteString
        }
        return t
    }

    /// 提取形如 <tagName href="..."/> 或 url="..." 的属性
    private static func extractAttrHref(tagName: String, from xml: String) -> String? {
        // 允许属性顺序任意：href / url / src
        let escaped = NSRegularExpression.escapedPattern(for: tagName)
        let pattern = "<\(escaped)\\b[^>]*(?:href|url|src)\\s*=\\s*[\"']([^\"']+)[\"'][^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 取第一个顶层标签块（简单实现：第一个匹配的开闭标签）
    private static func firstTopLevelBlock(_ xml: String, tag: String) -> String? {
        extractBlocks(from: xml, tag: tag).first
    }

    // MARK: RSS

    private static func parseRSS(_ xml: String, feedID: UUID, feedTitle: String) -> [Article] {
        let items = extractBlocks(from: xml, tag: "item")
        return items.compactMap { block -> Article? in
            let title = extractTag("title", from: block) ?? ""
            guard !title.isEmpty else { return nil }
            let link = extractTag("link", from: block) ??
                       extractTag("guid", from: block) ?? ""
            let description = extractTag("description", from: block) ??
                              extractTag("summary", from: block) ?? ""
            let content = extractTag("content:encoded", from: block) ??
                         extractTag("content", from: block) ?? description
            let pubDate = extractTag("pubDate", from: block) ??
                         extractTag("published", from: block) ?? ""
            return Article(
                id: UUID(),
                feedID: feedID,
                feedTitle: feedTitle,
                title: stripHTML(title),
                link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                summary: String(stripHTML(description).prefix(200)),
                content: content.isEmpty ? description : content,
                publishedDate: parseDate(pubDate),
                isRead: false
            )
        }
    }

    // MARK: Atom

    private static func parseAtom(_ xml: String, feedID: UUID, feedTitle: String) -> [Article] {
        let entries = extractBlocks(from: xml, tag: "entry")
        return entries.compactMap { block -> Article? in
            let title = extractTag("title", from: block) ?? ""
            guard !title.isEmpty else { return nil }
            // Atom link is an attribute: <link href="..."/>
            let link = extractLinkHref(from: block)
            let summary = extractTag("summary", from: block) ?? ""
            let content = extractTag("content", from: block) ?? summary
            let published = extractTag("published", from: block) ??
                           extractTag("updated", from: block) ?? ""
            return Article(
                id: UUID(),
                feedID: feedID,
                feedTitle: feedTitle,
                title: stripHTML(title),
                link: link,
                summary: String(stripHTML(summary).prefix(200)),
                content: content.isEmpty ? summary : content,
                publishedDate: parseDate(published),
                isRead: false
            )
        }
    }

    // MARK: Helpers

    static func extractBlocks(from xml: String, tag: String) -> [String] {
        var blocks: [String] = []
        var search = xml
        let open = "<\(tag)"
        let close = "</\(tag)>"
        while let start = search.range(of: open, options: .caseInsensitive) {
            guard let end = search.range(of: close, options: .caseInsensitive, range: start.upperBound..<search.endIndex) else { break }
            let block = String(search[start.lowerBound..<end.upperBound])
            blocks.append(block)
            search = String(search[end.upperBound...])
        }
        return blocks
    }

    static func extractTag(_ tag: String, from xml: String) -> String? {
        // Handles <tag>content</tag> and <tag><![CDATA[content]]></tag>
        let openPat = "<\(tag)[^>]*>"
        let closePat = "</\(tag)>"
        guard let openRange = xml.range(of: openPat, options: [.regularExpression, .caseInsensitive]),
              let closeRange = xml.range(of: closePat, options: [.regularExpression, .caseInsensitive],
                                         range: openRange.upperBound..<xml.endIndex) else { return nil }
        var content = String(xml[openRange.upperBound..<closeRange.lowerBound])
        // Unwrap CDATA
        if content.hasPrefix("<![CDATA[") && content.hasSuffix("]]>") {
            content = String(content.dropFirst(9).dropLast(3))
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func extractLinkHref(from xml: String) -> String {
        // <link href="..." rel="alternate" .../>  or  <link href="..."/>
        let pattern = #"<link[^>]+href=[\"']([^\"']+)[\"'][^>]*/>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return "" }
        return String(xml[range])
    }

    static func stripHTML(_ html: String) -> String {
        HTMLUtils.stripTags(html)
    }

    static func parseDate(_ str: String) -> Date? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatters = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formatters {
            df.dateFormat = fmt
            if let date = df.date(from: trimmed) { return date }
        }
        return nil
    }
}

// MARK: - Feed Naming

enum FeedNaming {
    /// 有名称用名称；否则用清理后的域名（去掉协议、路径、www.）
    static func resolveTitle(parsed: String?, url: String) -> String {
        if let t = parsed?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        return domainName(from: url)
    }

    /// 只保留域名：去掉 https://、路径、查询参数、www.
    static func domainName(from urlString: String) -> String {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: s), let host = url.host, !host.isEmpty {
            return stripWWW(host)
        }
        // 手写解析兜底
        if let range = s.range(of: "://") {
            s = String(s[range.upperBound...])
        }
        if let slash = s.firstIndex(of: "/") {
            s = String(s[..<slash])
        }
        if let q = s.firstIndex(of: "?") {
            s = String(s[..<q])
        }
        if let hash = s.firstIndex(of: "#") {
            s = String(s[..<hash])
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return stripWWW(s).isEmpty ? urlString : stripWWW(s)
    }

    private static func stripWWW(_ host: String) -> String {
        let lower = host.lowercased()
        if lower.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }
}

// MARK: - Feed Discovery

struct FeedDiscovery {
    static func discoverFeeds(from url: URL) async throws -> [DiscoveredFeed] {
        var finalURL = url
        if url.scheme == nil || url.scheme!.isEmpty {
            finalURL = URL(string: "https://\(url.absoluteString)")!
        }

        let (data, response) = try await URLSession.shared.data(from: finalURL)
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""

        // Direct feed
        if contentType.contains("xml") || contentType.contains("rss") || contentType.contains("atom") {
            let articles = FeedParser.parse(data: data, feedID: UUID(), feedTitle: "")
            if !articles.isEmpty {
                let title = FeedNaming.resolveTitle(
                    parsed: FeedParser.extractFeedTitle(from: data),
                    url: finalURL.absoluteString
                )
                return [DiscoveredFeed(title: title, url: finalURL.absoluteString)]
            }
        }

        // Try parsing as feed anyway
        let articles = FeedParser.parse(data: data, feedID: UUID(), feedTitle: "")
        if !articles.isEmpty {
            let title = FeedNaming.resolveTitle(
                parsed: FeedParser.extractFeedTitle(from: data),
                url: finalURL.absoluteString
            )
            return [DiscoveredFeed(title: title, url: finalURL.absoluteString)]
        }

        // Parse HTML for <link rel="alternate" ...>
        let html = String(data: data, encoding: .utf8) ?? ""
        var found = parseAlternateFeedLinks(from: html, baseURL: finalURL)
        if found.isEmpty {
            found = guessCommonFeedPaths(baseURL: finalURL)
        }
        return found
    }

    private static func parseAlternateFeedLinks(from html: String, baseURL: URL) -> [DiscoveredFeed] {
        var feeds: [DiscoveredFeed] = []
        let pattern = #"<link[^>]+rel=[\"']alternate[\"'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let tag = String(html[matchRange])
            guard let type = extractAttr("type", from: tag),
                  (type.contains("rss") || type.contains("atom")),
                  let href = extractAttr("href", from: tag) else { continue }
            let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL.absoluteString ?? href
            let linkTitle = extractAttr("title", from: tag)
            let title = FeedNaming.resolveTitle(parsed: linkTitle, url: resolved)
            feeds.append(DiscoveredFeed(title: title, url: resolved))
        }
        return feeds
    }

    private static func guessCommonFeedPaths(baseURL: URL) -> [DiscoveredFeed] {
        let paths = ["/feed", "/feed/", "/rss", "/rss.xml", "/atom.xml", "/feed.xml", "/index.xml"]
        return paths.compactMap { path in
            guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { return nil }
            let title = FeedNaming.domainName(from: baseURL.absoluteString)
            return DiscoveredFeed(title: title, url: url.absoluteString)
        }
    }

    private static func extractAttr(_ attr: String, from tag: String) -> String? {
        let pattern = "\(attr)=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }
}

struct DiscoveredFeed: Identifiable {
    let id = UUID()
    let title: String
    let url: String
}

// MARK: - OPML Parser

struct OPMLItem {
    let title: String
    let url: String
}

struct OPMLParser {
    let data: Data

    func parse() -> [OPMLItem] {
        guard var xml = decodeXMLString(data) else { return [] }
        // 去掉 BOM / 声明噪声，统一换行，便于跨行匹配
        if xml.hasPrefix("\u{FEFF}") { xml = String(xml.dropFirst()) }
        xml = xml.replacingOccurrences(of: "\r\n", with: "\n")
        xml = xml.replacingOccurrences(of: "\r", with: "\n")

        var items: [OPMLItem] = []
        var seen = Set<String>()

        // 匹配 <outline ...> / <outline .../>，属性可跨行
        let pattern = #"<outline\\b[\\s\\S]*?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, range: range)
        for match in matches {
            guard let matchRange = Range(match.range, in: xml) else { continue }
            let tag = String(xml[matchRange])
            // 文件夹节点通常只有 text 没有 feed URL，跳过
            guard let rawURL = firstFeedURL(in: tag) else { continue }
            let url = HTMLUtils.decodeEntities(rawURL).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { continue }
            let canonical = FeedURL.canonical(url)
            guard !canonical.isEmpty, !seen.contains(canonical) else { continue }
            seen.insert(canonical)
            let rawTitle = extractAttr("text", from: tag)
                ?? extractAttr("title", from: tag)
                ?? extractAttr("description", from: tag)
            let title = FeedNaming.resolveTitle(
                parsed: rawTitle.map { HTMLUtils.decodeEntities($0) },
                url: url
            )
            items.append(OPMLItem(title: title, url: url))
        }

        // 若没有 outline，尝试把整文件当 RSS/Atom 时由上层处理；这里再尝试 <link type="application/rss+xml"> 类订阅列表
        if items.isEmpty {
            items.append(contentsOf: parseLinkAlternateFeeds(from: xml, seen: &seen))
        }
        return items
    }

    private func decodeXMLString(_ data: Data) -> String? {
        // 跳过 UTF-8 BOM
        var bytes = data
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bytes = bytes.dropFirst(3)
        }
        if let s = String(data: bytes, encoding: .utf8), !s.isEmpty { return s }
        if let s = String(data: data, encoding: .utf16), !s.isEmpty { return s }
        if let s = String(data: data, encoding: .utf16LittleEndian), !s.isEmpty { return s }
        if let s = String(data: data, encoding: .utf16BigEndian), !s.isEmpty { return s }
        if let s = String(data: data, encoding: .isoLatin1), !s.isEmpty { return s }
        if let s = String(data: data, encoding: .windowsCP1252), !s.isEmpty { return s }
        return nil
    }

    /// 优先 xmlUrl；type=rss/atom 时接受 url；其次像 feed 的 url；最后谨慎使用 htmlUrl 仅当路径像 feed
    private func firstFeedURL(in tag: String) -> String? {
        let xmlKeys = ["xmlUrl", "xmlurl", "xmlURL", "XMLUrl", "xml_url", "xmluri", "xmlUri"]
        for key in xmlKeys {
            if let v = extractAttr(key, from: tag), looksLikeURL(v) { return v }
        }

        let type = (extractAttr("type", from: tag) ?? "").lowercased()
        let isFeedType = type.contains("rss") || type.contains("atom") || type == "feed" || type.contains("xml")

        if let v = extractAttr("url", from: tag), looksLikeURL(v) {
            if isFeedType || looksLikeFeedURL(v) { return v }
        }
        // 部分导出器用 htmlUrl 误放 feed 地址
        if let v = extractAttr("htmlUrl", from: tag) ?? extractAttr("htmlurl", from: tag),
           looksLikeFeedURL(v) {
            return v
        }
        return nil
    }

    private func looksLikeURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("feed://")
    }

    private func looksLikeFeedURL(_ s: String) -> Bool {
        guard looksLikeURL(s) else { return false }
        let t = s.lowercased()
        return t.contains("rss") || t.contains("atom") || t.contains("feed")
            || t.contains(".xml") || t.contains("/rdf") || t.contains("syndication")
    }

    private func extractAttr(_ attr: String, from tag: String) -> String? {
        // 支持双引号、单引号、无引号
        let pattern = "\(attr)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for i in 1...3 {
            if match.numberOfRanges > i,
               let range = Range(match.range(at: i), in: tag) {
                let value = String(tag[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// 从 HTML/XML 中的 <link rel="alternate" type="application/rss+xml" href="..."> 提取
    private func parseLinkAlternateFeeds(from xml: String, seen: inout Set<String>) -> [OPMLItem] {
        var items: [OPMLItem] = []
        let pattern = #"<link\\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        for match in matches {
            guard let r = Range(match.range, in: xml) else { continue }
            let tag = String(xml[r])
            let type = (extractAttr("type", from: tag) ?? "").lowercased()
            let rel = (extractAttr("rel", from: tag) ?? "").lowercased()
            let isFeed = type.contains("rss") || type.contains("atom") || type.contains("xml")
            guard isFeed || rel == "alternate" && (type.contains("rss") || type.contains("atom")) else { continue }
            guard let href = extractAttr("href", from: tag), looksLikeURL(href) else { continue }
            let url = HTMLUtils.decodeEntities(href).trimmingCharacters(in: .whitespacesAndNewlines)
            let canonical = FeedURL.canonical(url)
            guard !canonical.isEmpty, !seen.contains(canonical) else { continue }
            seen.insert(canonical)
            let title = extractAttr("title", from: tag).map { HTMLUtils.decodeEntities($0) }
            items.append(OPMLItem(
                title: FeedNaming.resolveTitle(parsed: title, url: url),
                url: url
            ))
        }
        return items
    }
}
