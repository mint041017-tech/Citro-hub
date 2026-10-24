# Citro Android v1.7.0 发版记录

- 日期：2026-10-23
- 版本：`1.7.0` / versionCode `1700`
- APK：`APK/Citro-v1.7.0-release.apk`（71.5 MB）
- SHA-256：`C3AC2229DBF3B65EA5722367017D7CDC8798CC5301AE42DE94C66C216850DCF7`

## 极限刹车：改为内嵌原始版（WebView）

手写 Canvas 渲染器（低多边形车模 + 无阴影/无反射/无 Bloom）与 three.js 原版
始终有肉眼可见的差距，本版直接把原版装进 App：

- **优先加载线上** `https://shache.org/` —— 与浏览器里玩的完全一致；
- **离线回退**：首次进入把 `assets/shache/{index.html,app.js,app.css}`
  （原站 3 个构建产物，共 765 KB）解压到应用目录，用
  `InAppLocalhostServer` 以 `http://localhost:8731` 提供。走真实 http origin，
  localStorage / fetch / AudioContext 行为与线上一致（`file://` 下会被拦掉）；
- 主文档加载失败（断网 / 站点不可达）时自动切到离线副本；
- 悬浮返回按钮 + 加载指示；启动时隐藏状态栏配色冲突；
- Android 网络安全配置只对 `localhost` / `127.0.0.1` 放开明文，其余仍强制 HTTPS。

**WebView 选型**：从 `webview_flutter` 换成 `flutter_inappwebview`。
两者底层都是系统 WebView（Android 上同为 Chromium），**页面渲染/游戏帧率没有
差别**；换它的实际收益是 `InAppLocalhostServer`（离线副本有真实 origin）、更细的
`InAppWebViewSettings`（硬件加速、禁用滚动/缩放、媒体无需手势即可播放）以及
更完整的错误回调。代价是原生依赖更大（APK +0.7 MB）、构建稍慢。

原 Canvas 实现（`lib/games/gbrake.dart`、`gbrake_scene.dart`）暂时保留在仓库中
但不再挂到游戏路由（`game_registry` 已指向 `GameBrakeWebPage`），后续可删除。

## 验证

- `dart analyze lib`：0 error / 0 warning。
- `flutter test --concurrency=1`：13 张 golden 通过。
- APK 内确认包含 `assets/flutter_assets/assets/shache/{index.html,app.js,app.css}`。
- aapt2：versionCode 1700 / versionName 1.7.0 / 三 ABI。
