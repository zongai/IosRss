import Foundation
import SwiftUI

@Observable
@MainActor
class AppStore {
    var feeds: [RSSFeed] = []
    var selectedFeedID: UUID?
    var isLoading = false
    var errorMessage: String?

    // Settings
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

    /// 已读文章保留天数，超过后自动清理
    private let readArticleRetentionDays: TimeInterval = 7 * 24 * 3600

    init() {
        loadFromStorage()
        if feeds.isEmpty {
            seedSampleData()
        }
        // 兼容旧数据：若存在 gemini 引擎偏好，迁移到 AI
        if UserDefaults.standard.string(forKey: "defaultTranslationEngine") == "Gemini" {
            defaultTranslationEngine = .ai
            if defaultTranslationProviderID == nil {
                defaultTranslationProviderID = aiProviders.first(where: { $0.kind == "gemini" })?.id
            }
        }
        if defaultSummaryProviderID == nil {
            defaultSummaryProviderID = aiProviders.first?.id
        }
        // 启动时清理过期已读文章
        purgeOldReadArticles()
    }

    var allArticles: [Article] {
        feeds.flatMap { $0.articles }.sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
    }

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
            }
        }
        saveToStorage()
    }

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

    /// 删除超过保留期的已读文章
    func purgeOldReadArticles() {
        let cutoff = Date().addingTimeInterval(-readArticleRetentionDays)
        var changed = false
        for i in feeds.indices {
            let before = feeds[i].articles.count
            feeds[i].articles.removeAll { article in
                guard article.isRead else { return false }
                // 优先用发布时间，没有则视为可清理（已读且无日期）
                if let date = article.publishedDate {
                    return date < cutoff
                }
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
            let existing = Set(feeds[idx].articles.map { $0.link })
            let newArticles = parsed.filter { !existing.contains($0.link) }
            feeds[idx].articles.insert(contentsOf: newArticles, at: 0)
            feeds[idx].unreadCount = feeds[idx].articles.filter { !$0.isRead }.count
            feeds[idx].lastFetched = Date()
            purgeOldReadArticles()
            saveToStorage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAll() async {
        for feed in feeds {
            await refreshFeed(feed.id)
        }
    }

    // MARK: - Translation

    func translateText(_ text: String) async throws -> String {
        switch defaultTranslationEngine {
        case .google:
            return try await GoogleTranslate.translate(text: text)
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
            return try await AITranslate.translate(text: text, provider: provider, apiKey: key)
        }
    }

    /// 分批翻译多段短文本（列表标题/预览），保持输入顺序；失败项为 nil
    func translateTexts(_ texts: [String], concurrency: Int? = nil) async -> [String?] {
        guard !texts.isEmpty else { return [] }
        let engine = defaultTranslationEngine
        let limit = concurrency ?? defaultListConcurrency(for: engine)

        switch engine {
        case .deepl:
            let key = Keychain.load(key: "deepl_translate_key") ?? ""
            return await translateNativeBatch(texts, chunkSize: 40) { chunk in
                try await DeepLTranslate.translate(texts: chunk, apiKey: key)
            }
        case .microsoft:
            let key = Keychain.load(key: "microsoft_translate_key") ?? ""
            return await translateNativeBatch(texts, chunkSize: 40) { chunk in
                try await MicrosoftTranslate.translate(texts: chunk, apiKey: key)
            }
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

    private func translateNativeBatch(
        _ texts: [String],
        chunkSize: Int,
        call: ([String]) async throws -> [String]
    ) async -> [String?] {
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

    /// 按长度分段翻译，支持并发；返回完整译文
    func translateLongText(_ text: String, maxChunkChars: Int = 1800) async throws -> String {
        let chunks = Self.splitTextIntoChunks(text, maxChars: maxChunkChars)
        guard !chunks.isEmpty else { return "" }
        if chunks.count == 1 {
            return try await translateText(chunks[0])
        }
        // 并发翻译各段
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    let result = try await self.translateText(chunk)
                    return (index, result)
                }
            }
            var ordered = Array(repeating: "", count: chunks.count)
            for try await (index, result) in group {
                ordered[index] = result
            }
            return ordered.joined(separator: "\n\n")
        }
    }

    /// 尽量按段落边界切分，避免在句子中间切断
    static func splitTextIntoChunks(_ text: String, maxChars: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.count <= maxChars { return [trimmed] }

        var chunks: [String] = []
        var current = ""
        // 按换行优先，其次按句号/问号等
        let paragraphs = trimmed.components(separatedBy: CharacterSet.newlines)

        for para in paragraphs {
            let p = para.trimmingCharacters(in: .whitespaces)
            if p.isEmpty { continue }
            if current.isEmpty {
                if p.count > maxChars {
                    // 超长段落再按句子切
                    chunks.append(contentsOf: splitBySentence(p, maxChars: maxChars))
                } else {
                    current = p
                }
            } else if current.count + p.count + 1 <= maxChars {
                current += "\n" + p
            } else {
                chunks.append(current)
                if p.count > maxChars {
                    chunks.append(contentsOf: splitBySentence(p, maxChars: maxChars))
                    current = ""
                } else {
                    current = p
                }
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
                if current.count + buffer.count <= maxChars {
                    current += buffer
                } else {
                    if !current.isEmpty { result.append(current) }
                    current = buffer
                }
                buffer = ""
            }
        }
        if !buffer.isEmpty {
            if current.count + buffer.count <= maxChars {
                current += buffer
            } else {
                if !current.isEmpty { result.append(current) }
                current = buffer
            }
        }
        if !current.isEmpty { result.append(current) }
        // 仍超长则硬切
        var final: [String] = []
        for piece in result {
            if piece.count <= maxChars {
                final.append(piece)
            } else {
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
        return try await AISummary.summarize(article: article, provider: provider, apiKey: key)
    }

    /// 从原文页抓取完整正文并写回文章
    @discardableResult
    func fetchFullContent(for article: Article) async throws -> Article {
        let result = try await ArticleContentFetcher.fetchFullContent(from: article.link)
        var updated = article
        updated.content = result.contentHTML
        updated.hasFullContent = true
        // 抓取全文后清空旧译文，避免与新正文不一致
        updated.translatedContent = nil
        updateArticle(updated)
        return updated
    }

    // MARK: - OPML

    func exportOPML() -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Feed Subscriptions</title></head>
          <body>
        """
        for feed in feeds {
            xml += "    <outline type=\"rss\" text=\"\(feed.title)\" xmlUrl=\"\(feed.url)\"/>\n"
        }
        xml += "  </body>\n</opml>"
        return xml
    }

    func importOPML(data: Data) {
        let parser = OPMLParser(data: data)
        let imported = parser.parse()
        for item in imported {
            if !feeds.contains(where: { $0.url == item.url }) {
                let title = FeedNaming.resolveTitle(parsed: item.title, url: item.url)
                let feed = RSSFeed(title: title, url: item.url)
                feeds.append(feed)
            }
        }
        saveToStorage()
    }

    // MARK: - Persistence

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
    }

    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: "feeds"),
           let decoded = try? JSONDecoder().decode([RSSFeed].self, from: data) {
            feeds = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "aiProviders"),
           let decoded = try? JSONDecoder().decode([AIProvider].self, from: data) {
            aiProviders = decoded
            // 兼容：旧数据没有 kind 字段时默认 openai；名称含 Gemini 的标为 gemini
            for i in aiProviders.indices {
                if aiProviders[i].kind.isEmpty {
                    aiProviders[i].kind = "openai"
                }
                if aiProviders[i].name.lowercased().contains("gemini") {
                    aiProviders[i].kind = "gemini"
                }
            }
        }
        fontSize = UserDefaults.standard.double(forKey: "fontSize").isZero ? 17 : UserDefaults.standard.double(forKey: "fontSize")
        if let raw = UserDefaults.standard.string(forKey: "titleDisplayMode") {
            titleDisplayMode = TitleDisplayMode(rawValue: raw) ?? .original
        }
        if let raw = UserDefaults.standard.string(forKey: "defaultTranslationEngine") {
            // 迁移旧的 Gemini 选项
            if raw == "Gemini" {
                defaultTranslationEngine = .ai
            } else {
                defaultTranslationEngine = TranslationEngine(rawValue: raw) ?? .google
            }
        }
        if let idStr = UserDefaults.standard.string(forKey: "defaultSummaryProviderID") {
            defaultSummaryProviderID = UUID(uuidString: idStr)
        }
        if let idStr = UserDefaults.standard.string(forKey: "defaultTranslationProviderID") {
            defaultTranslationProviderID = UUID(uuidString: idStr)
        }
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
                content: "<p>\(summaries[i])</p><p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.</p><p>Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident.</p>",
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
