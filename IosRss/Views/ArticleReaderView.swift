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
    @State private var summaryExpanded = true
    @State private var translationError: String?
    @State private var summaryError: String?
    @State private var fullContentError: String?
    @State private var showInAppBrowser = false
    @State private var translationProgress: String?
    @State private var fullContentHint: String?

    private var currentArticle: Article {
        store.feeds.flatMap { $0.articles }.first(where: { $0.id == article.id }) ?? article
    }

    private var displayTitle: String {
        if showTranslated, let t = currentArticle.translatedTitle, !t.isEmpty {
            return t
        }
        return currentArticle.title
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
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
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)

                    Divider()

                    // AI Summary card
                    if let summary = aiSummary ?? currentArticle.aiSummary {
                        AISummaryCard(
                            summary: summary,
                            expanded: $summaryExpanded,
                            fontSize: store.aiSummaryFontSize
                        )
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
                        Text(progress)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 20).padding(.top, 8)
                    }
                    if let hint = fullContentHint {
                        Text(hint)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 20).padding(.top, 8)
                    }

                    // 摘要过短时的提示条
                    if currentArticle.needsFullContentFetch && !isFetchingFull {
                        Button {
                            Task { await fetchFullContent() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc")
                                Text("RSS 仅为摘要，点击获取全文")
                                    .font(.system(size: 14, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.secondary)
                            }
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }

                    // Content
                    let displayContent = showTranslated
                        ? (translatedContent ?? currentArticle.translatedContent ?? currentArticle.content)
                        : currentArticle.content
                    ArticleContentView(html: displayContent, fontSize: store.fontSize)
                        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 40)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        store.toggleFavorite(currentArticle)
                    } label: {
                        Label(
                            currentArticle.isFavorite ? "已收藏" : "收藏",
                            systemImage: currentArticle.isFavorite ? "star.fill" : "star"
                        )
                    }

                    // 获取全文
                    Button {
                        Task { await fetchFullContent() }
                    } label: {
                        if isFetchingFull {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Label(
                                currentArticle.hasFullContent ? "已获取全文" : "全文",
                                systemImage: currentArticle.hasFullContent ? "text.book.closed" : "text.book.closed.fill"
                            )
                        }
                    }
                    .disabled(isFetchingFull)

                    Button {
                        Task { await toggleTranslation() }
                    } label: {
                        if isTranslating { ProgressView().scaleEffect(0.75) }
                        else {
                            // globe = 翻译；text.alignleft = 切回原文（避免对话气泡样式）
                            Label(showTranslated ? "原文" : "翻译",
                                  systemImage: showTranslated ? "translate" : "translate")
                        }
                    }
                    .disabled(isTranslating)

                    Button {
                        Task { await generateSummary() }
                    } label: {
                        if isGeneratingSummary { ProgressView().scaleEffect(0.75) }
                        else { Label("AI总结", systemImage: "wand.and.stars") }
                    }
                    .disabled(isGeneratingSummary)

                    if URL(string: article.link) != nil {
                        Button {
                            showInAppBrowser = true
                        } label: {
                            Label("浏览器", systemImage: "safari")
                        }
                    }
                }
            }
            .sheet(isPresented: $showInAppBrowser) {
                if let url = URL(string: article.link) {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
        .background(Color(.systemBackground))
        .onAppear {
            aiSummary = currentArticle.aiSummary
            // 已有缓存译文时直接显示，无需再点翻译
            if let cached = currentArticle.translatedContent, !cached.isEmpty {
                translatedContent = cached
                showTranslated = true
            } else if let t = currentArticle.translatedTitle, !t.isEmpty {
                showTranslated = true
            }
            // 摘要很短时自动尝试抓取全文（仅一次）
            if currentArticle.needsFullContentFetch {
                Task { await fetchFullContent(silent: true) }
            }
        }
    }

    private func fetchFullContent(silent: Bool = false) async {
        if currentArticle.hasFullContent && !silent {
            fullContentHint = "已是全文内容"
            return
        }
        fullContentError = nil
        isFetchingFull = true
        if !silent {
            fullContentHint = "正在获取全文…"
        }
        do {
            let updated = try await store.fetchFullContent(for: currentArticle)
            // 若正在看译文，切换回新正文
            showTranslated = false
            translatedContent = nil
            fullContentHint = silent ? nil : "已获取全文（约 \(HTMLUtils.stripTags(updated.content).count) 字）"
            // 自动提示几秒后消失
            if !silent {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if fullContentHint?.contains("已获取全文") == true {
                    fullContentHint = nil
                }
            }
        } catch {
            if !silent {
                fullContentError = error.localizedDescription
            }
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
        // 正文与标题都已缓存时直接展示
        if let cached = currentArticle.translatedContent {
            translatedContent = cached
            showTranslated = true
            // 若标题尚未翻译，后台补译
            if currentArticle.translatedTitle == nil {
                Task { await translateTitleIfNeeded() }
            }
            return
        }
        translationError = nil
        isTranslating = true
        translationProgress = "正在翻译…"
        do {
            // 1) 标题
            let titleTask = Task { () -> String? in
                if let existing = currentArticle.translatedTitle, !existing.isEmpty {
                    return existing
                }
                let t = currentArticle.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return nil }
                return try? await store.translateText(t)
            }

            // 2) 正文：保留图片位置，只翻译文字块
            let (plainWithPlaceholders, images) = HTMLUtils.extractImagesForTranslation(currentArticle.content)
            let result = try await store.translateLongText(plainWithPlaceholders, maxChunkChars: 1800)
            let restored = HTMLUtils.restoreImagesAfterTranslation(result, images: images)
            let htmlResult = restored
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { part -> String in
                    // 图片占位已还原为 <img ...>，其余包成段落
                    if part.localizedCaseInsensitiveContains("<img") {
                        return part
                    }
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
            summaryExpanded = true
            return
        }
        summaryError = nil
        isGeneratingSummary = true
        do {
            let result = try await store.generateSummary(for: currentArticle)
            aiSummary = result
            summaryExpanded = true
            var updated = currentArticle
            updated.aiSummary = result
            store.updateArticle(updated)
        } catch {
            summaryError = error.localizedDescription
        }
        isGeneratingSummary = false
    }
}

// MARK: - In-App Safari Browser

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = .label
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - AI Summary Card

struct AISummaryCard: View {
    let summary: String
    @Binding var expanded: Bool
    var fontSize: Double = 22

    private var points: [String] {
        summary.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .semibold))
                    Text("AI 摘要")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, point in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).")
                                .font(.system(size: fontSize, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .frame(width: 24, alignment: .leading)
                            Text(point)
                                .font(.system(size: fontSize))
                                .foregroundStyle(Color.primary)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Article Content View (supports images + HTML entities + links)

struct ArticleContentView: View {
    let html: String
    let fontSize: Double

    @State private var browserURL: URL?

    private var blocks: [ContentBlock] {
        ContentBlockParser.parse(html)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let attributed):
                    Text(attributed)
                        .font(.system(size: fontSize, design: .serif))
                        .foregroundStyle(Color.primary)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.openURL, OpenURLAction { url in
                            browserURL = url
                            return .handled
                        })
                case .image(let urlString):
                    if let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(height: 180)
                                    .overlay(ProgressView())
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            case .failure:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(height: 80)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundStyle(Color.secondary)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { browserURL != nil },
            set: { if !$0 { browserURL = nil } }
        )) {
            if let url = browserURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Content Block Parser

enum ContentBlock {
    case paragraph(AttributedString)
    case image(String)
}

enum ContentBlockParser {
    /// 中文排版常用首行缩进（两个全角空格）
    private static let firstLineIndent = "\u{3000}\u{3000}"

    static func parse(_ html: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var working = html

        working = working.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        working = working.replacingOccurrences(of: #"</p>|</div>|</li>|</h[1-6]>"#, with: "\n\n", options: .regularExpression)

        // 图片占位
        let imgPattern = #"<img[^>]+src=[\"']([^\"']+)[\"'][^>]*/?>"#
        var imageURLs: [String] = []
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                if match.numberOfRanges >= 2,
                   let urlRange = Range(match.range(at: 1), in: working) {
                    imageURLs.append(String(working[urlRange]))
                }
            }
            for (i, match) in matches.enumerated().reversed() {
                if let fullRange = Range(match.range, in: working) {
                    working.replaceSubrange(fullRange, with: "\n\n__IMG_\(i)__\n\n")
                }
            }
        }

        // 链接：先替换为占位，保留 href 与可见文本
        var linkHrefs: [String] = []
        var linkTexts: [String] = []
        let linkPattern = #"<a\s+[^>]*href=[\"']([^\"']+)[\"'][^>]*>([\s\S]*?)</a>"#
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                if match.numberOfRanges >= 3,
                   let hrefRange = Range(match.range(at: 1), in: working),
                   let textRange = Range(match.range(at: 2), in: working) {
                    linkHrefs.append(String(working[hrefRange]))
                    var inner = String(working[textRange])
                    inner = inner.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    linkTexts.append(inner)
                }
            }
            for (i, match) in matches.enumerated().reversed() {
                if let fullRange = Range(match.range, in: working) {
                    working.replaceSubrange(fullRange, with: "__LINK_\(i)__")
                }
            }
        }

        // 去掉其余标签
        working = working.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        working = HTMLUtils.decodeEntities(working)

        let parts = working.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for part in parts {
            if part.hasPrefix("__IMG_"), part.hasSuffix("__") {
                let idxStr = String(part.dropFirst(6).dropLast(2))
                if let idx = Int(idxStr), idx >= 0, idx < imageURLs.count {
                    blocks.append(.image(imageURLs[idx]))
                }
            } else {
                blocks.append(.paragraph(makeAttributedParagraph(part, linkHrefs: linkHrefs, linkTexts: linkTexts)))
            }
        }

        if blocks.isEmpty {
            let plain = HTMLUtils.stripTags(html)
            if !plain.isEmpty {
                blocks.append(.paragraph(makeAttributedParagraph(plain, linkHrefs: [], linkTexts: [])))
            }
        }
        return blocks
    }

    private static func makeAttributedParagraph(
        _ raw: String,
        linkHrefs: [String],
        linkTexts: [String]
    ) -> AttributedString {
        // 还原链接占位为可见文本，并记录区间
        var text = raw
        var ranges: [(range: Range<String.Index>, url: URL)] = []

        let placeholderPattern = #"__LINK_(\d+)__"#
        if let regex = try? NSRegularExpression(pattern: placeholderPattern) {
            while let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let fullRange = Range(match.range, in: text),
                      match.numberOfRanges >= 2,
                      let idxRange = Range(match.range(at: 1), in: text),
                      let idx = Int(text[idxRange]),
                      idx >= 0, idx < linkHrefs.count, idx < linkTexts.count else {
                    break
                }
                let label = HTMLUtils.decodeEntities(linkTexts[idx])
                let href = linkHrefs[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                let start = fullRange.lowerBound
                text.replaceSubrange(fullRange, with: label)
                let end = text.index(start, offsetBy: label.count, limitedBy: text.endIndex) ?? text.endIndex
                if let url = URL(string: href), !label.isEmpty {
                    ranges.append((start..<end, url))
                }
            }
        }

        // 首行缩进
        let indented = firstLineIndent + text
        var attributed = AttributedString(indented)

        // 链接样式（缩进偏移 2 个全角字符）
        let indentOffset = firstLineIndent.count
        for item in ranges {
            let lower = text.distance(from: text.startIndex, to: item.range.lowerBound) + indentOffset
            let upper = text.distance(from: text.startIndex, to: item.range.upperBound) + indentOffset
            guard lower >= 0, upper <= attributed.characters.count, lower < upper else { continue }
            let start = attributed.index(attributed.startIndex, offsetByCharacters: lower)
            let end = attributed.index(attributed.startIndex, offsetByCharacters: upper)
            attributed[start..<end].link = item.url
            attributed[start..<end].foregroundColor = .accentColor
            attributed[start..<end].underlineStyle = .single
        }
        return attributed
    }
}
