import Foundation

// MARK: - App Version

enum AppVersion {
    /// 营销版本，如 1.2（MARKETING_VERSION）
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2"
    }
    /// 工程构建号，如 4（CURRENT_PROJECT_VERSION）
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
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
    /// 展示：CI 为 v1.2-4-build43；本地为 v1.2-4
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
