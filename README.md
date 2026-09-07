# IosRss

原生 SwiftUI 实现的 iOS / iPadOS RSS 阅读器。支持 RSS 与 Atom，内置全文抓取、多引擎翻译、AI 摘要 / 解释、Edge TTS 朗读、源分组、评论（Substack 等）与离线缓存。

**版本展示**：CI 构建为 `v1.2-5-build{N}`（N 为 GitHub Actions `run_number`）；本地调试为 `v1.2-5`。

## 功能

### 订阅与分组
- **订阅管理**：添加 RSS / Atom；自动发现常见 feed 路径；源名称可重命名（立即刷新列表）
- **源分组**：添加时可指定分组；列表左滑 / 长按移动到分组；分组管理（增删改）；**分组可折叠**（状态持久化，折叠时显示未读合计）
- **无未读隐藏**：默认源列表只显示有未读的源；工具栏眼睛或设置「显示已读文章」可查看全部
- **OPML 导入 / 导出**：标准 OPML 2.0（含分组嵌套与 `groupName`）；系统文件选择器；导出可选保存位置；文件名 `IosRss-subscriptions.opml`
- **智能命名**：添加时优先解析 `channel` / `feed` 的 title；否则仅用清理后的域名
- **Feed 图标**：RSS/Atom `<image>` / itunes / media / Atom icon；DuckDuckGo favicon 回退；**只获取一次**（`faviconFetchDone`）；磁盘缓存与内容缓存隔离（清理离线缓存不删图标）
- **源级开关**：全文获取、评论获取、**自动翻译**可按源开启 / 关闭（长按菜单）
- **删除全部订阅**：导入/导出菜单中可一键清空所有源

