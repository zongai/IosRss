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
        .navigationTitle(liveFeedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Article.self) { article in
            ArticleReaderView(article: article)
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
                    store.showReadArticles.toggle()
                    store.persistSettings()
                } label: {
                    Image(systemName: store.showReadArticles ? "eye" : "eye.slash")
                }
                .accessibilityLabel(store.showReadArticles ? "隐藏已读" : "显示已读")

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
                        Image(systemName: "globe")
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
                    description: Text(store.showReadArticles ? "下拉刷新或稍后再来" : "点右上角眼睛可显示已读文章")
                )
            }
        }
        .refreshable { await store.refreshFeed(feed.id) }
        .task(id: feed.id) {
            await loadIfNeeded()
            // 本 feed 已有缓存译文时，打开列表直接显示译文
            let hasCachedTranslation = store.articlesForFeed(feed.id).contains {
                ($0.translatedTitle?.isEmpty == false) || ($0.translatedSummary?.isEmpty == false)
            }
            if hasCachedTranslation {
                showAllTranslations = true
            }
        }
    }

    /// 第一次打开且本地还没有文章时自动拉取，避免空白列表
    private func loadIfNeeded() async {
        if !store.articlesForFeed(feed.id).isEmpty { return }
        isInitialLoading = true
        await store.refreshFeed(feed.id)
        isInitialLoading = false
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
                jobs.append(ListTranslationJob(articleID: article.id, field: .title, text: article.title))
            }
            let preview = article.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if article.translatedSummary == nil && !preview.isEmpty {
                jobs.append(ListTranslationJob(articleID: article.id, field: .summary, text: preview))
            }
        }
        guard !jobs.isEmpty else { return }

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
            // 让出主线程，确保本批翻译结果先刷新到列表（避免前几条卡住仍显示原文）
            await Task.yield()
        }

        isTranslatingAll = false
        translationDone = 0
        translationTotal = 0
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
    let article: Article
    let showTranslation: Bool

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
                        .font(.system(size: store.listTitleFontSize, weight: live.isRead ? .regular : .semibold))
                        .foregroundStyle(live.isRead ? Color.secondary : Color.primary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if live.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: max(11, store.listTitleFontSize - 6))
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
