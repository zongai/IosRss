import SwiftUI

struct ArticleListView: View {
    @Environment(AppStore.self) private var store
    let feed: RSSFeed
    @Binding var isPresented: Bool
    let onOpenArticle: (Article) -> Void

    private var articles: [Article] { store.articlesForFeed(feed.id) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(articles) { article in
                    Button {
                        store.markAsRead(article)
                        onOpenArticle(article)
                    } label: { ArticleRow(article: article) }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .navigationTitle(feed.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                            Text("Feed")
                        }
                        .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await store.refreshFeed(feed.id) }
                    }
                }
            }
            .overlay {
                if articles.isEmpty {
                    ContentUnavailableView("暂无文章", systemImage: "newspaper",
                                          description: Text("下拉刷新或稍后再来"))
                }
            }
            .refreshable { await store.refreshFeed(feed.id) }
        }
    }
}

// MARK: - Article Row

struct ArticleRow: View {
    @Environment(AppStore.self) private var store
    let article: Article
    @State private var isTranslatingTitle = false
    @State private var translatedTitle: String?
    @State private var showTranslation = false

    var displayTitle: String {
        if showTranslation, let t = translatedTitle ?? article.translatedTitle { return t }
        return article.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayTitle)
                            .font(.system(size: 16, weight: article.isRead ? .regular : .semibold))
                            .foregroundStyle(article.isRead ? .secondary : .primary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        if showTranslation && store.titleDisplayMode == .bilingual {
                            Text(article.title).font(.system(size: 13))
                                .foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 6)
                    translateButton
                }
                HStack(spacing: 6) {
                    Text(article.feedTitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    if !article.relativeTime.isEmpty {
                        Text("·").font(.system(size: 12)).foregroundStyle(.tertiary)
                        Text(article.relativeTime).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                if !article.summary.isEmpty {
                    Text(article.summary).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.vertical, 14)
            Divider()
        }
    }

    var translateButton: some View {
        Button { Task { await toggleTranslation() } } label: {
            if isTranslatingTitle {
                ProgressView().scaleEffect(0.65).frame(width: 24, height: 24)
            } else {
                Text("译").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(showTranslation ? .white : .secondary)
                    .frame(width: 24, height: 24)
                    .background(showTranslation ? .black : Color.secondary.opacity(0.12),
                                in: .rect(cornerRadius: 4))
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleTranslation() async {
        if showTranslation { showTranslation = false; return }
        if let cached = article.translatedTitle { translatedTitle = cached; showTranslation = true; return }
        isTranslatingTitle = true
        if let result = try? await store.translateText(article.title) {
            translatedTitle = result
            var updated = article; updated.translatedTitle = result
            store.updateArticle(updated); showTranslation = true
        }
        isTranslatingTitle = false
    }
}
