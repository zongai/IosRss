# Changelog

本文件由维护者手动更新（不再由 GitHub Actions 自动追加）。

格式参考 [Keep a Changelog](https://keepachangelog.com/)。

---

## [Unreleased]

## [v1.2-5] — 2026-09-07

### Added
- AI 黑名单独立三级页（设置 → AI 设置 → AI 黑名单）
- 完整本地化：`Localizable.xcstrings`（源语言 zh-Hans，含 English）
- Edge TTS 朗读（无需 API Key，默认中文音色「云扬」）
- 文章黑名单：标题/摘要命中关键词时自动标为已读（与 AI 黑名单独立）
- 源级自动翻译开关（长按菜单）
- 一键删除全部订阅
- 源图标只获取一次（`faviconFetchDone`），磁盘缓存与离线内容隔离
- 无未读源默认隐藏（工具栏眼睛或「显示已读文章」可查看全部）
- 列表自动翻译未译且非中文的标题与摘要预览
- AI 摘要卡片显示 Provider 名称；框选菜单「AI解释」置顶
- AI 失败自动切换 Provider（`callAIWithFailover`）
- 源可重命名（立即刷新列表）
- 源级全文获取 / 评论获取开关
- Substack（含自定义域）公开评论抓取与评论页翻译
- 中/西文分排版（首行缩进等）
- 分组可折叠（状态持久化）

### Changed
- 设置布局调整：AI 黑名单、文章黑名单、字号等进入二级/三级页
- 默认中文 TTS 音色改为云扬（Yunyang）
- 移除 TXT 导出

### Fixed
- OPML 分组导入（`OPMLItem.groupName`）
- 重命名源后列表立即刷新
- 关闭全文抓取时隐藏阅读页全文按钮
- 重复 Swift 类型导致 EmitModule 失败
- AI summary 赋值使用 generateSummary 元组 `.text`

### Docs / CI
- README 全面刷新（TTS、黑名单、favicon 隔离、评论、自动翻译等）
- CI 构建时注入 `githubBuildNumber`；版本展示为 `v1.2-5-build{N}`
- 停止由 CI 自动回写 CHANGELOG / README（改由维护者手动更新）
