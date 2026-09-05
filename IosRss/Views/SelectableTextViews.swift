import SwiftUI
import UIKit

// MARK: - Selectable paragraph (UITextView + 选区菜单「AI解释」)

struct SelectableParagraphView: UIViewRepresentable {
    let attributed: AttributedString
    let fontSize: Double
    var onOpenURL: (URL) -> Void
    var onExplain: (String) -> Void

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
        context.coordinator.onOpenURL = onOpenURL
        apply(to: tv)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.onExplain = onExplain
        context.coordinator.onOpenURL = onOpenURL
        apply(to: uiView)
        uiView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 40
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    private func apply(to tv: UITextView) {
        let ns = NSAttributedString(attributed)
        let mutable = NSMutableAttributedString(attributedString: ns)
        let full = NSRange(location: 0, length: mutable.length)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        mutable.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            var next = attrs
            next[.font] = font
            if attrs[.link] == nil {
                next[.foregroundColor] = UIColor.label
            }
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 8
            para.alignment = .natural
            next[.paragraphStyle] = para
            mutable.setAttributes(next, range: range)
        }
        if tv.attributedText?.string != mutable.string {
            tv.attributedText = mutable
        } else if let current = tv.font?.pointSize, abs(Double(current) - fontSize) > 0.1 {
            tv.attributedText = mutable
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: (URL) -> Void
        var onExplain: (String) -> Void

        init(onOpenURL: @escaping (URL) -> Void, onExplain: @escaping (String) -> Void) {
            self.onOpenURL = onOpenURL
            self.onExplain = onExplain
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
                guard let self else { return }
                let ns = textView.text as NSString? ?? ""
                guard range.location + range.length <= ns.length else { return }
                let selected = ns.substring(with: range)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !selected.isEmpty else { return }    
                self.onExplain(selected)
            }
            return UIMenu(children: suggestedActions + [explain])
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
