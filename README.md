# Citro

> 游戏 Mod 与实用工具、15 款小游戏、食谱日记和同频社区。不卷段位，随缘开黑。

新版 Web、Android / iOS 与 Windows 桌面端共用 `flutter/lib/` 中的 Flutter 页面、游戏和业务逻辑，
后端继续使用 Node 零依赖 API。Windows 桌面端采用 iPad 同款界面与动效，并增加无边框自绘标题栏、
全量资源库与应用内更新；Web 宽屏继续使用手账桌面布局。根目录的 `index.html` 与 `styles/` 暂时保留为旧版网页，便于对照与回退。

- 线上站点：<https://chimu-claw.xyz>
- 新版前端：Flutter Web，`bash tool/build_web.sh` 构建（本地 CanvasKit、裁剪未用渲染器并预压缩）
- 后端零依赖：只用 Node 内置模块，数据落在 JSON 文件里

---

## 功能

| 模块 | 说明 |
| --- | --- |
| Windows 桌面端 | iPad 同款界面与动效、完全无边框 + 自绘标题栏、多比例自适应、全量资源库、应用内下载/静默安装/自动重启 |
| 首页 | 手账拼贴风布局、「今日小猫」随机贴纸、每日壁纸 |
| 资源下载 | 游戏 Mod 封面卡片、小工具与外设驱动的下载直链（外链到服务器） |
| 小游戏 | 2048、记忆卡牌、数独、Nonogram、滑动拼图、贪吃蛇、羊了个羊、跳一跳、碰碰、刹车挑战、咕噜果冻、铃渡等 15 款 |
| 文字游戏 | 成语接龙、飞花令、中秋猜灯谜 |
| 食谱日记 | 「吃什么」随机推荐、菜谱、步骤图上传 |
| 社区 | 注册 / 登录、发帖（实名或匿名）、点赞、抱一抱、评论回复 |
| 星象 | 今日运势、星盘、行运（依赖后端与第三方接口） |
| 小工具 | 天气、历史上的今天、便签、摸鱼配置等 |

## App Store 截图

> 1.9.9（1909）· iPhone 6.3 英寸 1206×2622 / iPad 13 英寸 2064×2752 · 演示账号 `CitroReview`
>
> 截图已上传 App Store Connect（两端各 6 张）；iPad 游戏页保留「小工具/资源库」入口，为外部工具导航。
> 文件与说明见 [`app dist/screenshots/final/README.txt`](app%20dist/screenshots/final/README.txt)。

### iPhone 6.3 英寸

| 首页 | 游戏 | 游戏内 |
| --- | --- | --- |
| <img src="app%20dist/screenshots/final/iphone-6.3-01-home.jpg" width="240" alt="iPhone 首页"> | <img src="app%20dist/screenshots/final/iphone-6.3-02-games.jpg" width="240" alt="iPhone 游戏"> | <img src="app%20dist/screenshots/final/iphone-6.3-03-game-slide.jpg" width="240" alt="iPhone 数字华容道"> |

| 社区 | 食谱 | 听隅 |
| --- | --- | --- |
| <img src="app%20dist/screenshots/final/iphone-6.3-04-community.jpg" width="240" alt="iPhone 社区"> | <img src="app%20dist/screenshots/final/iphone-6.3-05-cook.jpg" width="240" alt="iPhone 食谱库"> | <img src="app%20dist/screenshots/final/iphone-6.3-06-tingyu.jpg" width="240" alt="iPhone 听隅"> |

### iPad 13 英寸

| 首页 | 游戏 | 游戏内 |
| --- | --- | --- |
| <img src="app%20dist/screenshots/final/ipad-13-01-home.jpg" width="300" alt="iPad 首页"> | <img src="app%20dist/screenshots/final/ipad-13-02-games.jpg" width="300" alt="iPad 游戏"> | <img src="app%20dist/screenshots/final/ipad-13-03-game-slide.jpg" width="300" alt="iPad 数字华容道"> |

| 食谱 | 听隅 | 记忆卡牌 |
| --- | --- | --- |
| <img src="app%20dist/screenshots/final/ipad-13-04-cook.jpg" width="300" alt="iPad 食谱库"> | <img src="app%20dist/screenshots/final/ipad-13-05-tingyu.jpg" width="300" alt="iPad 听隅"> | <img src="app%20dist/screenshots/final/ipad-13-06-game-memory.jpg" width="300" alt="iPad 记忆卡牌"> |

