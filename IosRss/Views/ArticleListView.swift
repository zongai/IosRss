import SwiftUI

struct ArticleListView: View {
    @Environment(AppStore.self) private var store
    let feed: RSSFeed

    @State private var showAllTranslations = false
    @State private var isTranslatingAll = false
    @State private var isInitialLoading = false
    @State private var translationDone = 0
    @State private var translationTotal = 0
    /// 正在阅读中的文章：保持可见，避免 push 过程中从列表消失导致导航异常
    @State private var readingIDs: Set<UUID> = []
    /// 当前打开的阅读页文章；返回时清空并刷新过滤
    @State private var openedArticleID: UUID?
    /// 本页已尝试自动翻译的文章（避免重复请求）
    @State private var autoTranslateAttemptedIDs: Set<UUID> = []

    /// 列表翻译每批条数（标题 + 预览各算一条任务）
    /// 仅用于进度刷新粒度；实际并发由 AppStore.translateTexts 控制
    private let translationBatchSize = 24

    private var articles: [Article] {
        // 显式依赖 openedArticleID / readingIDs，保证返回后重新过滤
        let _ = openedArticleID
        let _ = readingIDs
        var all = store.articlesForFeed(feed.id)
        if store.sortByInterestScore && store.smartInterestFilterEnabled {
            all.sort {
                let s0 = $0.interestScore ?? 0.5
                let s1 = $1.interestScore ?? 0.5
                if abs(s0 - s1) > 0.02 { return s0 > s1 }
                return ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast)
            }
        } else {
            // 多数源入库已是新→旧；仅在乱序时排序，减少每次 body 的 O(n log n)
            if !Self.isSortedByDateDescending(all) {
                all.sort { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
            }
        }
        if store.showReadArticles {
            return all
        }
        return all.filter { article in
            !article.isRead || readingIDs.contains(article.id) || openedArticleID == article.id
        }
    }

    /// 抽样检查是否已按发布时间降序（O(n)，远小于乱序时全量 sort）
    private static func isSortedByDateDescending(_ items: [Article]) -> Bool {
        guard items.count > 1 else { return true }
        var prev = items[0].publishedDate ?? .distantPast
        for i in 1..<items.count {
            let d = items[i].publishedDate ?? .distantPast
            if d > prev { return false }
            prev = d
        }
        return true
    }

    private var liveFeedTitle: String {
        store.feeds.first(where: { $0.id == feed.id })?.title ?? feed.title
    }

