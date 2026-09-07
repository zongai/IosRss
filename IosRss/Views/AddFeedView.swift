import SwiftUI

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var urlText = ""
    @State private var isSearching = false
    @State private var discoveredFeeds: [DiscoveredFeed] = []
    @State private var errorMessage: String?
    @State private var phase: Phase = .input
    @FocusState private var isURLFocused: Bool
    /// 新源加入的分组；nil = 未分组
    @State private var selectedGroupID: UUID?
    @State private var showNewGroupAlert = false
    @State private var newGroupName = ""

    enum Phase { case input, discovering, select, adding }

    private var sortedGroups: [FeedGroup] {
        store.groups.sorted {
            $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name < $1.name)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // URL Input Area
                VStack(alignment: .leading, spacing: 8) {
                    Text("粘贴网站或 Feed 地址")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    HStack(spacing: 12) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        TextField("https://", text: $urlText)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isURLFocused)
                            .submitLabel(.search)
                            .onSubmit { Task { await discover() } }
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 10))
                    .padding(.horizontal, 20)

                    // 指定分组
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Picker("加入分组", selection: $selectedGroupID) {
                            Text("未分组").tag(Optional<UUID>.none)
                            ForEach(sortedGroups) { group in
                                Text(group.name).tag(Optional(group.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Spacer(minLength: 0)
                        Button {
                            newGroupName = ""
                            showNewGroupAlert = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .accessibilityLabel("新建分组")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 10))
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                if phase == .discovering {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在查找 Feed…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)
                }

                if !discoveredFeeds.isEmpty && phase == .select {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("发现以下 Feed，请选择：")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 8)

                        ForEach(discoveredFeeds) { feed in
                            Button {
                                Task { await addFeed(feed) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(feed.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.primary)
                                        Text(feed.url)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.primary)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 20)
                            }
                            Divider().padding(.leading, 20)
                        }
                    }
                }

                Spacer()

                Button {
                    Task { await discover() }
                } label: {
                    HStack {
                        if phase == .adding {
                            ProgressView().tint(.white)
                        } else {
                            Text(phase == .select ? "返回搜索" : "查找 Feed")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.primary)
                    .foregroundStyle(Color(.systemBackground))
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || phase == .discovering || phase == .adding)
            }
            .navigationTitle("添加订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("新建分组", isPresented: $showNewGroupAlert) {
                TextField("分组名称", text: $newGroupName)
                Button("创建") {
                    let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    store.addGroup(name: name)
                    if let g = store.groups.first(where: { $0.name == name }) {
                        selectedGroupID = g.id
                    }
                    newGroupName = ""
                }
                Button("取消", role: .cancel) { newGroupName = "" }
            } message: {
                Text("创建后将自动选中该分组")
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isURLFocused = true }
    }

    private func discover() async {
        let raw = urlText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        errorMessage = nil
        discoveredFeeds = []
        phase = .discovering

        var urlStr = raw
        if !urlStr.hasPrefix("http://") && !urlStr.hasPrefix("https://") {
            urlStr = "https://\(urlStr)"
        }
        guard let url = URL(string: urlStr) else {
            errorMessage = "无效的 URL"
            phase = .input
            return
        }

        do {
            let feeds = try await FeedDiscovery.discoverFeeds(from: url)
            if feeds.isEmpty {
                errorMessage = "未找到 Feed，请检查地址是否正确"
                phase = .input
            } else if feeds.count == 1 {
                await addFeed(feeds[0])
            } else {
                discoveredFeeds = feeds
                phase = .select
            }
        } catch {
            // Try parsing directly as feed
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let articles = FeedParser.parse(data: data, feedID: UUID(), feedTitle: "")
                if !articles.isEmpty {
                    let title = FeedNaming.resolveTitle(
                        parsed: FeedParser.extractFeedTitle(from: data),
                        url: urlStr
                    )
                    await addFeed(DiscoveredFeed(title: title, url: urlStr))
                } else {
                    errorMessage = "无法解析该地址的 Feed：\(error.localizedDescription)"
                    phase = .input
                }
            } catch {
                errorMessage = "网络错误：\(error.localizedDescription)"
                phase = .input
            }
        }
    }

    private func addFeed(_ discovered: DiscoveredFeed) async {
        phase = .adding
        guard let url = URL(string: discovered.url) else {
            errorMessage = "无效的 Feed URL"
            phase = .select
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            OfflineCache.saveFeedXML(url: discovered.url, data: data)
            let feedID = UUID()
            // 优先用 Feed 内 channel/title；没有再用 link 上的 title；仍没有则用域名
            let fromXML = FeedParser.extractFeedTitle(from: data)
            let fallbackName = (discovered.title != discovered.url
                                && discovered.title != FeedNaming.domainName(from: discovered.url))
                ? discovered.title : nil
            let resolvedTitle = FeedNaming.resolveTitle(
                parsed: fromXML ?? fallbackName,
                url: discovered.url
            )
            let articles = FeedParser.parse(data: data, feedID: feedID, feedTitle: resolvedTitle)
            let favicon = FeedParser.resolveFaviconURL(from: data, feedURL: discovered.url)
            // 若所选分组已被删除则回退为未分组
            let groupID: UUID? = {
                guard let gid = selectedGroupID else { return nil }
                return store.groups.contains(where: { $0.id == gid }) ? gid : nil
            }()
            let sampleLinks = articles.prefix(8).map(\.link)
            let enableComments = CommentFetcher.shouldAutoEnableComments(
                feedURL: discovered.url,
                sampleArticleLinks: Array(sampleLinks)
            )
            let feed = RSSFeed(
                id: feedID,
                title: resolvedTitle,
                url: discovered.url,
                faviconURL: favicon,
                unreadCount: articles.count,
                articles: articles,
                lastFetched: Date(),
                groupID: groupID,
                fetchCommentsEnabled: enableComments,
                faviconFetchDone: favicon != nil
            )
            store.addFeed(feed)
            dismiss()
        } catch {
            errorMessage = "订阅失败：\(error.localizedDescription)"
            phase = .select
        }
    }
}
