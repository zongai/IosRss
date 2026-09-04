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

    enum Phase { case input, discovering, select, adding }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
        }
        .presentationDetents([.medium])
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
            let feedID = UUID()
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
            let feed = RSSFeed(
                id: feedID,
                title: resolvedTitle,
                url: discovered.url,
                faviconURL: favicon,
                unreadCount: articles.count,
                articles: articles,
                lastFetched: Date()
            )
            store.addFeed(feed)
            dismiss()
        } catch {
            errorMessage = "订阅失败：\(error.localizedDescription)"
            phase = .select
        }
    }
}
