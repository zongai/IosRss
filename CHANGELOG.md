# Changelog

本文件由**维护者手动更新**，GitHub Actions **不会**自动改写本文件或 README。

格式参考 [Keep a Changelog](https://keepachangelog.com/)。

---

## [Unreleased]

### Changed
- 优化默认翻译/摘要/解释 AI Prompt，并自动迁移旧默认模板

### Added
- 收藏阅读页左滑下一篇收藏

### Fixed
- 少数派全文（API）与图片 src/data-src 解析

### Fixed
- Foreign Policy 全文抓取（content-gated--main-article）

### Fixed
- 开启自动翻译的源：进入列表/阅读页自动译未译内容

### Fixed
- Foreign Affairs 全文抓取（article__body-content / paywall-content）

### Added
- 评论：Hacker News 通过 RSS `<comments>` + Algolia API

### Added
- 评论：支持 OpenWeb/Spot.IM（Engadget 等）公开 SEO 接口

### Fixed
- 自动翻译跳过已隐藏文章；强化 HTML 去标签避免显示 <div>

### Fixed
- 阅读页下滑可靠隐藏导航栏与 TabBar（onScrollGeometryChange）

### Fixed
- 刷新失败时提示具体源名称

### Changed
- 阅读配色升级为 6 套 ReadingTheme（Classic / Sepia / Night / Midnight / Forest / High Contrast）

### Fixed
- 刷新 HTTP 源时 ATS 拦截导致失败；允许明文传输并在失败时尝试 HTTPS
- 订阅页下拉刷新与自定义 Progress 叠成两个转圈

### Changed
- 设置页层级重组：阅读 / 外观 / 翻译与 AI / 朗读 / 数据与清理 / 备份 / 关于

### Changed
- UI/UX：订阅页标题与源行信息、空状态一键显示全部、加载与错误提示

### Security
- API Key 改用系统钥匙串（迁移旧 UserDefaults Base64）
- 设置导出默认不含 Key；导入需确认
- 拒绝 localhost / 私网地址的拉取请求

### Changed
- 阅读页手势：弱化点击切换，换篇仅识别明确水平滑动
- Cloud stub 不再在启动时 configure

### Added
- 设置：翻译目标语言、AI 输出语言
- 收藏页：有译文直接显示；列表项使用未读强调配色

### Changed
- AI 测试改为针对单个 Provider（列表左滑 / 编辑页），不再使用全局默认摘要引擎

### Added
- 阅读页向下滑动自动隐藏顶部 toolbar 与底部 TabView（上滑/点击恢复）

### Added
- 订阅源**自动排序**：默认未读优先；可选名称 / 最近更新 / 手动拖拽（设置 → 订阅源排序）


## [v1.3-21] — 2026-09-09

### Changed
- AI Prompt 优化

## [v1.3-20] — 2026-09-09

### Added
- 收藏内左右滑换篇

## [v1.3-19] — 2026-09-09

### Fixed
- sspai 全文与图片

## [v1.3-18] — 2026-09-09

### Fixed
- FP 全文提取

## [v1.3-17] — 2026-09-09

### Fixed
- 源级自动翻译触发

## [v1.3-16] — 2026-09-09

### Fixed
- FA 全文提取

## [v1.3-15] — 2026-09-09

### Added
- HN 评论（comments 标签，非外链）

## [v1.3-14] — 2026-09-09

### Added
- Engadget 等 OpenWeb 评论抓取

## [v1.3-13] — 2026-09-09

### Fixed
- 隐藏文跳过自动翻译；正文/列表去 HTML 标签

## [v1.3-12] — 2026-09-09

### Fixed
- 阅读页工具条下滑隐藏

## [v1.3-11] — 2026-09-09

### Fixed
- 刷新错误标明源名

## [v1.3-10] — 2026-09-09

### Changed
- ReadingTheme 六套阅读配色 + Environment 注入

## [v1.3-9] — 2026-09-09

### Fixed
- Feed 刷新 ATS / 双 Progress

## [v1.3-8] — 2026-09-09

### Changed
- 设置选项层级与信息架构优化

## [v1.3-7] — 2026-09-08

### Changed
- 订阅/文章空状态引导、源列表元信息、加载与错误反馈

## [v1.3-6] — 2026-09-08

### Security
- 真 Keychain、导出密钥可选、内网 URL 拦截、导入确认

## [v1.3-5] — 2026-09-08

### Added
- 翻译目标语言 / AI 输出语言；收藏页译文与未读配色

## [v1.3-4] — 2026-09-08

### Changed
- AI 连接测试下沉到各 Provider

## [v1.3-3] — 2026-09-08

### Added
- 阅读页下滑隐藏导航栏与 TabBar

## [v1.3-2] — 2026-09-08

### Added
- 订阅源自动排序（未读优先等）

## [v1.3-1] — 2026-09-08

本版为 UI/体验里程碑：主题体系、系统外观、阅读手势与设置能力集中落地。

### Removed
- 移除内置思源黑体（Source Han Sans SC）字体文件，显著减小安装包体积；默认改用系统字体

### Added
- 设置 → **字体**：系统默认、苹方、宋体、黑体
- **外观**：跟随系统（默认）/ 浅色 / 深色；阅读色板随系统明暗自动匹配
- 阅读主题色板：Azure / Sepia / Midnight / Forest / Graphite（设计 token + 软卡片）
- 阅读页点击显隐导航栏；左滑下一篇 / 右滑上一篇
- 源列表拖拽排序（`sortOrder`）
- AI 连接测试；设置整包导出 / 导入（含 Key）
- 正文 MP3 / 音频链接播放卡片
- 新 App 图标（书 + RSS）

### Changed
- 默认使用系统字体（已移除内置思源黑体以减小包体）
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
