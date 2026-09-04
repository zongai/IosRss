import SwiftUI
import UniformTypeIdentifiers

struct FeedsListView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddFeed = false
    @State private var showOPMLMenu = false
    @State private var showOPMLImport = false
    @State private var showOPMLExportSheet = false
    @State private var opmlExportText = ""
    @State private var importMessage: String?

    private var importTypes: [UTType] {
        var types: [UTType] = [.xml, .text, .plainText, .data]
        if let opml = UTType(filenameExtension: "opml") { types.append(opml) }
        if let rss = UTType(filenameExtension: "rss") { types.append(rss) }
        if let atom = UTType(filenameExtension: "atom") { types.append(atom) }
        return types
    }

    var body: some View {
        NavigationStack {
            List {
                if store.feeds.isEmpty {
                    emptyState
                } else {
                    ForEach(store.feeds) { feed in
                        NavigationLink(value: feed) {
                            FeedRow(feed: feed)
                        }
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
            .navigationDestination(for: RSSFeed.self) { feed in
                ArticleListView(feed: feed)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 20) {
                        Button { showAddFeed = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("添加订阅")
                        Button { showOPMLMenu = true } label: {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("导入导出")
                    }
                }
            }
            .refreshable { await store.refreshAll() }
        }
        .sheet(isPresented: $showAddFeed) { AddFeedView() }
        .confirmationDialog("导入/导出", isPresented: $showOPMLMenu) {
            Button("导入 OPML / XML") { showOPMLImport = true }
            Button("导出 OPML") { opmlExportText = store.exportOPML(); showOPMLExportSheet = true }
            Button("取消", role: .cancel) {}
        }
        .fileImporter(isPresented: $showOPMLImport, allowedContentTypes: importTypes) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showOPMLExportSheet) { OPMLExportView(text: opmlExportText) }
        .alert("导入结果", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("好", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            var data: Data?
            let coordinator = NSFileCoordinator()
            var coordError: NSError?
            coordinator.coordinate(readingItemAt: url, error: &coordError) { coordinated in
                data = try? Data(contentsOf: coordinated)
            }
            if data == nil {
                data = try? Data(contentsOf: url)
            }
            guard let data else {
                importMessage = "无法读取该文件"
                return
            }
            let imported = store.importSubscriptions(data: data)
            if imported.added == 0 && imported.skipped == 0 {
                importMessage = "未能识别为 OPML、RSS 或 Atom，请检查文件内容"
            } else {
                let kind = imported.kind == "rss" ? "RSS/Atom" : "OPML"
                var text = "已从 \(kind) 导入 \(imported.added) 个订阅"
                if imported.skipped > 0 {
                    text += "，跳过 \(imported.skipped) 个已存在的源"
                }
                importMessage = text
                if imported.added > 0 {
                    Task { await store.refreshAll() }
                }
            }
        case .failure(let error):
            importMessage = error.localizedDescription
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
    @Environment(AppStore.self) private var store
    let feed: RSSFeed
    var body: some View {
        HStack(spacing: 14) {
            FeedIcon(feed: feed, size: 38)
            Text(feed.title)
                .font(.system(size: store.feedTitleFontSize, weight: .medium))
                .foregroundStyle(Color.primary)
            Spacer()
            if feed.unreadCount > 0 {
                Text("\(feed.unreadCount)")
                    .font(.system(size: max(11, store.feedTitleFontSize - 4), weight: .bold))
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
        Group {
            if let urlStr = feed.faviconURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    case .failure:
                        letterFallback
                    case .empty:
                        ProgressView()
                            .frame(width: size, height: size)
                    @unknown default:
                        letterFallback
                    }
                }
            } else {
                letterFallback
            }
        }
    }

    private var letterFallback: some View {
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
