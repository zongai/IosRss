# Changelog

本文件由 CI 在每次构建成功后自动追加条目（基于自上一构建标签以来的提交说明）。

格式参考 [Keep a Changelog](https://keepachangelog.com/)。

---

## [Unreleased]

## [v1.2-5-build98] — 2026-09-07

- ci: fix CHANGELOG step YAML (indent multiline python)


## [v1.2-5] — 种子条目（历史摘要）
- docs: refresh README for TTS, article blacklist, favicon isolation (`3316fb1`)
- feat: article blacklist, isolated favicon cache, settings layout, list perf (`9d5c901`)
- chore: default Chinese TTS voice to Yunyang (云扬) (`543bd4c`)
- feat: Edge TTS read-aloud (no API key) (`e23ef00`)
- chore: bump CURRENT_PROJECT_VERSION to 5 (v1.2-5) (`8426292`)
- fix: RSSFeed init argument order for faviconFetchDone (`88e59eb`)
- feat: remove TXT export; delete all feeds; favicon once; per-feed auto-translate (`d38455a`)
- docs: update README for comments, auto-translate, failover, UI polish (`c7f1349`)
- fix: remove numbered list from AI summary card UI (`d7e8294`)
- feat: show AI summary provider; put AI解释 first in selection menu (`788133b`)
- fix: use generateSummary tuple .text for aiSummary assignment (`6256e66`)
- fix: OPMLItem.groupName for grouped OPML import (`04b7867`)
- fix: remove duplicate Swift types causing EmitModule failure (`a67b26a`)
- feat: hide feeds with no unread in source list (`8fd04b7`)
- fix: hide full-content toolbar icon when feed disables fetch (`643932a`)
- fix: rename feed refreshes list immediately (`8cbeb50`)
- feat: full sync local features — AI failover, comments, typography, groups (`bbacfca`)
- chore: register FeedsListSupporting in pbxproj (`142dc4c`)
- feat: FeedsListSupporting views (GroupHeader, FeedRow, document pickers) (`8bf862e`)
- fix: restore FeedsListView with rename and comments toggles (`6c74871`)
- feat: FeedsListView rename + per-feed full content/comments toggles (`659ee59`)
- feat: ArticleContentViews for reader body rendering (`7ee983f`)
- feat: ArticleContentViews + pbxproj (reader content/AI explain) (`3a63553`)
- feat: ArticleReaderExtras (Safari/AISummary/Content) + pbxproj (`c842ce1`)
- fix: restore ArticleReaderView with comments button (`6575ae4`)

