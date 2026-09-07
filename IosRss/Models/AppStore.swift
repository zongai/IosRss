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
    var aiBlacklistFallbackProviderID: UUID?
    var showReadArticles: Bool = false
    var translationPrompt: String = AppStore.defaultTranslationPrompt
    var summaryPrompt: String = AppStore.defaultSummaryPrompt
    var explainPrompt: String = AppStore.defaultExplainPrompt
    var readRetentionDays: Int = 7
    var fullContentCacheDays: Int = 30
    /// Edge TTS 音色；空则按正文语言自动选择
    var ttsVoice: String = ""

    static let defaultTranslationPrompt = "请将以下内容翻译成中文，只输出译文，不要解释：\n\n{{text}}"
    static let defaultSummaryPrompt = "请用3-5句话概括以下文章的核心内容，用中文回答。每句话单独一行，不要使用1. 2. 3.等序号，不要加标题：\n\n标题：{{title}}\n\n内容：{{content}}"
    static let defaultExplainPrompt = """
    请用简洁的中文解释下面这段文字（词义、专有名词、语境或背景）。只输出解释，不要标题，不要复述整段原文：

    {{text}}
    """

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

    func addFeed(_ feed: RSSFeed) { feeds.append(feed); saveToStorage() }
    func deleteFeed(at offsets: IndexSet) { feeds.remove(atOffsets: offsets); saveToStorage() }

    func deleteAllFeeds() {
        feeds = []
        saveToStorage()
    }

    var feedsByGroup: [(group: FeedGroup?, feeds: [RSSFeed])] {
        let sortedGroups = groups.sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name < $1.name) }
        var sections: [(FeedGroup?, [RSSFeed])] = []
        for g in sortedGroups {
            let items = feeds.filter { $0.groupID == g.id }
            if !items.isEmpty { sections.append((g, items)) }
        }
        let ungrouped = feeds.filter { feed in
            guard let gid = feed.groupID else { return true }
            return !groups.contains(where: { $0.id == gid })
        }
        if !ungrouped.isEmpty || sections.isEmpty { sections.append((nil, ungrouped)) }
        return sections
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

    func refreshAll() async { for feed in feeds { await refreshFeed(feed.id) } }

    func containsBlacklistedTerm(_ text: String) -> Bool {
        let haystack = text.lowercased()
        for raw in aiBlacklistTerms {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            if haystack.contains(term.lowercased()) { return true }
        }
        return false
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
            let key = Keychain.load(key: "ai_key_\(provider.id)") ?? ""
            guard !key.isEmpty else { continue }
            triedAnyKey = true
            do {
                let raw = try await callAI(
                    prompt: prompt,
                    provider: provider,
                    apiKey: key,
                    maxTokens: maxTokens
                )
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty || Self.looksLikeAIErrorResponse(text) {
                    throw TranslationError.apiError(text.isEmpty ? "空响应" : text)
                }
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
        switch defaultTranslationEngine {
        case .google: return try await GoogleTranslate.translate(text: text)
        case .microsoft:
            let key = Keychain.load(key: "microsoft_translate_key") ?? ""
            return try await MicrosoftTranslate.translate(text: text, apiKey: key)
        case .deepl:
            let key = Keychain.load(key: "deepl_translate_key") ?? ""
            return try await DeepLTranslate.translate(text: text, apiKey: key)
        case .ai:
            let preferred = defaultTranslationProviderID ?? defaultSummaryProviderID
            let template = translationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppStore.defaultTranslationPrompt : translationPrompt
            var prompt = template.replacingOccurrences(of: "{{text}}", with: text)
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

    func translateTexts(_ texts: [String], concurrency: Int? = nil) async -> [String?] {
        guard !texts.isEmpty else { return [] }
        let engine = defaultTranslationEngine
        let limit = concurrency ?? (engine == .ai ? 3 : (engine == .google ? 4 : 5))
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

    static func cleanSummaryText(_ text: String) -> String {
        let pattern = #"^(\d+[\.\)、:：]|[(（]\d+[)）])\s*"#
        let regex = try? NSRegularExpression(pattern: pattern)
        return text.components(separatedBy: "\n").map { line -> String in
            var s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, let regex else { return s }
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
            return s.trimmingCharacters(in: .whitespaces)
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
        var prompt = template.replacingOccurrences(of: "{{text}}", with: clipped)
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
        if let data = try? JSONEncoder().encode(aiProviders) { UserDefaults.standard.set(data, forKey: "aiProviders") }
        if let id = defaultSummaryProviderID { UserDefaults.standard.set(id.uuidString, forKey: "defaultSummaryProviderID") }
        if let id = defaultTranslationProviderID { UserDefaults.standard.set(id.uuidString, forKey: "defaultTranslationProviderID") }
        if let id = defaultExplainProviderID {
            UserDefaults.standard.set(id.uuidString, forKey: "defaultExplainProviderID")
        } else {
            UserDefaults.standard.removeObject(forKey: "defaultExplainProviderID")
        }
        if let data = try? JSONEncoder().encode(aiBlacklistTerms) { UserDefaults.standard.set(data, forKey: "aiBlacklistTerms") }
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
        if let raw = UserDefaults.standard.string(forKey: "defaultTranslationEngine"),
           let engine = TranslationEngine(rawValue: raw) { defaultTranslationEngine = engine }
        showReadArticles = UserDefaults.standard.object(forKey: "showReadArticles") as? Bool ?? false
        if let p = UserDefaults.standard.string(forKey: "translationPrompt") { translationPrompt = p }
        if let p = UserDefaults.standard.string(forKey: "summaryPrompt") { summaryPrompt = p }
        if let p = UserDefaults.standard.string(forKey: "explainPrompt") { explainPrompt = p }
        readRetentionDays = UserDefaults.standard.object(forKey: "readRetentionDays") as? Int ?? 7
        fullContentCacheDays = UserDefaults.standard.object(forKey: "fullContentCacheDays") as? Int ?? 30
        ttsVoice = UserDefaults.standard.string(forKey: "ttsVoice") ?? ""
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
        if let s = UserDefaults.standard.string(forKey: "aiBlacklistFallbackProviderID"),
           let id = UUID(uuidString: s) { aiBlacklistFallbackProviderID = id }
    }

    private func seedSampleData() {}
}
