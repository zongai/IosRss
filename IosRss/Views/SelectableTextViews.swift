import SwiftUI
import UIKit

// MARK: - Selectable paragraph (UITextView + 选区菜单「AI解释」)

struct SelectableParagraphView: UIViewRepresentable {
    let attributed: AttributedString
    let fontSize: Double
    var typography: ReaderTypography = .latin
    var onOpenURL: (URL) -> Void
    var onExplain: (String) -> Void
    var onHighlight: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: onOpenURL, onExplain: onExplain)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = []
        tv.delegate = context.coordinator
        tv.linkTextAttributes = [
            .foregroundColor: UIColor.tintColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        context.coordinator.onExplain = onExplain
        context.coordinator.onHighlight = onHighlight
        context.coordinator.onOpenURL = onOpenURL
        apply(to: tv)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.onExplain = onExplain
        context.coordinator.onHighlight = onHighlight
        context.coordinator.onOpenURL = onOpenURL
        // 内容未变则跳过整段属性重建 + sizeThatFits，滚动时主线程开销下降明显
        let mark = contentMark
        guard uiView.accessibilityValue != mark else { return }
        apply(to: uiView, mark: mark)
        uiView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 40
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    /// 轻量内容指纹：避免每次 update 都对全文做 hash + 属性枚举
    private var contentMark: String {
        let sample = attributed.characters
        let len = sample.count
        // 取头尾少量字符即可区分段落，避免对整段 String 做 hashValue
        let head = String(sample.prefix(24))
        let tail = len > 48 ? String(sample.suffix(16)) : ""
        return "\(typography)-\(Int(fontSize))-\(len)-\(head)-\(tail)"
    }

    private func apply(to tv: UITextView, mark: String? = nil) {
        let resolvedMark = mark ?? contentMark
        if tv.accessibilityValue == resolvedMark { return }

        let ns = NSAttributedString(attributed)
        let mutable = NSMutableAttributedString(attributedString: ns)
        let full = NSRange(location: 0, length: mutable.length)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.alignment = .natural
        switch typography {
        case .chinese:
            para.firstLineHeadIndent = fontSize * 2.0
            para.lineSpacing = max(4, fontSize * 0.45)
            para.paragraphSpacing = max(6, fontSize * 0.35)
            para.lineBreakMode = .byWordWrapping
        case .latin:
            para.firstLineHeadIndent = 0
            para.lineSpacing = max(3, fontSize * 0.28)
            para.paragraphSpacing = max(8, fontSize * 0.4)
            para.lineBreakMode = .byWordWrapping
        }
        mutable.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            var next = attrs
            next[.font] = font
            if attrs[.link] == nil {
                next[.foregroundColor] = UIColor.label
            }
            next[.paragraphStyle] = para
            mutable.setAttributes(next, range: range)
        }
        tv.attributedText = mutable
        tv.accessibilityValue = resolvedMark
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: (URL) -> Void
        var onExplain: (String) -> Void
        var onHighlight: ((String) -> Void)?

        init(onOpenURL: @escaping (URL) -> Void, onExplain: @escaping (String) -> Void) {
            self.onOpenURL = onOpenURL
            self.onExplain = onExplain
        }

        private func selectedText(_ textView: UITextView, range: NSRange) -> String? {
            let ns = textView.text as NSString? ?? ""
            guard range.location + range.length <= ns.length else { return nil }
            let selected = ns.substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return selected.isEmpty ? nil : selected
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            if case .link(let url) = textItem.content {
                return UIAction { [weak self] _ in self?.onOpenURL(url) }
            }
            return defaultAction
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else {
                return UIMenu(children: suggestedActions)
            }
            let explain = UIAction(
                title: "AI解释",
                image: UIImage(systemName: "sparkles")
            ) { [weak self] _ in
                guard let self, let selected = self.selectedText(textView, range: range) else { return }
                self.onExplain(selected)
            }
            let highlight = UIAction(
                title: "高亮",
                image: UIImage(systemName: "highlighter")
            ) { [weak self] _ in
                guard let self, let selected = self.selectedText(textView, range: range) else { return }
                self.onHighlight?(selected)
            }
            return UIMenu(children: [explain, highlight] + suggestedActions)
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            onOpenURL(URL)
            return false
        }
    }
}

// MARK: - AI 解释结果面板

struct AIExplainSheet: View {
    @Environment(AppStore.self) private var store
    let query: String
    let result: String?
    let error: String?
    let isLoading: Bool
    var onRetry: () -> Void
    var onDismiss: () -> Void

    private var providerName: String? {
        let id = store.defaultExplainProviderID
            ?? store.defaultSummaryProviderID
            ?? store.defaultTranslationProviderID
        return store.aiProviders.first(where: { $0.id == id })?.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("选中内容")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(query)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("AI 解释")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if let providerName {
                                Text(providerName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color(.systemBackground))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary, in: .capsule)
                            }
                        }

                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("正在解释…")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                        } else if let error {
                            Text(error)
                                .font(.system(size: 15))
                                .foregroundStyle(.red)
                            Button("重试", action: onRetry)
                                .buttonStyle(.bordered)
                        } else if let result, !result.isEmpty {
                            Text(result)
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                                .lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("暂无结果")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("AI 解释")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { onDismiss() }
                }
            }
        }
    }
}

