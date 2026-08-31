import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                // General
                Section("通用") {
                    HStack {
                        Text("阅读字号")
                        Spacer()
                        Text("\(Int(store.fontSize))")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $store.fontSize, in: 12...24, step: 1)
                            .labelsHidden()
                    }

                    Picker("标题显示模式", selection: $store.titleDisplayMode) {
                        ForEach(TitleDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }

                // Translation Settings
                Section {
                    NavigationLink(destination: TranslationSettingsView()) {
                        Label("翻译设置", systemImage: "text.bubble")
                    }
                    NavigationLink(destination: AISettingsView()) {
                        Label("AI 设置", systemImage: "sparkles")
                    }
                } header: {
                    Text("功能设置")
                }

                // About
                Section("关于") {
                    HStack {
                        Text("默认翻译引擎")
                        Spacer()
                        Text(store.defaultTranslationEngine.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    if let pid = store.defaultSummaryProviderID,
                       let provider = store.aiProviders.first(where: { $0.id == pid }) {
                        HStack {
                            Text("默认摘要引擎")
                            Spacer()
                            Text(provider.name)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Feed")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
        }
    }
}

// MARK: - Translation Settings

struct TranslationSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var googleKey = Keychain.load(key: "google_translate_key") ?? ""
    @State private var microsoftKey = Keychain.load(key: "microsoft_translate_key") ?? ""
    @State private var deeplKey = Keychain.load(key: "deepl_translate_key") ?? ""   // 新增

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
                    Text("Google 翻译")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    if store.defaultTranslationEngine == .google {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.black)
                    }
                }
                TextField("API Key（可选，免费模式无需填写）", text: $googleKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: googleKey) { _, new in
                        if new.isEmpty { Keychain.delete(key: "google_translate_key") }
                        else { Keychain.save(key: "google_translate_key", value: new) }
                    }
            } header: {
                Text("Google 翻译")
            } footer: {
                Text("不填 API Key 时使用免费翻译接口，有请求频率限制")
            }

            Section {
                HStack {
                    Text("Microsoft 翻译")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    if store.defaultTranslationEngine == .microsoft {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.black)
                    }
                }
                TextField("Ocp-Apim-Subscription-Key", text: $microsoftKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: microsoftKey) { _, new in
                        if new.isEmpty { Keychain.delete(key: "microsoft_translate_key") }
                        else { Keychain.save(key: "microsoft_translate_key", value: new) }
                    }
            } header: {
                Text("Microsoft Translator")
            }

            // 新增：DeepL Section
            Section {
                HStack {
                    Text("DeepL 翻译")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    if store.defaultTranslationEngine == .deepl {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.black)
                    }
                }
                TextField("DeepL API Key", text: $deeplKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: deeplKey) { _, new in
                        if new.isEmpty { Keychain.delete(key: "deepl_translate_key") }
                        else { Keychain.save(key: "deepl_translate_key", value: new) }
                    }
            } header: {
                Text("DeepL")
            } footer: {
                Text("免费版 Key 以 \":fx\" 结尾，会自动使用免费端点；付费版 Key 使用正式端点")
            }
            
            Section {
                HStack {
                    Text("AI 翻译")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    if store.defaultTranslationEngine == .ai {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.black)
                    }
                }
                if let pid = store.defaultTranslationProviderID,
                   let provider = store.aiProviders.first(where: { $0.id == pid }) {
                    Text("使用 \(provider.name) · \(provider.model)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Text("在 AI 设置中指定翻译 Provider")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("AI 翻译")
            }
        }
        .navigationTitle("翻译设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AI Settings

struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddProvider = false
    @State private var editingProvider: AIProvider?

    var body: some View {
        Form {
            Section {
                ForEach(store.aiProviders) { provider in
                    AIProviderRow(provider: provider)
                        .contentShape(Rectangle())
                        .onTapGesture { editingProvider = provider }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.aiProviders.removeAll(where: { $0.id == provider.id })
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }

                Button {
                    showAddProvider = true
                } label: {
                    Label("添加 Provider", systemImage: "plus")
                }
            } header: {
                Text("AI Provider")
            }
        }
        .navigationTitle("AI 设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddProvider) {
            EditProviderView(provider: nil)
        }
        .sheet(item: $editingProvider) { provider in
            EditProviderView(provider: provider)
        }
    }
}

struct AIProviderRow: View {
    @Environment(AppStore.self) private var store
    let provider: AIProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(provider.name)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                HStack(spacing: 8) {
                    if provider.isDefaultSummary || store.defaultSummaryProviderID == provider.id {
                        ProviderTag(text: "摘要", color: .black)
                    }
                    if provider.isDefaultTranslation || store.defaultTranslationProviderID == provider.id {
                        ProviderTag(text: "翻译", color: .gray)
                    }
                }
            }
            Text(provider.model)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(provider.baseURL)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: .capsule)
    }
}

// MARK: - Edit Provider View

struct EditProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    let provider: AIProvider?

    @State private var name = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var isDefaultSummary = false
    @State private var isDefaultTranslation = false

    private var isNew: Bool { provider == nil }
    private var providerID: UUID { provider?.id ?? UUID() }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider 模板") {
                    Button("OpenAI") { applyTemplate(.openAITemplate) }
                        .foregroundStyle(.primary)
                    Button("Anthropic") { applyTemplate(.anthropicTemplate) }
                        .foregroundStyle(.primary)
                }

                Section("基本信息") {
                    TextField("名称", text: $name)
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("模型名", text: $model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section {
                    TextField("API Key", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("API Key")
                } footer: {
                    Text("API Key 加密存储在系统 Keychain 中，不会明文保存")
                }

                Section("默认设置") {
                    Toggle("设为默认摘要引擎", isOn: $isDefaultSummary)
                    Toggle("设为默认 AI 翻译引擎", isOn: $isDefaultTranslation)
                }
            }
            .navigationTitle(isNew ? "添加 Provider" : "编辑 Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
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
        apiKey = Keychain.load(key: "ai_key_\(p.id)") ?? ""
        isDefaultSummary = store.defaultSummaryProviderID == p.id
        isDefaultTranslation = store.defaultTranslationProviderID == p.id
    }

    private func applyTemplate(_ template: AIProvider) {
        name = template.name
        baseURL = template.baseURL
        model = template.model
    }

    private func save() {
        let id = provider?.id ?? UUID()
        let updated = AIProvider(
            id: id,
            name: name,
            baseURL: baseURL,
            model: model,
            isDefaultSummary: isDefaultSummary,
            isDefaultTranslation: isDefaultTranslation
        )

        if !apiKey.isEmpty {
            Keychain.save(key: "ai_key_\(id)", value: apiKey)
        }

        if isDefaultSummary { store.defaultSummaryProviderID = id }
        if isDefaultTranslation { store.defaultTranslationProviderID = id }

        if let idx = store.aiProviders.firstIndex(where: { $0.id == id }) {
            store.aiProviders[idx] = updated
        } else {
            store.aiProviders.append(updated)
        }
        dismiss()
    }
}
