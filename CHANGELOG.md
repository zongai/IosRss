# Changelog

本文件由维护者手动更新（不再由 GitHub Actions 自动追加）。

格式参考 [Keep a Changelog](https://keepachangelog.com/)。

---

## [Unreleased]

### Added
- 阅读页点击内容自动显隐导航工具栏
- 开启自动翻译的源：进入阅读页自动翻译正文（非目标语言时）
- 文章已是目标中文时隐藏翻译按钮
- 订阅源拖拽排序（列表左上角「排序」）
- 阅读页左滑下一篇 / 右滑上一篇
- AI 设置 → 测试 AI 连接（验证 Provider 与 Key）
- 设置导出 / 导入（JSON，含 Provider Key、黑名单、字号等）
- 正文 MP3 / 音频链接播放卡片（`<audio>` 与裸链）

### Changed
- 订阅页、文章列表页移除眼睛「显示已读」按钮（改在设置 → 阅读）

### Fixed
- 正文误显示的百分号编码片段（如 `%e8%ae%ae`）自动解码

## [v1.2-5] — 2026-09-07

### Added
- AI 黑名单独立三级页；完整本地化；Edge TTS；文章黑名单
- 源级自动翻译 / 全文 / 评论开关；源排序与分组折叠
- 列表自动翻译；AI failover；Substack 评论

### Docs / CI
- README / CHANGELOG 改为维护者手动更新
