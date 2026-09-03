import SwiftUI

struct FeedsListView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedFeed: RSSFeed?
    @State private var showAddFeed = false
    @State private var showOPMLMenu = false
    @State private var showOPMLImport = false
    @State private var showOPMLExportSheet = false
    @State private var opmlExportText = ""

    var body: some View {
        NavigationStack {
            List {
                if store.feeds.isEmpty {
                    emptyState
                } else {
                    ForEach(store.feeds) { feed in
                        Button {
                            // Use sheet(item:) so the first presentation always
                            // has a concrete feed (isPresented + optional was blank).
                            selectedFeed = feed
                        } label: { FeedRow(feed: feed) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if let idx = store.feeds.firstIndex(where: { $0.id == feed.id }) {
                                    store.deleteFeed(at: IndexSet([idx]))
                                }
                            } label: { Label("删除", systemImage: "trash") }
                            Button { Task { await store.refreshFeed(feed.id) } } label: {
                                Label("刷新", systemImage: "arrow.clockwise")
                            }.tint(.blue)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 20) {
                        Button { showAddFeed = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        Button { showOPMLMenu = true } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .refreshable { await store.refreshAll() }
        }
        .sheet(isPresented: $showAddFeed) { AddFeedView() }
        .confirmationDialog("导入/导出", isPresented: $showOPMLMenu) {
            Button("导入 OPML") { showOPMLImport = true }
            Button("导出 OPML") { opmlExportText = store.exportOPML(); showOPMLExportSheet = true }
            Button("取消", role: .cancel) {}
        }
        .fileImporter(isPresented: $showOPMLImport, allowedContentTypes: [.xml, .text]) { result in
            if case .success(let url) = result,
               url.startAccessingSecurityScopedResource(),
               let data = try? Data(contentsOf: url) {
                store.importOPML(data: data)
                url.stopAccessingSecurityScopedResource()
            }
        }
        .sheet(isPresented: $showOPMLExportSheet) { OPMLExportView(text: opmlExportText) }
        // Feed article list — presented from root; the article reader is
        // now presented from within ArticleListView, so back-navigation is
        // hierarchical: Reader → Article List → Feed List.
        .sheet(item: $selectedFeed) { feed in
            ArticleListView(feed: feed)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    var emptyState: some View {
        ContentUnavailableView {
            Label("暂无订阅", systemImage: "newspaper")
        } description: {
            Text("点击右上角 + 添加你的第一个 RSS 订阅源")
        } actions: {
            Button("添加订阅") { showAddFeed = true }.buttonStyle(.bordered)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(.init(top: 60, leading: 0, bottom: 0, trailing: 0))
    }
}

struct FeedRow: View {
    let feed: RSSFeed
    var body: some View {
        HStack(spacing: 14) {
            FeedIcon(feed: feed, size: 38)
            Text(feed.title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.primary)
            Spacer()
            if feed.unreadCount > 0 {
                Text("\(feed.unreadCount)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary, in: .capsule)
            }
        }
        .padding(.vertical, 10)
    }
}

struct FeedIcon: View {
    let feed: RSSFeed
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary)
                .frame(width: size, height: size)
            Text(String(feed.title.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(Color(.systemBackground))
        }
    }
}

struct OPMLExportView: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text).font(.system(size: 12, design: .monospaced)).padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("导出 OPML").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: text, subject: Text("Feed 订阅列表"), message: Text("Feed OPML Export"))
                }
            }
        }
    }
}
