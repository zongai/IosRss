import SwiftUI
import SafariServices

struct ArticleContentView: View {
    @Environment(AppStore.self) private var store
    let html: String
    let fontSize: Double
    /// 译文默认按中文排版；原文按内容语言自动判断
    var prefersChineseTypography: Bool = false
    var onHighlight: ((String) -> Void)? = nil
    /// 表格横向滑动时置 true，供阅读页屏蔽换篇手势
    var suppressArticleSwipe: Binding<Bool> = .constant(false)
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
                case .table(let headers, let rows):
                    ArticleTableView(
                        headers: headers,
                        rows: rows,
                        fontSize: fontSize,
                        suppressArticleSwipe: suppressArticleSwipe
                    )
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
    /// 数据表（Visual Capitalist 等）：首行可为表头
    case table(headers: [String], rows: [[String]])
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

        // 表格先于图片抽出，避免表内 <img> 被换成 __IMG_n__ 文本残留
        var tablePlaceholders: [(token: String, headers: [String], rows: [[String]])] = []
        if let tableRe = try? NSRegularExpression(
            pattern: #"<table\b[\s\S]*?</table>"#,
            options: [.caseInsensitive]
        ) {
            let ns = working as NSString
            let matches = tableRe.matches(in: working, range: NSRange(location: 0, length: ns.length)).reversed()
            for (ti, match) in matches.enumerated() {
                guard let full = Range(match.range, in: working) else { continue }
                let tableHTML = String(working[full])
                let parsed = parseHTMLTable(tableHTML)
                guard !parsed.rows.isEmpty || !parsed.headers.isEmpty else {
                    working.replaceSubrange(full, with: "\n")
                    continue
                }
                let token = "__TABLE_\(ti)__"
                tablePlaceholders.append((token, parsed.headers, parsed.rows))
                working.replaceSubrange(full, with: "\n\(token)\n")
            }
        }

