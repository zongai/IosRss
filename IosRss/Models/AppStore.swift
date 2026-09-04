import Foundation
import SwiftUI

@Observable
@MainActor
class AppStore {
    var feeds: [RSSFeed] = []
    var selectedFeedID: UUID?
    var isLoading = false
    var errorMessage: String?

    var fontSize: Double = 17
    var titleDisplayMode: TitleDisplayMode = .original
    var defaultTranslationEngine: TranslationEngine = .google
    var aiProviders: [AIProvider] = [
        AIProvider(id: UUID(), name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", kind: "openai"),
        AIProvider(id: UUID(), name: "Anthropic", baseURL: "https://api.anthropic.com/v1", model: "claude-3-haiku-20240307", kind: "openai"),
        AIProvider(id: UUID(), name: "Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta", model: "gemini-2.0-flash", kind: "gemini")
    ]
    var defaultSummaryProviderID: UUID?
    var defaultTranslationProviderID: UUID?
    var showReadArticles: Bool = false
    var translationPrompt: String = AppStore.defaultTranslationPrompt
    var summaryPrompt: String = AppStore.defaultSummaryPrompt

    static let defaultTranslationPrompt = "请将以下内容翻译成中文，只输出译文，不要解释：\n\n{{text}}"
    static let defaultSummaryPrompt = "请用3-5句话概括以下文章的核心内容，用中文回答，每句话用换行分隔：\n\n标题：{{title}}\n\n内容：{{content}}"

    private let readArticleRetentionDays: TimeInterval = 7 * 24 * 3600
    private var readArticleLinks: Set<String> = []

    init() {
        loadFromStorage()
        if feeds.isEmpty { seedSampleData() }
        if UserDefaults.standard.string(forKey: "defaultTranslationEngine") == "Gemini" {
            defaultTranslationEngine = .ai
            if defaultTranslationProviderID == nil {
                defaultTranslationProviderID = aiProviders.first(where: { $0.kind == "gemini" })?.id
            }
        }
        if defaultSummaryProviderID == nil {
            defaultSummaryProviderID = aiProviders.first?.id
        }
        rebuildReadLinksFromArticles()
        purgeOldReadArticles()
    }

    static func canonicalLink(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        if let url = URL(string: s), var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.fragment = nil
            if let host = comps.host { comps.host = host.lowercased() }
            if let scheme = comps.scheme { comps.scheme = scheme.lowercased() }
            if let rebuilt = comps.url?.absoluteString {
                s = rebuilt
                if s.hasSuffix("/") { s = String(s.dropLast()) }
            }
        }
        return s
    }

    private func rebuildReadLinksFromArticles() {
        for article in allArticles where article.isRead {
            let key = Self.canonicalLink(article.link)
            if !key.isEmpty { readArticleLinks.insert(key) }
        }
        persistReadLinks()
    }

    private func persistReadLinks() {
        UserDefaults.standard.set(Array(readArticleLinks), forKey: "readArticleLinks")
    }

    private func loadReadLinks() {
        if let arr = UserDefaults.standard.array(forKey: "readArticleLinks") as? [String] {
            readArticleLinks = Set(arr)
        }
    }

    private func rememberReadLink(_ link: String) {
        let key = Self.canonicalLink(link)
        guard !key.isEmpty else { return }
        if readArticleLinks.insert(key).inserted { persistReadLinks() }
    }

    private func forgetReadLink(_ link: String) {
        let key = Self.canonicalLink(link)
        guard !key.isEmpty else { return }
        if readArticleLinks.remove(key) != nil { persistReadLinks() }
    }

    var allArticles: [Article] {
        feeds.flatMap { $0.articles }.sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
    }

    var favoriteArticles: [Article] { allArticles.filter(\.isFavorite) }

    func articlesForFeed(_ feedID: UUID) -> [Article] {
        feeds.first(where: { $0.id == feedID })?.articles ?? []
    }

