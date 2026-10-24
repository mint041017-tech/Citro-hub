# Citro Android v1.5.7 发版记录

- 日期：2026-10-23
- 版本：`1.5.7` / versionCode `1507`
- 包名：`com.chimu.crew`（minSdk 24 / targetSdk 36）
- APK：`APK/Citro-v1.5.7-release.apk`（通用 ABI：arm64-v8a / armeabi-v7a / x86_64，69.5 MB / 72,824,906 bytes）
- SHA-256：`10665a875c76c924d4bd0fa970d2777b2edc7305775f71daadea5c5cf172b293`
- 签名：与 v1.1.1 相同的 release key（证书 SHA-256 `0701ae253cf5cbf9826380c79f8cf395a97127535f021a03e6e56be2def1b3b3`），可覆盖升级

## 主导航切换提速

1. **单程 90ms**：首页/游戏/社区切换改为「立即换页 + 新页 90ms 滑入（36px × 方向）+ 轻微淡入」，不再有旧页淡出阶段，完整切换控制在 100ms 以内（上一版为两段各 150ms）。
2. 页面状态仍由 IndexedStack 保留；食谱日记内部视图沿用 v1.5.6 的方向平移。

## 验证

- 模拟器（393×852dp）安装测试包，点击社区后 30ms 抓帧：新页已在滑入途中（横向偏移 + 淡入），随后立即稳定；登录态、列表与收件箱胶囊均正常。
- 正式包 `aapt`：versionCode 1507 / versionName 1.5.7 / 三个 ABI；`usesCleartextTraffic=false`；`apksigner` 签名通过；`libapp.so` 含 `chimu-claw.xyz` 与 `open.bigmodel.cn`，无本地测试地址。
- 线上站点本次**未部署**；`index.html` 与本地 `APK/Citro-v1.5.7-release.apk` 已同步。
