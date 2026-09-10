import Foundation
import SwiftUI

@Observable
@MainActor
class AppStore {
    var feeds: [RSSFeed] = []
    var groups: [FeedGroup] = []
    var collapsedGroupIDs: Set<UUID> = []
    var isUngroupedCollapsed: Bool = false
    var selectedFeedID: UUID?
    var isLoading = false
    var isRefreshingAll = false
    var refreshProgressCurrent = 0
    var refreshProgressTotal = 0
    var refreshProgressTitle = ""
    var errorMessage: String?

    var fontSize: Double = 17
    var listTitleFontSize: Double = 18
    var listSummaryFontSize: Double = 15
    var readerTitleFontSize: Double = 24
    var aiSummaryFontSize: Double = 22
    var feedTitleFontSize: Double = 17
    var groupTitleFontSize: Double = 13

    var titleDisplayMode: TitleDisplayMode = .original
    var defaultTranslationEngine: TranslationEngine = .google
    var aiProviders: [AIProvider] = [
        AIProvider(id: UUID(), name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", kind: "openai"),
        AIProvider(id: UUID(), name: "Anthropic", baseURL: "https://api.anthropic.com/v1", model: "claude-3-haiku-20240307", kind: "openai"),
        AIProvider(id: UUID(), name: "Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta", model: "gemini-2.0-flash", kind: "gemini")
    ]
    var defaultSummaryProviderID: UUID?
    var defaultTranslationProviderID: UUID?
    var defaultExplainProviderID: UUID?
    var aiBlacklistTerms: [String] = []
    /// 文章黑名单：标题/摘要命中则自动标为已读（与 AI 黑名单独立）
    var articleBlacklistTerms: [String] = []
    var aiBlacklistFallbackProviderID: UUID?
    var showReadArticles: Bool = false
    var translationPrompt: String = AppStore.defaultTranslationPrompt
    var summaryPrompt: String = AppStore.defaultSummaryPrompt
    var explainPrompt: String = AppStore.defaultExplainPrompt
    var readRetentionDays: Int = 7
    var fullContentCacheDays: Int = 30
    /// Edge TTS 音色；空则按正文语言自动选择
    var ttsVoice: String = ""
    /// TTS 语速倍数，1.0 为正常（0.5～2.0）
    var ttsRate: Double = 1.2
    /// 阅读主题色板
    var colorTheme: ReadingTheme = .classicLight
    /// 外观：跟随系统 / 浅色 / 深色
    var appearanceMode: AppearanceMode = .system
    /// 界面与阅读字体
    var appFontFamily: AppFontFamily = .system
    /// 订阅源排序方式（默认未读优先自动排序）
    var feedSortMode: FeedSortMode = .unreadThenTitle
    /// 翻译目标语言
    var targetLanguage: AppLanguage = .zhHans
    /// 翻译并发度：0=自动（按引擎），1～8 为固定并发；AI 多 Provider 时还会跨 Provider 分片
    var translationConcurrency: Int = 0
    /// AI 摘要/解释等输出语言
    var aiOutputLanguage: AppLanguage = .zhHans
    /// Azure Translator 区域（eastasia / eastus / global 等）
    var microsoftTranslateRegion: String = "global"

    static let defaultTranslationPrompt = """
你是专业译者。将下面内容翻译成{{lang}}。

要求：
- 只输出译文，不要前言、注释、双语对照或「译文如下」之类说明
- 忠实原意，专有名词可保留原文或通用译法
- 保持段落与换行；不要添加原文没有的标题或列表序号
- 若原文含 [[IMG_数字]] 等占位符，原样保留

{{text}}
"""

    static let defaultSummaryPrompt = """
你是资讯编辑。用{{lang}}概括下面文章，帮助读者快速抓住要点。

要求：
- 输出 3～5 条要点，每条单独一行
- 不要使用 1. 2. 3.、-、• 等序号或项目符号
- 不要标题、不要「总结如下」等套话
- 优先写事实与结论，少写修辞；有争议观点时注明是谁的看法
- 总长控制在约 120～220 字（或等量信息）

标题：{{title}}

正文：
{{content}}
"""

    static let defaultExplainPrompt = """
你是知识助手。用简洁的{{lang}}解释用户选中的文字。

要求：
- 只输出解释本身：词义、专有名词、背景或在语境中的含义
- 2～6 句为宜，可分段；不要标题，不要复述整段原文
- 不确定时说明不确定，不要编造
- 不要推荐产品或扩展无关话题

选中文字：
{{text}}
"""


    private var readArticleLinks: Set<String> = []

    init() {
        loadFromStorage()
        _ = applyArticleBlacklist()
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
        if defaultExplainProviderID == nil {
            defaultExplainProviderID = defaultSummaryProviderID ?? aiProviders.first?.id
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
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                if !feeds[i].articles[j].isRead {
                    feeds[i].articles[j].isRead = true
                    feeds[i].unreadCount = max(0, feeds[i].articles.filter { !$0.isRead }.count)
                }
                rememberReadLink(feeds[i].articles[j].link)
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

    func applyListTranslations(_ updates: [(id: UUID, title: String?, summary: String?)]) {
        guard !updates.isEmpty else { return }
        var byID: [UUID: (title: String?, summary: String?)] = [:]
        for u in updates {
            var merged = byID[u.id] ?? (nil, nil)
            if let t = u.title { merged.title = t }
            if let s = u.summary { merged.summary = s }
            byID[u.id] = merged
        }
        var changed = false
        for i in feeds.indices {
            for j in feeds[i].articles.indices {
                guard let patch = byID[feeds[i].articles[j].id] else { continue }
                if let t = patch.title { feeds[i].articles[j].translatedTitle = t; changed = true }
                if let s = patch.summary { feeds[i].articles[j].translatedSummary = s; changed = true }
            }
        }
        if changed { saveToStorage() }
    }

    func addFeed(_ feed: RSSFeed) {
        var f = feed
        f.sortOrder = (feeds.map(\.sortOrder).max() ?? -1) + 1
        feeds.append(f)
        saveToStorage()
    }
    func deleteFeed(at offsets: IndexSet) { feeds.remove(atOffsets: offsets); saveToStorage() }

    func deleteAllFeeds() {
        feeds = []
        saveToStorage()
    }

    // MARK: - Settings export / import / AI probe

    struct SettingsExportPayload: Codable {
        var version: Int
        var fontSize: Double
        var listTitleFontSize: Double
        var listSummaryFontSize: Double
        var readerTitleFontSize: Double
        var aiSummaryFontSize: Double
        var feedTitleFontSize: Double
        var groupTitleFontSize: Double
        var titleDisplayMode: String
        var defaultTranslationEngine: String
        var showReadArticles: Bool
        var translationPrompt: String
        var summaryPrompt: String
        var explainPrompt: String
        var readRetentionDays: Int
        var fullContentCacheDays: Int
        var ttsVoice: String
        var ttsRate: Double?
        var colorTheme: String
        var appearanceMode: String?
        var aiBlacklistTerms: [String]
        var articleBlacklistTerms: [String]
        var defaultSummaryProviderID: UUID?
        var defaultTranslationProviderID: UUID?
        var defaultExplainProviderID: UUID?
        var aiBlacklistFallbackProviderID: UUID?
        var aiProviders: [AIProvider]
        var translationKeys: [String: String]?
        var aiKeys: [String: String]?
    }

    func exportSettingsJSON(includeSecrets: Bool = false) throws -> Data {
        let payload = SettingsExportPayload(
            version: 1,
            fontSize: fontSize,
            listTitleFontSize: listTitleFontSize,
            listSummaryFontSize: listSummaryFontSize,
            readerTitleFontSize: readerTitleFontSize,
            aiSummaryFontSize: aiSummaryFontSize,
            feedTitleFontSize: feedTitleFontSize,
            groupTitleFontSize: groupTitleFontSize,
            titleDisplayMode: titleDisplayMode.rawValue,
            defaultTranslationEngine: defaultTranslationEngine.rawValue,
            showReadArticles: showReadArticles,
            translationPrompt: translationPrompt,
            summaryPrompt: summaryPrompt,
            explainPrompt: explainPrompt,
            readRetentionDays: readRetentionDays,
            fullContentCacheDays: fullContentCacheDays,
            ttsVoice: ttsVoice,
            ttsRate: ttsRate,
            colorTheme: colorTheme.rawValue,
            appearanceMode: appearanceMode.rawValue,
            aiBlacklistTerms: aiBlacklistTerms,
            articleBlacklistTerms: articleBlacklistTerms,
            defaultSummaryProviderID: defaultSummaryProviderID,
            defaultTranslationProviderID: defaultTranslationProviderID,
            defaultExplainProviderID: defaultExplainProviderID,
            aiBlacklistFallbackProviderID: aiBlacklistFallbackProviderID,
            aiProviders: aiProviders,
            translationKeys: includeSecrets ? [
                "google_translate_key": Keychain.load(key: "google_translate_key") ?? "",
                "microsoft_translate_key": Keychain.load(key: "microsoft_translate_key") ?? "",
                "deepl_translate_key": loadDeepLKeys().joined(separator: "\n")
            ].filter { !$0.value.isEmpty } : nil,
            aiKeys: includeSecrets ? Dictionary(uniqueKeysWithValues: aiProviders.compactMap { p -> (String, String)? in
                let keys = loadAIKeys(for: p.id)
                guard !keys.isEmpty else { return nil }
                return (p.id.uuidString, keys.joined(separator: "\n"))
            }) : nil
        )
        return try JSONEncoder().encode(payload)
    }

    func importSettingsJSON(_ data: Data) throws {
        let payload = try JSONDecoder().decode(SettingsExportPayload.self, from: data)
        fontSize = payload.fontSize
        listTitleFontSize = payload.listTitleFontSize
        listSummaryFontSize = payload.listSummaryFontSize
        readerTitleFontSize = payload.readerTitleFontSize
        aiSummaryFontSize = payload.aiSummaryFontSize
        feedTitleFontSize = payload.feedTitleFontSize
        groupTitleFontSize = payload.groupTitleFontSize
        if let m = TitleDisplayMode(rawValue: payload.titleDisplayMode) { titleDisplayMode = m }
        if let e = TranslationEngine(rawValue: payload.defaultTranslationEngine) { defaultTranslationEngine = e }
        showReadArticles = payload.showReadArticles
        translationPrompt = payload.translationPrompt
        summaryPrompt = payload.summaryPrompt
        explainPrompt = payload.explainPrompt
        readRetentionDays = payload.readRetentionDays
        fullContentCacheDays = payload.fullContentCacheDays
        ttsVoice = payload.ttsVoice
        if let r = payload.ttsRate { ttsRate = min(2.0, max(0.5, r)) }
        if let th = ReadingTheme(rawValue: payload.colorTheme) {
            colorTheme = th
        } else {
            switch payload.colorTheme {
            case "azure": colorTheme = .classicLight
            case "sepia": colorTheme = .sepiaPaper
            case "midnight": colorTheme = .midnightBlue
            case "forest": colorTheme = .forestSage
            case "graphite": colorTheme = .nightDark
            default: break
            }
        }
        if let raw = payload.appearanceMode, let mode = AppearanceMode(rawValue: raw) { appearanceMode = mode }
        aiBlacklistTerms = payload.aiBlacklistTerms
        articleBlacklistTerms = payload.articleBlacklistTerms
        defaultSummaryProviderID = payload.defaultSummaryProviderID
        defaultTranslationProviderID = payload.defaultTranslationProviderID
        defaultExplainProviderID = payload.defaultExplainProviderID
        aiBlacklistFallbackProviderID = payload.aiBlacklistFallbackProviderID
        if !payload.aiProviders.isEmpty { aiProviders = payload.aiProviders }
        for (k, v) in (payload.translationKeys ?? [:]) where !v.isEmpty {
            if k == "deepl_translate_key" {
                let parts = v.components(separatedBy: CharacterSet.newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                saveDeepLKeys(parts.isEmpty ? [v] : parts)
            } else {
                Keychain.save(key: k, value: v)
            }
        }
        for (idStr, v) in (payload.aiKeys ?? [:]) where !v.isEmpty {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            let parts = v.components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            saveAIKeys(for: uuid, keys: parts.isEmpty ? [v] : parts)
        }
        saveToStorage()
    }

    /// 仅测试指定 Provider（不 failover 到其它）
    func testAIProvider(_ providerID: UUID?) async throws -> String {
        guard let id = providerID,
              let provider = aiProviders.first(where: { $0.id == id }) else {
            throw TranslationError.noProvider
        }
        let keys = loadAIKeys(for: id)
        guard !keys.isEmpty else {
            throw TranslationError.apiError("未配置 API Key")
        }
        let prompt = "You are a connectivity probe. Reply with exactly the two letters: OK"
        let text = try await callAIWithProviderKeys(provider: provider, prompt: prompt, maxTokens: 32)
        return "\(provider.name) (\(keys.count) Key): " + text
    }

    /// 测试当前或指定翻译引擎（短句连通性 / Key 是否可用）
    func testTranslationEngine(_ engine: TranslationEngine? = nil) async throws -> String {
        let eng = engine ?? defaultTranslationEngine
        let sample = "Hello, world."
        let previous = defaultTranslationEngine
        defaultTranslationEngine = eng
        defer { defaultTranslationEngine = previous }
        let out = try await translateText(sample)
        let preview = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preview.isEmpty else {
            throw TranslationError.apiError("\(eng.rawValue) 返回空译文")
        }
        return "\(eng.rawValue) 可用：\(preview.prefix(80))"
    }


    var feedsByGroup: [(group: FeedGroup?, feeds: [RSSFeed])] {
        let sortedGroups = groups.sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name < $1.name) }
        var sections: [(FeedGroup?, [RSSFeed])] = []
        for g in sortedGroups {
            let items = sortedFeeds(feeds.filter { $0.groupID == g.id })
            if !items.isEmpty { sections.append((g, items)) }
        }
        let ungrouped = sortedFeeds(feeds.filter { feed in
            guard let gid = feed.groupID else { return true }
            return !groups.contains(where: { $0.id == gid })
        })
        if !ungrouped.isEmpty || sections.isEmpty { sections.append((nil, ungrouped)) }
        return sections
    }

    /// 按当前 `feedSortMode` 对源列表排序
    func sortedFeeds(_ list: [RSSFeed]) -> [RSSFeed] {
        switch feedSortMode {
        case .unreadThenTitle:
            return list.sorted {
                if $0.unreadCount != $1.unreadCount { return $0.unreadCount > $1.unreadCount }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .title:
            return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .lastFetched:
            return list.sorted {
                let a = $0.lastFetched ?? .distantPast
                let b = $1.lastFetched ?? .distantPast
                if a != b { return a > b }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .manual:
            return list.sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    /// 同组内重排：source/destination 为该组可见列表中的下标
    func reorderFeeds(groupID: UUID?, from source: IndexSet, to destination: Int) {
        var ids = feeds
            .filter { feed in
                if let groupID { return feed.groupID == groupID }
                return feed.groupID == nil || !groups.contains(where: { $0.id == feed.groupID })
            }
            .sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.title < $1.title) }
            .map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        for (order, id) in ids.enumerated() {
            guard let idx = feeds.firstIndex(where: { $0.id == id }) else { continue }
            var f = feeds[idx]
            f.sortOrder = order
            feeds[idx] = f
        }
        saveToStorage()
    }

    func addGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if groups.contains(where: { $0.name == trimmed }) { return }
        let order = (groups.map(\.sortOrder).max() ?? -1) + 1
        groups.append(FeedGroup(name: trimmed, sortOrder: order))
        saveToStorage()
    }

    func renameGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].name = trimmed
        saveToStorage()
    }

    func deleteGroup(_ id: UUID) {
        for i in feeds.indices where feeds[i].groupID == id { feeds[i].groupID = nil }
        groups.removeAll { $0.id == id }
        saveToStorage()
    }

    func moveFeed(_ feedID: UUID, toGroup groupID: UUID?) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        feeds[idx].groupID = groupID
        saveToStorage()
    }

