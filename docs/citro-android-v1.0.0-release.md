# Citro 原生安卓 App v1.0.0 — 构建与交接说明

> 生成时间：2026-10-19（Asia/Shanghai）
> 目标：基于工作区根目录**最新版 Citro 网站**（`index.html` + `styles/*.css` + `素材/` + `fonts/` + `manifest.json`），
> 构建名称 **Citro**、版本 **1.0.0** 的原生安卓外壳 App，外观与手机端网站像素级一致、功能全部保留。
> 架构沿用 1.0 起验证过的 **Kotlin 原生外壳 + 本地 WebView 内容**（不是 Capacitor，也不是 Compose 重写）。

---

## 一、产物

| 项 | 值 |
| --- | --- |
| Release APK | `APK/Citro-v1.0.0-release.apk` |
| 大小 | 10,142,106 bytes（**9.67 MB**） |
| SHA-256 | `4B54D6A84FA1AB37F3C86C249B15E11E4536C7434558C2D4B885C6C30DA1DEEE` |
| 包名 / applicationId | `com.chimu.crew`（**保持与旧版一致，可覆盖升级**） |
| versionCode / versionName | **1000 / 1.0.0**（versionCode 规则 `major*1000+minor*100+patch`；旧版 1.9 = 190，故可覆盖安装） |
| 应用名称（桌面 label） | **Citro** |
| 签名 | `密钥/chimu-release.jks`（与旧版同一把，CN=Chimu Crew；SHA-256 `30a30b98…413654`） |
| minSdk / targetSdk / compileSdk | 23 / 35 / 35 |
| 渠道 | stable（离线内置网页资源，打开快、不依赖网络；beta 渠道代码保留未打） |
| 构建命令 | `cd kotlin; $env:JAVA_HOME="C:\Android\jdk-21.0.12.1+1"; node build.js release` |
| 构建结果 | `BUILD SUCCESSFUL in 1m 12s`，47 tasks |

**安装**：直接 `adb install -r APK/Citro-v1.0.0-release.apk` 或手机点击安装；
旧版「迟暮·Crew 1.9」可直接覆盖升级（保登录态 / localStorage / 已授权通知渠道）。

---

## 二、架构（为何能“外观像素级一致”）

```
Kotlin 原生外壳（启动页 / 权限 / 相机 / 文件选择 / 返回键 / 通知）
        │
        ▼
WebView ── 加载 assets/www/index.html（本地资源，0 网络）
        │   WebViewAssetLoader 以虚拟域名 https://chimu-claw.xyz/assets/ 提供
        │   → 与后端同源：Cookie / credentials:include / 登录态原生可用
        ▼
后端 https://chimu-claw.xyz/trashapi（仅数据请求走网络）
```

- App 内网页与网站**使用同一份 HTML/CSS/JS/字体/图片**，由同一 WebView 渲染，故布局/配色/字体/动效一致；
  App 副本只在构建时做 3 类「装进 App 才需要」的改动（见第三章），不改视觉。
- 站点首屏脚本检测 Android WebView UA（含 `; wv)`）自动加 `html.app-shell`，App 与手机浏览器同为手机壳布局。
- 原生启动页消除首帧白屏；原生通知/前台服务负责「社区消息、食谱计时到点、排行榜被超越」系统推送。

---

## 三、本次改动

### 3.1 网页资源同步管线 `kotlin/sync-www.js`（重写，421 → 约 700 行）

- **同步清单**：`index.html` 副本、`manifest.json`、`styles/`（10 个 `citro-*.css`）、
  `fonts/`（仅被引用的 5 个 woff2）、`素材/`（仅被引用的 22 个文件：唯一字标、favicon/图标、赞赏码、
  MOD 图 6 张、每日小猫 9 张）。**共 40 文件 / 9.03 MB**（旧版 30 文件 / 14.53 MB，−38%）。
- **排除**（全站零引用，仅源目录留档）：`素材/_原图备份` 13.29MB、启动动画 mp4 9.55MB、
  启动页/壁纸/旧 logo/CiCi.jpg、未引用字体（马善政/Noto Serif/ZCOOL 全量）、`idioms.txt`/`feihua.txt`
  （新站游戏已改走 MiMo API）、`beian.html`（已不存在）。
- **App 副本补丁**（只改 `assets/www` 副本，根网站源码一字不动）：
  1. 删除「下载 App」入口 2 处（`#pageMe` 应用区块 + 头像下拉菜单 `amDownloadApk`）；副本 `.apk` 残留 0。
  2. 13 条 App 兼容补丁（MiMo 根路径、`authH` 统一鉴权头、fish/打卡/抽签/星盘等）逐条命中校验；
     这些修正**已并入网站源码**，脚本保留「目标形态已存在则跳过 / 原文命中数不符则中止」的保护。
  3. 旧 3 条状态栏避让内联 CSS 迁出为 App 专用 `styles/app-shell.css`（仅 safe-area 规则、
     全部限定 `html.app-shell`，在 `</body>` 前幂等注入）；网页端不加载、非全面屏 `env()=0` ⇒ 观感不变。
