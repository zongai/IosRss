import Foundation

// MARK: - Core Models

struct RSSFeed: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var faviconURL: String?
    var unreadCount: Int = 0
    var articles: [Article] = []
    var lastFetched: Date?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: RSSFeed, rhs: RSSFeed) -> Bool { lhs.id == rhs.id }
}

struct Article: Identifiable, Codable, Hashable {
    var id = UUID()
    var feedID: UUID
    var feedTitle: String
    var title: String
    var link: String
    var summary: String
    var content: String
    var publishedDate: Date?
    var isRead: Bool = false
    var translatedTitle: String?
    var translatedContent: String?
    var aiSummary: String?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Article, rhs: Article) -> Bool { lhs.id == rhs.id }

    var relativeTime: String {
        guard let date = publishedDate else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 3600 { return "\(Int(diff / 60))分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600))小时前" }
        return "\(Int(diff / 86400))天前"
    }
}

enum TitleDisplayMode: String, CaseIterable, Codable {
    case original = "原文"
    case translated = "译文"
    case bilingual = "双语对照"
}

enum TranslationEngine: String, CaseIterable, Codable {
    case google = "Google 翻译"
    case microsoft = "Microsoft 翻译"
    case deepl = "DeepL"   // 新增
    case gemini = "Gemini" 
    case ai = "AI 翻译"
}

// MARK: - AI Provider

struct AIProvider: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var baseURL: String
    var model: String
    var isDefaultSummary: Bool = false
    var isDefaultTranslation: Bool = false

    static let openAITemplate = AIProvider(
        name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini"
    )
    static let anthropicTemplate = AIProvider(
        name: "Anthropic", baseURL: "https://api.anthropic.com/v1", model: "claude-3-haiku-20240307"
    )
}

// MARK: - Keychain Helper (UserDefaults-backed, base64-encoded)

enum Keychain {
    private static let prefix = "feed_kc_"

    static func save(key: String, value: String) {
        let encoded = Data(value.utf8).base64EncodedString()
        UserDefaults.standard.set(encoded, forKey: prefix + key)
    }

    static func load(key: String) -> String? {
        guard let encoded = UserDefaults.standard.string(forKey: prefix + key),
              let data = Data(base64Encoded: encoded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        UserDefaults.standard.removeObject(forKey: prefix + key)
    }
}
