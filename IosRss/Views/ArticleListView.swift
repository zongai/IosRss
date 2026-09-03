import SwiftUI

struct ArticleListView: View {
    @Environment(AppStore.self) private var store
    let feed: RSSFeed
    @Binding var isPresented: Bool

    @State private var selectedArticle: Article?
    @State private var showArticle = false
    @State private var showAllTranslations = false
    @State private var isTranslatingAll = false

    private var articles: [Article] {
        store.articlesForFeed(feed.id).filter { !$0.isRead }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(articles) { article in
                    Button {
                        store.markAsRead(article)
                        selectedArticle = article
                        showArticle = true
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleTranslateAll() }
                    } label: {
                        if isTranslatingAll {
                            ProgressView().scaleEffect(0.75)
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
                if articles.isEmpty {
                    ContentUnavailableView("暂无文章", systemImage: "newspaper",
                                          description: Text("下拉刷新或稍后再来"))
                }
            }
            .refreshable { await store.refreshFeed(feed.id) }
        }
        .sheet(isPresented: $showArticle) {
            if let article = selectedArticle {
                ArticleReaderView(article: article, isPresented: $showArticle)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    private func toggleTranslateAll() async {
        if showAllTranslations {
            showAllTranslations = false
            return
        }
        let needTranslation = articles.filter { $0.translatedTitle == nil }
        if !needTranslation.isEmpty {
            isTranslatingAll = true
            for article in needTranslation {
                if let result = try? await store.translateText(article.title) {
                    var updated = article
                    updated.translatedTitle = result
                    store.updateArticle(updated)
                }
            }
            isTranslatingAll = false
        }
        showAllTranslations = true
    }
}

struct ArticleRow: View {
    @Environment(AppStore.self) private var store
    let article: Article
    let showTranslation: Bool

    var displayTitle: String {
        if showTranslation, let t = article.translatedTitle { return t }
        return article.title
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
                if !article.summary.isEmpty {
                    Text(article.summary).font(.system(size: 13)).foregroundStyle(Color.secondary).lineLimit(2)
                }
            }
            .padding(.vertical, 14)
            Divider()
        }
    }
}