        // 整标签匹配，再从 src / data-src / srcset 等解析真实 URL（VC 等懒加载站）
        let imgPattern = #"<img\b[^>]*>"#
        var imageURLs: [String] = []
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            var keepIndexByMatch: [Int: Int] = [:]
            for (mi, match) in matches.enumerated() {
                guard let fullRange = Range(match.range, in: working) else { continue }
                let tag = String(working[fullRange])
                guard var u = resolveImageURL(fromImgTag: tag) else { continue }
                if u.hasPrefix("//") { u = "https:" + u }
                guard u.count > 8, !isIgnorableImageURL(u) else { continue }
                keepIndexByMatch[mi] = imageURLs.count
                imageURLs.append(u)
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
            } else if part.hasPrefix("__TABLE_"), part.hasSuffix("__") {
                lastImageURL = nil
                if let found = tablePlaceholders.first(where: { $0.token == part }) {
                    blocks.append(.table(headers: found.headers, rows: found.rows))
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
    /// 从 img 标签解析最佳 URL（src / data-* / srcset）
    private static func resolveImageURL(fromImgTag tag: String) -> String? {
        func attr(_ name: String) -> String? {
            let pat = name + #"\s*=\s*[\"']([^\"']+)[\"']"#
            guard let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) else { return nil }
            let ns = tag as NSString
            guard let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: tag) else { return nil }
            return String(tag[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func bestFromSrcset(_ srcset: String?) -> String? {
            guard let srcset, !srcset.isEmpty else { return nil }
            var best: String?
            var bestW = -1
            for part in srcset.split(separator: ",") {
                let bits = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard let url = bits.first.map(String.init), !url.isEmpty else { continue }
                var w = 0
                if bits.count >= 2 {
                    let d = bits[1].lowercased()
                    if d.hasSuffix("w") { w = Int(d.dropLast()) ?? 0 }
                    else if d.hasSuffix("x") { w = Int((Double(d.dropLast()) ?? 1) * 1000) }
                }
                if w >= bestW { bestW = w; best = url }
                else if best == nil { best = url }
            }
            return best
        }
        let src = attr("src")
        let srcIsPlaceholder: Bool = {
            guard let s = src?.lowercased() else { return true }
            if s.hasPrefix("data:") { return true }
            if s.contains("placeholder") || s.contains("1x1") || s.contains("blank.gif") { return true }
            return false
        }()
        let candidates = [
            attr("data-src"),
            attr("data-lazy-src"),
            attr("data-original"),
            attr("data-full-url"),
            attr("data-large_image"),
            attr("data-url"),
            bestFromSrcset(attr("data-srcset")),
            bestFromSrcset(attr("srcset")),
            srcIsPlaceholder ? nil : src,
            src
        ].compactMap { $0 }.filter { !$0.isEmpty && !$0.hasPrefix("data:") }
        return candidates.first
    }

    private static func isIgnorableImageURL(_ url: String) -> Bool {
        let u = url.lowercased()
        if u.hasPrefix("data:") { return true }
        if u.contains("fly-images/") { return true }
        if u.contains("1x1") || u.contains("pixel") || u.contains("spacer") { return true }
        if u.contains("doubleclick") || u.contains("googlesyndication") { return true }
        if u.contains("gravatar.com") { return true }
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


// MARK: - HTML table → rows

private func parseHTMLTable(_ html: String) -> (headers: [String], rows: [[String]]) {
    func cellTexts(in fragment: String, tag: String) -> [String] {
        let pattern = "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let ns = fragment as NSString
        return re.matches(in: fragment, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: fragment) else { return nil }
            var t = String(fragment[r])
            // 表内国旗/图标：img → emoji，再处理纯文本占位如 `_IMG_O_ Israel`
            t = TableCellIconMapper.replaceIcons(in: t)
            t = t.replacingOccurrences(of: #"<img\b[^>]*>"#, with: " ", options: .regularExpression)
            t = t.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            t = HTMLUtils.decodeEntities(t)
            t = TableCellIconMapper.replaceTextualPlaceholders(in: t)
            t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    var headers: [String] = []
    // thead th first
    if let theadRange = html.range(of: #"<thead[\s\S]*?</thead>"#, options: [.regularExpression, .caseInsensitive]) {
        headers = cellTexts(in: String(html[theadRange]), tag: "th")
        if headers.isEmpty {
            headers = cellTexts(in: String(html[theadRange]), tag: "td")
        }
    }
    var rows: [[String]] = []
    let rowPattern = #"<tr\b[^>]*>([\s\S]*?)</tr>"#
    guard let rowRe = try? NSRegularExpression(pattern: rowPattern, options: .caseInsensitive) else {
        return (headers, rows)
    }
    let ns = html as NSString
    let trMatches = rowRe.matches(in: html, range: NSRange(location: 0, length: ns.length))
    for (i, m) in trMatches.enumerated() {
        guard let r = Range(m.range(at: 1), in: html) else { continue }
        let rowHTML = String(html[r])
        // skip header row already taken from thead
        if i == 0 && headers.isEmpty {
            let ths = cellTexts(in: rowHTML, tag: "th")
            if !ths.isEmpty {
                headers = ths
                continue
            }
        }
        if rowHTML.lowercased().contains("<th") && headers.isEmpty {
            headers = cellTexts(in: rowHTML, tag: "th")
            if !headers.isEmpty { continue }
        }
        var cells = cellTexts(in: rowHTML, tag: "td")
        if cells.isEmpty {
            cells = cellTexts(in: rowHTML, tag: "th")
        }
        // 过滤分页提示行
        let joined = cells.joined(separator: " ").lowercased()
        if joined.contains("showing") && joined.contains("entries") { continue }
        if cells.isEmpty { continue }
        rows.append(cells)
    }
    return (headers, rows)
}

/// 表格单元格内国旗/图标 → emoji（无法显示原图时的可读回退）
private enum TableCellIconMapper {
    static func replaceIcons(in html: String) -> String {
        var work = html
        // 逐个 <img>：从 alt/title/src 推断国旗 emoji
        if let re = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive) {
            let ns = work as NSString
            let matches = re.matches(in: work, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                guard let range = Range(m.range, in: work) else { continue }
                let tag = String(work[range])
                let emoji = flagEmoji(fromImgTag: tag)
                work.replaceSubrange(range, with: emoji.map { " \($0) " } ?? " ")
            }
        }
        return work
    }

    /// 纯文本残留：`_IMG_O_ Israel`、`__IMG_0__`、`[flag] Israel` 等 → 🇮🇱 Israel
    static func replaceTextualPlaceholders(in text: String) -> String {
        var work = text

        // 1) `_IMG_O_ Israel` / `_IMG_12_United States` / `__IMG_0__ France`
        let placeholderWithName = [
            #"(?:_{1,2}IMG_[A-Za-z0-9]+_{1,2})\s*([A-Za-z][A-Za-z\u{00C0}-\u{024F}\s.\-']{1,48})"#,
            #"\[(?:flag|img)[^\]]*\]\s*([A-Za-z][A-Za-z\u{00C0}-\u{024F}\s.\-']{1,48})"#
        ]
        for pattern in placeholderWithName {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = work as NSString
            let matches = re.matches(in: work, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                guard let full = Range(m.range, in: work),
                      m.numberOfRanges >= 2,
                      let nameR = Range(m.range(at: 1), in: work) else { continue }
                let name = String(work[nameR]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let emoji = flagEmoji(forNameOrCode: name) {
                    work.replaceSubrange(full, with: "\(emoji) \(name)")
                } else {
                    // 认不出国旗时至少去掉丑陋占位，保留国名
                    work.replaceSubrange(full, with: name)
                }
            }
        }

        // 2) 孤立占位 `_IMG_O_` / `__IMG_3__`（无国名）直接去掉
        work = work.replacingOccurrences(
            of: #"_{1,2}IMG_[A-Za-z0-9]+_{1,2}"#,
            with: " ",
            options: .regularExpression
        )

        // 3) 单元格以国名开头且尚无 emoji 时，前缀国旗（常见：仅有 "Israel"）
        let trimmed = work.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           !trimmed.unicodeScalars.contains(where: { $0.value >= 0x1F1E6 && $0.value <= 0x1F1FF }),
           let emoji = flagEmoji(forNameOrCode: trimmed) {
            // 整格就是国名
            if nameToFlag[trimmed.lowercased()] != nil
                || (trimmed.count <= 3 && (iso2ToFlag[trimmed.lowercased()] != nil || iso3ToIso2[trimmed.lowercased()] != nil)) {
                work = "\(emoji) \(trimmed)"
            }
        }

        return work
    }

    private static func flagEmoji(fromImgTag tag: String) -> String? {
        func attr(_ name: String) -> String? {
            let pat = name + #"\s*=\s*[\"']([^\"']+)[\"']"#
            guard let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) else { return nil }
            let ns = tag as NSString
            guard let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: tag) else { return nil }
            return String(tag[r])
        }
        // alt / title 常为国名
        if let alt = attr("alt"), let e = flagEmoji(forNameOrCode: alt) { return e }
        if let title = attr("title"), let e = flagEmoji(forNameOrCode: title) { return e }
        // src：…/flags/il.png、il.svg、country/israel
        if let src = attr("src") ?? attr("data-src") {
            let lower = src.lowercased()
            // /flags/xx 或 _xx. 或 /xx.png
            if let re = try? NSRegularExpression(
                pattern: #"(?:flags?|country|countries)[/_\-]([a-z]{2,3})(?:[./_]|$)"#,
                options: .caseInsensitive
            ),
               let m = re.firstMatch(in: lower, range: NSRange(location: 0, length: (lower as NSString).length)),
               m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: lower) {
                if let e = flagEmoji(forNameOrCode: String(lower[r])) { return e }
            }
            // 文件名末尾两位：il.png
            if let re = try? NSRegularExpression(
                pattern: #"[/_\-]([a-z]{2})\.(?:png|svg|webp|jpg|jpeg|gif)"#,
                options: .caseInsensitive
            ),
               let m = re.firstMatch(in: lower, range: NSRange(location: 0, length: (lower as NSString).length)),
               m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: lower) {
                if let e = flagEmoji(forNameOrCode: String(lower[r])) { return e }
            }
            // 路径中国名
            for (name, emoji) in nameToFlag {
                if lower.contains(name) { return emoji }
            }
        }
        return nil
    }

    private static func flagEmoji(forNameOrCode raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if s.count == 2, let e = iso2ToFlag[s] { return e }
        if s.count == 3, let iso2 = iso3ToIso2[s], let e = iso2ToFlag[iso2] { return e }
        if let e = nameToFlag[s] { return e }
        // "Flag of Israel" / "Israel flag"
        for (name, emoji) in nameToFlag {
            if s.contains(name) { return emoji }
        }
        return nil
    }

    /// ISO 3166-1 alpha-2 → regional indicator flag
    private static func flag(fromISO2 code: String) -> String? {
        let c = code.uppercased()
        let scalars = Array(c.unicodeScalars)
        guard scalars.count == 2 else { return nil }
        let a = scalars[0], b = scalars[1]
        guard (65...90).contains(Int(a.value)), (65...90).contains(Int(b.value)) else { return nil }
        let base: UInt32 = 127397
        guard let s1 = UnicodeScalar(base + a.value),
              let s2 = UnicodeScalar(base + b.value) else { return nil }
        return String(String.UnicodeScalarView([s1, s2]))
    }

    private static let iso2ToFlag: [String: String] = {
        var map: [String: String] = [:]
        let codes = [
            "us","gb","uk","cn","jp","kr","de","fr","it","es","ru","in","br","ca","au","mx","ar","cl",
            "co","pe","ve","za","eg","ng","ke","et","il","sa","ae","tr","ir","iq","sy","lb","jo","ps",
            "pk","bd","id","my","th","vn","ph","sg","nz","se","no","dk","fi","nl","be","ch","at","pl",
            "cz","hu","ro","ua","gr","pt","ie","is","fi","tw","hk","mo","kp","mn","kz","uz","qa","kw",
            "om","bh","ye","af","lk","np","mm","kh","la","bn","tl","fj","pg","cu","jm","ht","do","pr",
            "gt","hn","sv","ni","cr","pa","bo","py","uy","ec","gy","sr","bz","tt","bb","bs","lc","gd"
        ]
        for c in codes {
            let iso = c == "uk" ? "gb" : c
            if let e = flag(fromISO2: iso) { map[c] = e }
        }
        return map
    }()

    private static let iso3ToIso2: [String: String] = [
        "usa": "us", "gbr": "gb", "chn": "cn", "jpn": "jp", "kor": "kr", "deu": "de", "fra": "fr",
        "ita": "it", "esp": "es", "rus": "ru", "ind": "in", "bra": "br", "can": "ca", "aus": "au",
        "mex": "mx", "isr": "il", "sau": "sa", "are": "ae", "tur": "tr", "irn": "ir", "irq": "iq",
        "syr": "sy", "lbn": "lb", "jor": "jo", "pse": "ps", "pak": "pk", "bgd": "bd", "idn": "id",
        "mys": "my", "tha": "th", "vnm": "vn", "phl": "ph", "sgp": "sg", "nld": "nl", "bel": "be",
        "che": "ch", "aut": "at", "pol": "pl", "ukr": "ua", "grc": "gr", "prt": "pt", "irl": "ie",
        "twn": "tw", "hkg": "hk", "nzl": "nz", "swe": "se", "nor": "no", "dnk": "dk", "fin": "fi",
        "arg": "ar", "chl": "cl", "col": "co", "per": "pe", "zaf": "za", "egy": "eg", "nga": "ng"
    ]

    private static let nameToFlag: [String: String] = {
        let pairs: [(String, String)] = [
            ("israel", "il"), ("united states", "us"), ("usa", "us"), ("america", "us"),
            ("united kingdom", "gb"), ("britain", "gb"), ("england", "gb"), ("china", "cn"),
            ("japan", "jp"), ("south korea", "kr"), ("korea", "kr"), ("germany", "de"),
            ("france", "fr"), ("italy", "it"), ("spain", "es"), ("russia", "ru"),
            ("india", "in"), ("brazil", "br"), ("canada", "ca"), ("australia", "au"),
            ("mexico", "mx"), ("saudi arabia", "sa"), ("united arab emirates", "ae"),
            ("uae", "ae"), ("turkey", "tr"), ("türkiye", "tr"), ("iran", "ir"), ("iraq", "iq"),
            ("syria", "sy"), ("lebanon", "lb"), ("jordan", "jo"), ("palestine", "ps"),
            ("pakistan", "pk"), ("bangladesh", "bd"), ("indonesia", "id"), ("malaysia", "my"),
            ("thailand", "th"), ("vietnam", "vn"), ("philippines", "ph"), ("singapore", "sg"),
            ("netherlands", "nl"), ("belgium", "be"), ("switzerland", "ch"), ("austria", "at"),
            ("poland", "pl"), ("ukraine", "ua"), ("greece", "gr"), ("portugal", "pt"),
            ("ireland", "ie"), ("taiwan", "tw"), ("hong kong", "hk"), ("new zealand", "nz"),
            ("sweden", "se"), ("norway", "no"), ("denmark", "dk"), ("finland", "fi"),
            ("argentina", "ar"), ("chile", "cl"), ("colombia", "co"), ("peru", "pe"),
            ("south africa", "za"), ("egypt", "eg"), ("nigeria", "ng"), ("qatar", "qa"),
            ("kuwait", "kw"), ("oman", "om"), ("bahrain", "bh"), ("yemen", "ye"),
            ("afghanistan", "af"), ("czechia", "cz"), ("czech republic", "cz"), ("hungary", "hu"),
            ("romania", "ro"), ("morocco", "ma"), ("algeria", "dz"), ("tunisia", "tn"),
            ("ethiopia", "et"), ("kenya", "ke"), ("cuba", "cu"), ("venezuela", "ve")
        ]
        var map: [String: String] = [:]
        for (name, iso) in pairs {
            if let e = flag(fromISO2: iso) { map[name] = e }
        }
        return map
    }()
}

/// 横向可滚动数据表（适配 Visual Capitalist 等宽表）
struct ArticleTableView: View {
    let headers: [String]
    let rows: [[String]]
    var fontSize: Double = 15
    var suppressArticleSwipe: Binding<Bool> = .constant(false)

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0, 1)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                if !headers.isEmpty {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { i in
                            Text(i < headers.count ? headers[i] : "")
                                .font(.system(size: max(12, fontSize - 1), weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(minWidth: 88, maxWidth: 220, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { i in
                            Text(i < row.count ? row[i] : "")
                                .font(.system(size: max(12, fontSize - 1)))
                                .foregroundStyle(.primary)
                                .frame(minWidth: 88, maxWidth: 220, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                        }
                    }
                    .background(idx % 2 == 0 ? Color.clear : Color(.secondarySystemBackground).opacity(0.45))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 横向拖动表格时暂时屏蔽阅读页换篇手势
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        if !suppressArticleSwipe.wrappedValue {
                            suppressArticleSwipe.wrappedValue = true
                        }
                    }
                }
                .onEnded { _ in
                    // 略延迟，避免与父级 onEnded 竞态导致仍触发换篇
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        suppressArticleSwipe.wrappedValue = false
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("数据表")
    }
}