## 技术栈

- **Web**：Flutter 3.47 原生 Widget，与移动端共享页面和状态；浏览器定位、录音等能力通过条件导入适配
- **Windows**：Flutter 3.47 Windows 原生构建（Impeller），`window_manager` 无边框窗口，Inno Setup 用户级安装与静默更新；WebView2 运行「极限刹车」
- **旧版前端**：原生 HTML / CSS / JavaScript，保留在根目录用于对照与回退
- **后端**：Node.js 内置模块（`http` / `fs` / `crypto`），零第三方依赖；JSON 文件存储 + scrypt 密码哈希 + httpOnly Cookie 会话
- **Android / iOS**：与 Web 共用 Flutter 原生 Widget 实现，全部页面 / 游戏 / 社区 / 食谱 / 星象均为原生 UI

## 目录结构

```
Citro/
├─ index.html                 # 整站单页（HTML + 内联 CSS/JS）
├─ manifest.json              # PWA manifest
├─ styles/                    # 11 个外置样式表
├─ fonts/                     # 本地字体子集（woff2）
├─ 素材/                       # 站点用到的图片素材（logo / 图标 / Mod 封面 / 猫猫贴纸）
├─ trash/                     # 后端
│  ├─ trash.js                #   Node 零依赖 API 服务（端口 10003）
│  ├─ config.local.example.json  # 本地密钥配置模板
│  └─ data/                   #   运行时用户数据（.gitignore 排除，仅保留 README）
├─ flutter/                   # Flutter Web / Android / iOS
│  ├─ build.js                #   Android 一键打包脚本
│  ├─ lib/                    #   共享页面 / 游戏 / 组件 / 状态 / API 与平台适配
│  ├─ web/                    #   Web 入口、PWA manifest 与品牌图标
│  ├─ windows/                #   Windows runner（无边框窗口、单实例、高性能 GPU）
│  ├─ tool/build_windows.js   #   Windows 构建 + Inno Setup 安装包 + 更新清单
│  └─ android/                #   包名 com.chimu.crew、签名与启动资源
├─ WIN/                       # Windows 便携版构建产物（不入库）
├─ exe/                       # Windows 安装包与 update.json（不入库，上传 OBS）
├─ kotlin/                    # 旧版 Kotlin WebView 外壳（历史存档，不再发版）
├─ devtools/                  # 字体子集、图标、图片压缩、本地静态服务等脚本
├─ docs/                      # 设计规范、素材清单、部署清单、发版记录
└─ APK/                       # 站内提供下载的安装包
```

## 本地运行

### 1. 运行 Flutter Web（新版）

```bash
cd flutter
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8019
```

打开 <http://127.0.0.1:8019/>。Release 构建：

```bash
cd flutter
bash tool/build_web.sh
# 产物：flutter/build/web/，包含本地 CanvasKit、gzip 预压缩文件并已裁剪未用渲染器
```

部署时保留服务端 `/trashapi` 与 `/api` 反向代理，并将前端路由回退到 `index.html`。
Nginx 请启用 `gzip_static` 并参考 [`docs/nginx-citro-web.conf`](docs/nginx-citro-web.conf) 设置压缩与缓存；
线上完整 vhost 与 `/trashapi` 反代配置见 [`docs/nginx/`](docs/nginx/)（含修改前备份）。
Edge 与 Safari 会使用本站 CanvasKit，不再请求 CDN。构建命令不会覆盖根目录的旧版 `index.html`。

### 2. Windows 桌面端（开发）

前置：Windows 10 1809+ / Windows 11 x64、VS 2022 Build Tools（勾选 **Desktop development with C++**）、
NuGet CLI（`flutter_inappwebview_windows` 构建 WebView2 时需要）、Microsoft Edge WebView2 Runtime（Win10/11 通常已内置）。
直接运行：

```powershell
cd flutter
flutter pub get
flutter run -d windows
```

窗口默认 1200×720、最小 780×560；支持完全无边框拖拽、双击标题栏最大化、四周缩放、单实例；
全站搜索只保留侧栏入口，不显示滚动条；“我的”为圆角浮窗。桌面端数独用 1–9 / 方向键 / 退格，
贪吃蛇用 WASD / 方向键，跳一跳支持空格；成语接龙与飞花令选好输入法候选词后点“接”提交。
Windows 版使用 iPad 界面，不使用 Web 的手账桌面布局。

