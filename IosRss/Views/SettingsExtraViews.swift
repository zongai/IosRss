import SwiftUI

struct TranslationSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var googleKey = Keychain.load(key: "google_translate_key") ?? ""
    @State private var microsoftKey = Keychain.load(key: "microsoft_translate_key") ?? ""
    @State private var deeplKey = Keychain.load(key: "deepl_translate_key") ?? ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("翻译目标语言", selection: $store.targetLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                Picker("AI 输出语言", selection: $store.aiOutputLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            } header: {
                Text("语言")
            } footer: {
                Text("翻译引擎将内容译为「翻译目标语言」；摘要/解释使用「AI 输出语言」。")
            }

            Section {
                Picker("默认翻译引擎", selection: $store.defaultTranslationEngine) {
                    ForEach(TranslationEngine.allCases, id: \.self) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("选择默认翻译引擎")
            }

            Section {
                Picker("并发度", selection: $store.translationConcurrency) {
                    Text("自动（推荐）").tag(0)
                    ForEach(1...8, id: \.self) { n in
                        Text("\(n) 路").tag(n)
                    }
                }
            } header: {
                Text("并发")
            } footer: {
                Text("同时请求数。自动：Google 6、免 Key 4、AI 4。列表整批并发。过高可能限流。")
            }

            Section {
                HStack {
                    Text("Google 翻译").font(.system(size: 15, weight: .medium))
                    Spacer()
                    if store.defaultTranslationEngine == .google {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.primary)
                    }
                }
                TextField("API Key（可选，免费模式无需填写）", text: $googleKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: googleKey) { _, new in
                        if new.isEmpty { Keychain.delete(key: "google_translate_key") }
                        else { Keychain.save(key: "google_translate_key", value: new) }
                    }
            } header: { Text("Google 翻译") }
            footer: { Text("不填 API Key 时使用免费翻译接口，有请求频率限制") }

            Section {
                freeEngineRow("MyMemory（免 Key）", selected: store.defaultTranslationEngine == .mymemory)
                freeEngineRow("Lingva（免 Key）", selected: store.defaultTranslationEngine == .lingva)
                freeEngineRow("LibreTranslate（免 Key）", selected: store.defaultTranslationEngine == .libre)
            } header: {
                Text("免注册免 Key")
            } footer: {
                Text("MyMemory / Lingva / LibreTranslate 均无需注册与 Key。公共实例可能限流，失败时可换 Google 或其它引擎。")
            }

            Section {
                HStack {
                    Text("Microsoft 翻译").font(.system(size: 15, weight: .medium))
                    Spacer()
                    if store.defaultTranslationEngine == .microsoft {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.primary)
                    }
                }
                TextField("Ocp-Apim-Subscription-Key", text: $microsoftKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: microsoftKey) { _, new in
                        if new.isEmpty { Keychain.delete(key: "microsoft_translate_key") }
                        else { Keychain.save(key: "microsoft_translate_key", value: new) }
                    }
            } header: { Text("Microsoft Translator") }

            Section {
                HStack {
                    Text("DeepL 翻译").font(.system(size: 15, weight: .medium))
                    Spacer()
                    if store.defaultTranslationEngine == .deepl {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.primary)
                    }
                }
                TextField("DeepL API Key", text: $deeplKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: deeplKey) { _, new in
                        if new.isEmpty { Keychain.delete(key: "deepl_translate_key") }
                        else { Keychain.save(key: "deepl_translate_key", value: new) }
                    }
            } header: { Text("DeepL") }
            footer: { Text("免费版 Key 以 \":fx\" 结尾，会自动使用免费端点；付费版 Key 使用正式端点") }

            Section {
                HStack {
                    Text("AI 翻译").font(.system(size: 15, weight: .medium))
                    Spacer()
                    if store.defaultTranslationEngine == .ai {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.primary)
                    }
                }
                if let pid = store.defaultTranslationProviderID,
                   let provider = store.aiProviders.first(where: { $0.id == pid }) {
                    Text("使用 \(provider.name) · \(provider.model)")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    Text("在 AI 设置中指定翻译 Provider（支持 OpenAI / Anthropic / Gemini）")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            } header: { Text("AI 翻译") }
            footer: { Text("Gemini、OpenAI、Anthropic 等统一在「AI 设置」中配置，选择「AI 翻译」后即可使用") }
        }
        .navigationTitle("翻译设置")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
        .onChange(of: store.defaultTranslationEngine) { _, _ in store.persistSettings() }
        .onChange(of: store.translationConcurrency) { _, _ in store.persistSettings() }
        .onChange(of: store.targetLanguage) { _, _ in store.persistSettings() }
        .onChange(of: store.aiOutputLanguage) { _, _ in store.persistSettings() }
    }

    @ViewBuilder
    private func freeEngineRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.primary)
            }
        }
    }
}


// MARK: - 文章黑名单（与 AI 黑名单独立）

struct ArticleBlacklistSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var newTerm = ""
    @State private var appliedCount: Int?

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                if store.articleBlacklistTerms.isEmpty {
                    Text("暂无关键词").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.articleBlacklistTerms.enumerated()), id: \.offset) { index, term in
                        HStack {
                            Text(term)
                            Spacer()
                            Button {
                                store.articleBlacklistTerms.remove(at: index)
                                store.persistSettings()
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("关键词，如广告、招聘", text: $newTerm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { addTerm() }
                    Button("添加") { addTerm() }
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("关键词")
            } footer: {
                Text("标题或摘要包含任一关键词时，自动标为已读并按未读规则隐藏。与 AI 黑名单互不影响，不区分大小写。")
            }

            if !store.articleBlacklistTerms.isEmpty {
                Section {
                    Button("立即应用到已有文章") {
                        let n = store.applyArticleBlacklist()
                        appliedCount = n
                    }
                    if let appliedCount {
                        Text(appliedCount == 0 ? "没有新的命中条目" : "已将 \(appliedCount) 篇标为已读")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("文章黑名单")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let exists = store.articleBlacklistTerms.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
        guard !exists else { newTerm = ""; return }
        store.articleBlacklistTerms.append(term)
        store.persistSettings()
        newTerm = ""
        appliedCount = store.applyArticleBlacklist()
    }
}


import UniformTypeIdentifiers

struct SettingsExportPicker: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onDismiss() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onDismiss() }
    }
}

struct SettingsImportPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .data], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }
    }
}
