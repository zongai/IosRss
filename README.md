# IosRss

原生 SwiftUI 实现的 iOS / iPadOS RSS 阅读器。支持 RSS 与 Atom，内置全文抓取、多引擎翻译、AI 摘要 / 解释、源分组与离线缓存。

**版本展示**：CI 构建为 `v1.2-4-build{N}`（N 为 GitHub Actions `run_number`）；本地调试为 `v1.2-4`。

## 功能

### 订阅与分组
- **订阅管理**：添加 RSS / Atom；自动发现常见 feed 路径
- **源分组**：添加时可指定分组；列表左滑 / 长按移动到分组；分组管理（增删改）；**分组可折叠**（状态持久化，折叠时显示未读合计）
- **OPML 导入 / 导出**：标准 OPML 2.0（含分组嵌套）；系统文件选择器；导出可选保存位置；文件名 `IosRss-subscriptions.opml`
- **智能命名**：添加时优先解析 `channel` / `feed` 的 title；否则仅用清理后的域名
- **Feed 图标**：RSS/Atom `<image>` / itunes / media / Atom icon；DuckDuckGo favicon 回退；失败后缓存标记，不再反复请求

### 阅读
- **全文抓取**：摘要过短时自动或手动从原文页抓取（**平衡标签匹配** + 启发式打分；WordPress 站点可走 REST API 回退）
- **阅读体验**：段落首行缩进、HTML 实体解码、`AsyncImage` 配图、正文链接可点、应用内 Safari（默认关闭 Reader）
- **框选 AI 解释**：选中文字菜单「AI解释」；可单独指定解释用 AI Provider
- **已读**：打开即标已读并实时隐藏（可配置显示已读）；左滑标已读 / 全部已读；已读链接持久化
- **收藏**：列表 / 阅读页收藏，独立收藏 Tab；清理时跳过收藏

### 翻译与 AI
- **翻译引擎**：Google / Microsoft / DeepL / AI（OpenAI 兼容 + Gemini）
- **列表翻译**：标题 + 预览分批翻译
- **长文翻译**：约 1800 字分块并发，保留 `<img>`
- **AI 摘要**：多 Provider；去除 `1. 2. 3.` 序号；展示所用 Provider 名称
- **AI 黑名单**：原文命中关键词时自动切换到指定 fallback Provider

### 其它
- **离线缓存**：订阅列表、Feed XML、文章全文 HTML、图片；网络失败回退本地
- **分区字号**：分组名称、订阅列表、文章列表、阅读器、AI 摘要可独立调节
- **深色模式**：系统自适应
- **CI**：GitHub Actions 产出 `IosRss-{版本}-{工程构建}-build{run}.ipa`，并打对应 Release tag

## 结构

```
IosRss/
├── App.swift / ContentView.swift / Cloud.swift
├── Models/
│   ├── AppStore.swift      # 状态、分组折叠、黑名单路由、全文与翻译
│   └── FeedModels.swift    # 模型 + AppVersion
├── Services/
│   ├── FeedParser.swift           # RSS/Atom、OPML、命名与图标
│   ├── ArticleContentFetcher.swift # 全文提取（平衡匹配 + WP REST）
│   ├── OfflineCache.swift
│   └── TranslationServices.swift  # 翻译 / AI 摘要 / AI 解释
└── Views/
    ├── FeedsListView / AddFeedView / GroupManager
    ├── ArticleListView / ArticleReaderView
    ├── SelectableTextViews          # 框选 + AI 解释面板
    ├── FavoritesListView / SettingsView
```

## 要求

- Xcode 16+ / iOS 18.0+
- Swift 5

打开 `IosRss.xcodeproj` 即可编译运行。Bundle ID 默认为 `com.example.IosRss`。

## 设置说明

1. **字号**：分组名称、订阅列表、文章列表、阅读器、AI 摘要分别调节
2. **自动清理**：已读保留天数、全文磁盘缓存天数（0 = 不清理）
3. **离线**：查看占用，可清除全文 / Feed / 图片缓存（不影响订阅）
4. **翻译设置**：默认引擎与各引擎 Key
5. **AI 设置**
   - Provider 列表（摘要 / 翻译 / **解释** 标签）
   - **默认解释引擎**（可跟随摘要或单独指定）
   - 黑名单关键词与命中后 fallback Provider
   - 翻译 / 摘要 Prompt

API Key 仅保存在本机 Keychain。

## 版本号

| 场景 | 设置页显示 | IPA / Release |
|------|------------|---------------|
| 本地 Xcode | `v1.2-4` | — |
| GitHub Actions | `v1.2-4-build{N}` | `IosRss-1.2-4-build{N}.ipa` |

- `1.2` = `MARKETING_VERSION`
- `4` = `CURRENT_PROJECT_VERSION`
- `{N}` = Actions `run_number`（编译前写入 `AppVersion.githubBuildNumber`）

## 主要实现要点

| 能力 | 位置 |
|------|------|
| 版本展示 | `AppVersion` in `FeedModels.swift` + CI sed 注入 |
| 源分组 / 折叠 | `FeedGroup`、`collapsedGroupIDs`、`FeedsListView` |
| 分组名字号 | `groupTitleFontSize` + Settings 步进器 |
| OPML 导入导出 | `OPMLParser` / `exportOPML` + `UIDocumentPicker` |
| 全文抓取 | `ArticleContentFetcher`（平衡 div + WP REST） |
| AI 解释 Provider | `defaultExplainProviderID`、`explainText` |
| AI 黑名单 | `resolveAIProvider(preferredID:forText:)` |
| 摘要去序号 | `cleanSummaryText` |
| 已读实时更新 | `markAsRead` + 列表依赖文章状态 |
| 图标缓存 | `OfflineCache` favicon 成功 / 失败标记 |

## CI

推送到 `main` **不会**自动构建。只在下面两种情况产出未签名 IPA：

1. **手动**：Actions → *Build Unsigned IPA* → *Run workflow*
2. **打版本标签**：`git tag v1.2-4-buildN && git push origin v1.2-4-buildN`

产物名：`IosRss-1.2-4-build{N}.ipa`。设置页在 CI 包内显示 `v1.2-4-build{N}`。

## License

私有项目，按需自行约定。