### 3. 查看旧版前端（可选）

任选一种静态服务器（旧站用根相对路径，必须起 HTTP 服务，直接双击 `index.html` 部分功能不可用）：

```bash
# Python
python -m http.server 8019

# 或 Node（任意静态服务器）
npx serve -l 8019
```

```powershell
# 或仓库自带的极简静态服务（Windows，零依赖）
powershell -NoProfile -ExecutionPolicy Bypass -File devtools/serve.ps1 -Port 8019
```

打开 <http://127.0.0.1:8019/> 即可。

### 4. 起后端（社区 / 登录 / 食谱 / 星象）

```bash
node trash/trash.js
# 默认监听 127.0.0.1:10003，对外暴露 /api/*
```

前端通过 `/trashapi` 前缀访问后端（线上由 Nginx 反代）。纯本地静态预览时社区/登录功能不可用，
控制台出现 `/trashapi` 404 属正常现象。

`trash/data/` 会在首次启动时自动创建，无需手工准备数据。

## 配置

敏感配置**不写进代码**，`trash/trash.js` 优先读环境变量，其次读 `trash/config.local.json`
（该文件已被 `.gitignore` 排除）：

| 变量 / 字段 | 用途 | 不配置时 |
| --- | --- | --- |
| `SHOWAPI_KEY` | 万维易源 appKey（星座运势接口） | 运势接口不可用，其它功能正常 |
| `GLM_API_KEY` | 智谱 GLM Key，仅供 Web `/trashapi/api/ai` 服务端代理使用 | Web AI 返回“暂未配置”，其它功能正常 |
| `INVITE_CODE` | 注册邀请码 | 注册不校验邀请码（开放注册） |

```bash
# 环境变量方式
SHOWAPI_KEY=xxx INVITE_CODE=xxx node trash/trash.js

# 或复制模板后填写
cp trash/config.local.example.json trash/config.local.json
```

完整部署步骤见 [`docs/citro-部署上传清单.md`](docs/citro-部署上传清单.md)。

## Windows 构建

前置：VS 2022 Build Tools（C++ 桌面工作负载）、Windows 10 SDK、NuGet CLI、Inno Setup 6（仅打安装包需要）。
构建脚本会自动产出便携版、用户级安装包和更新清单：

```powershell
cd flutter
node tool/build_windows.js
# 产物（均已 gitignore，不入库）：
# WIN/Citro-v1.8.0-win64/            便携版（Citro.exe + data + DLL）
# exe/Citro-v1.8.0-win64-setup.exe   安装包（Inno Setup，安装到 %LOCALAPPDATA%\Programs\Citro，无需管理员）
# exe/update.json                    应用内更新清单（含 size 与 SHA-256）
# 只出便携版：node tool/build_windows.js --no-installer
```

安装器使用 Citro 手账主题和全中文向导：自定义欢迎 / 完成页插画、应用图标、中文语言文件与
“创建桌面快捷方式 / 启动 Citro”等全部文案；安装到当前用户目录，无需管理员权限。

安装包支持静默更新：应用内检查到新版本后，下载到临时目录 → 校验 size + SHA-256 → 启动 Inno Setup →
应用退出 → 静默安装 → 自动拉起新版本。更新安装脚本用 PowerShell 运行，确认 Setup 已启动后应用才退出，
避免脚本被一起结束或旧实例互斥锁挡住重启。

发布更新时，把 `exe/Citro-vX-win64-setup.exe` 和 `exe/update.json` 上传到
`https://obs.chimu-claw.xyz/exe/`（清单中的 `url` 默认指向该目录）。构建时可覆盖：

- `UPDATE_BASE_URL=https://your.host/exe`：修改清单里生成的下载地址
- `WINDOWS_UPDATE_MANIFEST_URL=https://your.host/exe/update.json`：修改应用内检查地址
- 清单字段：`version`、`versionCode`、`url`（HTTPS）、`size`、`sha256`、`notes`、`publishedAt`、`force`

**代码签名**：当前安装包与 exe 未签名，Windows SmartScreen 可能提示“未知发布者”。正式分发建议为
`Citro.exe` 和 setup 配置代码签名证书（Inno Setup 的 `SignTool`），不要在仓库中保存证书/口令。

