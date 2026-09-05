import Foundation

// MARK: - App Version

enum AppVersion {
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
    }
    static var githubBuild: String? {
        let v = Bundle.main.infoDictionary?["IosRssGitHubBuild"] as? String
        guard let v, !v.isEmpty else { return nil }
        return v
    }
    static var display: String {
        if let g = githubBuild {
            return "v\(marketing)-\(build)-build\(g)"
        }
        return "v\(marketing)-\(build)"
    }
}

// MARK: - Core Models

/// 订阅源分组（类似文件夹）
struct FeedGroup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var sortOrder: Int = 0

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: FeedGroup, rhs: FeedGroup) -> Bool { lhs.id == rhs.id }
}

struct RSSFeed: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var faviconURL: String?
    var unreadCount: Int = 0
    var articles: [Article] = []
    var lastFetched: Date?
    /// 所属分组；nil = 未分组
    var groupID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, title, url, faviconURL, unreadCount, articles, lastFetched, groupID
    }

    init(id: UUID = UUID(), title: String, url: String, faviconURL: String? = nil,
         unreadCount: Int = 0, articles: [Article] = [], lastFetched: Date? = nil,
         groupID: UUID? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.faviconURL = faviconURL
        self.unreadCount = unreadCount
        self.articles = articles
        self.lastFetched = lastFetched
        self.groupID = groupID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(String.self, forKey: .url)
        faviconURL = try c.decodeIfPresent(String.self, forKey: .faviconURL)
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        articles = try c.decodeIfPresent([Article].self, forKey: .articles) ?? []
        lastFetched = try c.decodeIfPresent(Date.self, forKey: .lastFetched)
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
    }

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
    var isFavorite: Bool = false
    var translatedTitle: String?
    var translatedSummary: String?
    var translatedContent: String?
    var aiSummary: String?
    var hasFullContent: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, feedID, feedTitle, title, link, summary, content
        case publishedDate, isRead, isFavorite, translatedTitle, translatedSummary, translatedContent, aiSummary, hasFullContent
    }

    init(id: UUID = UUID(), feedID: UUID, feedTitle: String, title: String, link: String,
         summary: String, content: String, publishedDate: Date? = nil, isRead: Bool = false,
         isFavorite: Bool = false,
         translatedTitle: String? = nil, translatedSummary: String? = nil,
         translatedContent: String? = nil, aiSummary: String? = nil,
         hasFullContent: Bool = false) {
        self.id = id
        self.feedID = feedID
        self.feedTitle = feedTitle
        self.title = title
        self.link = link
        self.summary = summary
        self.content = content
        self.publishedDate = publishedDate
        self.isRead = isRead
        self.isFavorite = isFavorite
        self.translatedTitle = translatedTitle
        self.translatedSummary = translatedSummary
        self.translatedContent = translatedContent
        self.aiSummary = aiSummary
        self.hasFullContent = hasFullContent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        feedID = try c.decode(UUID.self, forKey: .feedID)
        feedTitle = try c.decode(String.self, forKey: .feedTitle)
        title = try c.decode(String.self, forKey: .title)
        link = try c.decode(String.self, forKey: .link)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        publishedDate = try c.decodeIfPresent(Date.self, forKey: .publishedDate)
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        translatedTitle = try c.decodeIfPresent(String.self, forKey: .translatedTitle)
        translatedSummary = try c.decodeIfPresent(String.self, forKey: .translatedSummary)
        translatedContent = try c.decodeIfPresent(String.self, forKey: .translatedContent)
        aiSummary = try c.decodeIfPresent(String.self, forKey: .aiSummary)
        hasFullContent = try c.decodeIfPresent(Bool.self, forKey: .hasFullContent) ?? false
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Article, rhs: Article) -> Bool { lhs.id == rhs.id }

    var relativeTime: String {
        guard let date = publishedDate else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 3600 { return "\(Int(diff / 60))分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600))小时前" }
        return "\(Int(diff / 86400))天前"
    }

    var needsFullContentFetch: Bool {
        if hasFullContent { return false }
        let plain = HTMLUtils.stripTags(content)
        return plain.count < 400
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
    case deepl = "DeepL"
    case ai = "AI 翻译"
}

struct AIProvider: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var baseURL: String
    var model: String
    var kind: String = "openai"
    var isDefaultSummary: Bool = false
    var isDefaultTranslation: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, model, kind, isDefaultSummary, isDefaultTranslation
    }

    init(id: UUID = UUID(), name: String, baseURL: String, model: String, kind: String = "openai",
         isDefaultSummary: Bool = false, isDefaultTranslation: Bool = false) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.kind = kind
        self.isDefaultSummary = isDefaultSummary
        self.isDefaultTranslation = isDefaultTranslation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        model = try c.decode(String.self, forKey: .model)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "openai"
        isDefaultSummary = try c.decodeIfPresent(Bool.self, forKey: .isDefaultSummary) ?? false
        isDefaultTranslation = try c.decodeIfPresent(Bool.self, forKey: .isDefaultTranslation) ?? false
        if name.lowercased().contains("gemini") { kind = "gemini" }
    }

    static let openAITemplate = AIProvider(
        name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", kind: "openai"
    )
    static let anthropicTemplate = AIProvider(
        name: "Anthropic", baseURL: "https://api.anthropic.com/v1", model: "claude-3-haiku-20240307", kind: "openai"
    )
    static let geminiTemplate = AIProvider(
        name: "Gemini",
        baseURL: "https://generativelanguage.googleapis.com/v1beta",
        model: "gemini-2.0-flash",
        kind: "gemini"
    )
}

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

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var i = startIndex
        while i < endIndex {
            let j = index(i, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[i..<j]))
            i = j
        }
        return result
    }
}

struct SubscriptionImportResult {
    var added: Int = 0
    var skipped: Int = 0
    var kind: String = ""
}

enum FeedURL {
    static func canonical(_ raw: String) -> String {
        var s = HTMLUtils.decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("feed://") {
            s = "https://" + String(s.dropFirst(7))
        }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s
    }
}
