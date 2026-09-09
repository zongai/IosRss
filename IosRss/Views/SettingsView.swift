struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var cacheSizeText: String = "计算中…"
    @State private var settingsExportURL: URL?
    @State private var showSettingsExport = false
    @State private var showSettingsImport = false
    @State private var settingsIOMessage: String?
    @State private var exportIncludeSecrets = false
    @State private var showImportConfirm = false
    @State private var pendingImportData: Data?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                // MARK: 阅读
                Section {
                    Picker("标题显示", selection: $store.titleDisplayMode) {
                        ForEach(TitleDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Toggle("显示已读文章", isOn: $store.showReadArticles)
                    Picker("订阅源排序", selection: $store.feedSortMode) {
                        ForEach(FeedSortMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: store.feedSortMode) { _, _ in store.persistSettings() }
                } header: {
                    Text("阅读")
                } footer: {
                    Text("控制列表标题语言、已读是否出现在订阅/文章列表，以及源的排序方式。")
                }

                // MARK: 外观
                Section {
                    Picker("外观", selection: $store.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: store.appearanceMode) { _, _ in store.persistSettings() }

                    NavigationLink {
                        Form {
                            ThemePalettePicker(selection: $store.colorTheme)
                                .onChange(of: store.colorTheme) { _, _ in store.persistSettings() }
                        }
                        .navigationTitle("阅读主题")
                        .navigationBarTitleDisplayMode(.inline)
                        .appScreenBackground()
                    } label: {
                        HStack {
                            Text("阅读主题")
                            Spacer()
                            Text(store.colorTheme.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        Form {
                            ForEach(AppFontFamily.allCases) { family in
                                Button {
                                    store.appFontFamily = family
                                    store.persistSettings()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(family.displayName)
                                                .font(AppTypography.font(size: 16, weight: .medium, family: family))
                                                .foregroundStyle(Color.primary)
                                            Text(family.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if store.appFontFamily == family {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(store.colorTheme.tokens.accent)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .navigationTitle("字体")
                        .navigationBarTitleDisplayMode(.inline)
                        .appScreenBackground()
                    } label: {
                        HStack {
                            Text("字体")
                            Spacer()
                            Text(store.appFontFamily.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink(destination: FontSettingsView()) {
                        HStack {
                            Text("字号")
                            Spacer()
                            Text("分组 / 列表 / 阅读")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("外观")
                } footer: {
                    Text("外观可跟随系统深色模式；主题与字体影响全局界面与阅读页。")
                }

                // MARK: 翻译与 AI
                Section {
                    NavigationLink(destination: TranslationSettingsView()) {
                        HStack {
                            Text("翻译")
                            Spacer()
                            Text(store.targetLanguage.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink(destination: AISettingsView()) {
                        HStack {
                            Text("AI")
                            Spacer()
                            Text("\(store.aiProviders.count) 个 Provider")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink(destination: ArticleBlacklistSettingsView()) {
                        HStack {
                            Text("文章黑名单")
                            Spacer()
                            if !store.articleBlacklistTerms.isEmpty {
                                Text("\(store.articleBlacklistTerms.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("翻译与 AI")
                } footer: {
                    Text("翻译目标语言、引擎与 Key 在「翻译」；模型、Prompt、AI 黑名单在「AI」。文章黑名单命中后自动标已读。")
                }

                // MARK: 朗读
                Section {
                    Picker("默认音色", selection: $store.ttsVoice) {
                        Text("自动（按语言）").tag("")
                        ForEach(EdgeTTS.popularVoices, id: \.id) { v in
                            Text(v.name).tag(v.id)
                        }
                    }
                } header: {
                    Text("朗读")
                } footer: {
                    Text("使用 Microsoft Edge 在线语音，无需 API Key。阅读页工具栏可开始/停止朗读。")
                }

                // MARK: 数据与清理
                Section {
                    Stepper(value: $store.readRetentionDays, in: 0...365) {
                        if store.readRetentionDays == 0 {
                            Text("已读保留：关闭自动清理")
                        } else {
                            Text("已读保留 \(store.readRetentionDays) 天")
                        }
                    }
                    .onChange(of: store.readRetentionDays) { _, _ in
                        store.persistSettings()
                        store.purgeOldReadArticles()
                    }
                    Stepper(value: $store.fullContentCacheDays, in: 0...365) {
                        if store.fullContentCacheDays == 0 {
                            Text("全文缓存：不按时间清理")
                        } else {
                            Text("全文缓存 \(store.fullContentCacheDays) 天")
                        }
                    }
                    .onChange(of: store.fullContentCacheDays) { _, _ in
                        store.persistSettings()
                        store.pruneFullContentCache()
                    }
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
                    Text("数据与清理")
                } footer: {
                    Text("订阅列表、已读标记与源图标始终保留。清除缓存只删全文、Feed 快照与正文图片。")
                }
                .onAppear { cacheSizeText = store.cacheSizeDescription() }

                // MARK: 备份
                Section {
                    Toggle("导出时包含 API Key", isOn: $exportIncludeSecrets)
                    Button {
                        do {
                            let data = try store.exportSettingsJSON(includeSecrets: exportIncludeSecrets)
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("IosRss-settings.json")
                            try data.write(to: url, options: .atomic)
                            settingsExportURL = url
                            showSettingsExport = true
                        } catch {
                            settingsIOMessage = "导出失败：\(error.localizedDescription)"
                        }
                    } label: {
                        Label("导出设置", systemImage: "square.and.arrow.up")
                    }
                    Button { showSettingsImport = true } label: {
                        Label("导入设置", systemImage: "square.and.arrow.down")
                    }
                    if let settingsIOMessage {
                        Text(settingsIOMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("备份")
                } footer: {
                    Text("默认不含 API Key。订阅源请用 OPML 单独导出。")
                }

                // MARK: 关于
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(AppVersion.display).foregroundStyle(.secondary)
                    }
                    if let pid = store.defaultSummaryProviderID,
                       let provider = store.aiProviders.first(where: { $0.id == pid }) {
                        HStack {
                            Text("默认摘要")
                            Spacer()
                            Text(provider.name).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("翻译引擎")
                        Spacer()
                        Text(store.defaultTranslationEngine.rawValue).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSettingsExport) {
                if let url = settingsExportURL {
                    SettingsExportPicker(url: url) { showSettingsExport = false }
                }
            }
            .sheet(isPresented: $showSettingsImport) {
                SettingsImportPicker { url in
                    showSettingsImport = false
                    guard let url else { return }
                    do {
                        pendingImportData = try Data(contentsOf: url)
                        showImportConfirm = true
                    } catch {
                        settingsIOMessage = "读取文件失败：\(error.localizedDescription)"
                    }
                }
            }
            .alert("导入设置？", isPresented: $showImportConfirm) {
                Button("取消", role: .cancel) { pendingImportData = nil }
                Button("导入", role: .destructive) {
                    guard let data = pendingImportData else { return }
                    do {
                        try store.importSettingsJSON(data)
                        settingsIOMessage = "设置已导入"
                    } catch {
                        settingsIOMessage = "导入失败：\(error.localizedDescription)"
                    }
                    pendingImportData = nil
                }
            } message: {
                Text("将覆盖当前字号、主题、翻译与 AI 配置等。若文件含 API Key 也会写入。此操作不可撤销。")
            }
            .onDisappear { store.persistSettings() }
            .onChange(of: store.showReadArticles) { _, _ in store.persistSettings() }
            .onChange(of: store.titleDisplayMode) { _, _ in store.persistSettings() }
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