Windows 端已验证：Win11 21H2 x64 上多比例窗口（800×600 / 1024×768 / 1200×720 / 1600×700 / 800×1000）、
最大化/最小化/还原/拖拽/缩放/单实例、资源库 3 列/2 列、WebView2 极限刹车、AI 代理、定位天气、
全局搜索、应用内更新全链路。Win10 未在真机逐项验证；如需最低版本兼容性验收，请在 Win10 1809+ 上复跑。

## Android 构建

前置：JDK 17+、Android SDK（在 `flutter/android/local.properties` 写 `sdk.dir=...`，该文件不入库）。

```bash
cd flutter
node build.js release     # 产出 ../APK/Citro-v1.8.0-release.apk
```

- v1.8.0 在 v1.7.10 基础上新增 **App 内检查更新**：启动自动检查、应用内下载、进度 / 取消 / 跳过版本、FileProvider 拉起系统安装器；启动页保持纯插画，不显示版本号。v1.7.10 的账号注销、隐私政策 / 用户协议、注册同意勾选、AI 数据披露、社区举报与本地黑名单、120Hz 与小游戏优化全部保留。
- 12 个游戏页（2048 / 记忆卡牌 / 数独 / 数织 / 数字华容道 / 贪吃蛇 / 羊了个羊 / 跳一跳 / 淘气小球 / 极限刹车 / 成语接龙 / 飞花令）按 Web 原版逐像素复刻：390×844 下与 Chrome 参考图均差 0.97~3.65（0~255 灰度），标题 / HUD / 按钮 / 棋盘几何逐行对齐；成语接龙与飞花令的 AI 兜底走 GLM-5.3-Flash 轻度思考（`thinking.type=enabled` + `reasoning_effort=low`）。
- APK：`APK/Citro-v1.8.0-release.apk`（versionCode 1800，versionName 1.8.0，通用 ABI，release 签名与 v1.1.1 相同）；打卡抽签支持 12 张每日轮换卡背与 3D 翻面动画，星象运势全部由 AI 生成。
- 构建内存已限制为 3G 堆 / 768M Metaspace，关闭 Gradle daemon、并行与 VFS 监听；**不要同时运行模拟器和 Gradle 构建**，避免 16G 开发机进入内存/供电压力区。
- 工程路径含中文时，AOT 编译对路径编码敏感：请先执行 `subst X: "C:\网站web\Citro"`，再从 `X:\flutter` 构建（`build.js` 会自动注入 UTF-8 JVM 参数）。
- 签名依赖 `flutter/android/app/key.properties` 与 `密钥/citro-release.jks`，两者只存在本地、**绝不入库**；
  缺失时只能产出 debug 签名的验证包。

## 仓库安全约定

本仓库**不包含**以下内容，克隆后请自行准备：

- 任何密钥、签名文件（`密钥/`、`*.jks`、`keystore.properties`、`.env`、`config.local.json`）
- 线上用户数据（`trash/data/` 下账号、会话、帖子、头像、语音等）
- 构建产物与缓存（`kotlin/app/build/`、`.gradle*`、`assets/www`、`*.apk` 除 `APK/` 内提供下载的版本）
- 第三方大文件下载资源（`小工具/`、`外设驱动/`，体积大且有版权风险，只在服务器上提供）
- 服务端 AI/星象组件（`zodiac-ai/` Python 星盘引擎、`/api/mimo.php` AI 代理）不在本仓库内，
  因此单独 clone 无法完整复现线上的 AI 星象能力

## 文档

- [设计规范](docs/citro-design.md)
- **手账桌面 Paper Desk**（当前视觉）：[执行记录](docs/citro-手账桌面-执行记录.md)、[协作简报](docs/citro-手账桌面-改版简报.md)
- [素材与字体清单](docs/citro-assets.md)
- [手账布局](docs/citro-手账布局说明.md)、[毛玻璃](docs/citro-毛玻璃说明.md)、[视觉精修](docs/citro-视觉精修说明.md)
- [部署上传清单](docs/citro-部署上传清单.md)
- [Android 发版记录](docs/)（`citro-android-v1.0.*.md`）、[Kotlin 原生版交接](docs/迟暮Crew-Kotlin原生版-交接.md)
- [功能规格](docs/compose/spec/)

## 说明

个人项目，代码可自由参考学习。站点内涉及的第三方素材（游戏 Mod 封面、字体子集、客户端图标等）
版权归各自作者所有，请勿直接商用。部署到公网前请务必替换为自己的域名、密钥与用户数据。
