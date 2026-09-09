import Foundation
import Security

// MARK: - App Version

enum AppVersion {
    /// 营销版本，如 1.3（MARKETING_VERSION）
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3"
    }
    /// 工程构建号，如 10（CURRENT_PROJECT_VERSION）
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "24"
    }
    /// CI 在编译前写入 run_number；本地为空字符串
    /// 勿改字面量格式，build.yml 依赖此行做 sed 替换
    static let githubBuildNumber: String = ""
    /// GitHub Actions run_number（优先编译期常量，其次 Info.plist）
    static var githubBuild: String? {
        if !githubBuildNumber.isEmpty { return githubBuildNumber }
        for key in ["IosRssGitHubBuild", "GitHubBuild", "CI_BUILD_NUMBER"] {
            if let v = Bundle.main.infoDictionary?[key] as? String, !v.isEmpty { return v }
            if let n = Bundle.main.infoDictionary?[key] as? NSNumber { return n.stringValue }
        }
        return nil
    }
    /// 展示：CI 为 v1.3-24-build43；本地为 v1.3-24
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
    /// 是否对该源自动/手动抓取全文；默认开启
    var fetchFullContentEnabled: Bool = true
    /// 是否在阅读页提供「评论」入口（如 Substack）；默认关闭
    var fetchCommentsEnabled: Bool = false
    /// 是否已对该源执行过图标获取（成功或失败后均为 true，后台用）
    var faviconFetchDone: Bool = false
    /// 列表进入时是否自动翻译非目标语言且未译条目
    var autoTranslateEnabled: Bool = true
    /// 同组内排序（越小越靠前）
    var sortOrder: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, title, url, faviconURL, unreadCount, articles, lastFetched, groupID
        case fetchFullContentEnabled, fetchCommentsEnabled, faviconFetchDone, autoTranslateEnabled, sortOrder
    }

    init(id: UUID = UUID(), title: String, url: String, faviconURL: String? = nil,
         unreadCount: Int = 0, articles: [Article] = [], lastFetched: Date? = nil,
         groupID: UUID? = nil, fetchFullContentEnabled: Bool = true,
         fetchCommentsEnabled: Bool = false,
         faviconFetchDone: Bool = false,
         autoTranslateEnabled: Bool = true,
         sortOrder: Int = 0) {
        self.id = id
        self.title = title
        self.url = url
        self.faviconURL = faviconURL
        self.unreadCount = unreadCount
        self.articles = articles
        self.lastFetched = lastFetched
        self.groupID = groupID
        self.fetchFullContentEnabled = fetchFullContentEnabled
        self.fetchCommentsEnabled = fetchCommentsEnabled
        self.faviconFetchDone = faviconFetchDone
        self.autoTranslateEnabled = autoTranslateEnabled
        self.sortOrder = sortOrder
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
        fetchFullContentEnabled = try c.decodeIfPresent(Bool.self, forKey: .fetchFullContentEnabled) ?? true
        fetchCommentsEnabled = try c.decodeIfPresent(Bool.self, forKey: .fetchCommentsEnabled) ?? false
        faviconFetchDone = try c.decodeIfPresent(Bool.self, forKey: .faviconFetchDone) ?? false
        autoTranslateEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoTranslateEnabled) ?? true
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
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
    /// 生成该摘要时使用的 AI Provider 名称
    var aiSummaryProvider: String?
    /// 是否已从原文页抓取过全文
    var hasFullContent: Bool = false
    /// RSS/Atom `<comments>` 讨论页（如 HN item），优先于 link 抓评论
    var commentsURL: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, feedID, feedTitle, title, link, summary, content
        case publishedDate, isRead, isFavorite, translatedTitle, translatedSummary, translatedContent
        case aiSummary, aiSummaryProvider, hasFullContent, commentsURL
    }

    init(id: UUID = UUID(), feedID: UUID, feedTitle: String, title: String, link: String,
         summary: String, content: String, publishedDate: Date? = nil, isRead: Bool = false,
         isFavorite: Bool = false,
         translatedTitle: String? = nil, translatedSummary: String? = nil,
         translatedContent: String? = nil, aiSummary: String? = nil,
         aiSummaryProvider: String? = nil,
         hasFullContent: Bool = false,
         commentsURL: String? = nil) {
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
        self.aiSummaryProvider = aiSummaryProvider
        self.hasFullContent = hasFullContent
        self.commentsURL = commentsURL
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
        aiSummaryProvider = try c.decodeIfPresent(String.self, forKey: .aiSummaryProvider)
        hasFullContent = try c.decodeIfPresent(Bool.self, forKey: .hasFullContent) ?? false
        commentsURL = try c.decodeIfPresent(String.self, forKey: .commentsURL)
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

    /// RSS 摘要是否偏短，适合触发全文抓取（不检查源级开关）
    var needsFullContentFetch: Bool {
        if hasFullContent { return false }
        let plain = HTMLUtils.stripTags(content)
        return plain.count < 400
    }
}

