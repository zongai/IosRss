import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var cacheSizeText: String = "计算中…"

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("通用") {
                    Picker("标题显示模式", selection: $store.titleDisplayMode) {
                        ForEach(TitleDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Toggle("显示已读文章", isOn: $store.showReadArticles)
                }
                .onChange(of: store.titleDisplayMode) { _, _ in store.persistSettings() }
                .onChange(of: store.showReadArticles) { _, _ in store.persistSettings() }

                Section {
                    NavigationLink(destination: FontSettingsView()) {
                        Label("字号设置", systemImage: "textformat.size")
                    }
                    NavigationLink(destination: TranslationSettingsView()) {
                        Label("翻译设置", systemImage: "translate")
                    }
                    NavigationLink(destination: AISettingsView()) {
                        Label("AI 设置", systemImage: "wand.and.stars")
                    }
                } header: {
                    Text("功能设置")
                }

                Section {
                    HStack {
                        Text("已读保留")
                        Spacer()
                        Text(store.readRetentionDays == 0 ? "不清理" : "\(store.readRetentionDays) 天")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $store.readRetentionDays, in: 0...90, step: 1).labelsHidden()
                    }
                    HStack {
                        Text("全文缓存")
                        Spacer()
                        Text(store.fullContentCacheDays == 0 ? "不清理" : "\(store.fullContentCacheDays) 天")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $store.fullContentCacheDays, in: 0...180, step: 1).labelsHidden()
                    }
                } header: {
                    Text("自动清理")
                } footer: {
                    Text("已读保留：超过天数的非收藏已读条目会从列表移除。全文缓存：磁盘上的抓取正文超过天数后删除。设为 0 表示不自动清理。")
                }
                .onChange(of: store.readRetentionDays) { _, _ in
                    store.persistSettings()
                    store.purgeOldReadArticles()
                }
                .onChange(of: store.fullContentCacheDays) { _, _ in
                    store.persistSettings()
                    store.pruneFullContentCache()
                }

                Section {
                    HStack {
                        Label("内容缓存", systemImage: "internaldrive")
                        Spacer()
                        Text(cacheSizeText).foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        store.clearOfflineContentCache()
                        cacheSizeText = store.cacheSizeDescription()
                    } label: {
                        Label("清除离线缓存", systemImage: "trash")
                    }
                } header: {
                    Text("离线")
                } footer: {
                    Text("订阅列表与已读标记始终保存在本地。清除后仅删除文章全文、Feed 快照与图片缓存，不影响订阅。")
                }
                .onAppear { cacheSizeText = store.cacheSizeDescription() }

                Section("关于") {
                    HStack {
                        Text("默认翻译引擎")
                        Spacer()
                        Text(store.defaultTranslationEngine.rawValue).foregroundStyle(.secondary)
                    }
                    if let pid = store.defaultSummaryProviderID,
                       let provider = store.aiProviders.first(where: { $0.id == pid }) {
                        HStack {
                            Text("默认摘要引擎")
                            Spacer()
                            Text(provider.name).foregroundStyle(.secondary)
                        }
                    }
                    if let pid = store.defaultExplainProviderID,
                       let provider = store.aiProviders.first(where: { $0.id == pid }) {
                        HStack {
                            Text("默认解释引擎")
                            Spacer()
                            Text(provider.name).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(AppVersion.display).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .onDisappear { store.persistSettings() }
        }
    }

}

struct FontSettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                fontStepper(title: "分组名称", value: $store.groupTitleFontSize, range: 11...22)
                fontStepper(title: "订阅列表标题", value: $store.feedTitleFontSize, range: 14...22)
                fontStepper(title: "文章列表标题", value: $store.listTitleFontSize, range: 14...24)
                fontStepper(title: "文章列表摘要", value: $store.listSummaryFontSize, range: 12...20)
            } header: {
                Text("列表")
            }

            Section {
                fontStepper(title: "阅读器标题", value: $store.readerTitleFontSize, range: 18...32)
                fontStepper(title: "阅读器正文", value: $store.fontSize, range: 12...28)
                fontStepper(title: "AI 摘要", value: $store.aiSummaryFontSize, range: 14...28)
            } header: {
                Text("阅读")
            } footer: {
                Text("调整后立即生效，并自动保存。")
            }
        }
        .navigationTitle("字号设置")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
        .onChange(of: store.groupTitleFontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.feedTitleFontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.listTitleFontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.listSummaryFontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.readerTitleFontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.fontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.aiSummaryFontSize) { _, _ in store.persistSettings() }
    }

    @ViewBuilder
    private func fontStepper(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value.wrappedValue))").foregroundStyle(.secondary).monospacedDigit()
            Stepper("", value: value, in: range, step: 1).labelsHidden()
        }
    }
}

