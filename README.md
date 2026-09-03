# IosRss

原生 SwiftUI 实现的 iOS / iPadOS RSS 阅读器。支持 RSS 与 Atom，内置全文抓取、多引擎翻译与 AI 摘要。

## 功能

- **订阅管理**：添加 RSS / Atom 源；自动发现常见 feed 路径与 OPML
- **智能命名**：添加时优先解析 `channel` / `feed` 的 title；没有名称时仅用清理后的域名（去掉协议、路径、`www.`）
- **全文阅读**：RSS 摘要过短（约 <400 字）时自动或手动从原文页抓取正文（启发式可读性提取）
- **翻译**：Google / Microsoft / DeepL，以及统一 AI 翻译（OpenAI 兼容接口 + Gemini）
- **长文翻译**：`translateLongText` 按约 1800 字分块并发翻译后拼接
- **AI 摘要**：可配置多个 Provider（OpenAI、Anthropic、Gemini 等），Key 存 Keychain
- **已读清理**：启动与刷新时自动清理超过 7 天的已读文章
- **深色模式**：使用 `Color.primary` / `Color(.systemBackground)` 自适应对比
- **阅读体验**：HTML 实体解码（含 `&#8216;` 等）、`AsyncImage` 配图、应用内 `SFSafariViewController`

## 结构

```
IosRss/
├── App.swift                 # 入口，Cloud 配置
├── ContentView.swift         # Tab：订阅 / 设置
├── Cloud.swift               # BaaS 客户端（LeanCloud 风格）
├── Models/
│   ├── AppStore.swift        # 状态、持久化、刷新、清理、全文与翻译编排
│   └── FeedModels.swift      # RSSFeed / Article / AIProvider 等
├── Services/
│   ├── FeedParser.swift      # RSS/Atom 解析、发现、FeedNaming
│   ├── ArticleContentFetcher.swift  # 原文全文启发式提取
│   └── TranslationServices.swift    # 翻译 / AI / HTML 工具
└── Views/
    ├── FeedsListView.swift
    ├── AddFeedView.swift
    ├── ArticleListView.swift
    ├── ArticleReaderView.swift
    └── SettingsView.swift
```

## 要求

- Xcode 16+ / iOS 18.0+
- Swift 5

打开 `IosRss.xcodeproj` 即可编译运行。Bundle ID 默认为 `com.example.IosRss`，可按需修改。

## 设置说明

1. **翻译设置**：选择默认引擎；Google 可不填 Key（有频率限制）；Microsoft / DeepL 填对应 Key。
2. **AI 设置**：添加 Provider（可用 OpenAI / Anthropic / Gemini 模板）。Gemini 使用 `kind = gemini` 走专用接口，其余走 OpenAI 兼容 Chat Completions。
3. API Key 仅保存在本机 Keychain，不会写入仓库。

## 主要实现要点

| 能力 | 位置 |
|------|------|
| Feed 标题解析与域名回退 | `FeedNaming` in `FeedParser.swift` |
| 全文抓取 | `ArticleContentFetcher` + `AppStore.fetchFullContent` |
| AI 统一调用 | `callAI` → `callGemini` / `callOpenAICompatible` |
| 长文分块翻译 | `AppStore.translateLongText`（约 1800 字符） |
| 已读过期清理 | `AppStore.purgeOldReadArticles`（7 天） |

## License

私有项目，按需自行约定。