    func markAsRead(_ article: Article) {
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                if !feeds[i].articles[j].isRead {
                    feeds[i].articles[j].isRead = true
                    feeds[i].unreadCount = max(0, feeds[i].unreadCount - 1)
                }
                rememberReadLink(feeds[i].articles[j].link)
            }
        }
        saveToStorage()
    }

    func markAsUnread(_ article: Article) {
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                if feeds[i].articles[j].isRead {
                    feeds[i].articles[j].isRead = false
                    feeds[i].unreadCount = feeds[i].articles.filter { !$0.isRead }.count
                }
                forgetReadLink(feeds[i].articles[j].link)
            }
        }
        saveToStorage()
    }

    func markAllAsRead(in feedID: UUID) {
        guard let i = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        var changed = false
        for j in feeds[i].articles.indices where !feeds[i].articles[j].isRead {
            feeds[i].articles[j].isRead = true
            rememberReadLink(feeds[i].articles[j].link)
            changed = true
        }
        if changed {
            feeds[i].unreadCount = 0
            saveToStorage()
        }
    }

    func toggleFavorite(_ article: Article) {
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                feeds[i].articles[j].isFavorite.toggle()
            }
        }
        saveToStorage()
    }

    func persistSettings() { saveToStorage() }

    func updateArticle(_ article: Article) {
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                feeds[i].articles[j] = article
                feeds[i].unreadCount = feeds[i].articles.filter { !$0.isRead }.count
            }
        }
        saveToStorage()
    }

    func addFeed(_ feed: RSSFeed) {
        feeds.append(feed)
        saveToStorage()
    }

    func deleteFeed(at offsets: IndexSet) {
        feeds.remove(atOffsets: offsets)
        saveToStorage()
    }

    func purgeOldReadArticles() {
        let cutoff = Date().addingTimeInterval(-readArticleRetentionDays)
        var changed = false
        for i in feeds.indices {
            let before = feeds[i].articles.count
            feeds[i].articles.removeAll { article in
                guard article.isRead else { return false }
                if article.isFavorite { return false }
                if let date = article.publishedDate { return date < cutoff }
                return true
            }
            if feeds[i].articles.count != before {
                feeds[i].unreadCount = feeds[i].articles.filter { !$0.isRead }.count
                changed = true
            }
        }
        if changed { saveToStorage() }
    }

    func refreshFeed(_ feedID: UUID) async {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        let urlStr = feeds[idx].url
        guard let url = URL(string: urlStr) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let parsed = FeedParser.parse(data: data, feedID: feedID, feedTitle: feeds[idx].title)
            let existingKeys = Set(feeds[idx].articles.map { Self.canonicalLink($0.link) })
            var newArticles: [Article] = []
            for var article in parsed {
                let key = Self.canonicalLink(article.link)
                if key.isEmpty || existingKeys.contains(key) { continue }
                if readArticleLinks.contains(key) { article.isRead = true }
                newArticles.append(article)
            }
            feeds[idx].articles.insert(contentsOf: newArticles, at: 0)
            feeds[idx].unreadCount = feeds[idx].articles.filter { !$0.isRead }.count
            feeds[idx].lastFetched = Date()
            if let resolved = FeedParser.resolveFaviconURL(from: data, feedURL: urlStr) {
                let current = feeds[idx].faviconURL ?? ""
                let isFallbackOnly = current.isEmpty
                    || current.contains("duckduckgo.com/ip3/")
                    || current.contains("google.com/s2/favicons")
                let fromFeed = FeedParser.extractFeedImage(from: data) != nil
                if isFallbackOnly || fromFeed {
                    feeds[idx].faviconURL = resolved
                }
            }
            purgeOldReadArticles()
            saveToStorage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAll() async {
        for feed in feeds { await refreshFeed(feed.id) }
    }

    func translateText(_ text: String) async throws -> String {
        switch defaultTranslationEngine {
        case .google: return try await GoogleTranslate.translate(text: text)
        case .microsoft:
            let key = Keychain.load(key: "microsoft_translate_key") ?? ""
            return try await MicrosoftTranslate.translate(text: text, apiKey: key)
        case .deepl:
            let key = Keychain.load(key: "deepl_translate_key") ?? ""
            return try await DeepLTranslate.translate(text: text, apiKey: key)
        case .ai:
            guard let providerID = defaultTranslationProviderID ?? defaultSummaryProviderID,
                  let provider = aiProviders.first(where: { $0.id == providerID }) else {
                throw TranslationError.noProvider
            }
            let key = Keychain.load(key: "ai_key_\(provider.id)") ?? ""
            return try await AITranslate.translate(text: text, provider: provider, apiKey: key, promptTemplate: translationPrompt)
        }
    }

    func translateTexts(_ texts: [String], concurrency: Int? = nil) async -> [String?] {
        guard !texts.isEmpty else { return [] }
        let engine = defaultTranslationEngine
        let limit = concurrency ?? defaultListConcurrency(for: engine)
        switch engine {
        case .deepl:
            let key = Keychain.load(key: "deepl_translate_key") ?? ""
            return await translateNativeBatch(texts, chunkSize: 40) { try await DeepLTranslate.translate(texts: $0, apiKey: key) }
        case .microsoft:
            let key = Keychain.load(key: "microsoft_translate_key") ?? ""
            return await translateNativeBatch(texts, chunkSize: 40) { try await MicrosoftTranslate.translate(texts: $0, apiKey: key) }
        case .google, .ai:
            return await translateConcurrently(texts, concurrency: limit)
        }
    }

    private func defaultListConcurrency(for engine: TranslationEngine) -> Int {
        switch engine {
        case .ai: return 3
        case .google: return 4
        default: return 5
        }
    }

    private func translateNativeBatch(_ texts: [String], chunkSize: Int, call: ([String]) async throws -> [String]) async -> [String?] {
        var out = Array<String?>(repeating: nil, count: texts.count)
        var offset = 0
        for chunk in texts.chunked(into: chunkSize) {
            do {
                let translated = try await call(chunk)
                for (i, t) in translated.enumerated() where offset + i < out.count {
                    let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    out[offset + i] = trimmed.isEmpty ? nil : trimmed
                }
            } catch {
                for (i, text) in chunk.enumerated() {
                    if let r = try? await translateText(text) {
                        let trimmed = r.trimmingCharacters(in: .whitespacesAndNewlines)
                        out[offset + i] = trimmed.isEmpty ? nil : trimmed
                    }
                }
            }
            offset += chunk.count
        }
        return out
    }

    private func translateConcurrently(_ texts: [String], concurrency: Int) async -> [String?] {
        var results = Array<String?>(repeating: nil, count: texts.count)
        await withTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            let spawn = min(max(concurrency, 1), texts.count)
            while next < spawn {
                let i = next
                let text = texts[i]
                group.addTask {
                    let r = try? await self.translateText(text)
                    let trimmed = r?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (i, (trimmed?.isEmpty == false) ? trimmed : nil)
                }
                next += 1
            }
            for await (index, result) in group {
                results[index] = result
                if next < texts.count {
                    let i = next
                    let text = texts[i]
                    next += 1
                    group.addTask {
                        let r = try? await self.translateText(text)
                        let trimmed = r?.trimmingCharacters(in: .whitespacesAndNewlines)
                        return (i, (trimmed?.isEmpty == false) ? trimmed : nil)
                    }
                }
            }
        }
        return results
    }

    func translateLongText(_ text: String, maxChunkChars: Int = 1800) async throws -> String {
        let chunks = Self.splitTextIntoChunks(text, maxChars: maxChunkChars)
        guard !chunks.isEmpty else { return "" }
        if chunks.count == 1 { return try await translateText(chunks[0]) }
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask { (index, try await self.translateText(chunk)) }
            }
            var ordered = Array(repeating: "", count: chunks.count)
            for try await (index, result) in group { ordered[index] = result }
            return ordered.joined(separator: "\n\n")
        }
    }

    static func splitTextIntoChunks(_ text: String, maxChars: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.count <= maxChars { return [trimmed] }
        var chunks: [String] = []
        var current = ""
        let paragraphs = trimmed.components(separatedBy: CharacterSet.newlines)
        for para in paragraphs {
            let p = para.trimmingCharacters(in: .whitespaces)
            if p.isEmpty { continue }
            if current.isEmpty {
                if p.count > maxChars { chunks.append(contentsOf: splitBySentence(p, maxChars: maxChars)) }
                else { current = p }
            } else if current.count + p.count + 1 <= maxChars {
                current += "\n" + p
            } else {
                chunks.append(current)
                if p.count > maxChars {
                    chunks.append(contentsOf: splitBySentence(p, maxChars: maxChars))
                    current = ""
                } else { current = p }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func splitBySentence(_ text: String, maxChars: Int) -> [String] {
        var result: [String] = []
        var current = ""
        let separators = CharacterSet(charactersIn: ".!?。！？\n")
        var buffer = ""
        for ch in text {
            buffer.append(ch)
            if String(ch).rangeOfCharacter(from: separators) != nil {
                if current.count + buffer.count <= maxChars { current += buffer }
                else {
                    if !current.isEmpty { result.append(current) }
                    current = buffer
                }
                buffer = ""
            }
        }
        if !buffer.isEmpty {
            if current.count + buffer.count <= maxChars { current += buffer }
            else {
                if !current.isEmpty { result.append(current) }
                current = buffer
            }
        }
        if !current.isEmpty { result.append(current) }
        var final: [String] = []
        for piece in result {
            if piece.count <= maxChars { final.append(piece) }
            else {
                var start = piece.startIndex
                while start < piece.endIndex {
                    let end = piece.index(start, offsetBy: maxChars, limitedBy: piece.endIndex) ?? piece.endIndex
                    final.append(String(piece[start..<end]))
                    start = end
                }
            }
        }
        return final
    }

    func generateSummary(for article: Article) async throws -> String {
        guard let providerID = defaultSummaryProviderID,
              let provider = aiProviders.first(where: { $0.id == providerID }) else {
            throw TranslationError.noProvider
        }
        let key = Keychain.load(key: "ai_key_\(provider.id)") ?? ""
        return try await AISummary.summarize(article: article, provider: provider, apiKey: key, promptTemplate: summaryPrompt)
    }

    @discardableResult
    func fetchFullContent(for article: Article) async throws -> Article {
        let result = try await ArticleContentFetcher.fetchFullContent(from: article.link)
        var updated = article
        updated.content = result.contentHTML
        updated.hasFullContent = true
        updated.translatedContent = nil
        updateArticle(updated)
        return updated
    }

    func exportOPML() -> String {
        var xml = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <opml version=\"2.0\">
          <head><title>Feed Subscriptions</title></head>
          <body>
        """
        for feed in feeds {
            xml += "    <outline type=\"rss\" text=\"\(feed.title)\" xmlUrl=\"\(feed.url)\"/>\n"
        }
        xml += "  </body>\n</opml>"
        return xml
    }

    func importOPML(data: Data) { _ = importSubscriptions(data: data) }

    @discardableResult
    func importSubscriptions(data: Data) -> SubscriptionImportResult {
        let opmlItems = OPMLParser(data: data).parse()
        if !opmlItems.isEmpty {
            var added = 0
            var skipped = 0
            for item in opmlItems {
                let url = FeedURL.canonical(item.url)
                guard !url.isEmpty else { continue }
                if feeds.contains(where: { FeedURL.canonical($0.url) == url }) {
                    skipped += 1
                    continue
                }
                let title = FeedNaming.resolveTitle(parsed: item.title, url: url)
                feeds.append(RSSFeed(
                    title: title,
                    url: url,
                    faviconURL: FeedParser.siteFaviconURL(for: url)
                ))
                added += 1
            }
            if added > 0 || skipped > 0 {
                saveToStorage()
                return SubscriptionImportResult(added: added, skipped: skipped, kind: "opml")
            }
        }

        let feedID = UUID()
        let parsedTitle = FeedParser.extractFeedTitle(from: data)
        var feedURL = FeedParser.extractFeedLink(from: data)
        let resolvedTitle = FeedNaming.resolveTitle(parsed: parsedTitle, url: feedURL ?? "")
        let articles = FeedParser.parse(data: data, feedID: feedID, feedTitle: resolvedTitle)

        if (feedURL == nil || feedURL?.isEmpty == true),
           let firstLink = articles.first(where: { !$0.link.isEmpty })?.link,
           let host = URL(string: firstLink)?.host {
            feedURL = "https://\(host)/"
        }

        guard !articles.isEmpty else {
            return SubscriptionImportResult(added: 0, skipped: 0, kind: "empty")
        }
        guard let url = feedURL, !url.isEmpty else {
            return SubscriptionImportResult(added: 0, skipped: 0, kind: "empty")
        }
        let canonical = FeedURL.canonical(url)
        if feeds.contains(where: { FeedURL.canonical($0.url) == canonical }) {
            return SubscriptionImportResult(added: 0, skipped: 1, kind: "rss")
        }
        let favicon = FeedParser.resolveFaviconURL(from: data, feedURL: canonical)
        let feed = RSSFeed(
            id: feedID,
            title: resolvedTitle.isEmpty ? FeedNaming.domainName(from: canonical) : resolvedTitle,
            url: canonical,
            faviconURL: favicon,
            unreadCount: articles.filter { !$0.isRead }.count,
            articles: articles,
            lastFetched: Date()
        )
        feeds.append(feed)
        saveToStorage()
        return SubscriptionImportResult(added: 1, skipped: 0, kind: "rss")
    }

    private func saveToStorage() {
        if let data = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(data, forKey: "feeds")
        }
        if let data = try? JSONEncoder().encode(aiProviders) {
            UserDefaults.standard.set(data, forKey: "aiProviders")
        }
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
        UserDefaults.standard.set(titleDisplayMode.rawValue, forKey: "titleDisplayMode")
        UserDefaults.standard.set(defaultTranslationEngine.rawValue, forKey: "defaultTranslationEngine")
        if let id = defaultSummaryProviderID {
            UserDefaults.standard.set(id.uuidString, forKey: "defaultSummaryProviderID")
        }
        if let id = defaultTranslationProviderID {
            UserDefaults.standard.set(id.uuidString, forKey: "defaultTranslationProviderID")
        }
        UserDefaults.standard.set(showReadArticles, forKey: "showReadArticles")
        UserDefaults.standard.set(translationPrompt, forKey: "translationPrompt")
        UserDefaults.standard.set(summaryPrompt, forKey: "summaryPrompt")
    }

    private func loadFromStorage() {
        loadReadLinks()
        if let data = UserDefaults.standard.data(forKey: "feeds"),
           let decoded = try? JSONDecoder().decode([RSSFeed].self, from: data) {
            feeds = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "aiProviders"),
           let decoded = try? JSONDecoder().decode([AIProvider].self, from: data) {
            aiProviders = decoded
            for i in aiProviders.indices {
                if aiProviders[i].kind.isEmpty { aiProviders[i].kind = "openai" }
                if aiProviders[i].name.lowercased().contains("gemini") { aiProviders[i].kind = "gemini" }
            }
        }
        fontSize = UserDefaults.standard.double(forKey: "fontSize").isZero ? 17 : UserDefaults.standard.double(forKey: "fontSize")
        if let raw = UserDefaults.standard.string(forKey: "titleDisplayMode") {
            titleDisplayMode = TitleDisplayMode(rawValue: raw) ?? .original
        }
        if let raw = UserDefaults.standard.string(forKey: "defaultTranslationEngine") {
            if raw == "Gemini" { defaultTranslationEngine = .ai }
            else { defaultTranslationEngine = TranslationEngine(rawValue: raw) ?? .google }
        }
        if let idStr = UserDefaults.standard.string(forKey: "defaultSummaryProviderID") {
            defaultSummaryProviderID = UUID(uuidString: idStr)
        }
        if let idStr = UserDefaults.standard.string(forKey: "defaultTranslationProviderID") {
            defaultTranslationProviderID = UUID(uuidString: idStr)
        }
        showReadArticles = UserDefaults.standard.bool(forKey: "showReadArticles")
        let storedTranslation = UserDefaults.standard.string(forKey: "translationPrompt") ?? ""
        translationPrompt = storedTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultTranslationPrompt : storedTranslation
        let storedSummary = UserDefaults.standard.string(forKey: "summaryPrompt") ?? ""
        summaryPrompt = storedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultSummaryPrompt : storedSummary
    }

    private func seedSampleData() {
        let tcID = UUID()
        let vergeID = UUID()
        let dfID = UUID()
        feeds = [
            RSSFeed(id: tcID, title: "TechCrunch", url: "https://techcrunch.com/feed/",
                    faviconURL: nil, unreadCount: 3, articles: sampleArticles(feedID: tcID, feedTitle: "TechCrunch")),
            RSSFeed(id: vergeID, title: "The Verge", url: "https://www.theverge.com/rss/index.xml",
                    faviconURL: nil, unreadCount: 2, articles: sampleArticles(feedID: vergeID, feedTitle: "The Verge")),
            RSSFeed(id: dfID, title: "Daring Fireball", url: "https://daringfireball.net/feeds/main",
                    faviconURL: nil, unreadCount: 0, articles: [])
        ]
    }

    private func sampleArticles(feedID: UUID, feedTitle: String) -> [Article] {
        let titles = [
            "Apple's New M4 Chip: What to Expect",
            "Google I/O 2024: Everything Announced",
            "Amazon Earnings Beat Wall Street Expectations",
            "OpenAI Launches New Reasoning Model",
            "Meta's AR Glasses Strategy for 2025"
        ]
        let summaries = [
            "The much-anticipated M4 chip promises significant performance gains over the M3 series, with a focus on AI and machine learning workloads.",
            "Google officially announced a suite of new AI features across Search, Workspace, and Android at this year's developer conference.",
            "Amazon reported strong Q1 results, driven by AWS cloud growth and improved retail margins.",
            "OpenAI unveiled its latest reasoning model, claiming superior performance on math and science benchmarks.",
            "Meta is betting big on augmented reality glasses with new partnerships and a refreshed timeline."
        ]
        return titles.enumerated().map { i, title in
            Article(
                id: UUID(),
                feedID: feedID,
                feedTitle: feedTitle,
                title: title,
                link: "https://example.com/article/\(i)",
                summary: summaries[i],
                content: "<p>\(summaries[i])</p><p>Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p>",
                publishedDate: Date().addingTimeInterval(-Double(i * 3600 + Int.random(in: 0...1800))),
                isRead: i > 2
            )
        }
    }
}

enum TranslationError: LocalizedError {
    case noProvider
    case apiError(String)
    var errorDescription: String? {
        switch self {
        case .noProvider: return "未配置翻译引擎，请在设置中添加AI提供商"
        case .apiError(let msg): return msg
        }
    }
}