    func group(for feed: RSSFeed) -> FeedGroup? {
        guard let gid = feed.groupID else { return nil }
        return groups.first { $0.id == gid }
    }

    func isGroupCollapsed(_ groupID: UUID?) -> Bool {
        if let id = groupID { return collapsedGroupIDs.contains(id) }
        return isUngroupedCollapsed
    }

    func toggleGroupCollapsed(_ groupID: UUID?) {
        if let id = groupID {
            if collapsedGroupIDs.contains(id) { collapsedGroupIDs.remove(id) }
            else { collapsedGroupIDs.insert(id) }
        } else {
            isUngroupedCollapsed.toggle()
        }
        persistCollapsedGroups()
    }

    private func persistCollapsedGroups() {
        UserDefaults.standard.set(collapsedGroupIDs.map(\.uuidString), forKey: "collapsedGroupIDs")
        UserDefaults.standard.set(isUngroupedCollapsed, forKey: "isUngroupedCollapsed")
    }

    private func loadCollapsedGroups() {
        if let arr = UserDefaults.standard.array(forKey: "collapsedGroupIDs") as? [String] {
            collapsedGroupIDs = Set(arr.compactMap { UUID(uuidString: $0) })
        }
        isUngroupedCollapsed = UserDefaults.standard.bool(forKey: "isUngroupedCollapsed")
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
        _ = await refreshFeedResult(feedID)
    }

