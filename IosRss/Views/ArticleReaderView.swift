import SwiftUI
import SafariServices

struct ArticleReaderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let article: Article
    var feedID: UUID? = nil
    /// 收藏页进入：左右滑在收藏列表内换篇
    var browseFavorites: Bool = false

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
    @ObservedObject private var tts = EdgeTTSPlayer.shared
    @State private var showChrome = true
    @State private var currentID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var lastScrollY: CGFloat = 0

    private var activeID: UUID { currentID ?? article.id }

    private var currentArticle: Article {
        store.feeds.flatMap { $0.articles }.first(where: { $0.id == activeID }) ?? article
    }

    private var feedArticles: [Article] {
        if browseFavorites {
            return store.favoriteArticles
                .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
        }
        let fid = feedID ?? currentArticle.feedID
        return store.articlesForFeed(fid)
            .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
    }

    private var currentIndex: Int? {
        feedArticles.firstIndex(where: { $0.id == activeID })
    }

    private var needsTranslation: Bool {
        // 以正文为准：正文足够长时只看正文；否则才回退标题
        let body = HTMLUtils.plainText(currentArticle.content)
        let sample: String
        if body.count >= 40 {
            sample = body
        } else {
            sample = (currentArticle.title + "\n" + body).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if sample.isEmpty { return false }
        if currentArticle.hasTranslatedBody { return false }
        return !ListLanguageDetect.isMostlyTarget(sample, language: store.targetLanguage)
    }


    private var displayTitle: String {
        if showTranslated, let t = currentArticle.translatedTitle, !t.isEmpty { return t }
        return currentArticle.title
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            Color.clear.frame(height: 0).id("readerTop")
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayTitle)
                        .font(AppTypography.font(size: store.readerTitleFontSize, weight: .semibold))
                        .tracking(AppTypography.titleTracking)
                        .foregroundStyle(theme.text)
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
                if let err = tts.errorMessage {
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
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 56)
            }
        }
        .background(Color(.systemBackground))
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { oldY, newY in
            let delta = newY - oldY
            // 向下滑（offset 增大）隐藏；向上滑或接近顶部显示
            if newY > 28, delta > 1.5 {
                if showChrome {
                    withAnimation(.easeInOut(duration: 0.2)) { showChrome = false }
                }
            } else if delta < -1.5 || newY < 12 {
                if !showChrome {
                    withAnimation(.easeInOut(duration: 0.2)) { showChrome = true }
                }
            }
            lastScrollY = newY
        }
        .navigationTitle("")
        .appScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showChrome ? .visible : .hidden, for: .navigationBar)
        .toolbar(showChrome ? .visible : .hidden, for: .tabBar)
        .toolbarBackground(showChrome ? .automatic : .hidden, for: .navigationBar)
        .toolbarBackground(showChrome ? .automatic : .hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.2), value: showChrome)
        // 换篇：仅识别明显水平滑动，避免干扰纵向滚动与工具栏显隐
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard abs(value.translation.width) > 90,
                          abs(value.translation.height) < 45 else { return }
                    if value.translation.width < 0 {
                        goNextArticle()
                    } else {
                        goPrevArticle()
                    }
                }
        )
        .onAppear {
            if currentID == nil { currentID = article.id }
            store.markAsRead(currentArticle)
        }
        .task(id: currentArticle.id) {
            await autoTranslateBodyIfNeeded()
        }
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
                if needsTranslation || showTranslated {
                    Button { Task { await toggleTranslation() } } label: {
                        if isTranslating { ProgressView().scaleEffect(0.75) }
                        else { Label(showTranslated ? "原文" : "翻译", systemImage: "translate") }
                    }
                    .disabled(isTranslating)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await generateSummary() } } label: {
                    if isGeneratingSummary { ProgressView().scaleEffect(0.75) }
                    else { Label("AI总结", systemImage: "wand.and.stars") }
                }
                .disabled(isGeneratingSummary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        let html = showTranslated
                            ? (translatedContent ?? currentArticle.translatedContent ?? currentArticle.content)
                            : currentArticle.content
                        let plain = HTMLUtils.stripTags(html)
                        let fallback = currentArticle.summary
                        let body = plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : plain
                        let text = displayTitle + "\n" + body
                        await tts.toggle(text: text, voice: store.ttsVoice.isEmpty ? nil : store.ttsVoice, rate: store.ttsRate)
                    }
                } label: {
                    if tts.isLoading {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Label(tts.isPlaying ? "停止朗读" : "朗读",
                              systemImage: tts.isPlaying ? "stop.fill" : "speaker.wave.2.fill")
                    }
                }
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
        .onDisappear { tts.stop() }
        .navigationDestination(isPresented: $showComments) {
            ArticleCommentsView(
                articleTitle: currentArticle.title,
                articleURL: currentArticle.link,
                commentsURL: currentArticle.commentsURL
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
        .onChange(of: activeID) { _, _ in
            // 左滑/右滑换篇后回到文章开头
            translationError = nil
            summaryError = nil
            fullContentError = nil
            fullContentHint = nil
            translationProgress = nil
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("readerTop", anchor: .top)
                }
            }
        }
        } // ScrollViewReader
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

    /// 源开启自动翻译时：打开阅读页自动译正文（已有译文则直接显示）
    private func autoTranslateBodyIfNeeded() async {
        let feed = store.feeds.first(where: { $0.id == currentArticle.feedID })
        guard feed?.autoTranslateEnabled == true else { return }
        // 已在显示译文或正在翻译
        if showTranslated || isTranslating { return }

        // 标题若未译且不像目标语言，一并处理（toggleTranslation 内也会做）
        if let cached = currentArticle.translatedContent, !cached.isEmpty {
            translatedContent = cached
            showTranslated = true
            return
        }

        let sample = HTMLUtils.plainText(currentArticle.content)
        if sample.count >= 40, ListLanguageDetect.isMostlyTarget(sample, language: store.targetLanguage) {
            // 正文已是目标语言：不显示翻译按钮态，也不请求
            return
        }
        // 内容过短则只译标题
        if sample.count < 20 {
            if currentArticle.translatedTitle == nil {
                await translateTitleIfNeeded()
            }
            return
        }

        await toggleTranslation()
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

    private func goNextArticle() {
        guard let idx = currentIndex, idx + 1 < feedArticles.count else { return }
        let next = feedArticles[idx + 1]
        switchToArticle(next)
    }

    private func goPrevArticle() {
        guard let idx = currentIndex, idx > 0 else { return }
        let prev = feedArticles[idx - 1]
        switchToArticle(prev)
    }

    private func switchToArticle(_ next: Article) {
        currentID = next.id
        showTranslated = false
        translatedContent = nil
        aiSummary = next.aiSummary
        aiSummaryProvider = next.aiSummaryProvider
        translationError = nil
        summaryError = nil
        fullContentError = nil
        fullContentHint = nil
        translationProgress = nil
        isTranslating = false
        isGeneratingSummary = false
        isFetchingFull = false
        store.markAsRead(next)
        withAnimation(.snappy(duration: 0.2)) { showChrome = true }
        // 滚动到顶部由 onChange(of: activeID) + ScrollViewReader 处理
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
