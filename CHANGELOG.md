# Changelog

本文件由**维护者手动更新**，GitHub Actions **不会**自动改写。

**约定：每个正式条目对应一次成功构建**（上一成功构建标签 → 本成功构建标签之间的全部变更），不按中间未构建版本号逐条拆分。

格式参考 [Keep a Changelog](https://keepachangelog.com/)。

---

## [Unreleased]

（自上次成功构建以来的改动，将在下次成功构建时归入正式条目。）

### Fixed
- 刷新时保留分组折叠/展开状态（稳定 section id，禁用刷新写入动画）
- 添加订阅未选择分组时不再误入分组（Picker 默认「未分组」）

### Changed
- 保留刷新进度条；列表结构更新不再带动折叠动画

---

## [v1.3-48] — 2026-09-11

成功构建：`v1.3-48-build-20260911133046`  
相对：`v1.3-47-build-20260910203058`

### Added
- AI 对话页（Tab）：仅限已配置 API Key 的 Provider；多轮上下文；本地历史与重命名/删除/清空
- Sixth Tone 全文：从 `__NEXT_DATA__` 提取正文与 `textImageList` 配图

### Fixed
- 源开启自动翻译时：打开文章即使标题已译，正文非目标语言仍自动翻译
- 超过 30 天的文章时间显示为具体年月日

---

## [v1.3-47] — 2026-09-10

成功构建：`v1.3-47-build-20260910203058`  
相对：`v1.3-43-build-20260910111644`

### Added
- 多 Key 自动轮询与冷却：无效 Key（约 1 小时）、限流 Key（约 5 分钟）自动跳过（AI / DeepL / Microsoft）
- 兼容 AI 思考模型：忽略 `reasoning` / Gemini `thought` parts；剥离 `<think>` 等标签，界面不展示思考过程

### Changed
- Google 翻译改回纯免 Key（`client=gtx` GET/POST），移除多 Key / 官方 API；默认串行以降低限流
- 刷新加速：最多 8 源并行；专用 Session；超时缩短；批量落盘

---

## [v1.3-43] — 2026-09-10

成功构建：`v1.3-43-build-20260910111644`  
相对：`v1.3-41-build-20260910105022`

### Changed
- Google 无 Key：优先 GET `translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=…&dt=t&q=…`（长文本回退 POST）

### Improved
- 测试 Key 时在每个 Key 行旁直接显示「可用 / 不可用」

---

## [v1.3-41] — 2026-09-10

成功构建：`v1.3-41-build-20260910105022`  
相对：`v1.3-38-build-20260910103959`

### Fixed
- 左右滑换篇后滚动回到文章开头

### Improved
- DeepL / Google / Microsoft：多 Key 失败时自动切换；Google 全失败可回退免 Key
- Lingva 公共实例更新（含 `lingva.ml`、plausibility、lunar.icu、projectsegfau、garudalinux）

---

## [v1.3-38] — 2026-09-10

成功构建：`v1.3-38-build-20260910103959`  
相对：`v1.3-35-build-20260910101755`

### Added
- 恢复 Lingva：REST v1 GET/POST，公共实例轮询 + 可选自定义实例

### Fixed
- Google 429：退避重试、降低默认并发、错误不再刷 HTML
- 翻译 / AI 测试标明每个 Key 是否可用（掩码）

---

## [v1.3-35] — 2026-09-10

成功构建：`v1.3-35-build-20260910101755`  
相对：`v1.3-32-build-20260910093639`

### Removed
- 移除当时不可用的 Lingva、LibreTranslate（原选择回退 Google）

### Fixed
- Microsoft 翻译 401：增加 `Ocp-Apim-Subscription-Region`，设置可填 Azure 区域

### Added
- 各翻译引擎「测试此引擎」连通性 / Key 检测

---

## [v1.3-32] — 2026-09-10

成功构建：`v1.3-32-build-20260910093639`  
相对：`v1.3-31-build-20260909140457`

### Added
- DeepL 多 Key + 配额耗尽切换 / 回退 Google

### Improved
- Google POST + 高连接数 Session；Microsoft 批量并行

---

## [v1.3-31] — 2026-09-09

成功构建：`v1.3-31-build-20260909140457`  
相对：`v1.3-28-build-20260909132331`

### Fixed
- 并发翻译：取消 AI 跨 Provider 分片，恢复单链路 failover
- 提高默认并发与列表批次，避免小批串行拖慢速度

### Changed
- 文章是否已翻译 / 是否需翻译以**正文**为准

---

## [v1.3-28] — 2026-09-09

成功构建：`v1.3-28-build-20260909132331`  
相对：`v1.3-21-build-20260909121250`

### Added
- AI Provider 多 API Key（轮询 / 失败切换）
- 翻译并发可配置
- 免 Key 翻译：MyMemory；Google 可不填 Key
- TTS 语速设置（0.5×～2.0×），默认 1.2×
- 刷新进度条（n/m · 源名）与动画优化

### Changed
- 优化默认翻译 / 摘要 / 解释 AI Prompt，并自动迁移旧默认模板

---

## [v1.3-21] — 2026-09-09

成功构建：`v1.3-21-build-20260909121250`  
相对：更早成功构建

### Added
- 收藏阅读页左滑下一篇收藏
- 评论：Hacker News（`<comments>` + Algolia）；Engadget 等 OpenWeb/Spot.IM
- 6 套阅读主题（Classic / Sepia / Night / Midnight / Forest / High Contrast）
- 设置：翻译目标语言、AI 输出语言
- 订阅源自动排序；阅读页下滑隐藏导航栏与 TabBar

### Fixed
- 少数派 / Foreign Policy / Foreign Affairs 全文与图片
- 开启自动翻译的源：进入列表/阅读页自动译未译内容
- 自动翻译跳过已隐藏文章；强化 HTML 去标签
- 刷新失败提示具体源名；HTTP 源 ATS；双重 Progress 转圈

### Security
- API Key 使用系统钥匙串；导出默认不含 Key；拦截私网 URL

### Changed
- 设置页层级重组；UI/UX 空状态与错误提示
- AI 测试改为针对单个 Provider

---

## [v1.3-1] — 2026-09-08

### Changed
- 版本线升至 1.3；主题、手势阅读、设置备份、Edge TTS 等里程碑能力汇总见 README

---

## [v1.2-5] — 2026-09-07

### Added
- Edge TTS、文章黑名单、源级自动翻译、图标一次获取标记等（详见该阶段提交）

---

更早版本摘要见仓库历史提交与 README「实现对照」表。
