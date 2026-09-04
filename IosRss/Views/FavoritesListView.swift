import SwiftUI

struct FavoritesListView: View {
    @Environment(AppStore.self) private var store
    @State private var readingIDs: Set<UUID> = []

    private var articles: [Article] {
        store.allArticles.filter(\.isFavorite)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(articles) { article in
                    NavigationLink(value: article) {
                        ArticleRow(article: article, showTranslation: false)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.toggleFavorite(article)
                        } label: {
                            Label("取消收藏", systemImage: "star.slash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Article.self) { article in
                ArticleReaderView(article: article)
                    .onAppear {
                        readingIDs.insert(article.id)
                        store.markAsRead(article)
                    }
            }
            .overlay {
                if articles.isEmpty {
                    ContentUnavailableView {
                        Label("暂无收藏", systemImage: "star")
                    } description: {
                        Text("在文章列表左滑，或在阅读页点星号即可收藏。收藏的文章不会被自动清理。")
                    }
                }
            }
        }
    }
}
