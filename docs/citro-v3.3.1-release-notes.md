# Citro 3.3.1 发版记录

> 版本号：`3.3.1+3301` · 2026-11-23
> 汇总区间：3.3.0 → 3.3.1

## 每日一签：完全随机

- 取消同级 6 支签按日期逐日轮换的规则，等级 0–7 与具体签位 0–5 分别独立随机。
- 同一天同一身份仍然只抽一次并保持稳定，跨天重新随机；不是“上上签抽完才进下一档”。
- 服务端 `/api/draw` 同时随机 `idx` 与 `slot`，旧记录缺 `slot` 时补抽并落盘。
- 客户端缓存从 `日期:档位:账号` 升级为 `日期:档位:位置:账号`；旧三段缓存在首次读取时补随机签位，不再回退日期轮换。
- 转运接口同样随机签位，并只从 0–5 档抽，避免转运又转回凶签。

## 签文与今日一小步

- 签文改为七段文本协议流式输出：签题、诗、读签、关键词、今日一小步、忌、便签逐段呈现。
- `AiService.stream` 支持自定义 system，签文不再经过 CiCi 身份包装。
- 今日一小步新增生成后校验，拒绝依赖他人、通讯、外出、购买/预约、等待回复等没有落点的动作。
- 不合理动作优先回退本地签池，再回退到手边动作池；AI 失败时仍有可用内容。

## 社区长文

- 客户端删除发帖 200 字上限与手动校验，服务端删除 200 字截断并保留换行。
- 信息流按真实渲染宽度判断，超过五行折叠，可展开 / 收起。
- 帖子与评论共用 `cleanText`，本轮同时放开；连续空行最多保留一行。

## 四端打包

- Android：`Citro-v3.3.1-release.apk`，arm64-v8a，`com.chimu.crew`，versionCode 3301，Citro 发布签名，可直接覆盖 3.3.0。
- Windows：`Citro-v3.3.1-win64-setup.exe`，用户级安装，更新清单带 SHA-256 与静默更新；同时产出 `WIN/Citro-v3.3.1-win64/` 便携版。
- Web：`Citro-web-3.3.1.zip`，CanvasKit 本地分发、预压缩产物，`latest.json` 同步。
- 下载站：`Citro-downloads-3.3.1.zip`，Windows / Android 入口、版本号、大小、SHA-256 与更新日志同步到 3.3.1。
- iOS：完成预打包，`pubspec.yaml`、`Generated.xcconfig`、`flutter_export_environment.sh` 与文档同步到 `3.3.1 / 3301`；IPA 由 TestFlight CI 在 macOS 构建。

## 产物

| 平台 | 文件 |
| --- | --- |
| Android | `APK/Citro-v3.3.1-release.apk`、`APK/update.json` |
| Windows | `exe/Citro-v3.3.1-win64-setup.exe`、`exe/update.json`、`WIN/Citro-v3.3.1-win64/` |
| Web | `web/Citro-web-3.3.1.zip`、`web/latest.json` |
| 下载站 | `web/Citro-downloads-3.3.1.zip`、`web/downloads.json` |
| iOS | `docs/ios-预打包清单.md`（IPA 待 TestFlight CI 生成） |

## 校验

| 文件 | 字节 | SHA-256 |
| --- | --- | --- |
| Citro-v3.3.1-release.apk | 129,661,064 | `187d0fe2fff88b19bc4dda76483678ec95ff8715ebfd24382a440a01c93064d3` |
| Citro-v3.3.1-win64-setup.exe | 84,624,331 | `1102de39dfcbfc1d11fb6fc7f5ab07c4f3c1f24fba2aeb1456883a5c9509a7c1` |
| Citro-web-3.3.1.zip | 49,154,056 | `9df40e85108c382275740a8d6cdb095bce3ecc17131573820a83af5af13d37ea` |
| Citro-downloads-3.3.1.zip | 1,088,957 | `589bc796a15fd2005456997a119f514c590a79c18f74ba6a91abf0b5400674e2` |

- `dart analyze lib test`：0 error / 0 warning / 140 条既有 info。
- `fortune_pool_test` 11 项、`fortune_cache_owner_test` 3 项、`fortune_transfer_test` 2 项、`fortune_ai_sign_test` 12 项、`foldable_text_test` 2 项通过。
- Android 构建、Windows 便携版与 Inno Setup 安装包、Web 构建、下载站打包均成功。
- iOS 当前环境无 Xcode，按预打包流程完成版本、工程配置、权限与构建脚本核对。

## 部署注意

- 服务端需部署最新 `trash/trash.js` 并重启 PM2：随机抽签与旧记录补 `slot` 依赖 `/api/draw`、`/api/draw/reroll`。
- Web 与下载站用对应整包覆盖站点根；`latest.json` / `downloads.json` 随包上传 OBS。
- 推送 `main` 后 `.github/workflows/ios-testflight.yml` 会自动构建并上传 TestFlight。