/// 订阅源列表排序
enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case zhHans, zhHant, en, ja, ko, fr, de, es

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }

    /// Google Translate `tl`
    var googleCode: String {
        switch self {
        case .zhHans: return "zh-CN"
        case .zhHant: return "zh-TW"
        case .en: return "en"
        case .ja: return "ja"
        case .ko: return "ko"
        case .fr: return "fr"
        case .de: return "de"
        case .es: return "es"
        }
    }

    /// Microsoft Translator `to`
    var microsoftCode: String {
        switch self {
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        default: return googleCode
        }
    }

    /// DeepL `target_lang`
    var deeplCode: String {
        switch self {
        case .zhHans, .zhHant: return "ZH"
        case .en: return "EN"
        case .ja: return "JA"
        case .ko: return "KO"
        case .fr: return "FR"
        case .de: return "DE"
        case .es: return "ES"
        }
    }

    /// 写入 AI Prompt 的语言称呼
    var promptLabel: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "French"
        case .de: return "German"
        case .es: return "Spanish"
        }
    }

    var isChinese: Bool { self == .zhHans || self == .zhHant }
}

enum FeedSortMode: String, CaseIterable, Codable, Identifiable {
    case unreadThenTitle
    case title
    case lastFetched
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unreadThenTitle: return "未读优先（自动）"
        case .title: return "名称"
        case .lastFetched: return "最近更新"
        case .manual: return "手动排序"
        }
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
    case ai = "AI 翻译"   // Gemini / OpenAI / Anthropic 等统一走 AI Provider
}

// MARK: - AI Provider

struct AIProvider: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var baseURL: String
    var model: String
    /// 特殊标识：gemini 走 Google Generative Language API，其余走 OpenAI 兼容接口
    var kind: String = "openai" // "openai" | "gemini"
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

// MARK: - Keychain (Security.framework; migrates legacy UserDefaults Base64)

enum Keychain {
    private static let service = "com.example.IosRss.keys"
    private static let legacyPrefix = "feed_kc_"

    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        // 清除旧版明文/Base64 备份
        UserDefaults.standard.removeObject(forKey: legacyPrefix + key)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data,
           let s = String(data: data, encoding: .utf8), !s.isEmpty {
            return s
        }
        // 迁移：旧 UserDefaults Base64
        if let encoded = UserDefaults.standard.string(forKey: legacyPrefix + key),
           let data = Data(base64Encoded: encoded),
           let s = String(data: data, encoding: .utf8), !s.isEmpty {
            save(key: key, value: s)
            return s
        }
        return nil
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: legacyPrefix + key)
    }
}

// MARK: - Collection helpers

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

// MARK: - Import result

struct SubscriptionImportResult {
    var added: Int = 0
    var skipped: Int = 0
    var kind: String = "" // "opml" | "rss" | "empty"
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