- **安全护栏**：构建前后校验根目录网站源文件 SHA-256（index.html 等 39 个被复制文件），
  任何改动直接中止；静态扫描 42 个本地引用确认全部存在。
- 连续两次同步结果逐文件哈希一致（幂等）；根 `index.html` 构建后 SHA-256
  `38117623…7DBFCE59` 与构建前一致，mtime 仍是站点作者的 07:40。

### 3.2 原生外壳品牌化

| 位置 | 改动 |
| --- | --- |
| `res/values/strings.xml` | `app_name = Citro` |
| `res/values/themes.xml` | 背景/状态栏/导航栏 `#EDE6D6`、light status/nav bar（与网站浅色 `--bg` 同源） |
| `res/mipmap-*` | 全套 launcher 图标：方形（`citro-logo-square.jpg`）、圆形、自适应前景/背景；字标按 Ø66dp 安全圆缩放，圆形/方圆遮罩不裁切（生成脚本 `devtools/gen-citro-app-icons.py`） |
| `res/drawable/splash_logo.png` | 透明字标（裁透明边），启动页主视觉 |
| `MainActivity.buildSplash` | `#EDE6D6` 底 + 字标 216dp + 副标「游戏 · 食谱 · 社区」14sp `#67634F` + 淡入上浮 420ms，顶部留白 24% |
| `MainActivity` | WebView 背景 `#EDE6D6`、UA 追加 `Citro/1.0.0`（保留原生 `; wv)` 标记）、离线兜底页 Citro 文案与配色 |
| `build.gradle.kts` | versionName 1.0.0 / versionCode 1000；applicationId、namespace 不变 |
| `build.js` | 产物命名 `APK/Citro-v<version>-release.apk`（beta 带 `-beta`），同步/打包流程与根 HTML 守卫不变 |

### 3.3 网页 ↔ 原生桥接（1.8 四项系统推送）适配

- 对照最新站逐项核实：localStorage 三个键、计时器 DOM（`.tn/.tt/.tx[data-del]`）、
  `/api/games/score`、`/api/games/board`、`/api/notifications(/read)`、Capacitor LocalNotifications 垫片入口——
  **全部未变**，桥接零破坏。
- 品牌文案改 Citro（bridge 默认通知标题、Notify 渠道显示名、PushChecker/CookTimerService 用户可见文案）；
  通知渠道 ID 保持不变（`chimu_messages` / `chimu_cook_done` / `chimu_cook_run`），老用户通知设置不丢。
- 修复边界：自定义计时上限 1440 分钟时页面显示 `1440:00`（4 位分钟），原解析会漏镜像 → 已放宽。
- `node kotlin/chimu-bridge.selftest.js`：**58 项断言全部通过**（原 21 项扩充）。

---

## 四、验收证据

| 项 | 结果 | 证据 |
| --- | --- | --- |
| Gradle 构建 | ✅ BUILD SUCCESSFUL | 构建日志 |
| APK 元数据 | ✅ com.chimu.crew / 1000 / 1.0.0 / label Citro / minSdk23 / targetSdk35 | `aapt2 dump badging` |
| 签名 | ✅ apksigner verify 通过，与旧版同证书 | `_tmp/qa-citro-app/build-info.txt` |
| APK 内容 | ✅ assets/www 40 文件 9.03MB；styles 11 / fonts 5 / 素材 22 / 根级 2 | 同上 |
| App 副本改动范围 | ✅ 与根 index.html 仅 3 处差异（删 2 个下载入口 + 1 个安全区 CSS link） | `_tmp/qa-citro-app/` |
| 桥接自测 | ✅ 58/58 断言 | `_tmp/team/bridge-compat/selftest-output.txt` |
| 同步幂等/只读守卫 | ✅ 两次同步哈希一致；根 HTML 未改 | `_tmp/team/sync-pipeline/report.md` |
| 像素级对比（App 副本 vs 网站，手机 390×844 浅/深） | ✅ 见 `_tmp/qa-citro-app/final-report.md` | 差异图 + 量化比例 |
| 手机端功能冒烟 | ✅ 见 `_tmp/qa-citro-app/final-report.md` | 路由/主题/游戏/浮层/console |
| 真机运行 | ⚠️ **未验证（本机无 Android 设备/模拟器）** | 仅编译、打包、签名、静态与 headless 验证 |

