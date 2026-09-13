import SwiftUI
import SafariServices

struct ArticleContentView: View {
    var onHighlight: ((String) -> Void)? = nil
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
        VStack(alignment: .leading, spacing: prefersChineseTypography ? 12 : 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let attributed, let style):
                    SelectableParagraphView(
                        attributed: attributed,
                        fontSize: fontSize,
                        typography: style,
                        onOpenURL: { browserURL = $0 },
                        onExplain: { startExplain($0) },
                        onHighlight: onHighlight
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .audio(let urlString):
                    AudioLinkPlayerCard(urlString: urlString)
                case .image(let urlString):
                    if let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                // 避免原文大量图片加载时出现成片 180pt 灰块留白
                                Color.clear.frame(height: 1)
                            case .success(let image):
                                image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                            case .failure:
                                EmptyView()
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
    case audio(String)
}

enum ContentBlockParser {
    static func parse(_ html: String, prefersChineseTypography: Bool = false) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var working = HTMLUtils.decodePercentEncodings(HTMLUtils.decodeEntities(html))
        working = normalizeHTMLWhitespace(working)
        working = working.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        // 仅块级闭合换段，避免每个嵌套 </div> 都制造空段
        working = working.replacingOccurrences(of: #"</p>|</li>|</h[1-6]>|</blockquote>|</section>|</article>"#, with: "\n\n", options: .regularExpression)
        working = working.replacingOccurrences(of: #"</div>"#, with: "\n", options: .regularExpression)

        let audioPattern = #"<a[^>]+href=[\"']([^\"']+\.(?:mp3|m4a|wav|aac)(?:\?[^\"']*)?)[\"'][^>]*>.*?</a>|<(?:audio|source)[^>]+src=[\"']([^\"']+)[\"'][^>]*>"#
        if let aregex = try? NSRegularExpression(pattern: audioPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let ns = working as NSString
            let matches = aregex.matches(in: working, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                var url: String?
                if match.numberOfRanges >= 2, match.range(at: 1).location != NSNotFound, let r = Range(match.range(at: 1), in: working) {
                    url = String(working[r])
                } else if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound, let r = Range(match.range(at: 2), in: working) {
                    url = String(working[r])
                }
                if let url, !url.isEmpty {
                    blocks.append(.audio(url))
                }
                if let full = Range(match.range, in: working) {
                    working.replaceSubrange(full, with: "\n")
                }
            }
        }
        // bare mp3 URLs in text
        if let bare = try? NSRegularExpression(pattern: #"https?://[^\s<>\"']+\.mp3(?:\?[^\s<>\"']*)?"#, options: .caseInsensitive) {
            let ns = working as NSString
            for match in bare.matches(in: working, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let r = Range(match.range, in: working) {
                    let url = String(working[r])
                    blocks.append(.audio(url))
                    working.replaceSubrange(r, with: "\n")
                }
            }
        }

        let imgPattern = #"<img\b[^>]*(?:src|data-src|data-original)=[\"']([^\"']+)[\"'][^>]*/?>"#
        var imageURLs: [String] = []
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            // 先收集有效图，再按原顺序写入占位，跳过追踪图/极小图以免留下大块空白占位
            var keepIndexByMatch: [Int: Int] = [:]
            for (mi, match) in matches.enumerated() {
                if match.numberOfRanges >= 2, let urlRange = Range(match.range(at: 1), in: working) {
                    var u = String(working[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if u.hasPrefix("//") { u = "https:" + u }
                    guard u.count > 8, !isIgnorableImageURL(u) else { continue }
                    keepIndexByMatch[mi] = imageURLs.count
                    imageURLs.append(u)
                }
            }
            for (mi, match) in matches.enumerated().reversed() {
                if let fullRange = Range(match.range, in: working) {
                    if let kept = keepIndexByMatch[mi] {
                        working.replaceSubrange(fullRange, with: "\n\n__IMG_\(kept)__\n\n")
                    } else {
                        working.replaceSubrange(fullRange, with: "\n")
                    }
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

        // 去掉 script/style/注释与全部标签，避免界面出现 <div> 等字面量
        if let re = try? NSRegularExpression(pattern: #"<!--([\s\S]*?)-->"#, options: []) {
            working = re.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }
        if let re = try? NSRegularExpression(pattern: #"<script[\s\S]*?</script>"#, options: .caseInsensitive) {
            working = re.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }
        if let re = try? NSRegularExpression(pattern: #"<style[\s\S]*?</style>"#, options: .caseInsensitive) {
            working = re.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }
        if let re = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: [.dotMatchesLineSeparators]) {
            working = re.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }
        if let re = try? NSRegularExpression(pattern: #"</?[A-Za-z][^<>]{0,80}"#, options: []) {
            working = re.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }
        working = HTMLUtils.decodeEntities(working)

        let parts = working.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var lastImageURL: String?
        for part in parts {
            if part.hasPrefix("__IMG_"), part.hasSuffix("__") {
                let idxStr = String(part.dropFirst(6).dropLast(2))
                if let idx = Int(idxStr), idx >= 0, idx < imageURLs.count {
                    let url = imageURLs[idx]
                    // 连续相同图片只保留一张，减少原文大图重复占位
                    if lastImageURL == url { continue }
                    lastImageURL = url
                    blocks.append(.image(url))
                }
            } else if isJunkParagraph(part) {
                lastImageURL = nil
                continue
            } else {
                lastImageURL = nil
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

    /// 去掉空标签、注释、多余空白，减轻原文大片留白
    private static func normalizeHTMLWhitespace(_ html: String) -> String {
        var work = html
        work = work.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)
        work = work.replacingOccurrences(of: "\u{200B}", with: "")
        work = work.replacingOccurrences(of: "\u{200C}", with: "")
        work = work.replacingOccurrences(of: "\u{200D}", with: "")
        work = work.replacingOccurrences(of: "\u{FEFF}", with: "")
        work = work.replacingOccurrences(
            of: #"<p[^>]*>\s*(?:&nbsp;|&#160;|\u{00A0}|\s)*\s*</p>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        work = work.replacingOccurrences(
            of: #"<div[^>]*>\s*(?:&nbsp;|&#160;|\u{00A0}|\s)*\s*</div>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        work = work.replacingOccurrences(
            of: #"<span[^>]*>\s*(?:&nbsp;|&#160;|\u{00A0}|\s)*\s*</span>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        work = work.replacingOccurrences(
            of: #"(?:<br\s*/?\s*>\s*){2,}"#,
            with: "<br>",
            options: [.regularExpression, .caseInsensitive]
        )
        work = work.replacingOccurrences(
            of: #"</?(?:font|center|o:p)[^>]*>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return work
    }

    /// 追踪图、推荐缩略图等，渲染只会留下空白占位
    private static func isIgnorableImageURL(_ url: String) -> Bool {
        let u = url.lowercased()
        if u.contains("fly-images/") { return true }
        if u.contains("1x1") || u.contains("pixel") || u.contains("spacer") { return true }
        if u.contains("doubleclick") || u.contains("googlesyndication") { return true }
        // 常见极小尺寸后缀
        if u.range(of: #"-80x42\.(webp|png|jpg|jpeg)"#, options: .regularExpression) != nil { return true }
        if u.range(of: #"-1x1\.(gif|png|jpg)"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// 广告脚本残留、订阅页脚碎片等，不应单独成段
    private static func isJunkParagraph(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        // 纯符号/分隔线
        if t.count <= 3, t.allSatisfy({ !$0.isLetter && !$0.isNumber }) { return true }
        if t.count <= 2, t.allSatisfy({ $0.isNumber || $0 == "." || $0 == "·" }) { return true }
        let lower = t.lowercased()
        if lower.contains("adsbygoogle") { return true }
        if lower.contains("(function(){") || lower.contains("function c(){") { return true }
        if lower == "comments" || lower == "subscribe" { return true }
        if lower.hasPrefix("become a member") { return true }
        if lower.hasPrefix("understand china ev") { return true }
        if lower.contains("real-time notifications when critical") { return true }
        if lower.contains("2,000,000+ data points") { return true }
        if lower.contains("most important news in your inbox") { return true }
        if lower.contains("0 of 27 topics") { return true }
        if lower.contains("bundle into one email") { return true }
        if lower.contains("no spam · unsubscribe") || lower.contains("no spam · unsubscribe") { return true }
        if lower.contains("join our telegram") || lower.contains("follow us on google news") { return true }
        if lower.contains("recommended for you") { return true }
        // 仅空白实体
        if t.replacingOccurrences(of: "\u{00A0}", with: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
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


// MARK: - MP3 / audio link player

import AVFoundation

struct AudioLinkPlayerCard: View {
    let urlString: String
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("音频")
                        .font(.system(size: 15, weight: .semibold))
                    Text(urlString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.vertical, 6)
        .onDisappear { stop() }
    }

    private func toggle() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        guard let url = URL(string: urlString) else {
            error = "无效音频地址"
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            self.error = error.localizedDescription
        }
        if player == nil {
            player = AVPlayer(url: url)
        }
        player?.play()
        isPlaying = true
        error = nil
    }

    private func stop() {
        player?.pause()
        player = nil
        isPlaying = false
    }
}
