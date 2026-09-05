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

                    Button {
                        Task { await fetchFullContent() }
                    } label: {
                        if isFetchingFull {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Label(
                                currentArticle.hasFullContent ? "已获取全文" : "全文",
                                systemImage: currentArticle.hasFullContent ? "arrow.down.doc" : "arrow.down.doc.fill"
                            )
                        }
                    }
                    .disabled(isFetchingFull)

                    Button {
                        Task { await toggleTranslation() }
                    } label: {
                        if isTranslating { ProgressView().scaleEffect(0.75) }
                        else {
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
            if let cached = currentArticle.translatedContent, !cached.isEmpty {
                translatedContent = cached
                showTranslated = true
            } else if let t = currentArticle.translatedTitle, !t.isEmpty {
                showTranslated = true
            }
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
            showTranslated = false
            translatedContent = nil
            fullContentHint = silent ? nil : "已获取全文（约 \(HTMLUtils.stripTags(updated.content).count) 字）"
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
        if let cached = currentArticle.translatedContent {
            translatedContent = cached
            showTranslated = true
            if currentArticle.translatedTitle == nil {
                Task { await translateTitleIfNeeded() }
            }
            return
        }
        translationError = nil
        isTranslating = true
        translationProgress = "正在翻译…"
        do {
            let titleTask = Task { () -> String? in
                if let existing = currentArticle.translatedTitle, !existing.isEmpty {
                    return existing
                }
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
        // 默认关闭阅读器视图，显示完整网页
        config.entersReaderIfAvailable = false
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
                        .font(.system(size: fontSize))
                        .lineSpacing(6)
                        .environment(\.openURL, OpenURLAction { url in
                            browserURL = url
                            return .handled
                        })
                case .image(let src):
                    AsyncImage(url: URL(string: src)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            EmptyView()
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
        }
        .sheet(item: $browserURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

enum ContentBlock {
    case paragraph(AttributedString)
    case image(String)
}

enum ContentBlockParser {
    static func parse(_ html: String) -> [ContentBlock] {
        let decoded = HTMLUtils.decodeEntities(html)
        var blocks: [ContentBlock] = []
        let pattern = "(?i)(<img[^>]+src=[\"']([^\"']+)[\"'][^>]*>)|([^<]+|<[^>]+>)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            if let attr = try? AttributedString(markdown: decoded) {
                blocks.append(.paragraph(attr))
            } else {
                blocks.append(.paragraph(AttributedString(HTMLUtils.stripTags(decoded))))
            }
            return blocks
        }
        let ns = decoded as NSString
        let matches = regex.matches(in: decoded, range: NSRange(location: 0, length: ns.length))
        var textBuf = ""
        func flushText() {
            let trimmed = textBuf.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { textBuf = ""; return }
            let plain = HTMLUtils.stripTags(trimmed)
            if plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textBuf = ""; return
            }
            if let attr = makeAttributed(from: trimmed) {
                blocks.append(.paragraph(attr))
            } else {
                blocks.append(.paragraph(AttributedString(plain)))
            }
            textBuf = ""
        }
        for m in matches {
            if m.range(at: 2).location != NSNotFound {
                flushText()
                let src = ns.substring(with: m.range(at: 2))
                if !src.isEmpty { blocks.append(.image(src)) }
            } else if m.range(at: 3).location != NSNotFound {
                textBuf += ns.substring(with: m.range(at: 3))
            }
        }
        flushText()
        return blocks
    }

    private static func makeAttributed(from htmlFragment: String) -> AttributedString? {
        let wrapped = "<div>\(htmlFragment)</div>"
        guard let data = wrapped.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let ns = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }
        var attr = AttributedString(ns)
        // first-line indent for paragraphs
        for run in attr.runs {
            if attr[run.range].presentationIntent == nil {
                // keep links
            }
        }
        return attr
    }
}

enum HTMLUtils {
    static func decodeEntities(_ s: String) -> String {
        var result = s
        let entities: [(String, String)] = [
            ("&", "&"), ("<", "<"), (">", ">"), (""", "\""), ("'", "'"),
            ("&#39;", "'"), ("&#x27;", "'"), ("&#8216;", "\u{2018}"), ("&#8217;", "\u{2019}"),
            ("&#8220;", "\u{201C}"), ("&#8221;", "\u{201D}"), ("&nbsp;", " "),
            ("&#160;", " "), ("&#8211;", "\u{2013}"), ("&#8212;", "\u{2014}")
        ]
        for (e, c) in entities {
            result = result.replacingOccurrences(of: e, with: c)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                if m.numberOfRanges > 1 {
                    let numStr = ns.substring(with: m.range(at: 1))
                    if let code = UInt32(numStr), let scalar = UnicodeScalar(code) {
                        result = (result as NSString).replacingCharacters(in: m.range, with: String(Character(scalar)))
                    }
                }
            }
        }
        return result
    }

    static func stripTags(_ html: String) -> String {
        let decoded = decodeEntities(html)
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>") else { return decoded }
        return regex.stringByReplacingMatches(in: decoded, range: NSRange(location: 0, length: (decoded as NSString).length), withTemplate: "")
    }

    static func extractImagesForTranslation(_ html: String) -> (String, [String]) {
        var images: [String] = []
        var result = html
        guard let regex = try? NSRegularExpression(pattern: "(?i)<img[^>]*>") else {
            return (stripTags(html), [])
        }
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
        for (i, m) in matches.enumerated() {
            let tag = ns.substring(with: m.range)
            images.insert(tag, at: 0)
            let placeholder = "[[IMG\(images.count - 1 - i)]]"
            result = (result as NSString).replacingCharacters(in: m.range, with: "\n\n\(placeholder)\n\n")
        }
        return (stripTags(result), images.reversed())
    }

    static func restoreImagesAfterTranslation(_ text: String, images: [String]) -> String {
        var result = text
        for (i, img) in images.enumerated() {
            result = result.replacingOccurrences(of: "[[IMG\(i)]]", with: img)
        }
        return result
    }
}
