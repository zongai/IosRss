import SwiftUI

/// 全库搜索：标题、摘要、已抓全文（译文优先显示）
struct SearchView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var results: [Article] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "搜索文章",
                        systemImage: "magnifyingglass",
                        description: Text("匹配标题、摘要与已抓取的全文")
                    )
                    .listRowSeparator(.hidden)
                } else if isSearching {
                    HStack {
                        ProgressView()
                        Text("搜索中…")
                            .foregroundStyle(.secondary)
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section {
                        ForEach(results) { article in
                            NavigationLink {
                                ArticleReaderView(article: article)
                            } label: {
                                SearchResultRow(article: article, query: query)
                            }
                        }
                    } header: {
                        Text("\(results.count) 条结果")
                    }
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $query, prompt: "标题、摘要、全文")
            .onChange(of: query) { _, newValue in
                scheduleSearch(newValue)
            }
        }
    }

    private func scheduleSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        // 轻量防抖：短查询同步即可
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            results = store.searchArticles(query: trimmed, limit: 80)
            isSearching = false
        }
    }
}

private struct SearchResultRow: View {
    let article: Article
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(article.feedTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !article.relativeTime.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(article.relativeTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if article.hasFullContent {
                    Text("全文")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            if let snippet = snippetText {
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var titleText: String {
        if let t = article.translatedTitle, !t.isEmpty { return t }
        return article.title
    }

    private var snippetText: String? {
        let q = query.lowercased()
        let candidates: [String] = [
            article.translatedSummary,
            article.summary,
            article.translatedContent.map { String(HTMLUtils.stripTags($0).prefix(400)) },
            article.hasFullContent ? String(HTMLUtils.stripTags(article.content).prefix(400)) : nil
        ].compactMap { $0 }.map { HTMLUtils.stripTags($0) }
        for c in candidates {
            let lower = c.lowercased()
            if let r = lower.range(of: q) {
                let start = lower.index(r.lowerBound, offsetBy: -24, limitedBy: lower.startIndex) ?? lower.startIndex
                let end = lower.index(r.upperBound, offsetBy: 48, limitedBy: lower.endIndex) ?? lower.endIndex
                let slice = String(c[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (start == lower.startIndex ? "" : "…") + slice + (end == lower.endIndex ? "" : "…")
            }
        }
        let summary = HTMLUtils.stripTags(article.translatedSummary ?? article.summary)
        return summary.isEmpty ? nil : String(summary.prefix(100))
    }
}