struct TranslationSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var googleKey = Keychain.load(key: "google_translate_key") ?? ""
    @State private var microsoftKey = Keychain.load(key: "microsoft_translate_key") ?? ""
    @State private var deeplKey = Keychain.load(key: "deepl_translate_key") ?? ""

    var body: some View {
        @Bindable var store = store
        Form {
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
    }
}

struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddProvider = false
    @State private var editingProvider: AIProvider?
    @State private var newBlacklistTerm = ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                ForEach(store.aiProviders) { provider in
                    AIProviderRow(provider: provider)
                        .contentShape(Rectangle())
                        .onTapGesture { editingProvider = provider }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.aiProviders.removeAll(where: { $0.id == provider.id })
                                if store.aiBlacklistFallbackProviderID == provider.id {
                                    store.aiBlacklistFallbackProviderID = nil
                                }
                                if store.defaultExplainProviderID == provider.id {
                                    store.defaultExplainProviderID = nil
                                }
                                if store.defaultSummaryProviderID == provider.id {
                                    store.defaultSummaryProviderID = store.aiProviders.first?.id
                                }
                                if store.defaultTranslationProviderID == provider.id {
                                    store.defaultTranslationProviderID = store.aiProviders.first?.id
                                }
                                store.persistSettings()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
                Button { showAddProvider = true } label: {
                    Label("添加 Provider", systemImage: "plus")
                }
            } header: {
                Text("AI Provider")
            } footer: {
                Text("Gemini、OpenAI、Anthropic 等统一管理。添加时可选模板，Gemini 会自动走专用接口。")
            }

            Section {
                Picker("默认解释引擎", selection: Binding(
                    get: { store.defaultExplainProviderID },
                    set: { store.defaultExplainProviderID = $0; store.persistSettings() }
                )) {
                    Text("跟随摘要引擎").tag(Optional<UUID>.none)
                    ForEach(store.aiProviders) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
            } header: {
                Text("AI 解释")
            } footer: {
                Text("框选文章文字后的「AI解释」使用此 Provider。选「跟随摘要引擎」时与摘要共用。")
            }

            Section {
                ForEach(Array(store.aiBlacklistTerms.enumerated()), id: \.offset) { index, term in
                    HStack {
                        Text(term).font(.system(size: 15))
                        Spacer()
                        Button {
                            store.aiBlacklistTerms.remove(at: index)
                            store.persistSettings()
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("添加关键词，如敏感词", text: $newBlacklistTerm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { addBlacklistTerm() }
                    Button("添加") { addBlacklistTerm() }
                        .disabled(newBlacklistTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Picker("命中后使用", selection: Binding(
                    get: { store.aiBlacklistFallbackProviderID },
                    set: { store.aiBlacklistFallbackProviderID = $0; store.persistSettings() }
                )) {
                    Text("不切换（保持默认）").tag(Optional<UUID>.none)
                    ForEach(store.aiProviders) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
            } header: {
                Text("AI 黑名单")
            } footer: {
                Text("当 AI 翻译 / 摘要 / 解释 的原文包含任一关键词时，自动改用上方指定的 Provider。不区分大小写。")
            }

            Section {
                TextEditor(text: $store.translationPrompt)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(minHeight: 110)
                Button("恢复默认翻译 Prompt") {
                    store.translationPrompt = AppStore.defaultTranslationPrompt
                    store.persistSettings()
                }
            } header: {
                Text("翻译 Prompt")
            } footer: {
                Text("仅「AI 翻译」引擎使用。用 {{text}} 表示待译内容。")
            }

            Section {
                TextEditor(text: $store.summaryPrompt)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(minHeight: 130)
                Button("恢复默认摘要 Prompt") {
                    store.summaryPrompt = AppStore.defaultSummaryPrompt
                    store.persistSettings()
                }
            } header: {
                Text("摘要 Prompt")
            } footer: {
                Text("用 {{title}} 表示标题，{{content}} 表示正文（自动截取前 2500 字）。")
            }

            Section {
                TextEditor(text: $store.explainPrompt)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(minHeight: 110)
                Button("恢复默认解释 Prompt") {
                    store.explainPrompt = AppStore.defaultExplainPrompt
                    store.persistSettings()
                }
            } header: {
                Text("解释 Prompt")
            } footer: {
                Text("框选文字「AI解释」使用。用 {{text}} 表示选中内容（最长约 800 字）。")
            }
        }
        .navigationTitle("AI 设置")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
        .onChange(of: store.translationPrompt) { _, _ in store.persistSettings() }
        .onChange(of: store.summaryPrompt) { _, _ in store.persistSettings() }
        .onChange(of: store.explainPrompt) { _, _ in store.persistSettings() }
        .sheet(isPresented: $showAddProvider) { EditProviderView(provider: nil) }
        .sheet(item: $editingProvider) { provider in EditProviderView(provider: provider) }
    }

    private func addBlacklistTerm() {
        let term = newBlacklistTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let exists = store.aiBlacklistTerms.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == term.lowercased()
        }
        if !exists {
            store.aiBlacklistTerms.append(term)
            store.persistSettings()
        }
        newBlacklistTerm = ""
    }
}

struct AIProviderRow: View {
    @Environment(AppStore.self) private var store
    let provider: AIProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(provider.name).font(.system(size: 15, weight: .medium))
                Spacer()
                HStack(spacing: 8) {
                    if provider.isDefaultSummary || store.defaultSummaryProviderID == provider.id {
                        ProviderTag(text: "摘要", color: Color.primary)
                    }
                    if provider.isDefaultTranslation || store.defaultTranslationProviderID == provider.id {
                        ProviderTag(text: "翻译", color: Color.secondary)
                    }
                    if store.defaultExplainProviderID == provider.id {
                        ProviderTag(text: "解释", color: .orange)
                    }
                }
            }
            Text(provider.model).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(provider.baseURL).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

struct ProviderTag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: .capsule)
    }
}