    var body: some View {
        List {
            ForEach(articles) { article in
                NavigationLink(value: article) {
                    ArticleRow(article: article, showTranslation: showAllTranslations)
                }
                // 仅用 id + 已读 + 是否显示译文；译文内容变化由 ArticleRow 读最新 article 字段刷新
                // （避免把整段译文塞进 id 导致行身份频繁失效、List 复用失败）
                .id("\(article.id.uuidString)-\(article.isRead)-\(showAllTranslations)-\(article.translatedTitle == nil ? 0 : 1)-\(article.translatedSummary == nil ? 0 : 1)")
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading) {
                    Button {
                        store.toggleFavorite(article)
                    } label: {
                        Label(article.isFavorite ? "取消收藏" : "收藏",
                              systemImage: article.isFavorite ? "star.slash.fill" : "star.fill")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if article.isRead {
                        Button {
                            store.markAsUnread(article)
                        } label: {
                            Label("未读", systemImage: "envelope.badge")
                        }
                        .tint(.blue)
                    } else {
                        Button {
                            store.markAsRead(article)
                        } label: {
                            Label("已读", systemImage: "envelope.open")
                        }
                        .tint(.green)
                    }
                    Button(role: .destructive) {
                        store.markNotInterested(article)
                    } label: {
                        Label("不感兴趣", systemImage: "hand.thumbsdown")
                    }
                }
                .contextMenu {
                    Button {
                        store.markNotInterested(article)
                    } label: {
                        Label("不感兴趣", systemImage: "hand.thumbsdown")
                    }
                    if article.isRead {
                        Button { store.markAsUnread(article) } label: {
                            Label("标为未读", systemImage: "envelope.badge")
                        }
                    } else {
                        Button { store.markAsRead(article) } label: {
                            Label("标为已读", systemImage: "envelope.open")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        // 只跟数量变化动画，避免每次 body 对全表 map(\.id)
        .animation(.snappy(duration: 0.25), value: articles.count)
        .appScreenBackground()
        .navigationTitle(liveFeedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Article.self) { article in
            ArticleReaderView(article: article, feedID: feed.id)
                .onAppear {
                    openedArticleID = article.id
                    readingIDs.insert(article.id)
                    store.markAsRead(article)
                }
                .onDisappear {
                    // 离开阅读页：清掉占位，列表立刻按已读过滤隐藏
                    if openedArticleID == article.id {
                        openedArticleID = nil
                    }
                    withAnimation(.snappy(duration: 0.25)) {
                        readingIDs.remove(article.id)
                    }
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await toggleTranslateAll() }
                } label: {
                    if isTranslatingAll {
                        HStack(spacing: 5) {
                            ProgressView().scaleEffect(0.75)
                            if translationTotal > 0 {
                                Text("\(translationDone)/\(translationTotal)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    } else {
                        Image(systemName: "translate")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(showAllTranslations ? Color(.systemBackground) : Color.primary)
                            .frame(width: 28, height: 28)
                            .background(showAllTranslations ? Color.primary : Color.secondary.opacity(0.15),
                                        in: .rect(cornerRadius: 6))
                    }
                }
                .accessibilityLabel(showAllTranslations ? "显示原文标题" : "翻译列表")
                .disabled(isTranslatingAll)

                Button {
                    store.markAllAsRead(in: feed.id)
                } label: {
                    Image(systemName: "checklist")
                }
                .accessibilityLabel("全部已读")
            }
        }
        .overlay {
            if isInitialLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载文章…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if articles.isEmpty {
                ContentUnavailableView {
                    Label(store.showReadArticles ? "暂无文章" : "暂无未读文章", systemImage: "newspaper")
                } description: {
                    Text(store.showReadArticles ? "下拉刷新或稍后再来" : "当前仅显示未读。可在设置中开启「显示已读文章」。")
                } actions: {
                    if !store.showReadArticles {
                        Button("显示已读文章") {
                            store.showReadArticles = true
                            store.persistSettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("刷新") {
                        Task { await store.refreshFeed(feed.id) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .refreshable {
            // 单源刷新：仍 await 完成后再自动译，避免译到旧列表
            await store.refreshFeed(feed.id)
            await autoTranslatePending(force: true)
        }
        .task(id: feed.id) {
            autoTranslateAttemptedIDs = []
            await loadIfNeeded()
            // 本 feed 已有缓存译文时，打开列表直接显示译文
            let hasCachedTranslation = store.articlesForFeed(feed.id).contains {
                ($0.translatedTitle?.isEmpty == false) || ($0.translatedSummary?.isEmpty == false)
            }
            if hasCachedTranslation {
                showAllTranslations = true
            }
            // 开启自动翻译的源：进入列表即翻译未译条目
            await autoTranslatePending(force: true)
        }
        .onChange(of: articles.count) { _, _ in
            Task { await autoTranslatePending(force: false) }
        }
    }

    /// 第一次打开且本地还没有文章时自动拉取，避免空白列表
    private func loadIfNeeded() async {
        if !store.articlesForFeed(feed.id).isEmpty { return }
        isInitialLoading = true
        await store.refreshFeed(feed.id)
        isInitialLoading = false
    }

    /// 自动翻译：仅处理「未译且非目标中文」的标题 / 摘要
    private func autoTranslatePending(force: Bool) async {
        guard !isTranslatingAll else { return }
        let live = store.feeds.first(where: { $0.id == feed.id })
        let feedEnabled = live?.autoTranslateEnabled ?? false
        guard feedEnabled else { return }
        // 仅翻译当前列表会显示的文章（已隐藏的已读条目跳过）
        let snapshot = store.articlesForFeed(feed.id).filter { article in
            if store.showReadArticles { return true }
            return !article.isRead
                || readingIDs.contains(article.id)
                || openedArticleID == article.id
        }
        var jobs: [ListTranslationJob] = []
        jobs.reserveCapacity(snapshot.count * 2)
        var skipMark: [(id: UUID, title: String?, summary: String?)] = []

        for article in snapshot {
            if !force && autoTranslateAttemptedIDs.contains(article.id) { continue }
            autoTranslateAttemptedIDs.insert(article.id)

            // 语言判定只抽样，避免对全文 content 做 plainText（长文列表 CPU 高）
            let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = HTMLUtils.plainText(article.summary)
            let langSample = Self.languageSample(title: title, preview: preview, content: article.content)
            let bodyIsTarget = !langSample.isEmpty
                && ListLanguageDetect.isMostlyTarget(langSample, language: store.targetLanguage)

            // 正文已是目标语言：标题/摘要直接标为「已对齐」，不发起翻译
            if bodyIsTarget {
                var tMark: String? = nil
                var sMark: String? = nil
                if article.translatedTitle == nil, !title.isEmpty { tMark = title }
                if article.translatedSummary == nil, !preview.isEmpty { sMark = preview }
                if tMark != nil || sMark != nil {
                    skipMark.append((article.id, tMark, sMark))
                }
                continue
            }

            // 标题（列表展示用；是否需译已由正文语言判定）
            if article.translatedTitle == nil, !title.isEmpty {
                jobs.append(ListTranslationJob(articleID: article.id, field: .title, text: title))
            }

            // 摘要预览
            if article.translatedSummary == nil, !preview.isEmpty {
                jobs.append(ListTranslationJob(articleID: article.id, field: .summary, text: preview))
            }
        }

        if !skipMark.isEmpty {
            store.applyListTranslations(skipMark, persist: jobs.isEmpty)
            showAllTranslations = true
        }
        guard !jobs.isEmpty else {
            if snapshot.contains(where: {
                $0.hasTranslatedBody
                    || ($0.translatedTitle?.isEmpty == false)
                    || ($0.translatedSummary?.isEmpty == false)
            }) {
                showAllTranslations = true
            }
            return
        }

        showAllTranslations = true
        await runTranslationJobs(jobs)
    }

    /// 一次点击：分批翻译所有标题和预览；再次点击切换回原文
    private func toggleTranslateAll() async {
        if showAllTranslations {
            showAllTranslations = false
            return
        }
        showAllTranslations = true

        let snapshot = articles
        var jobs: [ListTranslationJob] = []
        jobs.reserveCapacity(snapshot.count * 2)
        var skipMark: [(id: UUID, title: String?, summary: String?)] = []
        for article in snapshot {
            let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = HTMLUtils.plainText(article.summary)
            let langSample = Self.languageSample(title: title, preview: preview, content: article.content)
            let bodyIsTarget = !langSample.isEmpty
                && ListLanguageDetect.isMostlyTarget(langSample, language: store.targetLanguage)

            if bodyIsTarget {
                var tMark: String? = nil
                var sMark: String? = nil
                if article.translatedTitle == nil, !title.isEmpty { tMark = title }
                if article.translatedSummary == nil, !preview.isEmpty { sMark = preview }
                if tMark != nil || sMark != nil {
                    skipMark.append((article.id, tMark, sMark))
                }
                continue
            }
            if article.translatedTitle == nil, !title.isEmpty {
                jobs.append(ListTranslationJob(articleID: article.id, field: .title, text: title))
            }
            if article.translatedSummary == nil, !preview.isEmpty {
                jobs.append(ListTranslationJob(articleID: article.id, field: .summary, text: preview))
            }
        }
        if !skipMark.isEmpty {
            store.applyListTranslations(skipMark, persist: jobs.isEmpty)
        }
        guard !jobs.isEmpty else { return }
        await runTranslationJobs(jobs)
    }

    private func runTranslationJobs(_ jobs: [ListTranslationJob]) async {
        let session = store.beginListTranslationSession()
        isTranslatingAll = true
        translationDone = 0
        translationTotal = jobs.count

        // 整表一次交给底层并发池，避免「小批串行等待」把并发抵消掉
        // 仍按 batch 切片只为分段刷新进度与列表；批次间不落盘，结束统一 save
        for batch in jobs.chunked(into: translationBatchSize) {
            guard store.isListTranslationSessionActive(session) else {
                isTranslatingAll = false
                translationTotal = 0
                translationDone = 0
                store.saveToStorage()
                return
            }
            let results = await store.translateTexts(batch.map(\.text))
            var updates: [(id: UUID, title: String?, summary: String?)] = []
            updates.reserveCapacity(batch.count)
            for (job, result) in zip(batch, results) {
                translationDone += 1
                guard let result, !result.isEmpty else { continue }
                switch job.field {
                case .title:
                    updates.append((job.articleID, result, nil))
                case .summary:
                    updates.append((job.articleID, nil, result))
                }
            }
            if !updates.isEmpty {
                store.applyListTranslations(updates, persist: false)
            }
        }
        store.saveToStorage()

        isTranslatingAll = false
        translationDone = 0
        translationTotal = 0
    }

    /// 语言抽样：优先标题+摘要；正文只取前约 400 字符做 plainText，避免长文列表卡顿
    private static func languageSample(title: String, preview: String, content: String) -> String {
        if !title.isEmpty || !preview.isEmpty {
            let joined = [title, preview].filter { !$0.isEmpty }.joined(separator: "\n")
            // 标题摘要已够长则不必扫正文
            if joined.count >= 40 { return joined }
        }
        let head = content.count > 600 ? String(content.prefix(600)) : content
        let bodyHead = HTMLUtils.plainText(head)
        if bodyHead.count >= 40 { return String(bodyHead.prefix(240)) }
        return [title, preview, bodyHead].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// 列表翻译用：粗判文本是否已是目标中文，避免无谓请求
enum ListLanguageDetect {
    /// 文本是否已接近目标语言（用于跳过翻译）
    static func isMostlyTarget(_ text: String, language: AppLanguage) -> Bool {
        if language.isChinese { return isMostlyChinese(text) }
        if language == .ja { return isMostlyJapanese(text) }
        if language == .ko { return isMostlyKorean(text) }
        // 拉丁系：CJK 占比很低且拉丁字母足够
        return isMostlyLatin(text)
    }

    static func isMostlyJapanese(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var jp = 0, letters = 0
        for ch in trimmed {
            if ch.isNewline || ch.isWhitespace || ch.isPunctuation || ch.isSymbol || ch.isNumber { continue }
            letters += 1
            if let v = ch.unicodeScalars.first?.value {
                // Hiragana, Katakana, CJK
                if (0x3040...0x30FF).contains(v) || (0x4E00...0x9FFF).contains(v) { jp += 1 }
            }
        }
        guard letters > 0 else { return false }
        return Double(jp) / Double(letters) >= 0.35
    }

    static func isMostlyKorean(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var ko = 0, letters = 0
        for ch in trimmed {
            if ch.isNewline || ch.isWhitespace || ch.isPunctuation || ch.isSymbol || ch.isNumber { continue }
            letters += 1
            if let v = ch.unicodeScalars.first?.value, (0xAC00...0xD7AF).contains(v) { ko += 1 }
        }
        guard letters > 0 else { return false }
        return Double(ko) / Double(letters) >= 0.35
    }

    static func isMostlyLatin(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var latin = 0, letters = 0, cjk = 0
        for ch in trimmed {
            if ch.isNewline || ch.isWhitespace || ch.isPunctuation || ch.isSymbol || ch.isNumber { continue }
            letters += 1
            if isCJK(ch) { cjk += 1 }
            else if ch.isLetter { latin += 1 }
        }
        guard letters > 0 else { return false }
        return Double(cjk) / Double(letters) < 0.15 && Double(latin) / Double(letters) >= 0.5
    }

    /// 汉字占比足够高，或短文本中含明显汉字时视为中文
    static func isMostlyChinese(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var cjk = 0
        var letters = 0
        for ch in trimmed {
            if ch.isNewline || ch.isWhitespace || ch.isPunctuation || ch.isSymbol || ch.isNumber {
                continue
            }
            letters += 1
            if isCJK(ch) { cjk += 1 }
        }
        guard letters > 0 else { return false }
        // 短标题：有 ≥2 个汉字且汉字 ≥ 拉丁字母
        if letters <= 12 {
            return cjk >= 2 && Double(cjk) / Double(letters) >= 0.4
        }
        return Double(cjk) / Double(letters) >= 0.35
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        switch v {
        case 0x4E00...0x9FFF,   // CJK Unified
             0x3400...0x4DBF,   // Extension A
             0xF900...0xFAFF,   // Compatibility
             0x3000...0x303F,   // CJK symbols/punct
             0xFF00...0xFFEF:   // Fullwidth
            return true
        default:
            return false
        }
    }
}

private struct ListTranslationJob {
    enum Field { case title, summary }
    let articleID: UUID
    let field: Field
    let text: String
}

// MARK: - Article Row

struct ArticleRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let article: Article
    let showTranslation: Bool
    /// 收藏页等场景：始终使用未读样式（强调色）
    var preferUnreadStyle: Bool = false

    /// 优先用 ForEach 传入的最新 article；仅在同 feed 内轻量回查（避免全库 flatMap）
    private var live: Article {
        let list = store.articlesForFeed(article.feedID)
        return list.first(where: { $0.id == article.id }) ?? article
    }

    private var displayTitle: String {
        let raw: String
        if showTranslation, let t = live.translatedTitle, !t.isEmpty { raw = t }
        else { raw = live.title }
        // 列表标题通常已是纯文本；仅在含标签时去标签
        return raw.contains("<") ? HTMLUtils.plainText(raw) : raw
    }

    private var displaySummary: String {
        let raw: String
        if showTranslation, let t = live.translatedSummary, !t.isEmpty { raw = t }
        else { raw = live.summary }
        return raw.contains("<") ? HTMLUtils.plainText(raw) : raw
    }

    var body: some View {
        let item = live
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 6) {
                    Text(displayTitle)
                        .font(AppTypography.font(size: store.listTitleFontSize, weight: (preferUnreadStyle || !item.isRead) ? .semibold : .regular))
                        .foregroundStyle((preferUnreadStyle || !item.isRead) ? theme.text : theme.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: max(11, store.listTitleFontSize - 6)))
                            .foregroundStyle(.orange)
                            .padding(.top, 3)
                    }
                }
                if showTranslation && store.titleDisplayMode == .bilingual && item.translatedTitle != nil {
                    Text(item.title).font(.system(size: max(12, store.listTitleFontSize - 4)))
                        .foregroundStyle(Color.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(item.feedTitle).font(.system(size: max(11, store.listSummaryFontSize - 2))).foregroundStyle(Color.secondary)
                    if !item.relativeTime.isEmpty {
                        Text("·").font(.system(size: max(11, store.listSummaryFontSize - 2))).foregroundStyle(Color.secondary.opacity(0.6))
                        Text(item.relativeTime).font(.system(size: max(11, store.listSummaryFontSize - 2))).foregroundStyle(Color.secondary)
                    }
                    if store.smartInterestFilterEnabled, let score = item.interestScore {
                        Text("·").font(.system(size: max(11, store.listSummaryFontSize - 2))).foregroundStyle(Color.secondary.opacity(0.6))
                        Text(String(format: "%.0f%%", score * 100))
                            .font(.system(size: max(11, store.listSummaryFontSize - 2)))
                            .foregroundStyle(score < store.lowInterestThreshold ? Color.orange : Color.secondary)
                    }
                }
                if store.smartInterestFilterEnabled,
                   let score = item.interestScore,
                   score < store.lowInterestThreshold,
                   let reason = store.interestExplanation(for: item) {
                    Text(reason)
                        .font(.system(size: max(10, store.listSummaryFontSize - 3)))
                        .foregroundStyle(.orange.opacity(0.9))
                        .lineLimit(2)
                }
                // 仅对已读且配置了黑名单的条目计算，避免列表滚动时全量扫描
                if item.isRead, !store.articleBlacklistTerms.isEmpty,
                   let bl = store.articleBlacklistReason(for: item) {
                    Text(bl)
                        .font(.system(size: max(10, store.listSummaryFontSize - 3)))
                        .foregroundStyle(.red.opacity(0.85))
                        .lineLimit(1)
                }
                if !displaySummary.isEmpty {
                    Text(displaySummary)
                        .font(.system(size: store.listSummaryFontSize))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                    if showTranslation && store.titleDisplayMode == .bilingual
                        && item.translatedSummary != nil && !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.system(size: max(12, store.listSummaryFontSize - 2)))
                            .foregroundStyle(Color.secondary.opacity(0.8))
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 14)
            Divider()
        }
    }
}
