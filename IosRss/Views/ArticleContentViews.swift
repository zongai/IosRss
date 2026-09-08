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
                case .audio(let urlString, let title):
                    ArticleAudioCard(urlString: urlString, title: title)
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
    case audio(url: String, title: String)
}

enum ContentBlockParser {
    static func parse(_ html: String, prefersChineseTypography: Bool = false) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var working = html
        working = working.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        working = working.replacingOccurrences(of: #"</p>|</div>|</li>|</h[1-6]>"#, with: "\n\n", options: .regularExpression)

        // <audio src="..."> / <source src="...mp3">
        var audioItems: [(url: String, title: String)] = []
        let audioTagPattern = #"<audio\b[^>]*?(?:src=[\"']([^\"']+)[\"'][^>]*)?>([\s\S]*?)</audio>"#
        if let regex = try? NSRegularExpression(pattern: audioTagPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                var src: String?
                if match.numberOfRanges >= 2, match.range(at: 1).location != NSNotFound,
                   let r = Range(match.range(at: 1), in: working) {
                    src = String(working[r])
                }
                if src == nil, match.numberOfRanges >= 3, let bodyRange = Range(match.range(at: 2), in: working) {
                    let body = String(working[bodyRange])
                    if let srcRegex = try? NSRegularExpression(pattern: #"src=[\"']([^\"']+)[\"']"#, options: .caseInsensitive),
                       let m = srcRegex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
                       m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: body) {
                        src = String(body[r])
                    }
                }
                if let src, isAudioURL(src), let full = Range(match.range, in: working) {
                    audioItems.insert((src, audioTitle(from: src)), at: 0)
                    working.replaceSubrange(full, with: "\n\n__AUD_\(audioItems.count - 1)__\n\n")
                }
            }
        }

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
            } else if part.hasPrefix("__AUD_"), part.hasSuffix("__") {
                let idxStr = String(part.dropFirst(6).dropLast(2))
                if let idx = Int(idxStr), idx >= 0, idx < audioItems.count {
                    blocks.append(.audio(url: audioItems[idx].url, title: audioItems[idx].title))
                }
            } else {
                // 裸链 mp3/音频
                let candidate = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if isAudioURL(candidate) {
                    blocks.append(.audio(url: candidate, title: audioTitle(from: candidate)))
                } else {
                    // 段落中若含独立 mp3 URL 也抽出
                    let urls = extractAudioURLs(from: part)
                    if urls.isEmpty {
                        let style = ReaderTypography.resolve(text: part, preferChinese: prefersChineseTypography)
                        blocks.append(.paragraph(
                            makeAttributedParagraph(part, linkHrefs: linkHrefs, linkTexts: linkTexts),
                            style
                        ))
                    } else {
                        var remaining = part
                        for u in urls {
                            remaining = remaining.replacingOccurrences(of: u, with: "")
                            blocks.append(.audio(url: u, title: audioTitle(from: u)))
                        }
                        let leftover = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !leftover.isEmpty {
                            let style = ReaderTypography.resolve(text: leftover, preferChinese: prefersChineseTypography)
                            blocks.append(.paragraph(
                                makeAttributedParagraph(leftover, linkHrefs: linkHrefs, linkTexts: linkTexts),
                                style
                            ))
                        }
                    }
                }
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

    private static func isAudioURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        if lower.hasSuffix(".mp3") || lower.hasSuffix(".m4a") || lower.hasSuffix(".aac") || lower.hasSuffix(".wav") || lower.hasSuffix(".ogg") {
            return true
        }
        if lower.contains(".mp3?") || lower.contains(".m4a?") { return true }
        return false
    }

    private static func audioTitle(from url: String) -> String {
        if let u = URL(string: url) {
            let name = u.lastPathComponent.removingPercentEncoding ?? u.lastPathComponent
            if !name.isEmpty, name != "/" { return name }
        }
        return "音频"
    }

    private static func extractAudioURLs(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>\"']+\.(?:mp3|m4a|aac|wav|ogg)(?:\?[^\s<>\"']*)?"#, options: .caseInsensitive) else {
            return []
        }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            Range(m.range, in: text).map { String(text[$0]) }
        }
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

// MARK: - MP3 / Audio card

import AVFoundation
import Combine

@MainActor
final class ArticleAudioPlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var progress: Double = 0
    @Published var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func toggle(url: URL) {
        if isPlaying {
            pause()
            return
        }
        play(url: url)
    }

    func play(url: URL) {
        error = nil
        if let player, player.currentItem?.status == .readyToPlay,
           (player.currentItem?.asset as? AVURLAsset)?.url == url {
            player.play()
            isPlaying = true
            return
        }
        stop()
        isLoading = true
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            let secs = t.seconds
            if secs.isFinite { self.progress = secs }
            if let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.progress = 0
            self?.player?.seek(to: .zero)
        }
        p.play()
        isPlaying = true
        isLoading = false
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
        isLoading = false
        progress = 0
        duration = 0
    }

    deinit {
        // cleanup without MainActor isolation issues
    }
}

struct ArticleAudioCard: View {
    let urlString: String
    let title: String
    @StateObject private var model = ArticleAudioPlayerModel()

    private var url: URL? { URL(string: urlString) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    guard let url else { return }
                    model.toggle(url: url)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 44, height: 44)
                        if model.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(url == nil)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text("音频")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if model.duration > 0 {
                ProgressView(value: min(model.progress, model.duration), total: model.duration)
                    .tint(.accentColor)
                HStack {
                    Text(formatTime(model.progress))
                    Spacer()
                    Text(formatTime(model.duration))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            if let err = model.error {
                Text(err).font(.system(size: 12)).foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        .onDisappear { model.stop() }
    }

    private func formatTime(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