struct EditProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    let provider: AIProvider?

    @State private var name = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var kind = "openai"
    @State private var isDefaultSummary = false
    @State private var isDefaultTranslation = false
    @State private var isDefaultExplain = false

    private var isNew: Bool { provider == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider 模板") {
                    Button("OpenAI") { applyTemplate(.openAITemplate) }.foregroundStyle(Color.primary)
                    Button("Anthropic") { applyTemplate(.anthropicTemplate) }.foregroundStyle(Color.primary)
                    Button("Gemini") { applyTemplate(.geminiTemplate) }.foregroundStyle(Color.primary)
                }
                Section("基本信息") {
                    TextField("名称", text: $name)
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("模型名", text: $model)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Picker("接口类型", selection: $kind) {
                        Text("OpenAI 兼容").tag("openai")
                        Text("Gemini").tag("gemini")
                    }
                }
                Section {
                    SecureField("API Key", text: $apiKey)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                } header: {
                    Text("API Key")
                } footer: {
                    Text("API Key 加密存储，不会明文保存。Gemini 在 Google AI Studio 获取免费 Key。")
                }
                Section("默认设置") {
                    Toggle("设为默认摘要引擎", isOn: $isDefaultSummary)
                    Toggle("设为默认 AI 翻译引擎", isOn: $isDefaultTranslation)
                    Toggle("设为默认 AI 解释引擎", isOn: $isDefaultExplain)
                }
            }
            .navigationTitle(isNew ? "添加 Provider" : "编辑 Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty || baseURL.isEmpty || model.isEmpty)
                }
            }
        }
        .onAppear { loadProvider() }
    }

    private func loadProvider() {
        guard let p = provider else { return }
        name = p.name
        baseURL = p.baseURL
        model = p.model
        kind = p.kind.isEmpty ? (p.name.lowercased().contains("gemini") ? "gemini" : "openai") : p.kind
        apiKey = Keychain.load(key: "ai_key_\(p.id)") ?? ""
        isDefaultSummary = store.defaultSummaryProviderID == p.id
        isDefaultTranslation = store.defaultTranslationProviderID == p.id
        isDefaultExplain = store.defaultExplainProviderID == p.id
    }

    private func applyTemplate(_ template: AIProvider) {
        name = template.name
        baseURL = template.baseURL
        model = template.model
        kind = template.kind
    }

    private func save() {
        let id = provider?.id ?? UUID()
        let updated = AIProvider(
            id: id, name: name, baseURL: baseURL, model: model, kind: kind,
            isDefaultSummary: isDefaultSummary, isDefaultTranslation: isDefaultTranslation
        )
        if !apiKey.isEmpty { Keychain.save(key: "ai_key_\(id)", value: apiKey) }
        if isDefaultSummary { store.defaultSummaryProviderID = id }
        if isDefaultTranslation { store.defaultTranslationProviderID = id }
        if isDefaultExplain {
            store.defaultExplainProviderID = id
        } else if store.defaultExplainProviderID == id {
            store.defaultExplainProviderID = nil
        }
        if let idx = store.aiProviders.firstIndex(where: { $0.id == id }) {
            store.aiProviders[idx] = updated
        } else {
            store.aiProviders.append(updated)
        }
        store.persistSettings()
        dismiss()
    }
}
