import SwiftUI
import SafariServices

struct ArticleContentView: View {
    @Environment(AppStore.self) private var store
    let html: String
    let fontSize: Double
    /// 译文默认按中文排版；原文按内容语言自动判断
    var prefersChineseTypography: Bool = false
    @State private var browserURL: URL?
    @State private var explainQuery: String?
    @State private var explainResult: String?
    @State private var explainError: String?
    @State private var isExplaining = false
    @State private var showExplainSheet = false

    private var blocks: [ContentBlock] {
        ContentBlockParser.parse(html, prefersChineseTypography: prefersChineseTypography)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: prefersChineseTypography ? 18 : 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let attributed, let style):
                    SelectableParagraphView(
                        attributed: attributed,
                        fontSize: fontSize,
                        typography: style,
                        onOpenURL: { browserURL = $0 },
                        onExplain: { startExplain($0) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .image(let urlString):
                    if let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground))
                                    .frame(height: 180).overlay(ProgressView())
                            case .success(let image):
                                image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                            case .failure:
                                RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground))
                                    .frame(height: 80)
                                    .overlay(Image(systemName: "photo").foregroundStyle(Color.secondary))
                            @unknown default: EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { browserURL != nil }, set: { if !$0 { browserURL = nil } })) {
            if let url = browserURL { SafariView(url: url).ignoresSafeArea() }
        }
        .sheet(isPresented: $showExplainSheet) {
            AIExplainSheet(
                query: explainQuery ?? "",
                result: explainResult,
                error: explainError,
                isLoading: isExplaining,
                onRetry: { if let q = explainQuery { startExplain(q) } },
                onDismiss: { showExplainSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func startExplain(_ text: String) {
        let clipped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipped.isEmpty else { return }
        explainQuery = clipped
        explainResult = nil
        explainError = nil
        isExplaining = true
        showExplainSheet = true
        Task {
            do {
                let result = try await store.explainText(clipped)
                explainResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                explainError = error.localizedDescription
            }
            isExplaining = false
        }
    }
}

enum ReaderTypography {
    case chinese
    case latin

    static func resolve(text: String, preferChinese: Bool) -> ReaderTypography {
        if preferChinese { return .chinese }
        return ListLanguageDetect.isMostlyChinese(text) ? .chinese : .latin
    }
}

enum ContentBlock {
    case paragraph(AttributedString, ReaderTypography)
    case image(String)
}

enum ContentBlockParser {
    static func parse(_ html: String, prefersChineseTypography: Bool = false) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var working = html
        working = working.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        working = working.replacingOccurrences(of: #"</p>|</div>|</li>|</h[1-6]>"#, with: "\n\n", options: .regularExpression)

        let imgPattern = #"<img[^>]+src=[\"']([^\"']+)[\"'][^>]*/?>"#
        var imageURLs: [String] = []
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                if match.numberOfRanges >= 2, let urlRange = Range(match.range(at: 1), in: working) {
                    imageURLs.append(String(working[urlRange]))
                }
            }
            for (i, match) in matches.enumerated().reversed() {
                if let fullRange = Range(match.range, in: working) {
                    working.replaceSubrange(fullRange, with: "\n\n__IMG_\(i)__\n\n")
                }
            }
        }

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
                let style = ReaderTypography.resolve(text: part, preferChinese: prefersChineseTypography)
                blocks.append(.paragraph(
                    makeAttributedParagraph(part, linkHrefs: linkHrefs, linkTexts: linkTexts),
                    style
                ))
            }
        }
        if blocks.isEmpty {
            let plain = HTMLUtils.stripTags(html)
            if !plain.isEmpty {
                let style = ReaderTypography.resolve(text: plain, preferChinese: prefersChineseTypography)
                blocks.append(.paragraph(makeAttributedParagraph(plain, linkHrefs: [], linkTexts: []), style))
            }
        }
        return blocks
    }

    private static func makeAttributedParagraph(_ raw: String, linkHrefs: [String], linkTexts: [String]) -> AttributedString {
        var text = raw
        var ranges: [(range: Range<String.Index>, url: URL)] = []
        let placeholderPattern = #"__LINK_(\d+)__"#
        if let regex = try? NSRegularExpression(pattern: placeholderPattern) {
            while let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let fullRange = Range(match.range, in: text),
                      match.numberOfRanges >= 2,
                      let idxRange = Range(match.range(at: 1), in: text),
                      let idx = Int(text[idxRange]),
                      idx >= 0, idx < linkHrefs.count, idx < linkTexts.count else { break }
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
        var attributed = AttributedString(text)
        for item in ranges {
            let lower = text.distance(from: text.startIndex, to: item.range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: item.range.upperBound)
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
