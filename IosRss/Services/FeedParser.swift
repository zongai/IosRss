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
        let pattern = #"<link[^>]+href=["']([^"']+)["'][^>]*/>"#
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
        let pattern = #"<link[^>]+rel=["']alternate["'][^>]*>"#
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
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var items: [OPMLItem] = []
        let pattern = #"<outline[^>]+>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, range: range)
        for match in matches {
            guard let matchRange = Range(match.range, in: xml) else { continue }
            let tag = String(xml[matchRange])
            guard let url = extractAttr("xmlUrl", from: tag) ?? extractAttr("xmlurl", from: tag) else { continue }
            let rawTitle = extractAttr("text", from: tag) ?? extractAttr("title", from: tag)
            let title = FeedNaming.resolveTitle(parsed: rawTitle, url: url)
            items.append(OPMLItem(title: title, url: url))
        }
        return items
    }

    private func extractAttr(_ attr: String, from tag: String) -> String? {
        let pattern = "\(attr)=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }
}
