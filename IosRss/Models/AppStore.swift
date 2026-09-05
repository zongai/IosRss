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
    var listTitleFontSize: Double = 18
    var listSummaryFontSize: Double = 15
    var readerTitleFontSize: Double = 24
    var aiSummaryFontSize: Double = 22
    var feedTitleFontSize: Double = 17

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
    var readRetentionDays: Int = 7
    var fullContentCacheDays: Int = 30

    static let defaultTranslationPrompt = "请将以下内容翻译成中文，只输出译文，不要解释：\n\n{{text}}"
    static let defaultSummaryPrompt = "请用3-5句话概括以下文章的核心内容，用中文回答，每句话用换行分隔：\n\n标题：{{title}}\n\n内容：{{content}}"

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
        pruneFullContentCache()
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
        var didChange = false
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                if !feeds[i].articles[j].isRead {
                    feeds[i].articles[j].isRead = true
                    feeds[i].unreadCount = max(0, feeds[i].articles.filter { !$0.isRead }.count)
                    didChange = true
                }
                rememberReadLink(feeds[i].articles[j].link)
                // 触发 @Observable 对数组元素的感知（重新赋值整个 feed）
                let refreshed = feeds[i]
                feeds[i] = refreshed
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
                let refreshed = feeds[i]
                feeds[i] = refreshed
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
            let refreshed = feeds[i]
            feeds[i] = refreshed
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

    /// 批量写入列表翻译结果（标题/摘要），只在最后 save 一次，避免逐条落盘导致前几条 UI 不刷新。
    func applyListTranslations(_ updates: [(id: UUID, title: String?, summary: String?)]) {
        guard !updates.isEmpty else { return }
        var byID: [UUID: (title: String?, summary: String?)] = [:]
        byID.reserveCapacity(updates.count)
        for u in updates {
            var merged = byID[u.id] ?? (nil, nil)
            if let t = u.title { merged.title = t }
            if let s = u.summary { merged.summary = s }
            byID[u.id] = merged
        }
        var changed = false
        for i in feeds.indices {
            for j in feeds[i].articles.indices {
                let id = feeds[i].articles[j].id
                guard let patch = byID[id] else { continue }
                if let t = patch.title {
                    feeds[i].articles[j].translatedTitle = t
                    changed = true
                }
                if let s = patch.summary {
                    feeds[i].articles[j].translatedSummary = s
                    changed = true
                }
            }
        }
        if changed { saveToStorage() }
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
        let days = max(0, readRetentionDays)
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 24 * 3600)
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

    func pruneFullContentCache() {
        let days = max(0, fullContentCacheDays)
        if days == 0 { return }
        OfflineCache.pruneArticleHTML(maxAge: TimeInterval(days) * 24 * 3600)
    }

    func refreshFeed(_ feedID: UUID) async {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        let urlStr = feeds[idx].url
        guard let url = URL(string: urlStr) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            OfflineCache.saveFeedXML(url: urlStr, data: data)
            applyParsedFeed(data: data, feedID: feedID, idx: idx, urlStr: urlStr)
        } catch {
            if let cached = OfflineCache.loadFeedXML(url: urlStr) {
                applyParsedFeed(data: cached, feedID: feedID, idx: idx, urlStr: urlStr)
                errorMessage = "网络不可用，已使用本地缓存"
            } else {
                errorMessage = "网络不可用，且无本地缓存：\(error.localizedDescription)"
            }
        }
    }

    private func applyParsedFeed(data: Data, feedID: UUID, idx: Int, urlStr: String) {
        let parsed = FeedParser.parse(data: data, feedID: feedID, feedTitle: feeds[idx].title)
        let existingKeys = Set(feeds[idx].articles.map { Self.canonicalLink($0.link) })
        var newArticles: [Article] = []
        for var article in parsed {
            let key = Self.canonicalLink(article.link)
            if key.isEmpty || existingKeys.contains(key) { continue }
            if readArticleLinks.contains(key) { article.isRead = true }
            if let html = OfflineCache.loadArticleHTML(link: article.link), !html.isEmpty {
                article.content = html
                article.hasFullContent = true
            }
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
            if isFallbackOnly || fromFeed { feeds[idx].faviconURL = resolved }
        }
        purgeOldReadArticles()
        pruneFullContentCache()
        saveToStorage()
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

    func fetchFullContent(for article: Article) async throws -> Article {
        if article.hasFullContent, !article.content.isEmpty {
            OfflineCache.saveArticleHTML(link: article.link, html: article.content)
            return article
        }
        if let cached = OfflineCache.loadArticleHTML(link: article.link), !cached.isEmpty {
            var updated = article
            updated.content = cached
            updated.hasFullContent = true
            updateArticle(updated)
            return updated
        }
        let result = try await ArticleContentFetcher.fetchFullContent(from: article.link)
        var updated = article
        updated.content = result.contentHTML
        updated.hasFullContent = true
        OfflineCache.saveArticleHTML(link: article.link, html: result.contentHTML)
        updateArticle(updated)
        return updated
    }

    func cacheSizeDescription() -> String {
        OfflineCache.formattedSize(OfflineCache.contentCacheSize())
    }

    func clearOfflineContentCache() {
        OfflineCache.clearContentCache()
    }

    private static func xmlEscape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "\u{0026}amp;")
            .replacingOccurrences(of: "\"", with: "\u{0026}quot;")
            .replacingOccurrences(of: "<", with: "\u{0026}lt;")
            .replacingOccurrences(of: ">", with: "\u{0026}gt;")
    }

    func exportOPML() -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<opml version=\"2.0\">\n  <head><title>Feed Subscriptions</title></head>\n  <body>\n"
        for feed in feeds {
            let t = Self.xmlEscape(feed.title)
            let u = Self.xmlEscape(feed.url)
            xml += "    <outline type=\"rss\" text=\"\(t)\" xmlUrl=\"\(u)\"/>\n"
        }
        xml += "  </body>\n</opml>"
        return xml
    }

    func importOPML(data: Data) {
        _ = importSubscriptions(data: data)
    }

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
                feeds.append(RSSFeed(title: title, url: url, faviconURL: FeedParser.siteFaviconURL(for: url)))
                added += 1
            }
            if added > 0 { saveToStorage() }
            return SubscriptionImportResult(added: added, skipped: skipped, kind: "opml")
        }

        // Single RSS/Atom XML: extract channel/feed link + title
        if let link = FeedParser.extractFeedLink(from: data), !link.isEmpty {
            let url = FeedURL.canonical(link)
            if feeds.contains(where: { FeedURL.canonical($0.url) == url }) {
                return SubscriptionImportResult(added: 0, skipped: 1, kind: "rss")
            }
            let title = FeedNaming.resolveTitle(parsed: FeedParser.extractFeedTitle(from: data), url: url)
            let favicon = FeedParser.resolveFaviconURL(from: data, feedURL: url) ?? FeedParser.siteFaviconURL(for: url)
            feeds.append(RSSFeed(title: title, url: url, faviconURL: favicon))
            saveToStorage()
            return SubscriptionImportResult(added: 1, skipped: 0, kind: "rss")
        }

        return SubscriptionImportResult(added: 0, skipped: 0, kind: "empty")
    }

    func saveToStorage() {
        OfflineCache.saveFeeds(feeds)
        persistReadLinks()
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
        UserDefaults.standard.set(listTitleFontSize, forKey: "listTitleFontSize")
        UserDefaults.standard.set(listSummaryFontSize, forKey: "listSummaryFontSize")
        UserDefaults.standard.set(readerTitleFontSize, forKey: "readerTitleFontSize")
        UserDefaults.standard.set(aiSummaryFontSize, forKey: "aiSummaryFontSize")
        UserDefaults.standard.set(feedTitleFontSize, forKey: "feedTitleFontSize")
        UserDefaults.standard.set(titleDisplayMode.rawValue, forKey: "titleDisplayMode")
        UserDefaults.standard.set(defaultTranslationEngine.rawValue, forKey: "defaultTranslationEngine")
        UserDefaults.standard.set(showReadArticles, forKey: "showReadArticles")
        UserDefaults.standard.set(translationPrompt, forKey: "translationPrompt")
        UserDefaults.standard.set(summaryPrompt, forKey: "summaryPrompt")
        UserDefaults.standard.set(readRetentionDays, forKey: "readRetentionDays")
        UserDefaults.standard.set(fullContentCacheDays, forKey: "fullContentCacheDays")
        if let data = try? JSONEncoder().encode(aiProviders) {
            UserDefaults.standard.set(data, forKey: "aiProviders")
        }
        if let id = defaultSummaryProviderID {
            UserDefaults.standard.set(id.uuidString, forKey: "defaultSummaryProviderID")
        }
        if let id = defaultTranslationProviderID {
            UserDefaults.standard.set(id.uuidString, forKey: "defaultTranslationProviderID")
        }
    }

    func loadFromStorage() {
        if let loaded = OfflineCache.loadFeeds() {
            feeds = loaded
        }
        loadReadLinks()
        fontSize = UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 17
        listTitleFontSize = UserDefaults.standard.object(forKey: "listTitleFontSize") as? Double ?? 18
        listSummaryFontSize = UserDefaults.standard.object(forKey: "listSummaryFontSize") as? Double ?? 15
        readerTitleFontSize = UserDefaults.standard.object(forKey: "readerTitleFontSize") as? Double ?? 24
        aiSummaryFontSize = UserDefaults.standard.object(forKey: "aiSummaryFontSize") as? Double ?? 22
        feedTitleFontSize = UserDefaults.standard.object(forKey: "feedTitleFontSize") as? Double ?? 17
        if let raw = UserDefaults.standard.string(forKey: "titleDisplayMode"),
           let mode = TitleDisplayMode(rawValue: raw) {
            titleDisplayMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: "defaultTranslationEngine"),
           let engine = TranslationEngine(rawValue: raw) {
            defaultTranslationEngine = engine
        }
        showReadArticles = UserDefaults.standard.object(forKey: "showReadArticles") as? Bool ?? false
        if let p = UserDefaults.standard.string(forKey: "translationPrompt") { translationPrompt = p }
        if let p = UserDefaults.standard.string(forKey: "summaryPrompt") { summaryPrompt = p }
        readRetentionDays = UserDefaults.standard.object(forKey: "readRetentionDays") as? Int ?? 7
        fullContentCacheDays = UserDefaults.standard.object(forKey: "fullContentCacheDays") as? Int ?? 30
        if let data = UserDefaults.standard.data(forKey: "aiProviders"),
           let decoded = try? JSONDecoder().decode([AIProvider].self, from: data) {
            aiProviders = decoded
        }
        if let s = UserDefaults.standard.string(forKey: "defaultSummaryProviderID"),
           let id = UUID(uuidString: s) {
            defaultSummaryProviderID = id
        }
        if let s = UserDefaults.standard.string(forKey: "defaultTranslationProviderID"),
           let id = UUID(uuidString: s) {
            defaultTranslationProviderID = id
        }
    }

    private func seedSampleData() {}
}
