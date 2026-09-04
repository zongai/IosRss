import SwiftUI

struct ArticleListView: View {
    @Environment(AppStore.self) private var store
    let feed: RSSFeed

    @State private var showAllTranslations = false
    @State private var isTranslatingAll = false
    @State private var isInitialLoading = false
    @State private var translationDone = 0
    @State private var translationTotal = 0
    @State private var readingIDs: Set<UUID> = []

    private let translationBatchSize = 6

    private var articles: [Article] {
        let all = store.articlesForFeed(feed.id)
            .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
        if store.showReadArticles {
            return all
        }
        return all.filter { !$0.isRead || readingIDs.contains($0.id) }
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
        .animation(.default, value: articles.map(\.id))
        .navigationTitle(liveFeedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Article.self) { article in
            ArticleReaderView(article: article)
                .onAppear {
                    readingIDs.insert(article.id)
                    store.markAsRead(article)
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
        }
    }

    private func loadIfNeeded() async {
        if !store.articlesForFeed(feed.id).isEmpty { return }
        isInitialLoading = true
        await store.refreshFeed(feed.id)
        isInitialLoading = false
    }

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
                HStack(alignment: .top, spacing: 6) {
                    Text(displayTitle)
                        .font(.system(size: 18, weight: article.isRead ? .regular : .semibold))
                        .foregroundStyle(article.isRead ? Color.secondary : Color.primary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if article.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .padding(.top, 3)
                    }
                }
                if showTranslation && store.titleDisplayMode == .bilingual && article.translatedTitle != nil {
                    Text(article.title).font(.system(size: 14))
                        .foregroundStyle(Color.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(article.feedTitle).font(.system(size: 13)).foregroundStyle(Color.secondary)
                    if !article.relativeTime.isEmpty {
                        Text("·").font(.system(size: 13)).foregroundStyle(Color.secondary.opacity(0.6))
                        Text(article.relativeTime).font(.system(size: 13)).foregroundStyle(Color.secondary)
                    }
                }
                if !displaySummary.isEmpty {
                    Text(displaySummary)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                    if showTranslation && store.titleDisplayMode == .bilingual
                        && article.translatedSummary != nil && !article.summary.isEmpty {
                        Text(article.summary)
                            .font(.system(size: 13))
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