    /// 刷新单个源；返回失败说明（已含源名），成功返回 nil
    @discardableResult
    func refreshFeedResult(_ feedID: UUID, manageLoading: Bool = true) async -> String? {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return nil }
        let feedTitle = feeds[idx].title.isEmpty ? "未命名源" : feeds[idx].title
        let urlStr = feeds[idx].url
        guard var url = NetworkURLPolicy.validate(urlStr) else {
            let msg = "「\(feedTitle)」：不允许的地址（仅支持公网 http/https）"
            errorMessage = msg
            return msg
        }
        if manageLoading {
            withAnimation(.easeInOut(duration: 0.28)) {
                isLoading = true
                if !isRefreshingAll {
                    refreshProgressTotal = 1
                    refreshProgressCurrent = 1
                    refreshProgressTitle = feedTitle
                }
            }
        }
        defer {
            if manageLoading, !isRefreshingAll {
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        refreshProgressTitle = "完成"
                    }
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isLoading = false
                        refreshProgressCurrent = 0
                        refreshProgressTotal = 0
                        refreshProgressTitle = ""
                    }
                }
            }
        }
        do {
            let data = try await Self.fetchFeedData(from: url)
            OfflineCache.saveFeedXML(url: urlStr, data: data)
            applyParsedFeed(data: data, feedID: feedID, idx: idx, urlStr: urlStr)
            return nil
        } catch {
            // http 失败时尝试 https
            if url.scheme?.lowercased() == "http",
               var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                comps.scheme = "https"
                if let httpsURL = comps.url, NetworkURLPolicy.isAllowed(httpsURL) {
                    do {
                        let data = try await Self.fetchFeedData(from: httpsURL)
                        OfflineCache.saveFeedXML(url: urlStr, data: data)
                        applyParsedFeed(data: data, feedID: feedID, idx: idx, urlStr: urlStr)
                        if idx < feeds.count, feeds[idx].id == feedID {
                            feeds[idx].url = httpsURL.absoluteString
                            saveToStorage()
                        }
                        return nil
                    } catch { /* fall through */ }
                }
            }
            if let cached = OfflineCache.loadFeedXML(url: urlStr) {
                applyParsedFeed(data: cached, feedID: feedID, idx: idx, urlStr: urlStr)
                let msg = "「\(feedTitle)」：网络异常，已使用本地缓存"
                errorMessage = msg
                return msg
            } else {
                let tip = Self.friendlyNetworkError(error)
                let msg = "「\(feedTitle)」：\(tip)"
                errorMessage = msg
                return msg
            }
        }
    }

    private static func fetchFeedData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func friendlyNetworkError(_ error: Error) -> String {
        let ns = error as NSError
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("App Transport Security")
            || text.localizedCaseInsensitiveContains("secure connection") {
            return "该源使用了不安全的 HTTP。请确认系统允许，或改用 HTTPS 地址。"
        }
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "设备未连接网络"
            case NSURLErrorTimedOut: return "连接超时"
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "无法解析主机"
            case NSURLErrorAppTransportSecurityRequiresSecureConnection: return "需要 HTTPS 连接（ATS）"
            default: break
            }
        }
        return text
    }

    private func applyParsedFeed(data: Data, feedID: UUID, idx: Int, urlStr: String) {
        let parsed = FeedParser.parse(data: data, feedID: feedID, feedTitle: feeds[idx].title)
        var existingByLink: [String: Int] = [:]
        for (i, a) in feeds[idx].articles.enumerated() {
            let key = Self.canonicalLink(a.link)
            if !key.isEmpty { existingByLink[key] = i }
        }
        var newArticles: [Article] = []
        for var article in parsed {
            let key = Self.canonicalLink(article.link)
            if key.isEmpty { continue }
            if let ei = existingByLink[key] {
                // 刷新时补全 commentsURL（HN 等）
                if let c = article.commentsURL, !c.isEmpty,
                   feeds[idx].articles[ei].commentsURL == nil {
                    feeds[idx].articles[ei].commentsURL = c
                }
                continue
            }
            if readArticleLinks.contains(key) { article.isRead = true }
            if let html = OfflineCache.loadArticleHTML(link: article.link), !html.isEmpty {
                article.content = html
                article.hasFullContent = true
            }
            newArticles.append(article)
        }
        // 文章黑名单：新条目直接标已读
        for i in newArticles.indices {
            if matchesArticleBlacklist(newArticles[i]) {
                newArticles[i].isRead = true
                let key = Self.canonicalLink(newArticles[i].link)
                if !key.isEmpty { readArticleLinks.insert(key) }
            }
        }
        feeds[idx].articles.insert(contentsOf: newArticles, at: 0)
        feeds[idx].unreadCount = feeds[idx].articles.filter { !$0.isRead }.count
        feeds[idx].lastFetched = Date()
        // 图标获取只执行一次：无论成功与否都标记完成
        if !feeds[idx].faviconFetchDone {
            var feed = feeds[idx]
            if let resolved = FeedParser.resolveFaviconURL(from: data, feedURL: urlStr) {
                let current = feed.faviconURL ?? ""
                let isFallbackOnly = current.isEmpty || current.contains("duckduckgo.com/ip3/") || current.contains("google.com/s2/favicons")
                let fromFeed = FeedParser.extractFeedImage(from: data) != nil
                if isFallbackOnly || fromFeed { feed.faviconURL = resolved }
            }
            feed.faviconFetchDone = true
            feeds[idx] = feed
        }
        purgeOldReadArticles()
        pruneFullContentCache()
        saveToStorage()
    }

    func refreshAll() async {
        let snapshot = feeds
        guard !snapshot.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            isRefreshingAll = true
            isLoading = true
            refreshProgressTotal = snapshot.count
            refreshProgressCurrent = 0
            refreshProgressTitle = "准备中…"
        }
        var failures: [String] = []
        for (i, feed) in snapshot.enumerated() {
            let title = feed.title.isEmpty ? "未命名源" : feed.title
            withAnimation(.easeInOut(duration: 0.32)) {
                refreshProgressCurrent = i + 1
                refreshProgressTitle = title
            }
            if let err = await refreshFeedResult(feed.id, manageLoading: false) {
                failures.append(err)
            }
        }
        // 收尾：先走到 100%，再淡出，避免进度条突然消失
        withAnimation(.easeInOut(duration: 0.28)) {
            refreshProgressCurrent = snapshot.count
            refreshProgressTitle = "完成"
        }
        try? await Task.sleep(nanoseconds: 320_000_000)
        withAnimation(.easeInOut(duration: 0.35)) {
            isRefreshingAll = false
            isLoading = false
            refreshProgressCurrent = 0
            refreshProgressTotal = 0
            refreshProgressTitle = ""
        }
        if failures.isEmpty {
            errorMessage = nil
        } else if failures.count == 1 {
            errorMessage = failures[0]
        } else {
            // 从「源名」：中提取源名做摘要
            let names: [String] = failures.compactMap { line in
                guard line.hasPrefix("「"), let end = line.firstIndex(of: "」") else { return nil }
                return String(line[line.index(after: line.startIndex)..<end])
            }
            let shown = names.prefix(3).map { "「\($0)」" }.joined(separator: "、")
            let extra = names.count > 3 ? " 等\(names.count) 个源" : ""
            errorMessage = "\(shown)\(extra) 刷新异常（共 \(failures.count) 条）"
        }
    }

    func containsBlacklistedTerm(_ text: String) -> Bool {
        let haystack = text.lowercased()
        for raw in aiBlacklistTerms {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            if haystack.contains(term.lowercased()) { return true }
        }
        return false
    }

    func matchesArticleBlacklist(_ article: Article) -> Bool {
        guard !articleBlacklistTerms.isEmpty else { return false }
        let haystack = (article.title + "\n" + article.summary).lowercased()
        for raw in articleBlacklistTerms {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            if haystack.contains(term.lowercased()) { return true }
        }
        return false
    }

    /// 将命中文章黑名单的条目标为已读（不写 readArticleLinks 以外的额外逻辑）
    @discardableResult
    func applyArticleBlacklist(in feedID: UUID? = nil) -> Int {
        var marked = 0
        let indices: [Int]
        if let feedID, let idx = feeds.firstIndex(where: { $0.id == feedID }) {
            indices = [idx]
        } else {
            indices = Array(feeds.indices)
        }
        for i in indices {
            var feed = feeds[i]
            var changed = false
            for j in feed.articles.indices {
                guard !feed.articles[j].isRead else { continue }
                guard matchesArticleBlacklist(feed.articles[j]) else { continue }
                feed.articles[j].isRead = true
                let key = Self.canonicalLink(feed.articles[j].link)
                if !key.isEmpty { readArticleLinks.insert(key) }
                marked += 1
                changed = true
            }
            if changed {
                feed.unreadCount = feed.articles.filter { !$0.isRead }.count
                feeds[i] = feed
            }
        }
        if marked > 0 {
            persistReadLinks()
            saveToStorage()
        }
        return marked
    }

    func resolveAIProvider(preferredID: UUID?, forText text: String) -> AIProvider? {
        let preferred = preferredID.flatMap { id in aiProviders.first(where: { $0.id == id }) } ?? aiProviders.first
        guard let preferred else { return nil }
        guard containsBlacklistedTerm(text),
              let fallbackID = aiBlacklistFallbackProviderID,
              fallbackID != preferred.id,
              let fallback = aiProviders.first(where: { $0.id == fallbackID }) else {
            return preferred
        }
        return fallback
    }

    /// AI 调用顺序：优先 preferred（含黑名单切换），再其余 Provider；跳过无 Key 的
    func orderedAIProviders(preferredID: UUID?, forText text: String) -> [AIProvider] {
        var ordered: [AIProvider] = []
        var seen = Set<UUID>()
        if let first = resolveAIProvider(preferredID: preferredID, forText: text) {
            ordered.append(first)
            seen.insert(first.id)
        }
        for p in aiProviders where !seen.contains(p.id) {
            ordered.append(p)
            seen.insert(p.id)
        }
        return ordered
    }

    /// 判断 AI 返回是否像错误信息（部分网关用 200 + 正文报错）
    static func looksLikeAIErrorResponse(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        if t.count > 400 { return false }
        let lower = t.lowercased()
        let needles = [
            "error", "invalid api key", "incorrect api key", "authentication",
            "unauthorized", "forbidden", "rate limit", "quota", "overloaded",
            "model not found", "does not exist", "permission denied",
            "请求失败", "无效的", "未配置", "余额不足", "频率限制", "鉴权失败",
            "api key", "access denied", "service unavailable"
        ]
        return needles.contains { lower.contains($0) }
    }


    // MARK: - AI Provider 多 Key

    /// 读取某 Provider 的全部 Key（兼容旧版单 Key）
    func loadAIKeys(for providerID: UUID) -> [String] {
        let multiKey = "ai_keys_\(providerID.uuidString)"
        if let raw = Keychain.load(key: multiKey), !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        // 兼容旧单 Key
        let legacy = Keychain.load(key: "ai_key_\(providerID.uuidString)") ?? ""
        let one = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        return one.isEmpty ? [] : [one]
    }

    func saveAIKeys(for providerID: UUID, keys: [String]) {
        let cleaned = keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let multiKey = "ai_keys_\(providerID.uuidString)"
        let legacyKey = "ai_key_\(providerID.uuidString)"
        if cleaned.isEmpty {
            Keychain.delete(key: multiKey)
            Keychain.delete(key: legacyKey)
            return
        }
        if let data = try? JSONEncoder().encode(cleaned), let raw = String(data: data, encoding: .utf8) {
            Keychain.save(key: multiKey, value: raw)
        }
        // 同步首个 Key 到旧字段，兼容未升级逻辑
        Keychain.save(key: legacyKey, value: cleaned[0])
    }

    
    // MARK: - DeepL 多 Key

    func loadDeepLKeys() -> [String] {
        let multiKey = "deepl_translate_keys"
        if let raw = Keychain.load(key: multiKey), !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        let legacy = Keychain.load(key: "deepl_translate_key") ?? ""
        let one = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        return one.isEmpty ? [] : [one]
    }

    func saveDeepLKeys(_ keys: [String]) {
        let cleaned = keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let multiKey = "deepl_translate_keys"
        if cleaned.isEmpty {
            Keychain.delete(key: multiKey)
            Keychain.delete(key: "deepl_translate_key")
            return
        }
        if let data = try? JSONEncoder().encode(cleaned), let raw = String(data: data, encoding: .utf8) {
            Keychain.save(key: multiKey, value: raw)
        }
        Keychain.save(key: "deepl_translate_key", value: cleaned[0])
    }

    private var deeplKeyRoundRobin: Int = 0

    /// DeepL：多 Key 轮询；配额/鉴权失败换 Key；全部失败可回退其它引擎
    func translateWithDeepL(_ text: String, targetLang: String) async throws -> String {
        let keys = loadDeepLKeys()
        guard !keys.isEmpty else { throw TranslationError.apiError("未配置 DeepL API Key") }
        let start = deeplKeyRoundRobin % keys.count
        var lastError: Error = TranslationError.apiError("DeepL 全部 Key 不可用")
        for offset in 0..<keys.count {
            let idx = (start + offset) % keys.count
            let key = keys[idx]
            do {
                let out = try await DeepLTranslate.translate(text: text, apiKey: key, targetLang: targetLang)
                deeplKeyRoundRobin = idx + 1
                return out
            } catch {
                lastError = error
                if Self.isQuotaOrAuthError(error) { continue }
                // 非配额类错误也尝试下一把 Key（网络抖动）
                continue
            }
        }
        // 全部 Key 失败 → 回退 Google（免 Key）再试一次
        do {
            return try await GoogleTranslate.translate(text: text, targetLang: targetLanguage.googleCode)
        } catch {
            throw lastError
        }
    }

    func translateTextsWithDeepL(_ texts: [String], targetLang: String) async -> [String?] {
        let keys = loadDeepLKeys()
        guard !keys.isEmpty else {
            return Array(repeating: nil, count: texts.count)
        }
        // 按 Key 轮询分批并行，提高吞吐
        return await translateNativeBatchParallel(texts, chunkSize: 30, parallelism: min(3, max(1, keys.count))) { chunk in
            // 每批选用下一把 Key
            let key = self.loadDeepLKeys().isEmpty ? "" : {
                let ks = self.loadDeepLKeys()
                let i = self.deeplKeyRoundRobin % ks.count
                self.deeplKeyRoundRobin = i + 1
                return ks[i]
            }()
            do {
                return try await DeepLTranslate.translate(texts: chunk, apiKey: key, targetLang: targetLang)
            } catch {
                if Self.isQuotaOrAuthError(error) {
                    // 换 Key 重试整批
                    for k in self.loadDeepLKeys() where k != key {
                        if let r = try? await DeepLTranslate.translate(texts: chunk, apiKey: k, targetLang: targetLang) {
                            return r
                        }
                    }
                }
                throw error
            }
        }
    }

    static func isQuotaOrAuthError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        for token in ["456", "quota", "limit", "403", "401", "429", "exceed", "额度", "配额", "授权", "forbidden", "unauthorized"] {
            if msg.contains(token) { return true }
        }
        return false
    }

