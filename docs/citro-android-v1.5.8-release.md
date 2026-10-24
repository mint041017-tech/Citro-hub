# Citro Android v1.5.8 发版记录

- 日期：2026-10-23
- 版本：`1.5.8` / versionCode `1508`
- 包名：`com.chimu.crew`（minSdk 24 / targetSdk 36）
- APK：`APK/Citro-v1.5.8-release.apk`（通用 ABI：arm64-v8a / armeabi-v7a / x86_64，70.3 MB / 73,709,642 bytes）
- SHA-256：`d8c25a1ccf7b1bdc6040cb7bba76176413f723cb51dd33a41a66c65e6626a96e`
- 签名：与 v1.1.1 相同的 release key（证书 SHA-256 `0701ae253cf5cbf9826380c79f8cf395a97127535f021a03e6e56be2def1b3b3`），可覆盖升级

## 12 个游戏页按 Web 原版逐像素复刻

本版重点：把 App 内 12 个游戏页的视觉/版式按线上 Web 版（`index.html` + `styles/citro-games.css` + `styles/citro-arcade.css`，390×844 手机端）**逐像素重做**，替代此前的自造简化版骨架。

- 新增公共游戏 UI kit `flutter/lib/games/game_ui.dart`：`GameScaffold`（固定 56dp 顶栏 + 标题/手绘下划线 + HUD pill + 42dp 胶囊按钮 + 「正在玩」live 条 + 整页滚动）、`GameScorePill`、`GameActionButton`、`GameSegTabs`、`GameTape`（撕纸胶带）、`CssShadowLayer`（复刻 CSS 外阴影语义）、`GameIcons`（lucide 风格手绘图标）、`showGameRank` / `showGameAccount` / `gameFmtDuration`。
- 复刻项：纸面方格背景（24px 网格，横线相位按 Web 从底边起算）、页面光斑、顶栏 logo + 「游戏空间」、返回圆钮、账号圆钮、标题与荧光笔下划线的「手机端隐藏」规则、HUD 胶囊（62×56.6，accent 描边）、按钮（42 高、999 圆角、主按钮橙色渐变）、排行榜底部抽屉、各游戏棋盘/卡牌/画布/纸笺与结算浮层、live 悬浮条（44.7 高）。
- 各页与 Web 参考图（同 390×844、light）的逐像素均差：2048 1.54 / 记忆卡牌 2.07 / 数独 3.12 / 数织 1.89 / 数字华容道 2.43 / 贪吃蛇 0.97 / 羊了个羊 1.42 / 跳一跳 1.30 / 淘气小球 1.44 / 极限刹车 3.65 / 成语接龙 2.53 / 飞花令 2.57（0~255 灰度；残差基本为 Chrome LCD 子像素 AA 与 Flutter 灰度 AA 的字体栅格化差异，无结构性偏移）。
- 极限刹车（3D 赛道）为「布局/菜单卡/结算卡/暗场 HUD 一致 + Canvas 近似 3D 场景」，玩法逻辑保留。

## 成语接龙 / 飞花令 的 AI 兜底

- 兜底链路确认：本地词库/诗句优先，本地无候选时才走 AI；AI 调用统一走 `flutter/lib/services/ai.dart`（全项目仅此处有模型名与端点）。
- 模型：`glm-5.3-flash`，网关 `https://open.bigmodel.cn/api/paas/v4/chat/completions`，请求体固定 `thinking: {type: enabled}` + `reasoning_effort: "low"`（GLM 5.3 Flash 轻度思考）。
- API Key 由构建脚本 `flutter/build.js` 从 `密钥/glm.key` 读取并以 `--dart-define=GLM_API_KEY=...` 注入，不进仓库。
- App 内 AI 提示文案改为「AI 对战 · GLM-5.3-Flash 实时出题与判定 / 实时抽字与对诗」（Web 版为 MiMo，属钦定差异）。

## 验证

- 像素验收工具链：`flutter/test/preview/*_preview_test.dart` 逐页离屏渲染 golden（FontLoader 加载 Kalam / ZCOOL / Caveat / NotoSC，`tester.view.physicalSize=390×844`、dpr 1），`_tmp/tools/cmp_render.py` / `cmp_all.py` 与 Web 参考图对比输出均差、行差带与左右拼图（`_tmp/ref/cmp/all-side.png`）。
- `flutter test test/preview` 13 张 golden 全部通过（串行 `--concurrency=1` 更稳；并行偶发 did not complete）；`dart analyze lib test/preview` → 102 issues、**0 error / 0 warning**（全为 info）。
- 模拟器（393×852dp，emulator-5554）安装正式包后逐页截图核对 12 页：`_tmp/ref/native/v158-<game>.png`（拼图 `v158-montage.png`）；页面无 overflow、无报错。
- dark 主题抽样核对（g2048 暗色渲染 vs Web `_tmp/ref/games/g2048-m-d.png`）：页面底色 (25,25,32)、普通按钮 (191,191,191)、棋盘格与 tile 均一致，dark 样式由令牌自动继承。
- 正式包 `aapt2`：versionCode 1508 / versionName 1.5.8 / 三 ABI；`apksigner` 验签通过（同上证书）；`libapp.so` 含 `chimu-claw.xyz`、`open.bigmodel.cn`、`glm-5.3-flash`、`reasoning_effort`。
- 线上站点本次**未部署**。

## 构建注意（本版新增踩坑）

- 工程路径含中文（`C:\网站web\Citro`）时，直接从真实路径 `flutter build apk` 会在 `:app:compileFlutterBuildRelease` 失败：`Unable to read file: C:\网站web\Citro\flutter\.dart_tool\flutter_build\<hash>\app.dill` / `Cannot invoke "java.io.File.exists()" because "parent" is null`（中文路径在 AOT snapshot 生成器里被错误编码）。
- 正确做法：`subst X: "C:\网站web\Citro"`，然后 **`cd X:\flutter` 先 `flutter clean` 再构建**（纯 ASCII 路径下 `app.dill` 读写正常），产物再拷回 `APK/`。
- 16G 开发机不要同时开模拟器与 Gradle 构建。
