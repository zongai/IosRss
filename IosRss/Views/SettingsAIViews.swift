import SwiftUI

struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddProvider = false
    @State private var editingProvider: AIProvider?
    @State private var isTestingAI = false
    @State private var aiTestResult: String?

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
                Button {
                    Task {
                        isTestingAI = true
                        aiTestResult = nil
                        do {
                            aiTestResult = try await store.testAIProvider(store.defaultSummaryProviderID)
                        } catch {
                            aiTestResult = "失败：\(error.localizedDescription)"
                        }
                        isTestingAI = false
                    }
                } label: {
                    HStack {
                        Label("测试 AI 连接", systemImage: "network")
                        Spacer()
                        if isTestingAI { ProgressView() }
                    }
                }
                .disabled(isTestingAI || store.aiProviders.isEmpty)
                if let aiTestResult {
                    Text(aiTestResult)
                        .font(.footnote)
                        .foregroundStyle(aiTestResult.hasPrefix("失败") ? .red : .secondary)
                }
            } footer: {
                Text("使用默认摘要 Provider 发送极短请求，用于确认 Key 与接口可用。")
            }

            Section {
                NavigationLink {
                    AIBlacklistSettingsView()
                } label: {
                    HStack {
                        Text("AI 黑名单")
                        Spacer()
                        if !store.aiBlacklistTerms.isEmpty {
                            Text("\(store.aiBlacklistTerms.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("配置翻译 / 摘要 / 解释命中关键词时使用的备用 Provider。")
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
}

// MARK: - AI 黑名单（三级：设置 → AI 设置 → AI 黑名单）

struct AIBlacklistSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var newTerm = ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                if store.aiBlacklistTerms.isEmpty {
                    Text("暂无关键词").foregroundStyle(.secondary)
                } else {
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
                }
                HStack {
                    TextField("添加关键词，如敏感词", text: $newTerm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { addTerm() }
                    Button("添加") { addTerm() }
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("关键词")
            } footer: {
                Text("当 AI 翻译 / 摘要 / 解释 的原文包含任一关键词时，自动改用下方指定的 Provider。不区分大小写。")
            }

            Section {
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
                Text("备用 Provider")
            }
        }
        .navigationTitle("AI 黑名单")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let exists = store.aiBlacklistTerms.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == term.lowercased()
        }
        if !exists {
            store.aiBlacklistTerms.append(term)
            store.persistSettings()
        }
        newTerm = ""
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
