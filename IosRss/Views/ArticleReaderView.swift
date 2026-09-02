import SwiftUI
import SafariServices

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
    @State private var showInAppBrowser = false
    @State private var translationProgress: String?

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
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Text(currentArticle.feedTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.secondary)
                            if !currentArticle.relativeTime.isEmpty {
                                Text("·").foregroundStyle(Color.secondary.opacity(0.6))
                                Text(currentArticle.relativeTime)
                                    .font(.system(size: 13)).foregroundStyle(Color.secondary)
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
                    if let progress = translationProgress {
                        Text(progress)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary)
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
            .background(Color(.systemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresented = false } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                            Text("返回")
                        }
                        .foregroundStyle(Color.primary)
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
        }
        .background(Color(.systemBackground))
        .onAppear { aiSummary = currentArticle.aiSummary }
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
            return
        }
        translationError = nil
        isTranslating = true
        translationProgress = "正在翻译…"
        do {
            let plain = HTMLUtils.stripTags(currentArticle.content)
            // 按长度分段并发翻译
            let result = try await store.translateLongText(plain, maxChunkChars: 1800)
            // 保留段落结构
            let htmlResult = result
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { "<p>\($0)</p>" }
                .joined()
            translatedContent = htmlResult.isEmpty ? "<p>\(result)</p>" : htmlResult
            var updated = currentArticle
            updated.translatedContent = translatedContent
            store.updateArticle(updated)
            showTranslated = true
            translationProgress = nil
        } catch {
            translationError = error.localizedDescription
            translationProgress = nil
        }
        isTranslating = false
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

    private var points: [String] {
        summary.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
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
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .frame(width: 22, alignment: .leading)
                            Text(point)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.primary)
                                .lineSpacing(4)
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

// MARK: - Article Content View (supports images + HTML entities)

struct ArticleContentView: View {
    let html: String
    let fontSize: Double

    private var blocks: [ContentBlock] {
        ContentBlockParser.parse(html)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(text)
                        .font(.system(size: fontSize, design: .serif))
                        .foregroundStyle(Color.primary)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}

// MARK: - Content Block Parser

enum ContentBlock {
    case paragraph(String)
    case image(String)
}

enum ContentBlockParser {
    static func parse(_ html: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var working = html

        // 统一换行
        working = working.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        working = working.replacingOccurrences(of: #"</p>|</div>|</li>|</h[1-6]>"#, with: "\n\n", options: .regularExpression)

        // 提取 img 并用占位符替换，保留顺序
        let imgPattern = #"<img[^>]+src=["']([^"']+)["'][^>]*/?>"#
        var imageURLs: [String] = []
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            // 先从前到后收集 URL
            for match in matches {
                if match.numberOfRanges >= 2,
                   let urlRange = Range(match.range(at: 1), in: working) {
                    imageURLs.append(String(working[urlRange]))
                }
            }
            // 从后往前替换为占位符，避免 range 偏移
            for (i, match) in matches.enumerated().reversed() {
                if let fullRange = Range(match.range, in: working) {
                    working.replaceSubrange(fullRange, with: "\n\n__IMG_\(i)__\n\n")
                }
            }
        }

        // 去掉剩余标签
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
                blocks.append(.paragraph(part))
            }
        }

        // 若完全没有解析出内容，回退为整段纯文本
        if blocks.isEmpty {
            let plain = HTMLUtils.stripTags(html)
            if !plain.isEmpty {
                blocks.append(.paragraph(plain))
            }
        }
        return blocks
    }
}
