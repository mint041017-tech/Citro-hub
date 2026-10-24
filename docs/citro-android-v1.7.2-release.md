# Citro Android v1.7.2 发版记录

- 日期：2026-10-24
- 版本：`1.7.2` / versionCode `1702`
- APK：`APK/Citro-v1.7.2-release.apk`（71.1 MB）
- SHA-256：`F77C66DB09B3C73AE3912AEA4F1FC3A8256111F4D0E15669E0AC01B85A682B5E`

## 极限刹车「打开一片白」修复

先在本地复现：把 `assets/shache/index.html` 用本地静态服务跑在 Chrome（SwiftShader
软件 GL）里截图 —— **页面本身完全正常**（暗色赛道 + 玻璃面板 + 金色按钮）。因此
白屏出在 WebView 装载链路，而不是资源或页面代码。

原实现（v1.7.1）用 `InAppLocalhostServer` + `http://localhost:8731`，可能踩到：
端口占用 / 明文流量被拦 / JSDelivr 式 MIME 不匹配 / 服务器与 WebView 启动竞态
（`onWebViewCreated` 早于服务器就绪，两边都以为对方没好，从未发起加载）。

v1.7.2 改为**彻底不走网络、不走文件服务**：

- 启动时读取 4 个内置资源，拼成**一个完整的单文件 HTML**：
  `citro-bridge.js` 内联为普通 `<script>`（先于主包执行）、`app.js` 内联为
  `<script type="module">`、`app.css` 内联为 `<style>`，并对 `</script` 做转义；
- 注入 `localStorage` 兜底 shim（`loadData` 的 origin 下 `localStorage` 可能抛异常，
  原版启动时会读它，抛错会直接白屏）；
- 用 `webview.loadData(html, mimeType: text/html, encoding: utf-8,
  baseUrl: https://shache.local/)` 直接呈现 —— 无 HTTP、无临时文件、无 MIME 依赖；
- 保留 JS bridge：`citroScore` → `AppState.submitScore('brake', score)`，
  `citroLeaderboard` → `AppState.fetchBoard('brake')`。

另外白屏不再「无声」：

- `onLoadStop` 后执行 `!!document.querySelector('canvas')` 自检，没有画布就判定为
  WebGL/脚本失败；
- 任何主文档错误 / 构建异常都会显示**「游戏加载失败 + 具体原因 + 重新加载」**浮层，
  不会再只有一片白。

## 验证

- 内联后的单文件（766 KB）在本地 Chrome 软件 GL 下渲染正常：菜单、赛道、字体全对；
- `dart analyze lib`：0 error / 0 warning；
- aapt2：1702 / 1.7.2；APK 内含 `assets/flutter_assets/assets/shache/` 四件资源。
