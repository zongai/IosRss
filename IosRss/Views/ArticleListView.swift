import SwiftUI

struct ArticleListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let feed: RSSFeed

    @State private var selectedArticle: Article?
    @State private var showAllTranslations = false
    @State private var isTranslatingAll = false
    @State private var isInitialLoading = false
    @State private var translationDone = 0
    @State private var translationTotal = 0

    /// 列表翻译每批条数（标题 + 预览各算一条任务）
    private let translationBatchSize = 6

    /// 自动隐藏已读文章
    private var articles: [Article] {
        store.articlesForFeed(feed.id).filter { !$0.isRead }
    }

    private var liveFeedTitle: String {
        store.feeds.first(where: { $0.id == feed.id })?.title ?? feed.title
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(articles) { article in
                    Button {
                        store.markAsRead(article)
                        selectedArticle = article
                    } label: {
                        ArticleRow(article: article, showTranslation: showAllTranslations)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .animation(.default, value: articles.map(\.id))
            .navigationTitle(liveFeedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                            Text("Feed")
                        }
                        .foregroundStyle(.primary)
                    }
                }
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
                            Text("译")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(showAllTranslations ? Color(.systemBackground) : Color.primary)
                                .frame(width: 26, height: 26)
                                .background(showAllTranslations ? Color.primary : Color.secondary.opacity(0.15),
                                            in: .rect(cornerRadius: 6))
                        }
                    }
                    .disabled(isTranslatingAll)

                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await store.refreshFeed(feed.id) }
                    }
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
                    ContentUnavailableView("暂无文章", systemImage: "newspaper",
                                          description: Text("下拉刷新或稍后再来"))
                }
            }
            .refreshable { await store.refreshFeed(feed.id) }
            .task(id: feed.id) {
                await loadIfNeeded()
            }
        }
        // Article reader — nested under the article list, so returning from
        // the reader comes back here rather than jumping to the feed list.
        .sheet(item: $selectedArticle) { article in
            ArticleReaderView(article: article)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
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
        // 立刻展示已有译文，其余分批补齐
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
            for (job, result) in zip(batch, results) {
                translationDone += 1
                guard let result, !result.isEmpty else { continue }
                guard var article = store.articlesForFeed(feed.id).first(where: { $0.id == job.articleID }) else {
                    continue
                }
                switch job.field {
                case .title:
                    article.translatedTitle = result
                case .summary:
                    article.translatedSummary = result
                }
                store.updateArticle(article)
            }
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

    var displayTitle: String {
        if showTranslation, let t = article.translatedTitle { return t }
        return article.title
    }

    var displaySummary: String {
        if showTranslation, let t = article.translatedSummary { return t }
        return article.summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle)
                    .font(.system(size: 16, weight: article.isRead ? .regular : .semibold))
                    .foregroundStyle(article.isRead ? Color.secondary : Color.primary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if showTranslation && store.titleDisplayMode == .bilingual && article.translatedTitle != nil {
                    Text(article.title).font(.system(size: 13))
                        .foregroundStyle(Color.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(article.feedTitle).font(.system(size: 12)).foregroundStyle(Color.secondary)
                    if !article.relativeTime.isEmpty {
                        Text("·").font(.system(size: 12)).foregroundStyle(Color.secondary.opacity(0.6))
                        Text(article.relativeTime).font(.system(size: 12)).foregroundStyle(Color.secondary)
                    }
                }
                if !displaySummary.isEmpty {
                    Text(displaySummary)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                    if showTranslation && store.titleDisplayMode == .bilingual
                        && article.translatedSummary != nil && !article.summary.isEmpty {
                        Text(article.summary)
                            .font(.system(size: 12))
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
