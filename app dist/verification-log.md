# 本机核验记录

日期：2026-10-30 / Windows / Flutter 3.47.7 / Node 24.19.0

## 已完成

- iOS AppIcon 资产完整，包含 `Icon-App-1024x1024@1x.png`；`ITSAppUsesNonExemptEncryption=false` 已在 Info.plist。
- `flutter analyze`：**0 error / 0 warning**，163 条 info 级 lint（风格类，不阻塞编译）。
- 定向测试通过：`compliance_smoke_test`、`card_catalog_test`、`fortune_transfer_test`、`links_test`、`ai_proxy_test`。
- 单独复跑通过：`ipad_layout_smoke_test`（26 项）、`gliquid_physics_regression_test`（2 项）。
- 全量 `flutter test` 在并发和串行下仍出现 `did not complete`（集中在 iPad/Knockwater 的长套件），单独复跑对应文件可通过；属于本机测试运行稳定性问题，未发现对应产品断言失败。

## 后端沙箱回归

在临时目录、临时端口、临时 data 中运行 `trash/trash.js`，23 项检查全部通过：

- 注册/登录/`/api/auth/me`
- 发帖、举报、重复举报幂等、不能举报自己的内容
- 卡面同步、今日卡、抽卡扣次数、空卡面目录 400
- 注销：未登录 401、错误密码 403、正确密码 200；注销后帖子删除、其他账号不受影响
- 举报记录在运营端可持久化（`reports.json`）

**发现 1 个非阻塞边界**：`/api/cards/sync` 只要请求带 `migrate:true`，服务端会取较大值合并 `credits`。正常客户端只在本地首次登录时发一次，但旧端/手工请求理论上可用它把抽卡次数抬高。当前不影响 App Store 审核，建议后续决定是否加服务端一次性迁移标记。

## 公网只读核验

以下 URL 均返回 200：

- `https://chimu-claw.xyz/`
- `https://chimu-claw.xyz/support.html`
- `https://chimu-claw.xyz/privacy.html`
- `https://chimu-claw.xyz/terms.html`
- `https://chimu-claw.xyz/account-deletion.html`
- `https://chimu-claw.xyz/trashapi/api/posts`

哈希对比：

- `support.html`：公网与本地一致（已生效）。
- `privacy.html`：公网仍是旧版（Last-Modified 2026-10-23），本地新版哈希 `01fec897…`，需要上传。
- `terms.html`、`account-deletion.html`：公网与本地一致。

`/trashapi/api/posts` 返回 200 只能证明旧接口在线，不能证明最新版 `trash.js` 已部署；注销/举报/卡面同步仍需登录后逐项验证。

## 本机产出

- 公网上传包：`app dist/exports/Citro-public-pages-20261030.zip`
- 包内：`privacy.html`、`support.html`、`terms.html`、`account-deletion.html`、`README.txt`、`SHA256SUMS.txt`
- ZIP SHA256：`730d7a3d511eba814aa5a689c1cc6c257bb3b8a8597cdf4cb208b46a5057e7f6`

## 仍需 Mac / 服务器 / 账号

- 上传新版 `privacy.html`（公网仍是旧版）。
- 部署最新 `trash/trash.js`，验证注销/举报/卡面同步/AI。
- 恢复/清理线上 QA 数据。
- 创建演示账号、准备截图。
- Mac 出 IPA、TestFlight/真机验收、App Store Connect 提交。
- 决策并处理 UGC 发布前过滤与 iOS 资源库入口。
