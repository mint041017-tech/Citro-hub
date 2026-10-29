# Citro 1.9.9 更新日志

2026-10-30 · 版本 1.9.9（Android versionCode 1909）· Web / Windows / Android / iOS 源码同步

1.9.9 修复同一账号在不同端看到的卡面收藏、今日卡与抽卡次数不一致的问题：卡面状态改为账号级同步，首次登录自动合并本机进度，切换账号不会串数据。其余内容与 1.9.8 一致。

## 卡面收藏与抽卡跨端同步

- 新增账号级卡面状态：收藏列表、剩余抽卡次数、今日卡、游戏局数/每日机会与当日快捷机会由服务端保存。
- 同一账号在 Web / Windows / Android / iOS 登录后，收藏库、今日卡与剩余次数保持一致。
- 抽卡与今日卡由服务端在客户端提交的卡面目录中随机选择；各端不会各抽各的。
- 首次登录自动把本机已有的收藏、次数与今日卡合并到账号；同一设备重载或旧端延迟同步不会把已消耗的次数顶回去。
- 切换账号时本机缓存会清理，避免 A 账号的卡面串到 B 账号。
- 打开卡面收藏时自动拉取最新账号状态；游客和离线场景仍使用本机逻辑，联网后自动合并。

## 兼容说明

- 客户端为向后兼容做了回退：若线上后端尚未包含 `/api/cards/*`，会继续使用本机卡面逻辑，不会报错；新版 `trash.js` 部署后自动启用账号同步。
- **必须部署新版 `trash/trash.js` 后，跨端同步才会生效。** 部署前旧行为保持不变。

## 版本与分发

| 端 | 制品 | 状态 |
| --- | --- | --- |
| Android | `Citro-v1.9.9-release.apk`（versionCode 1909，90,375,064 B，sha256 `7f65ab93…`） | 已构建，已上传 OBS |
| Windows | `Citro-v1.9.9-win64-setup.exe`（21,998,453 B，sha256 `97671336…`）+ 便携版 | 已构建，已上传 OBS |
| Web | `Citro-web-1.9.9.zip`（27,122,049 B，sha256 `bd4aa4e6…`，build_id `7df59215daad791d9eb273ccba602aed`） | 已构建，已上传 OBS |
| iOS | 源码、工程与 Live Activity 组件就绪 | 无 IPA，需 Mac / Xcode / Team |

补充说明：

- 下载站整包 `Citro-downloads-1.9.9.zip`（1,088,071 B，sha256 `75d3c944…`）已生成并上传 OBS，公网 `dl.chimu-claw.xyz` 需用整包覆盖 nginx 站点根后生效。
- iOS 前置：pubspec 为唯一版本源，Runner/TimerWidget 使用 `FLUTTER_BUILD_NAME`/`FLUTTER_BUILD_NUMBER`，Live Activity、权限文案与隐私清单沿用既有配置；Mac 从 main/tag 拉取后执行 `bash ios/build_ipa.sh`。
