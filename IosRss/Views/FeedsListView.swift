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
    @State private var renameFeedTarget: RSSFeed?
    @State private var renameFeedText = ""
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
                        let groupID = section.group?.id
                        let collapsed = store.isGroupCollapsed(groupID)
                        let unreadSum = section.feeds.reduce(0) { $0 + $1.unreadCount }
                        Section {
                            if !collapsed {
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
                                    .contextMenu {
                                        Button {
                                            renameFeedTarget = feed
                                            renameFeedText = feed.title
                                        } label: {
                                            Label("重命名", systemImage: "pencil")
                                        }
                                        let fullOn = store.feeds.first(where: { $0.id == feed.id })?.fetchFullContentEnabled ?? true
                                        Button {
                                            store.setFeedFetchFullContent(feed.id, enabled: !fullOn)
                                        } label: {
                                            Label(fullOn ? "关闭全文获取" : "开启全文获取",
                                                  systemImage: fullOn ? "doc.badge.ellipsis" : "doc.richtext")
                                        }
                                        let commentsOn = store.feeds.first(where: { $0.id == feed.id })?.fetchCommentsEnabled ?? false
                                        Button {
                                            store.setFeedFetchComments(feed.id, enabled: !commentsOn)
                                        } label: {
                                            Label(commentsOn ? "关闭评论获取" : "开启评论获取",
                                                  systemImage: commentsOn ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                        }
                                        Button { moveFeedTarget = feed } label: {
                                            Label("移动到分组…", systemImage: "folder")
                                        }
                                        if feed.groupID != nil {
                                            Button { store.moveFeed(feed.id, toGroup: nil) } label: {
                                                Label("移出分组", systemImage: "folder.badge.minus")
                                            }
                                        }
                                        ForEach(store.groups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                                            if feed.groupID != group.id {
                                                Button { store.moveFeed(feed.id, toGroup: group.id) } label: {
                                                    Label(group.name, systemImage: "folder.fill")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } header: {
                            GroupSectionHeader(
                                title: section.group?.name ?? "未分组",
                                feedCount: section.feeds.count,
                                unreadCount: unreadSum,
                                isCollapsed: collapsed
                            ) {
                                withAnimation(.snappy(duration: 0.22)) {
                                    store.toggleGroupCollapsed(groupID)
                                }
                            }
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
            Button("导出为 OPML") { prepareExport(kind: .opml) }
            Button("导出为 TXT") { prepareExport(kind: .txt) }
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
        .alert("重命名订阅源", isPresented: Binding(
            get: { renameFeedTarget != nil },
            set: { if !$0 { renameFeedTarget = nil } }
        )) {
            TextField("源名称", text: $renameFeedText)
            Button("保存") {
                if let feed = renameFeedTarget {
                    store.renameFeed(feed.id, to: renameFeedText)
                }
                renameFeedTarget = nil
            }
            Button("取消", role: .cancel) { renameFeedTarget = nil }
        } message: {
            Text("修改后将同步更新该源下文章的来源名称")
        }
        .alert("导入结果", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
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
        guard !content.isEmpty,
              let url = store.writeExportFile(content: content, filename: filename) else {
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
        guard let data, !data.isEmpty else {
            importMessage = "无法读取该文件（\(url.lastPathComponent)）"
            return
        }
        if ext == "txt" {
            importMessage = importTXT(data: data)
            return
        }
        let imported = store.importSubscriptions(data: data)
        if imported.added == 0 && imported.skipped == 0 {
            importMessage = "未能识别有效订阅"
        } else {
            var text = "已导入 \(imported.added) 个订阅"
            if imported.skipped > 0 { text += "，跳过 \(imported.skipped) 个已存在的源" }
            importMessage = text
            if imported.added > 0 { Task { await store.refreshAll() } }
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
                    title: title, url: url,
                    faviconURL: FeedParser.siteFaviconURL(for: url),
                    groupID: groupID
                ))
                added += 1
                pendingTitle = nil
            } else {
                pendingTitle = line
            }
        }
        if added == 0 && skipped == 0 { return "TXT 中未找到有效的订阅地址" }
        var msg = "已从 TXT 导入 \(added) 个订阅"
        if skipped > 0 { msg += "，跳过 \(skipped) 个已存在的源" }
        if added > 0 { Task { await store.refreshAll() } }
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
