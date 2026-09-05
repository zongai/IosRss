import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FeedsListView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddFeed = false
    @State private var showOPMLMenu = false
    @State private var showOPMLImport = false
    @State private var showGroupManager = false
    @State private var exportFileURL: URL?
    @State private var showExportPicker = false
    @State private var importMessage: String?
    @State private var moveFeedTarget: RSSFeed?
    @State private var newGroupName = ""
    @State private var showNewGroupAlert = false

    private static let allowedImportExtensions: Set<String> = ["opml", "xml", "rss", "atom", "txt"]

    var body: some View {
        NavigationStack {
            List {
                if store.feeds.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(store.feedsByGroup.enumerated()), id: \.offset) { _, section in
                        Section {
                            ForEach(section.feeds) { feed in
                                NavigationLink(value: feed) {
                                    FeedRow(feed: feed)
                                }
                                .id("\(feed.id.uuidString)-\(feed.unreadCount)-\(feed.groupID?.uuidString ?? "")")
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
                                .swipeActions(edge: .leading) {
                                    Button { moveFeedTarget = feed } label: {
                                        Label("分组", systemImage: "folder")
                                    }.tint(.orange)
                                }
                            }
                        } header: {
                            Text(section.group?.name ?? "未分组")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: RSSFeed.self) { feed in
                ArticleListView(feed: feed)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 18) {
                        Button { showGroupManager = true } label: {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("管理分组")
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
        .sheet(isPresented: $showGroupManager) { GroupManagerView() }
        .confirmationDialog("导入/导出", isPresented: $showOPMLMenu) {
            Button("导入 OPML / XML / TXT") { showOPMLImport = true }
            Button("导出 OPML（选保存位置）") { prepareExport(kind: .opml) }
            Button("导出 TXT（选保存位置）") { prepareExport(kind: .txt) }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showOPMLImport) {
            OPMLDocumentPicker { url in
                showOPMLImport = false
                if let url { importFile(from: url) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showExportPicker) {
            if let exportFileURL {
                DocumentExportPicker(fileURL: exportFileURL) {
                    showExportPicker = false
                    self.exportFileURL = nil
                }
                .ignoresSafeArea()
            }
        }
        .confirmationDialog(
            "移动到分组",
            isPresented: Binding(
                get: { moveFeedTarget != nil },
                set: { if !$0 { moveFeedTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("未分组") {
                if let feed = moveFeedTarget { store.moveFeed(feed.id, toGroup: nil) }
                moveFeedTarget = nil
            }
            ForEach(store.groups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                Button(group.name) {
                    if let feed = moveFeedTarget { store.moveFeed(feed.id, toGroup: group.id) }
                    moveFeedTarget = nil
                }
            }
            Button("新建分组…") { showNewGroupAlert = true }
            Button("取消", role: .cancel) { moveFeedTarget = nil }
        }
        .alert("新建分组", isPresented: $showNewGroupAlert) {
            TextField("分组名称", text: $newGroupName)
            Button("创建") {
                let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                store.addGroup(name: name)
                if let feed = moveFeedTarget,
                   let g = store.groups.first(where: { $0.name == name }) {
                    store.moveFeed(feed.id, toGroup: g.id)
                }
                newGroupName = ""
                moveFeedTarget = nil
            }
            Button("取消", role: .cancel) {
                newGroupName = ""
                moveFeedTarget = nil
            }
        } message: {
            Text("输入新分组名称")
        }
        .alert("导入结果", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil }
            }
        )) {
            Button("好", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private enum ExportKind { case opml, txt }

    private func prepareExport(kind: ExportKind) {
        let content: String
        let filename: String
        switch kind {
        case .opml:
            content = store.exportOPML()
            filename = "IosRss-subscriptions.opml"
        case .txt:
            content = store.exportTXT()
            filename = "IosRss-subscriptions.txt"
        }
        guard let url = store.writeExportFile(content: content, filename: filename) else {
            importMessage = "无法创建导出文件"
            return
        }
        exportFileURL = url
        showExportPicker = true
    }

    private func importFile(from url: URL) {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, !Self.allowedImportExtensions.contains(ext) {
            importMessage = "仅支持 .opml / .xml / .rss / .atom / .txt 文件（当前：.\(ext)）"
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
        if data == nil { data = try? Data(contentsOf: url) }
        if data == nil, let copied = try? Data(contentsOf: URL(fileURLWithPath: url.path)) {
            data = copied
        }
        guard let data, !data.isEmpty else {
            importMessage = "无法读取该文件（\(url.lastPathComponent)）"
            return
        }

        if ext == "txt" {
            importMessage = importTXT(data: data)
            return
        }

        if ext.isEmpty {
            let head = String(data: data.prefix(200), encoding: .utf8)?.lowercased() ?? ""
            let looksOK = head.contains("opml") || head.contains("outline")
                || head.contains("<rss") || head.contains("<feed")
                || head.contains("http://") || head.contains("https://")
            if !looksOK {
                importMessage = "仅支持 OPML / XML / RSS / Atom / TXT 订阅文件"
                return
            }
        }
        let imported = store.importSubscriptions(data: data)
        if imported.added == 0 && imported.skipped == 0 {
            let head = String(data: data.prefix(400), encoding: .utf8) ?? ""
            if head.localizedCaseInsensitiveContains("opml")
                || head.localizedCaseInsensitiveContains("outline")
                || head.localizedCaseInsensitiveContains("xmlUrl") {
                importMessage = "已识别为 OPML，但未找到有效的 xmlUrl 订阅地址"
            } else if head.localizedCaseInsensitiveContains("<rss")
                        || head.localizedCaseInsensitiveContains("<feed") {
                importMessage = "已识别为 RSS/Atom，但未找到可用的源地址"
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
    }

    private func importTXT(data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            return "无法解析 TXT 文件"
        }
        var currentGroup: String? = nil
        var pendingTitle: String? = nil
        var added = 0
        var skipped = 0
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let name = line.dropFirst().trimmingCharacters(in: .whitespaces)
                currentGroup = name.isEmpty || name == "未分组" ? nil : String(name)
                pendingTitle = nil
                continue
            }
            let lower = line.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("feed://") {
                let url = FeedURL.canonical(line)
                if store.feeds.contains(where: { FeedURL.canonical($0.url) == url }) {
                    skipped += 1
                    pendingTitle = nil
                    continue
                }
                var groupID: UUID?
                if let gName = currentGroup {
                    if let existing = store.groups.first(where: { $0.name == gName }) {
                        groupID = existing.id
                    } else {
                        store.addGroup(name: gName)
                        groupID = store.groups.first(where: { $0.name == gName })?.id
                    }
                }
                let title = FeedNaming.resolveTitle(parsed: pendingTitle, url: url)
                store.addFeed(RSSFeed(
                    title: title,
                    url: url,
                    faviconURL: FeedParser.siteFaviconURL(for: url),
                    groupID: groupID
                ))
                added += 1
                pendingTitle = nil
            } else {
                pendingTitle = line
            }
        }
        if added == 0 && skipped == 0 {
            return "TXT 中未找到有效的订阅地址"
        }
        var msg = "已从 TXT 导入 \(added) 个订阅"
        if skipped > 0 { msg += "，跳过 \(skipped) 个已存在的源" }
        if added > 0 {
            Task { await store.refreshAll() }
        }
        return msg
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

struct GroupManagerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renameTarget: FeedGroup?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.groups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(group.name)
                            Spacer()
                            Text("\(store.feeds.filter { $0.groupID == group.id }.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            renameTarget = group
                            renameText = group.name
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteGroup(group.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("已有分组")
                } footer: {
                    Text("点分组可重命名；删除分组后源会回到「未分组」。左滑源可移动分组。")
                }

                Section("新建分组") {
                    HStack {
                        TextField("分组名称", text: $newName)
                        Button("添加") {
                            store.addGroup(name: newName)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("管理分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("重命名分组", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("名称", text: $renameText)
                Button("保存") {
                    if let g = renameTarget {
                        store.renameGroup(g.id, to: renameText)
                    }
                    renameTarget = nil
                }
                Button("取消", role: .cancel) { renameTarget = nil }
            }
        }
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
        .padding(.vertical, 6)
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
                Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else if loading {
                ProgressView().frame(width: size, height: size)
            } else {
                letterFallback
            }
        }
        .task(id: feed.id) { await loadIcon() }
    }
    private var letterFallback: some View {
        ZStack {
            Circle().fill(Color.primary).frame(width: size, height: size)
            Text(String(feed.title.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(Color(.systemBackground))
        }
    }
    private func loadIcon() async {
        if image != nil || useLetter { return }
        if let cached = FaviconCache.shared.image(for: cacheKey) { image = cached; return }
        if let data = OfflineCache.loadImage(url: cacheKey) {
            if data.isEmpty { useLetter = true; return }
            if let ui = UIImage(data: data), ui.size.width > 1 {
                FaviconCache.shared.store(ui, for: cacheKey); image = ui; return
            }
        }
        loading = true
        defer { loading = false }
        var candidates: [String] = []
        if let preferred = feed.faviconURL, !preferred.isEmpty { candidates.append(preferred) }
        else if let first = FeedParser.faviconCandidates(for: feed.url).first { candidates.append(first) }
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0).inserted }
        for urlStr in candidates {
            if let cached = FaviconCache.shared.image(for: urlStr) { commitSuccess(cached, sourceURL: urlStr); return }
            if let data = OfflineCache.loadImage(url: urlStr), let ui = UIImage(data: data), ui.size.width > 1 {
                FaviconCache.shared.store(ui, for: urlStr); commitSuccess(ui, sourceURL: urlStr); return
            }
            guard let url = URL(string: urlStr) else { continue }
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 6
                req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { continue }
                guard data.count > 32, let ui = UIImage(data: data), ui.size.width > 1 else { continue }
                OfflineCache.saveImage(url: urlStr, data: data)
                FaviconCache.shared.store(ui, for: urlStr)
                commitSuccess(ui, sourceURL: urlStr)
                return
            } catch { continue }
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
    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
    }
}

struct OPMLDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
    }
}

struct DocumentExportPicker: UIViewControllerRepresentable {
    let fileURL: URL
    var onFinish: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish() }
    }
}
