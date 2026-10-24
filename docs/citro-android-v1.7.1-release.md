# Citro Android v1.7.1 发版记录

- 日期：2026-10-23
- 版本：`1.7.1` / versionCode `1701`
- APK：`APK/Citro-v1.7.1-release.apk`（71.3 MB）
- SHA-256：`82B879EDBFE6F55F09A0732591947143299B51F3BD0F82D6F78A104DBD4C4FB5`

## 1. 用 REA 逆向原始版

- 把 shache.org 的构建产物（`index.html` + `assets/index-*.js` 746 KB +
  `index.css`）整理成应用目录 `_tmp/rea-app/`；
- 运行 `npx -y rea-agents@latest analyze-javascript-application` —— 成功产出
  应用图与语义图（evidence JSON，79 MB，存 `_tmp/rea-out.json`，graph 含
  request / storage / timer 等家族）。
- **REA 的局限**：它的报告明确写了「模板字符串里的动态路径可能无法解析」——
  这次确实没把 `` fetch(`/api/leaderboard?limit=${e}`) `` 还原成字面量。因此
  再对 bundle 做 `js-beautify` 后按调用点检索，拿到了完整后端契约：

  | 方法 | 路径 | 载荷 / 返回 |
  | --- | --- | --- |
  | GET | `/api/leaderboard?limit=N` | `{ entries: [...] }` |
  | POST | `/api/score` | `{ nickname, v0, stopTime }` |

  全站仅这两个后端调用（其余都是纯前端 three.js 场景）。

## 2. 接入 App 自己的排行榜（不再依赖 URL）

- 新增 `assets/shache/citro-bridge.js`，在 `app.js` 之前注入：接管
  `window.fetch`，把上述两个接口转成 JS bridge 调用
  `citroScore` / `citroLeaderboard`；未注入 bridge 时回退原生 fetch。
- Flutter 侧（`lib/games/gbrake_web.dart`）注册两个 handler：
  - `citroScore`：按原版公式 `score = round(v0² / stopTime)` 计算，调用
    `AppState.submitScore('brake', score)` 写入 App 榜单，并回传最新 entries；
  - `citroLeaderboard`：`AppState.fetchBoard('brake')` → 映射成原版需要的
    `{nickname, score, v0, stopTime}` 列表返回给页面。
- **完全去 URL 依赖**：删掉线上 `https://shache.org/` 加载分支，只从内置资源
  启动 —— 每次进入把 `assets/shache/*` 覆盖解压到应用目录，用
  `InAppLocalhostServer` 以 `http://localhost:8731` 提供（真实 origin，
  localStorage / fetch 正常）；APK 内已确认包含 index/app.js/app.css/bridge 四个文件。

## 验证

- `dart analyze lib`：0 error / 0 warning。
- `flutter test --concurrency=1`：13 张 golden 通过。
- APK `assets/flutter_assets/assets/shache/` 四件齐备；aapt2 确认 1701 / 1.7.1。
