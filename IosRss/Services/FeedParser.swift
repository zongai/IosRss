import Foundation

// EMERGENCY RESTORE - full file follows in next commit if truncated
enum FeedParser {
    static func parse(data: Data, feedID: UUID, feedTitle: String) -> [Article] { [] }
    static func extractFeedTitle(from data: Data) -> String? { nil }
    static func extractFeedLink(from data: Data) -> String? { nil }
    static func extractFeedImage(from data: Data) -> String? { nil }
    static func resolveFaviconURL(from data: Data, feedURL: String) -> String? { siteFaviconURL(for: feedURL) }
    static func siteFaviconURL(for feedURL: String) -> String? { faviconCandidates(for: feedURL).first }
    static func faviconCandidates(for feedOrSiteURL: String) -> [String] {
        guard let host = URL(string: feedOrSiteURL)?.host else { return [] }
        return ["https://www.google.com/s2/favicons?domain=\(host)&sz=128"]
    }
    static func extractBlocks(from xml: String, tag: String) -> [String] { [] }
    static func extractTag(_ tag: String, from xml: String) -> String? { nil }
    static func stripHTML(_ html: String) -> String { HTMLUtils.stripTags(html) }
    static func parseDate(_ str: String) -> Date? { nil }
}

enum FeedNaming {
    static func resolveTitle(parsed: String?, url: String) -> String {
        if let t = parsed?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return domainName(from: url)
    }
    static func domainName(from urlString: String) -> String {
        URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
    }
}

struct FeedDiscovery {
    static func discoverFeeds(from url: URL) async throws -> [DiscoveredFeed] { [] }
}

struct DiscoveredFeed: Identifiable {
    let id = UUID()
    let title: String
    let url: String
}

struct OPMLItem {
    let title: String
    let url: String
}

struct OPMLParser {
    let data: Data
    func parse() -> [OPMLItem] {
        guard var xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        xml = HTMLUtils.decodeEntities(xml)
        var items: [OPMLItem] = []
        var seen = Set<String>()
        let pattern = "xmlUrl\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        for match in matches {
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: xml) else { continue }
            let url = String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = url.lowercased()
            guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("feed://") else { continue }
            let canonical = FeedURL.canonical(url)
            guard !canonical.isEmpty, !seen.contains(canonical) else { continue }
            seen.insert(canonical)
            // title nearby
            let loc = match.range.location
            let start = max(0, loc - 120)
            let end = min((xml as NSString).length, loc + match.range.length + 40)
            let ctx = (xml as NSString).substring(with: NSRange(location: start, length: end - start))
            var title: String? = nil
            for key in ["text", "title"] {
                let tp = "\(key)\\s*=\\s*[\"']([^\"']+)[\"']"
                if let tr = try? NSRegularExpression(pattern: tp, options: .caseInsensitive),
                   let m = tr.firstMatch(in: ctx, range: NSRange(ctx.startIndex..., in: ctx)),
                   m.numberOfRanges > 1, let rr = Range(m.range(at: 1), in: ctx) {
                    let t = String(ctx[rr]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { title = t; break }
                }
            }
            items.append(OPMLItem(title: FeedNaming.resolveTitle(parsed: title, url: url), url: url))
        }
        return items
    }
}
