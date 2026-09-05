# IosRss

原生 SwiftUI 实现的 iOS / iPadOS RSS 阅读器。支持 RSS 与 Atom，内置全文抓取、多引擎翻译、AI 摘要与离线缓存。

**版本 1.2 (4)**

## 功能

- **订阅管理**：添加 RSS / Atom；自动发现常见 feed 路径；OPML / RSS XML 导入导出
- **智能命名**：添加时优先解析 `channel` / `feed` 的 title；否则仅用清理后的域名（去协议、路径、`www.`）
- **Feed 图标**：优先 RSS/Atom `<image>` / itunes / media / Atom icon；否则 DuckDuckGo favicon 回退
- **全文阅读**：摘要过短（约 <400 字）时自动或手动从原文页抓取正文（启发式可读性提取）
- **离线缓存**：订阅列表、Feed XML、文章全文 HTML、图片落盘（Application Support）；网络失败时回退本地缓存；URLCache 32MB/200MB
- **翻译**：Google / Microsoft / DeepL，以及统一 AI 翻译（OpenAI 兼容 + Gemini）
- **列表翻译**：点「译」同时翻译标题和预览；分批刷新；DeepL / Microsoft 批量接口，Google / AI 有限并发
- **长文翻译**：按约 1800 字分块并发，保留 `<img>` 位置并同步译标题
- **AI 摘要**：多 Provider（OpenAI / Anthropic / Gemini），Key 存 Keychain
- **已读**：左滑标已读 / 全部已读；已读链接持久化，刷新后不会再次变未读
- **已读清理**：可配置保留天数（默认 7 天，0 = 不清理）；收藏文章跳过清理
- **全文缓存清理**：可配置磁盘全文 HTML 保留天数（默认 30 天）
- **收藏**：列表 / 阅读页收藏，独立收藏 Tab
- **分区字号**：订阅列表、文章列表标题/摘要、阅读器标题/正文、AI 摘要均可在设置中独立调节
- **深色模式**：`Color.primary` / `Color(.systemBackground)` 自适应
- **阅读体验**：HTML 实体解码、`AsyncImage` 配图、应用内 `SFSafariViewController`
- **CI**：GitHub Actions 产出 `IosRss-{版本}-{构建号}.ipa`

## 结构

```
IosRss/
├── App.swift                 # 入口，URLCache 配置
├── ContentView.swift         # Tab：订阅 / 收藏 / 设置
├── Cloud.swift               # BaaS 客户端
├── Models/
│   ├── AppStore.swift        # 状态、磁盘持久化、刷新、清理、全文与翻译编排
│   └── FeedModels.swift      # RSSFeed / Article / AIProvider 等
├── Services/
│   ├── FeedParser.swift      # RSS/Atom、OPML、FeedNaming、图标解析
│   ├── ArticleContentFetcher.swift  # 原文全文启发式提取 + OfflineCache
│   ├── OfflineCache.swift    # 离线磁盘缓存（feeds / XML / HTML / 图片）
│   └── TranslationServices.swift    # 翻译 / AI / HTML 工具
└── Views/
    ├── FeedsListView.swift / AddFeedView.swift
    ├── ArticleListView.swift / ArticleReaderView.swift
    ├── FavoritesListView.swift / SettingsView.swift
```

## 要求

- Xcode 16+ / iOS 18.0+
- Swift 5

打开 `IosRss.xcodeproj` 即可编译运行。Bundle ID 默认为 `com.example.IosRss`。

## 设置说明

1. **字号**：订阅列表标题、文章列表标题/摘要、阅读器标题/正文、AI 摘要分别调节。
2. **自动清理**：已读文章保留天数、全文磁盘缓存保留天数（0 = 不自动清理）。
3. **离线**：查看内容缓存占用，可一键清除文章全文 / Feed 快照 / 图片（不影响订阅列表）。
4. **翻译设置**：默认引擎；Google 可不填 Key；Microsoft / DeepL 填对应 Key。
5. **AI 设置**：添加 Provider（OpenAI / Anthropic / Gemini 模板）。Gemini 使用 `kind = gemini`。

API Key 仅保存在本机 Keychain，不会写入仓库。

## 主要实现要点

| 能力 | 位置 |
|------|------|
| Feed 标题与域名回退 | `FeedNaming` in `FeedParser.swift` |
| Feed 图标 | `extractFeedImage` / `resolveFaviconURL` |
| 全文抓取 | `ArticleContentFetcher` + `AppStore.fetchFullContent` |
| 离线缓存 | `OfflineCache` + `AppStore` 磁盘 `feeds.json` |
| AI 统一调用 | `callAI` → Gemini / OpenAI 兼容 |
| 长文分块翻译 | `AppStore.translateLongText`（约 1800 字） |
| 列表分批翻译 | `ArticleListView` + `AppStore.translateTexts` |
| 已读持久化 | `readArticleLinks` 规范化 URL |
| 已读 / 全文清理 | `purgeOldReadArticles` / `pruneFullContentCache` |
| 分区字号 | `AppStore` 各 `*FontSize` + Settings 步进器 |

## License

私有项目，按需自行约定。
