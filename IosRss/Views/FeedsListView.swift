import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FeedsListView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddFeed = false
    @State private var showOPMLMenu = false
    @State private var showOPMLImport = false
    @State private var showOPMLExportSheet = false
    @State private var opmlExportText = ""
    @State private var importMessage: String?

    /// 仅展示可导入类型：OPML / XML / RSS / Atom（按扩展名与标准 UTI，不含 public.data）
    private var importTypes: [UTType] {
        var types: [UTType] = [.xml]
        for ext in ["opml", "xml", "rss", "atom"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        if let t = UTType(mimeType: "application/xml") { types.append(t) }
        if let t = UTType(mimeType: "text/xml") { types.append(t) }
        if let t = UTType(mimeType: "application/rss+xml") { types.append(t) }
        if let t = UTType(mimeType: "application/atom+xml") { types.append(t) }
        var seen = Set<String>()
        return types.filter { seen.insert($0.identifier).inserted }
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
                        .id("\(feed.id.uuidString)-\(feed.unreadCount)")
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
        .fileImporter(
            isPresented: $showOPMLImport,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: false
        ) { result in
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

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importMessage = "未选择文件"
                return
            }
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
            if data == nil, let copied = try? Data(contentsOf: URL(fileURLWithPath: url.path)) {
                data = copied
            }
            guard let data, !data.isEmpty else {
                importMessage = "无法读取该文件（\(url.lastPathComponent)）"
                return
            }
            let imported = store.importSubscriptions(data: data)
            if imported.added == 0 && imported.skipped == 0 {
                let head = String(data: data.prefix(200), encoding: .utf8) ?? ""
                if head.localizedCaseInsensitiveContains("opml")
                    || head.localizedCaseInsensitiveContains("outline") {
                    importMessage = "已识别为 OPML，但未找到有效的 xmlUrl 订阅地址"
                } else {
                    importMessage = "未能识别为 OPML、RSS 或 Atom（\(url.lastPathComponent)）"
                }
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

    private var live: RSSFeed {
        store.feeds.first(where: { $0.id == feed.id }) ?? feed
    }

    var body: some View {
        HStack(spacing: 14) {
            FeedIcon(feed: live, size: 38)
            Text(live.title)
                .font(.system(size: store.feedTitleFontSize, weight: .medium))
                .foregroundStyle(Color.primary)
            Spacer()
            if live.unreadCount > 0 {
                Text("\(live.unreadCount)")
                    .font(.system(size: max(11, store.feedTitleFontSize - 4), weight: .bold))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary, in: .capsule)
                    .monospacedDigit()
                    .animation(.snappy(duration: 0.2), value: live.unreadCount)
            }
        }
        .padding(.vertical, 10)
        .id("\(live.id.uuidString)-\(live.unreadCount)-\(live.faviconURL ?? "")")
    }
}

struct FeedIcon: View {
    let feed: RSSFeed
    let size: CGFloat

    @State private var image: UIImage?
    @State private var loading = false
    @State private var useLetter = false

    private var cacheKey: String { "feed-icon:\(feed.id.uuidString)" }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if loading {
                ProgressView()
                    .frame(width: size, height: size)
            } else {
                letterFallback
            }
        }
        .task(id: feed.id) {
            await loadIcon()
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

    private func loadIcon() async {
        if image != nil || useLetter { return }

        if let cached = FaviconCache.shared.image(for: cacheKey) {
            image = cached
            return
        }

        if let data = OfflineCache.loadImage(url: cacheKey) {
            if data.isEmpty {
                useLetter = true
                return
            }
            if let ui = UIImage(data: data), ui.size.width > 1 {
                FaviconCache.shared.store(ui, for: cacheKey)
                image = ui
                return
            }
        }

        loading = true
        defer { loading = false }

        var candidates: [String] = []
        if let preferred = feed.faviconURL, !preferred.isEmpty {
            candidates.append(preferred)
        } else if let first = FeedParser.faviconCandidates(for: feed.url).first {
            candidates.append(first)
        }
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0).inserted }

        for urlStr in candidates {
            if let cached = FaviconCache.shared.image(for: urlStr) {
                commitSuccess(cached, sourceURL: urlStr)
                return
            }
            if let data = OfflineCache.loadImage(url: urlStr),
               let ui = UIImage(data: data), ui.size.width > 1 {
                FaviconCache.shared.store(ui, for: urlStr)
                commitSuccess(ui, sourceURL: urlStr)
                return
            }
            guard let url = URL(string: urlStr) else { continue }
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 6
                req.setValue(
                    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                    forHTTPHeaderField: "User-Agent"
                )
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    continue
                }
                guard data.count > 32, let ui = UIImage(data: data), ui.size.width > 1 else {
                    continue
                }
                OfflineCache.saveImage(url: urlStr, data: data)
                FaviconCache.shared.store(ui, for: urlStr)
                commitSuccess(ui, sourceURL: urlStr)
                return
            } catch {
                continue
            }
        }

        OfflineCache.saveImage(url: cacheKey, data: Data())
        useLetter = true
    }

    private func commitSuccess(_ ui: UIImage, sourceURL: String) {
        if let data = ui.pngData() ?? ui.jpegData(compressionQuality: 0.9) {
            OfflineCache.saveImage(url: cacheKey, data: data)
        }
        FaviconCache.shared.store(ui, for: cacheKey)
        image = ui
    }
}

final class FaviconCache {
    static let shared = FaviconCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 16 * 1024 * 1024
    }
    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    func store(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
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
