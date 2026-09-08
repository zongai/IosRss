import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var cacheSizeText: String = "计算中…"
    @State private var settingsExportURL: URL?
    @State private var showSettingsExport = false
    @State private var showSettingsImport = false
    @State private var settingsMessage: String?
    @State private var settingsError: String?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    Picker("标题显示模式", selection: $store.titleDisplayMode) {
                        ForEach(TitleDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Toggle("显示已读文章", isOn: $store.showReadArticles)
                    NavigationLink {
                        ColorThemePickerView()
                    } label: {
                        HStack {
                            Label("阅读配色", systemImage: "paintpalette")
                            Spacer()
                            Text(store.colorTheme.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("阅读")
                }
                .onChange(of: store.titleDisplayMode) { _, _ in store.persistSettings() }
                .onChange(of: store.showReadArticles) { _, _ in store.persistSettings() }

                Section {
                    Picker("朗读音色", selection: $store.ttsVoice) {
                        Text("自动（按语言）").tag("")
                        ForEach(EdgeTTS.popularVoices, id: \.id) { v in
                            Text(v.name).tag(v.id)
                        }
                    }
                } header: {
                    Text("朗读")
                } footer: {
                    Text("使用 Microsoft Edge 在线语音，无需密钥。")
                }
                .onChange(of: store.ttsVoice) { _, _ in store.persistSettings() }

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
                    NavigationLink(destination: ArticleBlacklistSettingsView()) {
                        HStack {
                            Label("文章黑名单", systemImage: "eye.slash")
                            Spacer()
                            if !store.articleBlacklistTerms.isEmpty {
                                Text("\(store.articleBlacklistTerms.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("功能")
                } footer: {
                    Text("AI 黑名单在「AI 设置 → AI 黑名单」；文章黑名单自动将命中条目标为已读。")
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
                    Text("订阅列表、已读标记与源图标缓存始终保留。清除后仅删除文章全文、Feed 快照与正文图片缓存，不影响订阅与源图标。")
                }
                .onAppear { cacheSizeText = store.cacheSizeDescription() }

                Section {
                    Button {
                        exportSettings()
                    } label: {
                        Label("导出全部设置", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showSettingsImport = true
                    } label: {
                        Label("导入设置", systemImage: "square.and.arrow.down")
                    }
                    if let settingsMessage {
                        Text(settingsMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    if let settingsError {
                        Text(settingsError).font(.system(size: 13)).foregroundStyle(.red)
                    }
                } header: {
                    Text("设置备份")
                } footer: {
                    Text("包含字号、翻译/AI Provider 与 Key、黑名单、分组、朗读音色等。不含订阅文章正文。导入会覆盖当前设置。")
                }

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
            .sheet(isPresented: $showSettingsExport) {
                if let url = settingsExportURL {
                    NavigationStack {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("IosRss-settings.json")
                                .font(.headline)
                            ShareLink(item: url) {
                                Label("分享 / 保存", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal)
                            Spacer()
                        }
                        .padding(.top, 40)
                        .navigationTitle("导出设置")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("完成") { showSettingsExport = false }
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
            }
            .fileImporter(
                isPresented: $showSettingsImport,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importSettings(from: url)
                case .failure(let err):
                    settingsError = err.localizedDescription
                }
            }
        }
    }

    private func exportSettings() {
        settingsError = nil
        settingsMessage = nil
        do {
            let data = try store.exportSettingsJSON()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("IosRss-settings.json")
            try data.write(to: url, options: .atomic)
            settingsExportURL = url
            showSettingsExport = true
            settingsMessage = "已生成导出文件"
        } catch {
            settingsError = error.localizedDescription
        }
    }

    private func importSettings(from url: URL) {
        settingsError = nil
        settingsMessage = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try store.importSettingsJSON(data)
            settingsMessage = "设置已导入"
        } catch {
            settingsError = error.localizedDescription
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

// MARK: - 阅读配色选择

struct ColorThemePickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            Section {
                ForEach(AppColorTheme.allCases) { option in
                    Button {
                        store.colorTheme = option
                        store.persistSettings()
                    } label: {
                        HStack(spacing: 14) {
                            ThemeSwatch(theme: option)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.displayName)
                                    .font(AppTypography.label())
                                    .foregroundStyle(theme.text)
                                Text(option.subtitle)
                                    .font(AppTypography.caption())
                                    .foregroundStyle(theme.muted)
                            }
                            Spacer()
                            if store.colorTheme == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(option.tokens.accent)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.card)
                }
            } footer: {
                Text("配色影响背景、卡片、强调色与文字对比。Inter Tight 字体在所有主题下保持一致。")
                    .font(AppTypography.caption())
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("阅读配色")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThemeSwatch: View {
    let theme: AppColorTheme

    var body: some View {
        let t = theme.tokens
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(t.background)
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(t.card)
                    .frame(height: 14)
                    .padding(.horizontal, 6)
                HStack(spacing: 3) {
                    Circle().fill(t.accent).frame(width: 8, height: 8)
                    Capsule().fill(t.track).frame(height: 4)
                }
                .padding(.horizontal, 6)
            }
        }
        .frame(width: 44, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(t.ring, lineWidth: 1)
        )
        .shadow(color: t.shadow, radius: 4, y: 2)
    }
}
