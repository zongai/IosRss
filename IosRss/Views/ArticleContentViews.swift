import SwiftUI
import SafariServices

enum ReaderTypography {
    case chinese
    case latin

    static func resolve(text: String, preferChinese: Bool) -> ReaderTypography {
        if preferChinese { return .chinese }
        let cjk = text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letters > 0 && Double(cjk) / Double(max(1, letters)) > 0.3 ? .chinese : .latin
    }

    var firstLineIndent: CGFloat { self == .chinese ? 28 : 0 }
    var lineSpacing: CGFloat { self == .chinese ? 8 : 5 }
    var paragraphSpacing: CGFloat { self == .chinese ? 12 : 8 }
}

enum ContentBlock {
    case paragraph(AttributedString, ReaderTypography)
    case image(String)
}

enum ContentBlockParser {
    static func parse(_ html: String, prefersChineseTypography: Bool = false) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let parts = html.components(separatedBy: "<img")
        for (i, part) in parts.enumerated() {
            if i == 0 {
                appendParagraphs(from: part, prefersChinese: prefersChineseTypography, into: &blocks)
                continue
            }
            if let srcRange = part.range(of: "src=\"") {
                let after = part[srcRange.upperBound...]
                if let end = after.firstIndex(of: "\"") {
                    let url = String(after[..<end])
                    if !url.isEmpty { blocks.append(.image(url)) }
                }
                if let close = part.firstIndex(of: ">") {
                    let rest = String(part[part.index(after: close)...])
                    appendParagraphs(from: rest, prefersChinese: prefersChineseTypography, into: &blocks)
                }
            } else {
                appendParagraphs(from: part, prefersChinese: prefersChineseTypography, into: &blocks)
            }
        }
        if blocks.isEmpty {
            appendParagraphs(from: html, prefersChinese: prefersChineseTypography, into: &blocks)
        }
        return blocks
    }

    private static func appendParagraphs(from html: String, prefersChinese: Bool, into blocks: inout [ContentBlock]) {
        let decoded = HTMLUtils.decodeEntities(html)
        let plain = HTMLUtils.stripTags(decoded).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        for para in plain.components(separatedBy: "\n\n") {
            let t = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let style = ReaderTypography.resolve(text: t, preferChinese: prefersChinese)
            var attr = AttributedString(t)
            attr.font = .system(size: 17)
            blocks.append(.paragraph(attr, style))
        }
    }
}

struct ArticleContentView: View {
    @Environment(AppStore.self) private var store
    let html: String
    let fontSize: Double
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
                await MainActor.run {
                    explainResult = result
                    isExplaining = false
                }
            } catch {
                await MainActor.run {
                    explainError = error.localizedDescription
                    isExplaining = false
                }
            }
        }
    }
}
