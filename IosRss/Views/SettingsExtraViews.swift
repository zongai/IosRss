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
