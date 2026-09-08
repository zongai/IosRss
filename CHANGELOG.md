# Changelog

本文件由**维护者手动更新**，GitHub Actions **不会**自动改写本文件或 README。

格式参考 [Keep a Changelog](https://keepachangelog.com/)。

---

## [Unreleased]

### Added
- **思源黑体（Source Han Sans SC）** 内置四字重：Regular / Normal / Medium / Bold；默认界面与阅读字体
- 设置 → **字体**：思源黑体、系统默认、苹方、宋体、黑体
- **外观**：跟随系统（默认）/ 浅色 / 深色；阅读色板随系统明暗自动匹配
- 阅读主题色板：Azure / Sepia / Midnight / Forest / Graphite（设计 token + 软卡片）
- 阅读页点击显隐导航栏；左滑下一篇 / 右滑上一篇
- 源列表拖拽排序（`sortOrder`）
- AI 连接测试；设置整包导出 / 导入（含 Key）
- 正文 MP3 / 音频链接播放卡片
- 新 App 图标（书 + RSS）

### Changed
- 默认字体由 Inter Tight 改为思源黑体；无内置字体时回退系统字体
- 订阅页 / 文章列表移除眼睛按钮；「显示已读」仅在设置中
- 已是目标中文的文章隐藏翻译按钮
- README / CHANGELOG 改为维护者手动维护（CI 仅生成 Release 说明）

### Fixed
- 列表自动翻译改为覆盖源内全部文章（不限当前可见未读）
- 正文残留百分号编码（如 `%e8%ae%ae`）解码
- `AppColorTheme` / `AppTheme.swift` 工程引用与编译修复

## [v1.2-5] — 2026-09-07

### Added
- Edge TTS 朗读（默认云扬）
- 文章黑名单（命中标已读）；AI 黑名单三级页
- 源级自动翻译 / 全文 / 评论；Substack 评论
- 列表自动翻译；AI failover；OPML 分组
- 本地化（zh-Hans / en）

### Changed
- CI 版本号注入 `v1.2-5-build{N}`

## [v1.2-4] — 2026-09

### Added
- 实时未读、图标缓存、段首缩进、应用内打开链接
- 全文抓取、多引擎翻译、AI 摘要
