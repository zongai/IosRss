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
        AIProvider(id: UUID(), name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini"),
        AIProvider(id: UUID(), name: "Anthropic", baseURL: "https://api.anthropic.com/v1", model: "claude-3-haiku-20240307")
    ]
    var defaultSummaryProviderID: UUID?
    var defaultTranslationProviderID: UUID?

    init() {
        loadFromStorage()
        if feeds.isEmpty {
            seedSampleData()
        }
        defaultSummaryProviderID = aiProviders.first?.id
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
        case .deepl:                                                    // 新增
            let key = Keychain.load(key: "deepl_translate_key") ?? ""   // 新增
            return try await DeepLTranslate.translate(text: text, apiKey: key)  // 新增
        case .ai:
            guard let providerID = defaultTranslationProviderID ?? defaultSummaryProviderID,
                  let provider = aiProviders.first(where: { $0.id == providerID }) else {
                throw TranslationError.noProvider
            }
            let key = Keychain.load(key: "ai_key_\(provider.id)") ?? ""
            return try await AITranslate.translate(text: text, provider: provider, apiKey: key)
        }
    }

    func generateSummary(for article: Article) async throws -> String {
        guard let providerID = defaultSummaryProviderID,
              let provider = aiProviders.first(where: { $0.id == providerID }) else {
            throw TranslationError.noProvider
        }
        let key = Keychain.load(key: "ai_key_\(provider.id)") ?? ""
        return try await AISummary.summarize(article: article, provider: provider, apiKey: key)
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
                var feed = RSSFeed(title: item.title, url: item.url)
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
        }
        fontSize = UserDefaults.standard.double(forKey: "fontSize").isZero ? 17 : UserDefaults.standard.double(forKey: "fontSize")
        if let raw = UserDefaults.standard.string(forKey: "titleDisplayMode") {
            titleDisplayMode = TitleDisplayMode(rawValue: raw) ?? .original
        }
        if let raw = UserDefaults.standard.string(forKey: "defaultTranslationEngine") {
            defaultTranslationEngine = TranslationEngine(rawValue: raw) ?? .google
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
