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
    private let translationBatchSize = 6

    private var articles: [Article] {
        // 显式依赖 openedArticleID / readingIDs，保证返回后重新过滤
        let _ = openedArticleID
        let _ = readingIDs
        let all = store.articlesForFeed(feed.id)
            .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
        if store.showReadArticles {
            return all
        }
        return all.filter { article in
            !article.isRead || readingIDs.contains(article.id) || openedArticleID == article.id
        }
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
                // Article == 只比 id；并入 isRead 以便已读样式与过滤同步
                .id("\(article.id.uuidString)-\(article.isRead)-\(article.translatedTitle ?? "")-\(article.translatedSummary ?? "")-\(showAllTranslations)")
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
                }
            }
        }
        .listStyle(.plain)
        .animation(.snappy(duration: 0.25), value: articles.map(\.id))
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
                ContentUnavailableView(
                    store.showReadArticles ? "暂无文章" : "暂无未读文章",
                    systemImage: "newspaper",
                    description: Text(store.showReadArticles ? "下拉刷新或稍后再来" : "可在设置中开启「显示已读文章」")
                )
            }
        }
        .refreshable {
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
            await autoTranslatePending(force: false)
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
        let feedEnabled = live?.autoTranslateEnabled ?? true
        guard feedEnabled else { return }
        // 使用源内全部文章（不仅是当前可见未读），避免过滤导致跳过
        let snapshot = store.articlesForFeed(feed.id)
        var jobs: [ListTranslationJob] = []
        jobs.reserveCapacity(snapshot.count * 2)
        var skipMark: [(id: UUID, title: String?, summary: String?)] = []

        for article in snapshot {
            if !force && autoTranslateAttemptedIDs.contains(article.id) { continue }
            autoTranslateAttemptedIDs.insert(article.id)

            // 标题
            if article.translatedTitle == nil {
                let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if title.isEmpty {
                    // skip
                } else if ListLanguageDetect.isMostlyTarget(title, language: store.targetLanguage) {
                    // 已是目标语言：写入原文作译文，避免下次再判
                    skipMark.append((article.id, title, nil))
                } else {
                    jobs.append(ListTranslationJob(articleID: article.id, field: .title, text: title))
                }
            }

            // 摘要预览
            let preview = article.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if article.translatedSummary == nil && !preview.isEmpty {
                if ListLanguageDetect.isMostlyTarget(preview, language: store.targetLanguage) {
                    skipMark.append((article.id, nil, preview))
                } else {
                    jobs.append(ListTranslationJob(articleID: article.id, field: .summary, text: preview))
                }
            }
        }

        if !skipMark.isEmpty {
            store.applyListTranslations(skipMark)
            showAllTranslations = true
        }
        guard !jobs.isEmpty else {
            if snapshot.contains(where: {
                ($0.translatedTitle?.isEmpty == false) || ($0.translatedSummary?.isEmpty == false)
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
        for article in snapshot {
            if article.translatedTitle == nil {
                let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    if ListLanguageDetect.isMostlyTarget(title, language: store.targetLanguage) {
                        store.applyListTranslations([(article.id, title, nil)])
                    } else {
                        jobs.append(ListTranslationJob(articleID: article.id, field: .title, text: title))
                    }
                }
            }
            let preview = article.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if article.translatedSummary == nil && !preview.isEmpty {
                if ListLanguageDetect.isMostlyTarget(preview, language: store.targetLanguage) {
                    store.applyListTranslations([(article.id, nil, preview)])
                } else {
                    jobs.append(ListTranslationJob(articleID: article.id, field: .summary, text: preview))
                }
            }
        }
        guard !jobs.isEmpty else { return }
        await runTranslationJobs(jobs)
    }

    private func runTranslationJobs(_ jobs: [ListTranslationJob]) async {
        isTranslatingAll = true
        translationDone = 0
        translationTotal = jobs.count

        for batch in jobs.chunked(into: translationBatchSize) {
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
                store.applyListTranslations(updates)
            }
            await Task.yield()
        }

        isTranslatingAll = false
        translationDone = 0
        translationTotal = 0
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

    /// 始终取 store 中最新文章（已读/收藏/译文），避免 ForEach 快照滞后
    private var live: Article {
        store.feeds.flatMap(\.articles).first(where: { $0.id == article.id }) ?? article
    }

    var displayTitle: String {
        if showTranslation, let t = live.translatedTitle { return t }
        return live.title
    }

    var displaySummary: String {
        if showTranslation, let t = live.translatedSummary { return t }
        return live.summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 6) {
                    Text(displayTitle)
                        .font(AppTypography.font(size: store.listTitleFontSize, weight: (preferUnreadStyle || !live.isRead) ? .semibold : .regular))
                        .foregroundStyle((preferUnreadStyle || !live.isRead) ? theme.text : theme.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if live.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: max(11, store.listTitleFontSize - 6)))
                            .foregroundStyle(.orange)
                            .padding(.top, 3)
                    }
                }
                if showTranslation && store.titleDisplayMode == .bilingual && live.translatedTitle != nil {
                    Text(live.title).font(.system(size: max(12, store.listTitleFontSize - 4)))
                        .foregroundStyle(Color.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(live.feedTitle).font(.system(size: max(11, store.listSummaryFontSize - 2))).foregroundStyle(Color.secondary)
                    if !live.relativeTime.isEmpty {
                        Text("·").font(.system(size: max(11, store.listSummaryFontSize - 2))).foregroundStyle(Color.secondary.opacity(0.6))
                        Text(live.relativeTime).font(.system(size: max(11, store.listSummaryFontSize - 2))).foregroundStyle(Color.secondary)
                    }
                }
                if !displaySummary.isEmpty {
                    Text(displaySummary)
                        .font(.system(size: store.listSummaryFontSize))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                    if showTranslation && store.titleDisplayMode == .bilingual
                        && live.translatedSummary != nil && !live.summary.isEmpty {
                        Text(live.summary)
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
