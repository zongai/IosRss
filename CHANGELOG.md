# Changelog

本文件由**维护者手动更新**，GitHub Actions **不会**自动改写本文件或 README。

格式参考 [Keep a Changelog](https://keepachangelog.com/)。

---

## [Unreleased]

## [v1.3-42] — 2026-09-10
### Improved
- 测试 Key 可用性时在每个 Key 行旁直接显示「可用 / 不可用」标记（Google / Microsoft / DeepL / AI）


## [v1.3-41] — 2026-09-10
### Fixed
- 左右滑换篇后滚动回到文章开头
### Improved
- DeepL / Google / Microsoft：多 Key 失败时自动切换下一把（Google 全失败可回退免 Key）


## [v1.3-40] — 2026-09-10
### Changed
- Lingva 公共实例重新加入 lingva.ml


## [v1.3-39] — 2026-09-10
### Changed
- Lingva 公共实例改为：translate.plausibility.cloud、lingva.lunar.icu、translate.projectsegfau.lt、lingva.garudalinux.org


## [v1.3-38] — 2026-09-10
### Added
- 恢复 Lingva 翻译：支持 REST v1 GET 与 POST；公共实例轮询 + 可选自定义实例


## [v1.3-37] — 2026-09-10
### Fixed
- Google 翻译 429：免费接口退避重试、默认并发降至 3、错误不再刷 HTML
- 填写 Google Cloud Translation API Key 时走官方 v2 接口


## [v1.3-36] — 2026-09-10
### Improved
- 翻译 / AI 测试结果标明每个 Key 是否可用（掩码显示，多 Key 逐个检测）


## [v1.3-35] — 2026-09-10
### Removed
- 移除不可用的 Lingva、LibreTranslate 翻译引擎（原选择自动回退到 Google）


## [v1.3-34] — 2026-09-10
### Fixed
- Microsoft 翻译 401：请求增加 `Ocp-Apim-Subscription-Region`（默认 global），设置中可填 Azure 资源区域


## [v1.3-33] — 2026-09-10
### Fixed
- Lingva：扩充公共实例、可选自定义实例地址，失败提示更明确
- LibreTranslate：支持 API Key 与自定义实例（官方需 Key）
### Added
- 翻译设置：各引擎「测试此引擎」连通性 / Key 可用性检测


### Added
- DeepL 多 Key + 配额切换/回退 Google
### Improved
- Google POST + 高并发 Session；Microsoft 批量并行

### Fixed
- 提高默认并发并加大列表批次，避免串行拖慢

### Fixed
- 翻译并发回归：取消 AI 跨 Provider 分片，降低默认并发，恢复 failover 稳定性

### Changed
- 文章是否已翻译/需翻译以正文为准

### Added
- AI Provider 支持多 API Key（轮询/失败切换）

### Added
- 翻译并发可配置；AI 多 Provider 分片并行

### Added
- 免 Key 翻译：MyMemory；Google 可不填 Key

### Changed
- TTS 默认语速 1.2×

### Added
- TTS 语速设置（0.5×～2.0×）

### Changed
- 刷新进度条动画更流畅（缓动、收尾淡出）

### Added
- 刷新时顶部进度条（n/m · 源名）

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


## [v1.3-32] — 2026-09-10

### Added
- DeepL 多 Key

## [v1.3-31] — 2026-09-09

### Fixed
- 并发翻译速度

## [v1.3-30] — 2026-09-09

### Fixed
- 并发翻译质量回退修复

## [v1.3-29] — 2026-09-09

### Changed
- 翻译判定基于正文

## [v1.3-28] — 2026-09-09

### Added
- AI 多 Key

## [v1.3-27] — 2026-09-09

### Added
- 翻译并发与多 Provider 并行

## [v1.3-26] — 2026-09-09

### Added
- 免 Key 翻译引擎

## [v1.3-25] — 2026-09-09

### Changed
- TTS 默认 1.2×

## [v1.3-24] — 2026-09-09

### Added
- TTS 语速

## [v1.3-23] — 2026-09-09

### Changed
- 进度条动画

## [v1.3-22] — 2026-09-09

### Added
- 刷新进度显示

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
