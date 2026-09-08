# IosRss

原生 SwiftUI 实现的 iOS / iPadOS RSS 阅读器。支持 RSS 与 Atom，内置全文抓取、多引擎翻译、AI 摘要 / 解释、Edge TTS 朗读、源分组、评论（Substack 等）与离线缓存。

**版本**：本地调试 `v1.3-5`；CI 构建 `v1.3-5-build{N}`（`N` = GitHub Actions `run_number`）。

> **文档维护**：`README.md` 与 `CHANGELOG.md` 由维护者手动更新，**不由** GitHub Actions 自动改写。

## 功能

### 订阅与分组
- **订阅管理**：添加 RSS / Atom；自动发现常见 feed 路径；源名称可重命名
- **源分组**：添加时可指定分组；移动到分组；分组管理；**分组可折叠**
- **无未读隐藏**：默认只显示有未读的源；在设置中开启「显示已读文章」可查看全部
- **源排序**：默认**未读优先自动排序**；可按名称、最近更新或手动拖拽（设置 → 订阅源排序）
- **OPML 导入 / 导出**：标准 OPML 2.0（含分组嵌套）；导出可选保存位置
- **Feed 图标**：仅获取一次；磁盘缓存与内容缓存隔离
- **源级开关**：全文获取、评论获取、自动翻译
- **删除全部订阅**

### 阅读
- **全文抓取**：摘要过短时自动或手动抓取；源关闭时隐藏工具栏按钮
- **排版**：可选系统/苹方等字体；中/西文分排版；首行缩进
- **导航栏 / Tab 显隐**：阅读页向下滑动自动隐藏顶部工具栏与底部 Tab；上滑或点击可恢复
- **左右滑**：左滑下一篇、右滑上一篇（同列表）
- **TTS**：Edge 在线语音（默认云扬）；无需 API Key
- **框选 AI 解释**；**评论**（Substack 等）；**收藏**
- **MP3 / 音频卡片**：正文中的音频链接可内嵌播放
- **已读**：打开即标已读；设置中控制是否显示已读

### 翻译与 AI
- 引擎：Google / Microsoft / DeepL / AI（OpenAI 兼容 + Gemini）
- **翻译目标语言 / AI 输出语言**可在设置中分别配置
- 列表自动翻译（按源开关）；长文分块翻译
- AI 摘要 / 解释；失败自动切换 Provider
- AI 黑名单（三级页）；文章黑名单（命中标已读）
- 每个 AI Provider 可单独测试连接；设置整包导出 / 导入（含 Key）

### 外观与字体
- **外观**：跟随系统（默认）/ 浅色 / 深色
- **阅读主题**：Azure、Sepia、Midnight、Forest、Graphite（随系统明暗自动匹配浅/深色板）
- **字体**：系统默认（默认）、苹方、宋体、黑体（不内置大字体包，减小安装体积）
- 设计 token：软阴影卡片、无硬边框、分区字号

### 其它
- 离线缓存（图标缓存独立）；分区字号；多语言（zh-Hans / en）
- CI：打 `v*` 标签产出 unsigned IPA 与 Release 说明（不回写文档）

## 结构

```
IosRss/
├── App.swift / ContentView.swift / Cloud.swift / Info.plist
├── Theme/AppTheme.swift      # 主题 token、字体、外观
├── Models/
│   ├── AppStore.swift
│   └── FeedModels.swift
├── Services/
│   ├── FeedParser.swift
│   ├── ArticleContentFetcher.swift
│   ├── CommentFetcher.swift
│   ├── EdgeTTS.swift
│   ├── OfflineCache.swift
│   └── TranslationServices.swift
└── Views/
    ├── FeedsListView / AddFeedView
    ├── ArticleListView / ArticleReaderView
    ├── ArticleContentViews / SelectableTextViews
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
| 阅读 | 外观（跟随系统/浅/深）、阅读主题、字体、标题模式、显示已读 |
| 朗读 | Edge TTS 音色 |
| 功能 | 字号、翻译、AI、文章黑名单 |
| 设置备份 | 导出 / 导入 JSON（含 Provider 与 Key） |
| 自动清理 / 离线 | 保留天数、缓存清理（保留订阅与图标） |
| 关于 | 版本号 |

## 版本号

| 场景 | 显示 |
|------|------|
| 本地 Xcode | `v1.3-5` |
| GitHub Actions | `v1.3-5-build{N}` |

## Changelog

见 [`CHANGELOG.md`](CHANGELOG.md)（**手动维护**）。

## License

MIT（若仓库未另附 LICENSE，以仓库声明为准）。
