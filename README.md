# IosRss

原生 SwiftUI 实现的 iOS / iPadOS RSS 阅读器。支持 RSS 与 Atom，内置全文抓取、多引擎翻译、AI 摘要 / 解释、Edge TTS 朗读、源分组、评论（Substack / HN / Engadget 等）与离线缓存。

**版本**：本地调试 `v1.3-38`；CI 构建 `v1.3-38-build{N}`（`N` = GitHub Actions `run_number`）。

> **文档维护**：`README.md` 与 `CHANGELOG.md` 由维护者手动更新，**不由** GitHub Actions 自动改写。

## 功能

### 订阅与分组
- **订阅管理**：添加 RSS / Atom；自动发现常见 feed 路径；源名称可重命名
- **源分组**：添加时可指定分组；移动到分组；分组管理；**分组可折叠**
- **无未读隐藏**：默认只显示有未读的源；设置中开启「显示已读文章」可查看全部
- **源排序**：默认**未读优先自动排序**；可按名称、最近更新或手动拖拽
- **OPML 导入 / 导出**：标准 OPML 2.0（含分组嵌套）；导出可选保存位置
- **Feed 图标**：仅获取一次；磁盘缓存与内容缓存隔离（清缓存不删图标）
- **源级开关**：全文获取、评论获取、自动翻译
- **删除全部订阅**
- 刷新进度条；失败时标明具体源名称；HTTP 源允许 ATS 并尝试升级 HTTPS

### 阅读
- **全文抓取**：摘要过短时自动或手动抓取；源关闭时隐藏全文按钮（Foreign Affairs / Foreign Policy / 少数派等有站点优化）
- **排版**：系统 / 苹方 / 宋体 / 黑体；中西文分排版；首行缩进；HTML 标签清理
- **工具栏显隐**：向下滑动隐藏顶部导航与底部 Tab；上滑恢复
- **左右滑换篇**：源内或收藏列表内上一篇 / 下一篇
- **TTS**：Edge 在线语音（默认云扬、语速 1.2× 可调）；无需 API Key
- **框选 AI 解释**；**评论**（Substack、Hacker News、Engadget/OpenWeb 等）
- **收藏**（已译显示译文）；**MP3 / 音频卡片**
- **已读**：打开即标已读；文章黑名单命中自动标已读

### 翻译与 AI
- **引擎**：Google（可不填 Key）/ MyMemory / Lingva（免 Key，REST v1 GET/POST）/ Microsoft（Key + 区域）/ DeepL（多 Key）/ AI
- LibreTranslate 已移除；Lingva 支持自定义实例
- **翻译目标语言**与 **AI 输出语言**可分别配置
- 列表 / 阅读页自动翻译（按源开关；以正文是否已译为准；隐藏的已读条目可跳过）
- 并发可调；Google/Microsoft 提高连接与批量吞吐；DeepL 多 Key 轮询，配额耗尽回退 Google
- 设置中可对各翻译引擎做**连通性 / Key 测试**
- AI 摘要 / 解释（可自定义 Prompt）；单 Provider 测试；失败自动切换 Provider；每 Provider **多 Key**
- AI 黑名单（三级页）；文章黑名单（与 AI 黑名单独立）
- API Key 存**系统钥匙串**；设置导出默认不含 Key；网络拒绝本机/内网地址

### 外观与字体
- **外观**：跟随系统（默认）/ 浅色 / 深色
- **阅读主题（6 套）**：Classic Light / Sepia Paper / Night Dark / Midnight Blue / Forest Sage / High Contrast
- **字体**：系统默认、苹方、宋体、黑体（不内置大字体包）
- 设计 token：软阴影卡片、无硬边框、分区字号

### 其它
- 离线缓存；分区字号；多语言（zh-Hans / en）
- 设置备份导入 / 导出
- CI：打 `v*` 标签产出 unsigned IPA 与 Release 说明（不回写文档）

## 结构

```
IosRss/
├── App.swift / ContentView.swift / Cloud.swift / Info.plist
├── Theme/AppTheme.swift / ReadingThemes.swift
├── Models/
│   ├── AppStore.swift
│   └── FeedModels.swift
├── Services/
│   ├── FeedParser.swift
│   ├── ArticleContentFetcher.swift
│   ├── CommentFetcher.swift
│   ├── EdgeTTS.swift
│   ├── OfflineCache.swift
│   ├── NetworkURLPolicy.swift
│   └── TranslationServices.swift
└── Views/
    ├── FeedsListView / AddFeedView
    ├── ArticleListView / ArticleReaderView
    ├── ArticleContentViews / SelectableTextViews / ArticleCommentsView
    ├── FavoritesListView
    └── SettingsView / SettingsExtraViews / SettingsAIViews
```

## 要求

- Xcode 16+ / iOS 18.0+
- Swift 5

打开 `IosRss.xcodeproj` 即可编译运行。

## 设置说明

| 分区 | 内容 |
|------|------|
| 阅读 | 标题模式、显示已读、订阅源排序 |
| 外观 | 跟随系统/浅/深、阅读主题、字体、字号 |
| 翻译与 AI | 翻译引擎与 Key/区域测试、AI Provider、黑名单 |
| 朗读 | Edge TTS 音色与语速 |
| 数据与清理 | 已读保留、全文缓存、清除离线缓存 |
| 备份 | 导出 / 导入 JSON（默认不含 Key） |
| 关于 | 版本号与默认引擎摘要 |

## 版本号

| 场景 | 显示 |
|------|------|
| 本地 Xcode | `v1.3-38` |
| GitHub Actions | `v1.3-38-build{N}` |

## Changelog

见 [`CHANGELOG.md`](./CHANGELOG.md)。

## License

按仓库内声明使用。
