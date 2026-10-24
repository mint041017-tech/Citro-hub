# Citro Android v1.5.3 发版记录

- 日期：2026-10-23
- 版本：`1.5.3` / versionCode `1503`
- 包名：`com.chimu.crew`（minSdk 24 / targetSdk 36）
- APK：`APK/Citro-v1.5.3-release.apk`（通用 ABI：arm64-v8a / armeabi-v7a / x86_64，69.2 MB / 72,544,853 bytes）
- SHA-256：`b6526e8bcfc20d4fa7893a26458da312c17ea6eafd5926dc5423283eca638614`
- 签名：与 v1.1.1 相同的 release key（证书 SHA-256 `0701ae253cf5cbf9826380c79f8cf395a97127535f021a03e6e56be2def1b3b3`），可覆盖升级

## 本次改动

1. **启动页旧名移除**：启动页底部文案从「Citro · 迟暮 Crew」改为「Citro」，版本号显示 v1.5.3。
2. **CiCi 按钮放大**：「新对话」按钮高 40dp、带加号，关闭按钮改为 42dp 圆形，触控和视觉都更明显。
3. **计时悬浮卡**：计时器改为浮在内容上方的深色大卡片，包含 30sp 倒计时、进度条、较大的停止按钮和推送状态提示；计时期间为内容预留底部空间，不遮住「复制文本」或购物输入框。
4. **倒计时推送接入并修复**：
   - 计时开始时通过 `flutter_local_notifications` 排程系统通知（精确闹钟可用时用 exact，否则用 inexact 兜底）。
   - 补齐 App Manifest 的 `ScheduledNotificationReceiver` 与 `ScheduledNotificationBootReceiver`，并声明 `RECEIVE_BOOT_COMPLETED`；这是之前「闹钟响但系统没有通知」的根因。
   - 新增 R8/ProGuard keep 规则，保留 Gson `Signature`、`TypeToken` 和插件模型类，修复 `Missing type parameter` 导致排程保存失败。
   - 前台到点由应用内计时器收尾并取消系统通知；后台/进程被杀时由系统通知兜底。
5. **验证**：启动 1 分钟计时后按 Home 并 `am kill` 掉 App 进程，到点仍收到系统通知「⏰ 时间到 / 自定义计时」，通知点击可回到 App。

## 构建与稳定性

- Gradle 维持 3G 堆 / 768M Metaspace，daemon 关闭、workers=2，构建期间无模拟器并行。
- 正式包 `aapt`：versionCode 1503 / versionName 1.5.3 / 三个 ABI；manifest 已包含两个通知 receiver；`apksigner` 签名通过。
- 正式包内使用 `chimu-claw.xyz` 正式 API 与 GLM 端点，不含本地测试地址 `10.0.2.2`。

## 备注

- 线上站点本次**未部署**；`index.html` 与本地 `APK/Citro-v1.5.3-release.apk` 已同步。
- 如果用户关闭「我的 → 通知提醒」或系统通知权限，计时仍会在应用内到点提示，但不会发系统推送；计时卡会显示「仅应用内提醒」。
