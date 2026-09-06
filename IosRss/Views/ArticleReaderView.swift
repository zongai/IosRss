import SwiftUI
import SafariServices

struct ArticleReaderView: View {
    @Environment(AppStore.self) private var store
    let article: Article

    @State private var isTranslating = false
    @State private var isGeneratingSummary = false
    @State private var isFetchingFull = false
    @State private var translatedContent: String?
    @State private var showTranslated = false
    @State private var aiSummary: String?
    @State private var aiSummaryProvider: String?
    @State private var summaryExpanded = true
    @State private var translationError: String?
    @State private var summaryError: String?
    @State private var fullContentError: String?
    @State private var showInAppBrowser = false
    @State private var translationProgress: String?
    @State private var fullContentHint: String?
    @State private var showComments = false

    private var currentArticle: Article {
        store.feeds.flatMap { $0.articles }.first(where: { $0.id == article.id }) ?? article
    }

    private var displayTitle: String {
        if showTranslated, let t = currentArticle.translatedTitle, !t.isEmpty { return t }
        return currentArticle.title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayTitle)
                        .font(.system(size: store.readerTitleFontSize, weight: .bold, design: .serif))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showTranslated,
                       let translated = currentArticle.translatedTitle,
                       !translated.isEmpty,
                       store.titleDisplayMode == .bilingual {
                        Text(currentArticle.title)
                            .font(.system(size: max(13, store.readerTitleFontSize - 9)))
                            .foregroundStyle(Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Text(currentArticle.feedTitle)
                            .font(.system(size: max(12, store.readerTitleFontSize - 11), weight: .medium))
                            .foregroundStyle(Color.secondary)
                        if !currentArticle.relativeTime.isEmpty {
                            Text("·").foregroundStyle(Color.secondary.opacity(0.6))
                            Text(currentArticle.relativeTime)
                                .font(.system(size: max(12, store.readerTitleFontSize - 11))).foregroundStyle(Color.secondary)
                        }
                        if currentArticle.hasFullContent {
                            Text("·").foregroundStyle(Color.secondary.opacity(0.6))
                            Text("全文")
                                .font(.system(size: max(11, store.readerTitleFontSize - 12), weight: .medium))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 16)

                Divider()

                if let summary = aiSummary ?? currentArticle.aiSummary {
                    AISummaryCard(summary: summary, expanded: $summaryExpanded, fontSize: store.aiSummaryFontSize, providerName: aiSummaryProvider ?? currentArticle.aiSummaryProvider)
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
                if let err = fullContentError {
                    Text(err).font(.system(size: 13)).foregroundStyle(.red)
                        .padding(.horizontal, 20).padding(.top, 8)
                }
                if let progress = translationProgress {
                    Text(progress).font(.system(size: 13)).foregroundStyle(Color.secondary)
                        .padding(.horizontal, 20).padding(.top, 8)
                }
                if let hint = fullContentHint {
                    Text(hint).font(.system(size: 13)).foregroundStyle(Color.secondary)
                        .padding(.horizontal, 20).padding(.top, 8)
                }

                if shouldOfferFullContent && !isFetchingFull {
                    Button { Task { await fetchFullContent() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                            Text("RSS 仅为摘要，点击获取全文").font(.system(size: 14, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Color.secondary)
                        }
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20).padding(.top, 12)
                }

                let displayContent = showTranslated
                    ? (translatedContent ?? currentArticle.translatedContent ?? currentArticle.content)
                    : currentArticle.content
                ArticleContentView(html: displayContent, fontSize: store.fontSize, prefersChineseTypography: showTranslated)
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleFavorite(currentArticle) } label: {
                    Label(currentArticle.isFavorite ? "已收藏" : "收藏",
                          systemImage: currentArticle.isFavorite ? "star.fill" : "star")
                }
            }
            if fullContentAllowed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await fetchFullContent() } } label: {
                        if isFetchingFull { ProgressView().scaleEffect(0.75) }
                        else {
                            Label(currentArticle.hasFullContent ? "已获取全文" : "全文",
                                  systemImage: currentArticle.hasFullContent ? "arrow.down.doc" : "arrow.down.doc.fill")
                        }
                    }
                    .disabled(isFetchingFull)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await toggleTranslation() } } label: {
                    if isTranslating { ProgressView().scaleEffect(0.75) }
                    else { Label(showTranslated ? "原文" : "翻译", systemImage: "translate") }
                }
                .disabled(isTranslating)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await generateSummary() } } label: {
                    if isGeneratingSummary { ProgressView().scaleEffect(0.75) }
                    else { Label("AI总结", systemImage: "wand.and.stars") }
                }
                .disabled(isGeneratingSummary)
            }
            if commentsAllowed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showComments = true } label: {
                        Label("评论", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }
            if URL(string: article.link) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showInAppBrowser = true } label: {
                        Label("浏览器", systemImage: "safari")
                    }
                }
            }
        }
        .sheet(isPresented: $showInAppBrowser) {
            if let url = URL(string: article.link) {
                SafariView(url: url).ignoresSafeArea()
            }
        }
        .navigationDestination(isPresented: $showComments) {
            ArticleCommentsView(
                articleTitle: currentArticle.title,
                articleURL: currentArticle.link
            )
        }
        .onAppear {
            aiSummary = currentArticle.aiSummary
            aiSummaryProvider = currentArticle.aiSummaryProvider
            if let cached = currentArticle.translatedContent, !cached.isEmpty {
                translatedContent = cached
                showTranslated = true
            } else if let t = currentArticle.translatedTitle, !t.isEmpty {
                showTranslated = true
            }
            if shouldOfferFullContent {
                Task { await fetchFullContent(silent: true) }
            }
        }
    }

    private var fullContentAllowed: Bool {
        store.isFullContentEnabled(for: currentArticle)
    }

    private var commentsAllowed: Bool {
        store.isCommentsEnabled(for: currentArticle)
    }

    private var shouldOfferFullContent: Bool {
        fullContentAllowed && currentArticle.needsFullContentFetch
    }

    private func fetchFullContent(silent: Bool = false) async {
        guard fullContentAllowed else {
            if !silent { fullContentError = "该订阅源已关闭全文获取" }
            return
        }
        if currentArticle.hasFullContent && !silent {
            fullContentHint = "已是全文内容"
            return
        }
        fullContentError = nil
        isFetchingFull = true
        if !silent { fullContentHint = "正在获取全文…" }
        do {
            let updated = try await store.fetchFullContent(for: currentArticle)
            showTranslated = false
            translatedContent = nil
            fullContentHint = silent ? nil : "已获取全文（约 \(HTMLUtils.stripTags(updated.content).count) 字）"
            if !silent {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if fullContentHint?.contains("已获取全文") == true { fullContentHint = nil }
            }
        } catch {
            if !silent { fullContentError = error.localizedDescription }
            fullContentHint = nil
        }
        isFetchingFull = false
    }

    private func toggleTranslation() async {
        if showTranslated {
            showTranslated = false
            translationError = nil
            translationProgress = nil
            return
        }
        if let cached = currentArticle.translatedContent {
            translatedContent = cached
            showTranslated = true
            if currentArticle.translatedTitle == nil { Task { await translateTitleIfNeeded() } }
            return
        }
        translationError = nil
        isTranslating = true
        translationProgress = "正在翻译…"
        do {
            let titleTask = Task { () -> String? in
                if let existing = currentArticle.translatedTitle, !existing.isEmpty { return existing }
                let t = currentArticle.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return nil }
                return try? await store.translateText(t)
            }
            let (plainWithPlaceholders, images) = HTMLUtils.extractImagesForTranslation(currentArticle.content)
            let result = try await store.translateLongText(plainWithPlaceholders, maxChunkChars: 1800)
            let restored = HTMLUtils.restoreImagesAfterTranslation(result, images: images)
            let htmlResult = restored
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { part -> String in
                    if part.localizedCaseInsensitiveContains("<img") { return part }
                    return "<p>\(part)</p>"
                }
                .joined()
            translatedContent = htmlResult.isEmpty ? "<p>\(restored)</p>" : htmlResult
            let translatedTitle = await titleTask.value
            var updated = currentArticle
            updated.translatedContent = translatedContent
            if let translatedTitle, !translatedTitle.isEmpty {
                updated.translatedTitle = translatedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            store.updateArticle(updated)
            showTranslated = true
            translationProgress = nil
        } catch {
            translationError = error.localizedDescription
            translationProgress = nil
        }
        isTranslating = false
    }

    private func translateTitleIfNeeded() async {
        guard currentArticle.translatedTitle == nil else { return }
        let t = currentArticle.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let result = try? await store.translateText(t), !result.isEmpty {
            var updated = currentArticle
            updated.translatedTitle = result.trimmingCharacters(in: .whitespacesAndNewlines)
            store.updateArticle(updated)
        }
    }

    private func generateSummary() async {
        if let existing = currentArticle.aiSummary {
            aiSummary = existing
            aiSummaryProvider = currentArticle.aiSummaryProvider
            summaryExpanded = true
            return
        }
        summaryError = nil
        isGeneratingSummary = true
        do {
            let result = try await store.generateSummary(for: currentArticle)
            aiSummary = result.text
            aiSummaryProvider = result.providerName
            summaryExpanded = true
            var updated = currentArticle
            updated.aiSummary = result.text
            updated.aiSummaryProvider = result.providerName
            store.updateArticle(updated)
        } catch {
            summaryError = error.localizedDescription
        }
        isGeneratingSummary = false
    }
}

