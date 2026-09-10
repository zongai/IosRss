import SwiftUI

struct TranslationSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var googleKey = Keychain.load(key: "google_translate_key") ?? ""
    @State private var microsoftKey = Keychain.load(key: "microsoft_translate_key") ?? ""
    @State private var deeplKeys: [String] = []
    @State private var newDeepLKey = ""
    @State private var testingEngine: TranslationEngine?
    @State private var testMessage: String?
    @State private var testIsError = false

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
                Text("同时请求数。自动：Google 6、免 Key 4、AI 4。过高可能限流。")
            }

            // Google
            Section {
                engineHeader("Google 翻译", selected: store.defaultTranslationEngine == .google)
                TextField("API Key（可选，免费模式可不填）", text: $googleKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: googleKey) { _, v in
                        Keychain.save(key: "google_translate_key", value: v.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                testButton(for: .google)
            } header: { Text("Google") }
            footer: { Text("不填 Key 时使用公开接口；有 Key 时走官方 API。") }

            // Microsoft
            Section {
                engineHeader("Microsoft 翻译", selected: store.defaultTranslationEngine == .microsoft)
                TextField("API Key（必填）", text: $microsoftKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: microsoftKey) { _, v in
                        Keychain.save(key: "microsoft_translate_key", value: v.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                TextField("资源区域（如 eastasia / eastus / global）", text: $store.microsoftTranslateRegion)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                testButton(for: .microsoft)
            } header: { Text("Microsoft") }
            footer: { Text("401 时请填写 Azure 门户中该资源的「位置/区域」。多服务资源必须填区域；全球资源可填 global。") }

            // DeepL
            Section {
                engineHeader("DeepL", selected: store.defaultTranslationEngine == .deepl)
                ForEach(Array(deeplKeys.enumerated()), id: \.offset) { idx, key in
                    HStack {
                        Text(maskSecret(key)).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            deeplKeys.remove(at: idx)
                            store.saveDeepLKeys(deeplKeys)
                        } label: { Image(systemName: "trash") }
                    }
                }
                HStack {
                    TextField("添加 DeepL Key", text: $newDeepLKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("添加") {
                        let k = newDeepLKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !k.isEmpty else { return }
                        deeplKeys.append(k)
                        store.saveDeepLKeys(deeplKeys)
                        newDeepLKey = ""
                    }
                }
                testButton(for: .deepl)
            } header: { Text("DeepL（多 Key）") }
            footer: { Text("配额耗尽或失败时自动切换下一把 Key，全部失败则回退 Google。") }

            // MyMemory
            Section {
                engineHeader("MyMemory（免 Key）", selected: store.defaultTranslationEngine == .mymemory)
                testButton(for: .mymemory)
            } header: { Text("MyMemory") }
            footer: { Text("按 IP 有日配额；限流时请换引擎或稍后再试。") }


            // AI
            Section {
                engineHeader("AI 翻译", selected: store.defaultTranslationEngine == .ai)
                Text("在「AI 设置」中配置 Provider 与 Key，可对单个 Provider 左滑测试。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                testButton(for: .ai)
            } header: { Text("AI 翻译") }

            if let testMessage {
                Section {
                    Text(testMessage)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(testIsError ? .red : .primary)
                        .textSelection(.enabled)
                } header: { Text("测试结果（含 Key 可用性）") }
            }
        }
        .navigationTitle("翻译设置")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
        .onChange(of: store.defaultTranslationEngine) { _, _ in store.persistSettings() }
        .onChange(of: store.translationConcurrency) { _, _ in store.persistSettings() }
        .onChange(of: store.microsoftTranslateRegion) { _, _ in store.persistSettings() }
        .onAppear { deeplKeys = store.loadDeepLKeys() }
        .onChange(of: store.targetLanguage) { _, _ in store.persistSettings() }
        .onChange(of: store.aiOutputLanguage) { _, _ in store.persistSettings() }
    }

    private func maskSecret(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count > 8 else { return String(repeating: "•", count: max(4, k.count)) }
        return String(k.prefix(3)) + "…" + String(k.suffix(4))
    }

    @ViewBuilder
    private func engineHeader(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.primary)
            }
        }
    }

    private func testButton(for engine: TranslationEngine) -> some View {
        Button {
            Task { await runTest(engine) }
        } label: {
            HStack {
                if testingEngine == engine {
                    ProgressView().scaleEffect(0.85)
                    Text("测试中…")
                } else {
                    Label("测试此引擎", systemImage: "network")
                }
                Spacer()
            }
        }
        .disabled(testingEngine != nil)
    }

    @MainActor
    private func runTest(_ engine: TranslationEngine) async {
        testingEngine = engine
        testMessage = nil
        testIsError = false
        defer { testingEngine = nil }
        do {
            // 先保存当前输入的 Key
            Keychain.save(key: "google_translate_key", value: googleKey.trimmingCharacters(in: .whitespacesAndNewlines))
            Keychain.save(key: "microsoft_translate_key", value: microsoftKey.trimmingCharacters(in: .whitespacesAndNewlines))
            store.saveDeepLKeys(deeplKeys)
            store.persistSettings()
            let msg = try await store.testTranslationEngine(engine)
            testMessage = msg
            testIsError = false
        } catch {
            testMessage = error.localizedDescription
            testIsError = true
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
