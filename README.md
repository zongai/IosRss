# IosRss

原生 SwiftUI 实现的 iOS / iPadOS RSS 阅读器。支持 RSS 与 Atom，内置全文抓取、多引擎翻译与 AI 摘要。

**版本 1.2 (3)**

## 功能

- **订阅管理**：添加 RSS / Atom 源；自动发现常见 feed 路径；OPML / XML 导入导出
- **智能命名**：添加时优先解析 `channel` / `feed` 的 title；没有名称时仅用清理后的域名
- **全文阅读**：RSS 摘要过短时自动或手动从原文页抓取正文
- **翻译**：Google / Microsoft / DeepL，以及统一 AI 翻译（OpenAI 兼容 + Gemini）
- **列表翻译**：点「译」同时翻译标题和预览；长文翻译保留图片并同步译标题
- **AI 摘要**：可配置多个 Provider，Key 存本机
- **已读**：列表左滑标已读；全部已读；已读链接持久化，刷新后不会再次冒成未读；超过 7 天的非收藏已读自动清理
- **收藏**：列表/阅读页收藏，独立收藏 Tab，收藏文章不会被自动清理
- **深色模式**与应用内浏览器

## 结构

```
IosRss/
├── App.swift / ContentView.swift / Cloud.swift
├── Models/   AppStore.swift, FeedModels.swift
├── Services/ FeedParser, ArticleContentFetcher, TranslationServices
└── Views/    FeedsList, AddFeed, ArticleList, ArticleReader, FavoritesList, Settings
```

## 要求

- Xcode 16+ / iOS 18.0+
- 打开 `IosRss.xcodeproj` 即可编译运行

## License

私有项目，按需自行约定。