### 阅读
- **全文抓取**：摘要过短时自动或手动从原文页抓取（平衡标签匹配 + 启发式打分；WordPress 可走 REST 回退）；源关闭全文时隐藏工具栏按钮
- **阅读体验**：中/西文分排版（首行缩进、行距）；HTML 实体解码、`AsyncImage` 配图、正文链接可点、应用内 Safari（默认关闭 Reader）
- **TTS 朗读**：Microsoft Edge 在线神经语音（[edge-tts](https://github.com/rany2/edge-tts) 协议，无需 Key）；默认中文 **云扬**；阅读页工具栏朗读/停止；设置可选音色
- **框选 AI 解释**：选中文字菜单将「AI解释」置于最前；可单独指定解释 Provider 与自定义 Prompt（`{{text}}`）
- **评论**：源开启后阅读页显示评论入口；Substack（含自定义域）公开评论 API；评论页支持翻译；添加 / 导入时自动识别 Substack 类平台并开启评论
- **已读**：打开即标已读并实时隐藏（可配置显示已读）；左滑标已读 / 全部已读；已读链接持久化
- **收藏**：列表 / 阅读页收藏，独立收藏 Tab；清理时跳过收藏

### 翻译与 AI
- **翻译引擎**：Google / Microsoft / DeepL / AI（OpenAI 兼容 + Gemini）
- **列表自动翻译**：源开启时，进入列表自动翻译「未译且非中文」的标题与摘要预览
- **长文翻译**：约 1800 字分块并发，保留 `<img>`
- **AI 摘要**：多 Provider；去除序号；卡片展示 Provider 名称（无编号列表）
- **AI 黑名单**：发给 AI 的原文命中关键词时，切换到指定 fallback Provider（仅影响 AI 路由）
- **文章黑名单**：标题/摘要命中关键词时**自动标为已读**（与 AI 黑名单完全独立，设置 → 文章黑名单）
- **失败自动切换**：翻译 / 摘要 / 解释失败时按顺序尝试其他已配置 Key 的 Provider

### 其它
- **离线缓存**：订阅列表、Feed XML、文章全文 HTML、正文图片；源图标在独立目录；网络失败回退本地
- **分区字号**：分组名、订阅列表、文章列表、阅读器、AI 摘要（字号设置在二级页）
- **深色模式**：系统自适应
- **CI**：推送 `v*` 标签或手动 `workflow_dispatch` 产出 unsigned IPA，并打对应 Release

## 结构

```
IosRss/
├── App.swift / ContentView.swift / Cloud.swift
├── Models/
│   ├── AppStore.swift      # 状态、分组、黑名单、failover、导入导出
│   └── FeedModels.swift    # RSSFeed / Article / FeedGroup / AppVersion
├── Services/
│   ├── FeedParser.swift              # RSS/Atom、OPML（含分组）、命名与图标
│   ├── ArticleContentFetcher.swift   # 全文提取
│   ├── CommentFetcher.swift          # Substack 等评论 + 自动开启判断
│   ├── EdgeTTS.swift                 # Edge 在线 TTS（WebSocket）
│   ├── OfflineCache.swift            # feeds / 全文 / 图片 / favicons 隔离
│   └── TranslationServices.swift     # 翻译 / AI
└── Views/
    ├── FeedsListView / AddFeedView
    ├── ArticleListView / ArticleReaderView
    ├── ArticleContentViews / ArticleReaderExtras / SelectableTextViews
    ├── ArticleCommentsView
    ├── FavoritesListView
    └── SettingsView / SettingsExtraViews / SettingsAIViews
```

## 要求

- Xcode 16+ / iOS 18.0+
- Swift 5

打开 `IosRss.xcodeproj` 即可编译运行。Bundle ID 默认为 `com.example.IosRss`。

## 设置说明

| 分区 | 内容 |
|------|------|
| 阅读 | 标题显示模式、显示已读文章 |
| 朗读 | Edge TTS 音色（自动 / 云扬等） |
| 功能 | 字号、翻译、AI、**文章黑名单**（二级页） |
| 自动清理 | 已读保留天数、全文磁盘缓存天数（0 = 不清理） |
| 离线 | 查看占用；清除全文 / Feed / 正文图片（**保留订阅与源图标**） |
| 翻译设置 | 默认引擎与各引擎 Key |
| AI 设置 | Provider、默认解释引擎与 Prompt、**AI 黑名单**与 fallback |
| 关于 | 当前引擎摘要、版本号 |

API Key 仅保存在本机 Keychain。

## 版本号

| 场景 | 设置页显示 | IPA / Release |
|------|------------|---------------|
| 本地 Xcode | `v1.2-5` | — |
| GitHub Actions | `v1.2-5-build{N}` | `IosRss-1.2-5-build{N}.ipa` |

- `1.2` = `MARKETING_VERSION`
- `5` = `CURRENT_PROJECT_VERSION`
- `{N}` = Actions `run_number`（编译前写入 `AppVersion.githubBuildNumber`）

## 主要实现要点

| 能力 | 位置 |
|------|------|
| 版本展示 | `AppVersion` + CI sed 注入 |
| 源分组 / 折叠 / 无未读隐藏 | `FeedGroup`、`collapsedGroupIDs`、`visibleFeedSections` |
| OPML 分组导入 | `OPMLItem.groupName`、`OPMLParser` |
| 全文抓取 / 源开关 | `ArticleContentFetcher`、`fetchFullContentEnabled` |
| 评论 / Substack | `CommentFetcher`、`ArticleCommentsView` |
| 列表自动翻译 | `ArticleListView.autoTranslatePending`、`autoTranslateEnabled` |
| AI failover | `callAIWithFailover` |
| AI / 文章黑名单 | `aiBlacklistTerms` / `articleBlacklistTerms` |
| Edge TTS | `EdgeTTS.swift`、`EdgeTTSPlayer` |
| 图标缓存隔离 | `OfflineCache.favicons/`、`faviconFetchDone` |
| 中西文排版 | `ReaderTypography`、`SelectableParagraphView` |
| 已读实时更新 | `markAsRead` + 列表依赖文章状态 |

## License

MIT（若仓库未另附 LICENSE，以仓库声明为准）。