/// 轮询取下一个 Key（负载均衡）；无 Key 返回 nil
    private var aiKeyRoundRobin: [UUID: Int] = [:]

    func nextAIKey(for providerID: UUID) -> String? {
        let keys = loadAIKeys(for: providerID)
        guard !keys.isEmpty else { return nil }
        let start = aiKeyRoundRobin[providerID] ?? 0
        let idx = start % keys.count
        aiKeyRoundRobin[providerID] = idx + 1
        return keys[idx]
    }

    /// 按顺序尝试该 Provider 的所有 Key
    func callAIWithProviderKeys(
        provider: AIProvider,
        prompt: String,
        maxTokens: Int
    ) async throws -> String {
        let keys = loadAIKeys(for: provider.id)
        guard !keys.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        // 从轮询位点开始，转一圈
        let start = (aiKeyRoundRobin[provider.id] ?? 0) % keys.count
        var lastError: Error = TranslationError.apiError("全部 Key 失败")
        for offset in 0..<keys.count {
            let idx = (start + offset) % keys.count
            let key = keys[idx]
            do {
                let raw = try await callAI(prompt: prompt, provider: provider, apiKey: key, maxTokens: maxTokens)
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty || Self.looksLikeAIErrorResponse(text) {
                    throw TranslationError.apiError(text.isEmpty ? "空响应" : text)
                }
                aiKeyRoundRobin[provider.id] = idx + 1
                return text
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }


    /// 依次尝试可用 AI Provider，全部失败再抛错
    func callAIWithFailover(
        preferredID: UUID?,
        probeText: String,
        maxTokens: Int = 500,
        buildPrompt: () -> String
    ) async throws -> (text: String, provider: AIProvider) {
        let providers = orderedAIProviders(preferredID: preferredID, forText: probeText)
        guard !providers.isEmpty else { throw TranslationError.noProvider }
        let prompt = buildPrompt()
        var lastError: Error = TranslationError.noProvider
        var triedAnyKey = false
        for provider in providers {
            let keys = loadAIKeys(for: provider.id)
            guard !keys.isEmpty else { continue }
            triedAnyKey = true
            do {
                let text = try await callAIWithProviderKeys(provider: provider, prompt: prompt, maxTokens: maxTokens)
                return (text, provider)
            } catch {
                lastError = error
                continue
            }
        }
        if !triedAnyKey { throw TranslationError.apiError("未配置任何可用的 API Key") }
        throw lastError
    }

    func translateText(_ text: String) async throws -> String {
        let lang = targetLanguage
        switch defaultTranslationEngine {
        case .google: return try await GoogleTranslate.translate(text: text, targetLang: lang.googleCode)
        case .mymemory: return try await MyMemoryTranslate.translate(text: text, targetLang: lang.mymemoryCode)
        case .microsoft:
            let key = Keychain.load(key: "microsoft_translate_key") ?? ""
            return try await MicrosoftTranslate.translate(
                text: text,
                apiKey: key,
                region: microsoftTranslateRegion,
                targetLang: lang.microsoftCode
            )
        case .deepl:
            return try await translateWithDeepL(text, targetLang: lang.deeplCode)
        case .ai:
            let preferred = defaultTranslationProviderID ?? defaultSummaryProviderID
            let template = translationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppStore.defaultTranslationPrompt : translationPrompt
            var prompt = template
                .replacingOccurrences(of: "{{lang}}", with: lang.promptLabel)
                .replacingOccurrences(of: "{{text}}", with: text)
            if !template.contains("{{text}}") { prompt += "\n\n" + text }
            let (result, _) = try await callAIWithFailover(
                preferredID: preferred,
                probeText: text,
                maxTokens: 2048,
                buildPrompt: { prompt }
            )
            return result
        }
    }

    /// 解析实际并发度：显式参数 > 用户设置 > 引擎默认（偏稳，避免限流导致大片失败）
    func resolvedTranslationConcurrency(for engine: TranslationEngine, override: Int? = nil) -> Int {
        if let o = override, o > 0 { return min(8, o) }
        if translationConcurrency > 0 { return min(8, translationConcurrency) }
        switch engine {
        case .ai: return 4
        case .google: return 8
        case .mymemory: return 4
        case .microsoft: return 3
        case .deepl: return 3
        }
    }

    func translateTexts(_ texts: [String], concurrency: Int? = nil) async -> [String?] {
        guard !texts.isEmpty else { return [] }
        let engine = defaultTranslationEngine
        let limit = resolvedTranslationConcurrency(for: engine, override: concurrency)
        switch engine {
        case .deepl:
            return await translateTextsWithDeepL(texts, targetLang: targetLanguage.deeplCode)
        case .microsoft:
            let key = Keychain.load(key: "microsoft_translate_key") ?? ""
            let msLang = targetLanguage.microsoftCode
            let msRegion = microsoftTranslateRegion
            return await translateNativeBatchParallel(texts, chunkSize: 25, parallelism: 3) {
                try await MicrosoftTranslate.translate(texts: $0, apiKey: key, region: msRegion, targetLang: msLang)
            }
        case .google, .mymemory, .ai:
            // 统一走 translateText（含 AI failover / 多 Key），不再跨 Provider 分片，避免质量与失败率变差
            return await translateConcurrently(texts, concurrency: limit)
        }
    }

    /// AI 多 Provider：轮询分片，每 Provider 独立并发，总吞吐 ≈ Provider数 × 每路并发
    private func translateTextsWithAIProviders(_ texts: [String], perProviderConcurrency: Int) async -> [String?] {
        let preferred = defaultTranslationProviderID ?? defaultSummaryProviderID
        let providers = orderedAIProviders(preferredID: preferred, forText: texts.first ?? "").filter { p in
            !loadAIKeys(for: p.id).isEmpty
        }
        guard !providers.isEmpty else {
            return await translateConcurrently(texts, concurrency: perProviderConcurrency)
        }
        if providers.count == 1 {
            return await translateConcurrently(texts, concurrency: perProviderConcurrency)
        }
        // 分片：index % n → provider
        var buckets: [[(Int, String)]] = Array(repeating: [], count: providers.count)
        for (i, text) in texts.enumerated() {
            buckets[i % providers.count].append((i, text))
        }
        var results = Array<String?>(repeating: nil, count: texts.count)
        await withTaskGroup(of: [(Int, String?)].self) { group in
            for (pIdx, provider) in providers.enumerated() {
                let jobs = buckets[pIdx]
                guard !jobs.isEmpty else { continue }
                group.addTask {
                    await self.translateBucket(jobs, provider: provider, concurrency: perProviderConcurrency)
                }
            }
            for await part in group {
                for (idx, val) in part { results[idx] = val }
            }
        }
        return results
    }

    private func translateBucket(_ jobs: [(Int, String)], provider: AIProvider, concurrency: Int) async -> [(Int, String?)] {
        var out: [(Int, String?)] = []
        out.reserveCapacity(jobs.count)
        await withTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            let spawn = min(max(concurrency, 1), jobs.count)
            while next < spawn {
                let (idx, text) = jobs[next]
                next += 1
                group.addTask {
                    let r = try? await self.translateTextWithProvider(text, provider: provider)
                    let trimmed = r?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (idx, (trimmed?.isEmpty == false) ? trimmed : nil)
                }
            }
            for await item in group {
                out.append(item)
                if next < jobs.count {
                    let (idx, text) = jobs[next]
                    next += 1
                    group.addTask {
                        let r = try? await self.translateTextWithProvider(text, provider: provider)
                        let trimmed = r?.trimmingCharacters(in: .whitespacesAndNewlines)
                        return (idx, (trimmed?.isEmpty == false) ? trimmed : nil)
                    }
                }
            }
        }
        return out
    }

    /// 指定 Provider 翻译（不做 failover，供多路分片使用）
    private func translateTextWithProvider(_ text: String, provider: AIProvider) async throws -> String {
        let lang = targetLanguage
        let template = translationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppStore.defaultTranslationPrompt : translationPrompt
        var prompt = template
            .replacingOccurrences(of: "{{lang}}", with: lang.promptLabel)
            .replacingOccurrences(of: "{{text}}", with: text)
        if !template.contains("{{text}}") { prompt += "\n\n" + text }
        return try await callAIWithProviderKeys(provider: provider, prompt: prompt, maxTokens: 2048)
    }

    /// 多批并行（用于 Microsoft / DeepL 批量 API）
    private func translateNativeBatchParallel(
        _ texts: [String],
        chunkSize: Int,
        parallelism: Int,
        call: @escaping ([String]) async throws -> [String]
    ) async -> [String?] {
        let chunks: [[String]] = texts.chunked(into: max(1, chunkSize))
        var results = Array<String?>(repeating: nil, count: texts.count)
        await withTaskGroup(of: (Int, [String?]).self) { group in
            var next = 0
            let spawn = min(max(parallelism, 1), chunks.count)
            func submit(_ chunkIndex: Int) {
                let chunk = chunks[chunkIndex]
                group.addTask {
                    let translated = try? await call(chunk)
                    let mapped: [String?] = (translated ?? []).map { $0.isEmpty ? nil : $0 }
                    // pad
                    var row = mapped
                    while row.count < chunk.count { row.append(nil) }
                    return (chunkIndex, Array(row.prefix(chunk.count)))
                }
            }
            while next < spawn {
                submit(next); next += 1
            }
            for await (chunkIndex, row) in group {
                let base = chunkIndex * max(1, chunkSize)
                // recompute base from chunk sizes - safer by scanning
                var offset = 0
                for i in 0..<chunkIndex { offset += chunks[i].count }
                for (j, val) in row.enumerated() where offset + j < results.count {
                    results[offset + j] = val
                }
                if next < chunks.count {
                    submit(next); next += 1
                }
            }
        }
        return results
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
                let i = next; let text = texts[i]
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
                    let i = next; let text = texts[i]; next += 1
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
        let chunkLimit = min(2, max(1, resolvedTranslationConcurrency(for: defaultTranslationEngine)))
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var next = 0
            let spawn = min(chunkLimit, chunks.count)
            while next < spawn {
                let index = next
                let chunk = chunks[index]
                next += 1
                group.addTask { (index, try await self.translateText(chunk)) }
            }
            var ordered = Array(repeating: "", count: chunks.count)
            for try await (index, result) in group {
                ordered[index] = result
                if next < chunks.count {
                    let i = next
                    let chunk = chunks[i]
                    next += 1
                    group.addTask { (i, try await self.translateText(chunk)) }
                }
            }
            return ordered.joined(separator: "\n\n")
        }
    }

    static func splitTextIntoChunks(_ text: String, maxChars: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.count <= maxChars { return [trimmed] }
        var chunks: [String] = []
        var current = ""
        for para in trimmed.components(separatedBy: CharacterSet.newlines) {
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

    func generateSummary(for article: Article) async throws -> (text: String, providerName: String) {
        let probe = [article.title, article.summary, article.content]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let content = String(HTMLUtils.stripTags(article.content).prefix(2500))
        let template = summaryPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppStore.defaultSummaryPrompt : summaryPrompt
        var prompt = template
            .replacingOccurrences(of: "{{lang}}", with: aiOutputLanguage.promptLabel)
            .replacingOccurrences(of: "{{title}}", with: article.title)
            .replacingOccurrences(of: "{{content}}", with: content)
        if !template.contains("{{title}}") && !template.contains("{{content}}") {
            prompt += "\n\n标题：\(article.title)\n\n内容：\(content)"
        }
        let (raw, provider) = try await callAIWithFailover(
            preferredID: defaultSummaryProviderID,
            probeText: probe,
            maxTokens: 600,
            buildPrompt: { prompt }
        )
        return (Self.cleanSummaryText(raw), provider.name)
    }

    static func migrateLegacyDefaultPrompts(translation: inout String, summary: inout String, explain: inout String) {
        func normalize(_ s: String) -> String {
            s.replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let legacyTranslation = "请将以下内容翻译成{{lang}}，只输出译文，不要解释：\n\n{{text}}"
        let legacySummary = "请用3-5句话概括以下文章的核心内容，用{{lang}}回答。每句话单独一行，不要使用1. 2. 3.等序号，不要加标题：\n\n标题：{{title}}\n\n内容：{{content}}"
        let legacyExplain = "请用简洁的{{lang}}解释下面这段文字（词义、专有名词、语境或背景）。只输出解释，不要标题，不要复述整段原文：\n\n{{text}}"
        if normalize(translation) == normalize(legacyTranslation) || translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translation = defaultTranslationPrompt
        }
        if normalize(summary) == normalize(legacySummary) || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary = defaultSummaryPrompt
        }
        if normalize(explain) == normalize(legacyExplain) || explain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            explain = defaultExplainPrompt
        }
    }

    static func cleanSummaryText(_ text: String) -> String {
        let patterns = [
            #"^(\d+[\.\)、:：]|[(（]\d+[)）])\s*"#,
            #"^[-•●▪◦]\s+"#
        ]
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        return text.components(separatedBy: "\n").map { line -> String in
            var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return "" }
            for regex in regexes {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
                s = s.trimmingCharacters(in: .whitespaces)
            }
            for prefix in ["总结如下", "摘要如下", "要点如下", "译文如下", "如下：", "如下:"] {
                if s.hasPrefix(prefix) { return "" }
            }
            return s
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func explainText(_ text: String) async throws -> String {
        let preferred = defaultExplainProviderID
            ?? defaultSummaryProviderID
            ?? defaultTranslationProviderID
        let clipped = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(800))
        guard !clipped.isEmpty else { throw TranslationError.apiError("未选中有效文字") }
        let template = explainPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppStore.defaultExplainPrompt : explainPrompt
        var prompt = template
            .replacingOccurrences(of: "{{lang}}", with: aiOutputLanguage.promptLabel)
            .replacingOccurrences(of: "{{text}}", with: clipped)
        if !template.contains("{{text}}") { prompt += "\n\n\(clipped)" }
        let (result, _) = try await callAIWithFailover(
            preferredID: preferred,
            probeText: clipped,
            maxTokens: 500,
            buildPrompt: { prompt }
        )
        return result
    }

    func renameFeed(_ feedID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        // 整元素重写，确保 @Observable 能追踪到 feeds 变化并刷新列表
        var feed = feeds[idx]
        feed.title = trimmed
        for j in feed.articles.indices {
            feed.articles[j].feedTitle = trimmed
        }
        feeds[idx] = feed
        saveToStorage()
    }

    func setFeedFetchFullContent(_ feedID: UUID, enabled: Bool) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        var feed = feeds[idx]
        feed.fetchFullContentEnabled = enabled
        feeds[idx] = feed
        saveToStorage()
    }

    func setFeedFetchComments(_ feedID: UUID, enabled: Bool) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        var feed = feeds[idx]
        feed.fetchCommentsEnabled = enabled
        feeds[idx] = feed
        saveToStorage()
    }

    func setFeedAutoTranslate(_ feedID: UUID, enabled: Bool) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        var feed = feeds[idx]
        feed.autoTranslateEnabled = enabled
        feeds[idx] = feed
        saveToStorage()
    }

    func markFaviconFetchDone(_ feedID: UUID) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        guard !feeds[idx].faviconFetchDone else { return }
        var feed = feeds[idx]
        feed.faviconFetchDone = true
        feeds[idx] = feed
        saveToStorage()
    }

    func isFullContentEnabled(for article: Article) -> Bool {
        feeds.first(where: { $0.id == article.feedID })?.fetchFullContentEnabled ?? true
    }

    func isCommentsEnabled(for article: Article) -> Bool {
        feeds.first(where: { $0.id == article.feedID })?.fetchCommentsEnabled ?? false
    }

    func fetchFullContent(for article: Article) async throws -> Article {
        guard isFullContentEnabled(for: article) else {
            throw TranslationError.apiError("该订阅源已关闭全文获取")
        }
        if article.hasFullContent, !article.content.isEmpty,
           HTMLUtils.stripTags(article.content).count >= 400 {
            OfflineCache.saveArticleHTML(link: article.link, html: article.content)
            return article
        }
        if let cached = OfflineCache.loadArticleHTML(link: article.link), !cached.isEmpty,
           HTMLUtils.stripTags(cached).count >= 400 {
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

    func clearOfflineContentCache() { OfflineCache.clearContentCache() }
    func cacheSizeDescription() -> String { OfflineCache.formattedSize(OfflineCache.contentCacheSize()) }

    func exportOPML() -> String {
        var lines: [String] = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<opml version=\"2.0\">", "  <head><title>IosRss Subscriptions</title></head>", "  <body>"]
        func xmlEscape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "\u{0026}amp;").replacingOccurrences(of: "<", with: "\u{0026}lt;").replacingOccurrences(of: ">", with: "\u{0026}gt;").replacingOccurrences(of: "\"", with: "\u{0026}quot;")
        }
        for section in feedsByGroup {
            if let g = section.group {
                lines.append("    <outline text=\"\(xmlEscape(g.name))\" title=\"\(xmlEscape(g.name))\">")
                for f in section.feeds {
                    lines.append("      <outline type=\"rss\" text=\"\(xmlEscape(f.title))\" title=\"\(xmlEscape(f.title))\" xmlUrl=\"\(xmlEscape(f.url))\" />")
                }
                lines.append("    </outline>")
            } else {
                for f in section.feeds {
                    lines.append("    <outline type=\"rss\" text=\"\(xmlEscape(f.title))\" title=\"\(xmlEscape(f.title))\" xmlUrl=\"\(xmlEscape(f.url))\" />")
                }
            }
        }
        lines.append("  </body>")
        lines.append("</opml>")
        return lines.joined(separator: "\n")
    }


    func writeExportFile(content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            guard let data = content.data(using: .utf8) else { return nil }
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }

    @discardableResult
    func importSubscriptions(data: Data) -> SubscriptionImportResult {
        let items = OPMLParser(data: data).parse()
        if !items.isEmpty {
            var added = 0; var skipped = 0
            let existing = Set(feeds.map { Self.canonicalLink($0.url) })
            for item in items {
                let key = Self.canonicalLink(item.url)
                guard !key.isEmpty else { continue }
                if existing.contains(key) { skipped += 1; continue }
                var feed = RSSFeed(title: item.title.isEmpty ? key : item.title, url: item.url)
                feed.fetchCommentsEnabled = CommentFetcher.shouldAutoEnableComments(feedURL: item.url)
                if let gname = item.groupName, !gname.isEmpty {
                    if let g = groups.first(where: { $0.name == gname }) { feed.groupID = g.id }
                    else {
                        let order = (groups.map(\.sortOrder).max() ?? -1) + 1
                        let g = FeedGroup(name: gname, sortOrder: order)
                        groups.append(g); feed.groupID = g.id
                    }
                }
                feeds.append(feed); added += 1
            }
            if added > 0 { saveToStorage() }
            return SubscriptionImportResult(added: added, skipped: skipped, kind: "opml")
        }
        if let link = FeedParser.extractFeedLink(from: data), !link.isEmpty {
            let url = Self.canonicalLink(link)
            if feeds.contains(where: { Self.canonicalLink($0.url) == url }) {
                return SubscriptionImportResult(added: 0, skipped: 1, kind: "rss")
            }
            let title = FeedParser.extractFeedTitle(from: data) ?? url
            var feed = RSSFeed(title: title, url: link)
            feed.fetchCommentsEnabled = CommentFetcher.shouldAutoEnableComments(feedURL: link)
            feeds.append(feed)
            saveToStorage()
            return SubscriptionImportResult(added: 1, skipped: 0, kind: "rss")
        }
        return SubscriptionImportResult(added: 0, skipped: 0, kind: "empty")
    }

    func saveToStorage() {
        OfflineCache.saveFeeds(feeds)
        if let data = try? JSONEncoder().encode(groups) { UserDefaults.standard.set(data, forKey: "feedGroups") }
        persistCollapsedGroups()
        persistReadLinks()
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
        UserDefaults.standard.set(listTitleFontSize, forKey: "listTitleFontSize")
        UserDefaults.standard.set(listSummaryFontSize, forKey: "listSummaryFontSize")
        UserDefaults.standard.set(readerTitleFontSize, forKey: "readerTitleFontSize")
        UserDefaults.standard.set(aiSummaryFontSize, forKey: "aiSummaryFontSize")
        UserDefaults.standard.set(feedTitleFontSize, forKey: "feedTitleFontSize")
        UserDefaults.standard.set(groupTitleFontSize, forKey: "groupTitleFontSize")
        UserDefaults.standard.set(titleDisplayMode.rawValue, forKey: "titleDisplayMode")
        UserDefaults.standard.set(defaultTranslationEngine.rawValue, forKey: "defaultTranslationEngine")
        UserDefaults.standard.set(showReadArticles, forKey: "showReadArticles")
        UserDefaults.standard.set(translationPrompt, forKey: "translationPrompt")
        UserDefaults.standard.set(summaryPrompt, forKey: "summaryPrompt")
        UserDefaults.standard.set(explainPrompt, forKey: "explainPrompt")
        UserDefaults.standard.set(readRetentionDays, forKey: "readRetentionDays")
        UserDefaults.standard.set(fullContentCacheDays, forKey: "fullContentCacheDays")
        UserDefaults.standard.set(ttsVoice, forKey: "ttsVoice")
        UserDefaults.standard.set(ttsRate, forKey: "ttsRate")
        UserDefaults.standard.set(colorTheme.rawValue, forKey: "colorTheme")
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        UserDefaults.standard.set(appFontFamily.rawValue, forKey: "appFontFamily")
        UserDefaults.standard.set(feedSortMode.rawValue, forKey: "feedSortMode")
        UserDefaults.standard.set(targetLanguage.rawValue, forKey: "targetLanguage")
        UserDefaults.standard.set(translationConcurrency, forKey: "translationConcurrency")
        UserDefaults.standard.set(microsoftTranslateRegion, forKey: "microsoftTranslateRegion")
        UserDefaults.standard.set(aiOutputLanguage.rawValue, forKey: "aiOutputLanguage")
        if let data = try? JSONEncoder().encode(aiProviders) { UserDefaults.standard.set(data, forKey: "aiProviders") }
        if let id = defaultSummaryProviderID { UserDefaults.standard.set(id.uuidString, forKey: "defaultSummaryProviderID") }
        if let id = defaultTranslationProviderID { UserDefaults.standard.set(id.uuidString, forKey: "defaultTranslationProviderID") }
        if let id = defaultExplainProviderID {
            UserDefaults.standard.set(id.uuidString, forKey: "defaultExplainProviderID")
        } else {
            UserDefaults.standard.removeObject(forKey: "defaultExplainProviderID")
        }
        if let data = try? JSONEncoder().encode(aiBlacklistTerms) { UserDefaults.standard.set(data, forKey: "aiBlacklistTerms") }
        if let data = try? JSONEncoder().encode(articleBlacklistTerms) { UserDefaults.standard.set(data, forKey: "articleBlacklistTerms") }
        if let id = aiBlacklistFallbackProviderID {
            UserDefaults.standard.set(id.uuidString, forKey: "aiBlacklistFallbackProviderID")
        } else {
            UserDefaults.standard.removeObject(forKey: "aiBlacklistFallbackProviderID")
        }
    }

    func loadFromStorage() {
        if let loaded = OfflineCache.loadFeeds() { feeds = loaded }
        if let data = UserDefaults.standard.data(forKey: "feedGroups"),
           let decoded = try? JSONDecoder().decode([FeedGroup].self, from: data) { groups = decoded }
        loadCollapsedGroups()
        loadReadLinks()
        fontSize = UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 17
        listTitleFontSize = UserDefaults.standard.object(forKey: "listTitleFontSize") as? Double ?? 18
        listSummaryFontSize = UserDefaults.standard.object(forKey: "listSummaryFontSize") as? Double ?? 15
        readerTitleFontSize = UserDefaults.standard.object(forKey: "readerTitleFontSize") as? Double ?? 24
        aiSummaryFontSize = UserDefaults.standard.object(forKey: "aiSummaryFontSize") as? Double ?? 22
        feedTitleFontSize = UserDefaults.standard.object(forKey: "feedTitleFontSize") as? Double ?? 17
        groupTitleFontSize = UserDefaults.standard.object(forKey: "groupTitleFontSize") as? Double ?? 13
        if let raw = UserDefaults.standard.string(forKey: "titleDisplayMode"),
           let mode = TitleDisplayMode(rawValue: raw) { titleDisplayMode = mode }
        if let s = UserDefaults.standard.string(forKey: "microsoftTranslateRegion"), !s.isEmpty { microsoftTranslateRegion = s }
        if let raw = UserDefaults.standard.string(forKey: "defaultTranslationEngine") {
            if raw.contains("Lingva") || raw.contains("Libre") {
                defaultTranslationEngine = .google
            } else if let engine = TranslationEngine(rawValue: raw) {
                defaultTranslationEngine = engine
            }
        }
        showReadArticles = UserDefaults.standard.object(forKey: "showReadArticles") as? Bool ?? false
        if let p = UserDefaults.standard.string(forKey: "translationPrompt") { translationPrompt = p }
        if let p = UserDefaults.standard.string(forKey: "summaryPrompt") { summaryPrompt = p }
        if let p = UserDefaults.standard.string(forKey: "explainPrompt") { explainPrompt = p }
        // 旧版默认 Prompt 自动升级到优化版（用户自定义的不改）
        Self.migrateLegacyDefaultPrompts(
            translation: &translationPrompt,
            summary: &summaryPrompt,
            explain: &explainPrompt
        )
        readRetentionDays = UserDefaults.standard.object(forKey: "readRetentionDays") as? Int ?? 7
        fullContentCacheDays = UserDefaults.standard.object(forKey: "fullContentCacheDays") as? Int ?? 30
        ttsVoice = UserDefaults.standard.string(forKey: "ttsVoice") ?? ""
        if UserDefaults.standard.object(forKey: "ttsRate") != nil {
            ttsRate = min(2.0, max(0.5, UserDefaults.standard.double(forKey: "ttsRate")))
        }
        if let raw = UserDefaults.standard.string(forKey: "colorTheme") {
            if let theme = ReadingTheme(rawValue: raw) {
                colorTheme = theme
            } else {
                // 迁移旧 AppColorTheme 原始值
                switch raw {
                case "azure": colorTheme = .classicLight
                case "sepia": colorTheme = .sepiaPaper
                case "midnight": colorTheme = .midnightBlue
                case "forest": colorTheme = .forestSage
                case "graphite": colorTheme = .nightDark
                default: break
                }
            }
        }
        if let raw = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: raw) { appearanceMode = mode }
        if let raw = UserDefaults.standard.string(forKey: "appFontFamily"),
           let font = AppFontFamily(rawValue: raw) {
            appFontFamily = font
        } else if UserDefaults.standard.string(forKey: "appFontFamily") == "sourceHanSans" {
            appFontFamily = .system
        }
        if let raw = UserDefaults.standard.string(forKey: "feedSortMode"),
           let mode = FeedSortMode(rawValue: raw) {
            feedSortMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: "targetLanguage"),
           let lang = AppLanguage(rawValue: raw) {
            targetLanguage = lang
        }
        if UserDefaults.standard.object(forKey: "translationConcurrency") != nil {
            translationConcurrency = min(8, max(0, UserDefaults.standard.integer(forKey: "translationConcurrency")))
        }
        if let raw = UserDefaults.standard.string(forKey: "aiOutputLanguage"),
           let lang = AppLanguage(rawValue: raw) {
            aiOutputLanguage = lang
        }
        if let data = UserDefaults.standard.data(forKey: "aiProviders"),
           let decoded = try? JSONDecoder().decode([AIProvider].self, from: data) { aiProviders = decoded }
        if let s = UserDefaults.standard.string(forKey: "defaultSummaryProviderID"),
           let id = UUID(uuidString: s) { defaultSummaryProviderID = id }
        if let s = UserDefaults.standard.string(forKey: "defaultTranslationProviderID"),
           let id = UUID(uuidString: s) { defaultTranslationProviderID = id }
        if let s = UserDefaults.standard.string(forKey: "defaultExplainProviderID"),
           let id = UUID(uuidString: s) { defaultExplainProviderID = id }
        if let data = UserDefaults.standard.data(forKey: "aiBlacklistTerms"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) { aiBlacklistTerms = decoded }
        if let data = UserDefaults.standard.data(forKey: "articleBlacklistTerms"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) { articleBlacklistTerms = decoded }
        if let s = UserDefaults.standard.string(forKey: "aiBlacklistFallbackProviderID"),
           let id = UUID(uuidString: s) { aiBlacklistFallbackProviderID = id }
    }

    private func seedSampleData() {}
}