> QA 详细报告：`_tmp/qa-citro-app/final-report.md`；基线/对比截图：`_tmp/qa-citro-app/baseline-web/`、`_tmp/qa-citro-app/app-www/`、`_tmp/qa-citro-app/diff/`。

---

## 五、已知差异与边界

1. **App 内隐藏「下载 App」入口**（页面里已装好再显示下载按钮多余，沿用 1.7 起约定）；网站端入口保留。
2. **网站下载入口仍指向 `/APK/Citro-v1.9.apk`**：本次遵循「构建不改网站源」约定，未改根 `index.html`。
   若要把线上分发切到新包：上传 `APK/Citro-v1.0.0-release.apk` 到服务器 `/APK/`，
   再把 `index.html` 两处 `href="/APK/Citro-v1.9.apk"` 改为新文件名即可。
3. **beta 渠道**：实时加载线上站、不受 App 副本补丁影响，仍会显示下载入口；本次只打了 stable。
4. **通知渠道显示名**只在全新安装时生效（Android 不更新既有渠道名）；渠道 ID 未变，老用户设置不丢。
5. **无真机验证**：相机/录音/定位/系统通知弹出/前台服务常驻等原生能力未在真机实测；
   代码逻辑与 1.8 一致，仅品牌文案与页面资源变化。
6. 每日小猫 9 张 PNG 占 App 内素材 81%（4.33MB）；进一步瘦身需改站点 `CI_CATS` 路径，不在本次范围。
7. 站点源码若再次改动 `APP_PATCHES` 对应代码，`sync-www.js` 会命中数不符并**中止构建**（防呆），需同步更新补丁。
8. **网站侧既有瑕疵（App 原样复刻，未改网站源码）**：`styles/citro-scrapbook.css` 的
   `@media (max-width:1024px)` 段里有 **22 条**形如 `html[data-theme="dark"] html.app-shell …`
   的**死选择器**（`html` 里嵌 `html`，永不命中），导致手机宽度深色模式下首页的
   天气 / 摸鱼 / 星象 / 日历 / 食谱小组件仍是浅色底、浅色字对比度不足；其余区域正常深色。
   网站与 App 副本表现完全一致（同一份 CSS），不影响「App = 网站」一致性，但属产品可见瑕疵。
   修法（网站侧一行级）：把 `html[data-theme="dark"] html.app-shell` 改为 `html[data-theme="dark"].app-shell`，
   然后 `node sync-www.js` + 重新构建即可同步进 App。本次遵循「构建不修改网站源」约定，未擅自改动。

---

## 六、文件清单

新增/重写：

```
kotlin/sync-www.js                    ← 重写：Citro 资源同步 + App 补丁 + 引用扫描 + 只读守卫
kotlin/build.js                       ← 产物命名改 Citro-v<version>-release.apk
kotlin/app/build.gradle.kts           ← versionName 1.0.0 / versionCode 1000
kotlin/app/src/main/res/values/strings.xml     ← app_name=Citro
kotlin/app/src/main/res/values/themes.xml      ← Citro 主题色
kotlin/app/src/main/res/mipmap-*/…              ← 全套 Citro 图标（24 张 PNG）
kotlin/app/src/main/res/drawable/splash_logo.png
devtools/gen-citro-app-icons.py       ← 图标生成脚本（可复跑）
kotlin/app/src/main/assets/www/**      ← 同步产物（40 文件 9.03MB，构建时自动再生成）
kotlin/app/src/main/java/com/chimu/crew/MainActivity.kt      ← 启动页/UA/离线页/主题色
kotlin/app/src/main/assets/chimu-bridge.js                   ← Citro 文案 + 1440 分钟边界修复
kotlin/chimu-bridge.selftest.js                              ← 21 → 58 项断言
kotlin/app/src/main/java/com/chimu/crew/{Notify,PushChecker,ChimuBridge,CookTimerService}.kt ← Citro 文案
docs/citro-android-v1.0.0-release.md  ← 本文件
APK/Citro-v1.0.0-release.apk          ← 交付产物
```

未改动：根目录 `index.html` / `styles/` / `素材/` / `fonts/`（构建只读）；Capacitor 旧工程保留未删。

---

## 七、复现构建

```powershell
cd C:\迟暮\迟暮Crew\kotlin
$env:JAVA_HOME = "C:\Android\jdk-21.0.12.1+1"
node chimu-bridge.selftest.js     # 可选：桥接离线自测（58 项）
node build.js release             # 自动 sync-www.js + gradle + 复制到 ../APK/
```

> `build.js` 会先校验根目录网站源文件哈希；若网页在构建期间被改动会直接失败退出。
> 网页更新后重新构建即可带上最新站内容（App 无需改代码）。
