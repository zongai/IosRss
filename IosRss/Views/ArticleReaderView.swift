import SwiftUI

struct ArticleReaderView: View {
    @Environment(AppStore.self) private var store
    let article: Article
    @Binding var isPresented: Bool

    @State private var isTranslating = false
    @State private var isGeneratingSummary = false
    @State private var translatedContent: String?
    @State private var showTranslated = false
    @State private var aiSummary: String?
    @State private var summaryExpanded = true
    @State private var translationError: String?
    @State private var summaryError: String?

    private var currentArticle: Article {
        store.feeds.flatMap { $0.articles }.first(where: { $0.id == article.id }) ?? article
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentArticle.title)
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Text(currentArticle.feedTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                            if !currentArticle.relativeTime.isEmpty {
                                Text("·").foregroundStyle(.tertiary)
                                Text(currentArticle.relativeTime)
                                    .font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)

                    Divider()

                    // AI Summary card
                    if let summary = aiSummary ?? currentArticle.aiSummary {
                        AISummaryCard(summary: summary, expanded: $summaryExpanded)
                            .padding(.horizontal, 20).padding(.top, 16)
                    }
                    if let err = summaryError {
                        Text(err).font(.system(size: 13)).foregroundStyle(.red)
                            .padding(.horizontal, 20).padding(.top, 8)
                    }
                    if let err = translationError {
                        Text(err).font(.system(size: 13)).foregroundStyle(.red)
                            .padding(.horizontal, 20).padding(.top, 8)
                    }

                    // Content
                    let displayContent = showTranslated
                        ? (translatedContent ?? currentArticle.translatedContent ?? currentArticle.content)
                        : currentArticle.content
                    ArticleContentView(html: displayContent, fontSize: store.fontSize)
                        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 40)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresented = false } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                            Text("返回")
                        }
                        .foregroundStyle(.primary)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleTranslation() }
                    } label: {
                        if isTranslating { ProgressView().scaleEffect(0.75) }
                        else { Label(showTranslated ? "原文" : "翻译",
                                     systemImage: showTranslated ? "text.bubble.fill" : "text.bubble") }
                    }
                    .disabled(isTranslating)

                    Button {
                        Task { await generateSummary() }
                    } label: {
                        if isGeneratingSummary { ProgressView().scaleEffect(0.75) }
                        else { Label("AI总结", systemImage: "sparkles") }
                    }
                    .disabled(isGeneratingSummary)

                    if let url = URL(string: article.link) {
                        Link(destination: url) { Label("浏览器", systemImage: "safari") }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .onAppear { aiSummary = currentArticle.aiSummary }
    }

    private func toggleTranslation() async {
        if showTranslated { showTranslated = false; translationError = nil; return }
        if let cached = currentArticle.translatedContent { translatedContent = cached; showTranslated = true; return }
        translationError = nil; isTranslating = true
        do {
            let plain = currentArticle.content
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            let result = try await store.translateText(String(plain.prefix(3000)))
            translatedContent = "<p>\(result.replacingOccurrences(of: "\n", with: "</p><p>"))</p>"
            var updated = currentArticle; updated.translatedContent = translatedContent
            store.updateArticle(updated); showTranslated = true
        } catch { translationError = error.localizedDescription }
        isTranslating = false
    }

    private func generateSummary() async {
        if let existing = currentArticle.aiSummary { aiSummary = existing; summaryExpanded = true; return }
        summaryError = nil; isGeneratingSummary = true
        do {
            let result = try await store.generateSummary(for: currentArticle)
            aiSummary = result; summaryExpanded = true
            var updated = currentArticle; updated.aiSummary = result
            store.updateArticle(updated)
        } catch { summaryError = error.localizedDescription }
        isGeneratingSummary = false
    }
}

// MARK: - AI Summary Card

struct AISummaryCard: View {
    let summary: String
    @Binding var expanded: Bool

    private var points: [String] {
        summary.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                    Text("AI 摘要").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, point in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary).frame(width: 18, alignment: .leading)
                            Text(point).font(.system(size: 13)).foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
        .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Article Content View

struct ArticleContentView: View {
    let html: String
    let fontSize: Double

    private var paragraphs: [String] {
        html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>|</div>|</li>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                Text(para)
                    .font(.system(size: fontSize, design: .serif))
                    .foregroundStyle(.primary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
