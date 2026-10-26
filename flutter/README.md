# Citro · Flutter 原生版（v1.9.1）

Chimu Crew 的 Web / Android / iOS / Windows 客户端。页面与游戏均用 Flutter Widget 原生实现，
视觉按站点 393×852 手账 UI 逐页对齐；Web 的「极限刹车」使用 Flutter 3D 场景，
Android / iOS / Windows 使用内嵌 WebView（Windows 为 WebView2）。

## 功能

- 首页：账号 / 打卡、实时时钟、天气、食谱入口、摸鱼日历、农历日历、今日星象、每日一言
- 游戏：2048、记忆卡牌、数独、数织、数字华容道、贪吃蛇、羊了个羊、跳一跳、淘气小球、极限刹车、成语接龙、飞花令，含成绩榜与「正在玩」在线面板
- 社区：登录/注册、发帖（图文/语音/匿名）、点赞/抱抱/评论回复、收件箱、搜索与筛选
- 食谱日记：食谱库、广场、找菜、冰箱、购物清单、今天吃什么、分步编辑 / 计时 / 下厨日记
- 星象：每日运势、幸运指数与 AI 星语；抽签、灵敏度换算、我的、笔记、资料修改、深浅主题
- 「资源库」：Mod / 工具 / 外设驱动聚合页（iPad 从游戏页底部入口进入；Windows 侧栏/底栏直接进入）
- Windows 桌面端：iPad 同款界面与动效、无边框自绘标题栏、单实例、多比例布局、全站搜索、应用内更新

## 构建

```bash
# 中文路径推荐先映射到 ASCII 盘符
subst X: "C:\网站web\Citro"
cd X:\flutter
node build.js release
```

产物：`../APK/Citro-v1.9.1-release.apk`（versionCode 1901 / versionName 1.9.1，签名与 v1.1.1 相同，可覆盖升级）。

Windows 构建需要 VS 2022 Build Tools（C++ 工作负载）、NuGet CLI 与 Inno Setup 6：

```powershell
# 在 flutter/ 目录
node tool/build_windows.js
# ../WIN/Citro-v1.9.1-win64/            便携版
# ../exe/Citro-v1.9.1-win64-setup.exe   用户级安装包
# ../exe/update.json                    应用内更新清单（含 SHA-256）
```

## Web

```bash
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8019
bash tool/build_web.sh
```

Release 产物为 `build/web/`。桌面宽屏使用侧栏，窄屏使用底部导航；PWA manifest、启动加载页与 Citro 图标位于 `web/`。发布请使用 `tool/build_web.sh`：它固定本地 CanvasKit、删除未使用的 Skwasm/Wimp/WebParagraph 资源并生成 gzip 预压缩文件。Nginx 参考 `../docs/nginx-citro-web.conf` 开启 `gzip_static` 与缓存。

- 浏览器定位需要 HTTPS 或 localhost；拒绝授权后继续使用默认城市天气。
- Web 录音使用浏览器 Opus/WebM，图片选择、语音播放与截图分享使用浏览器能力。
- Web 不包含 Android 应用内更新；浏览器通知需要用户手动授权。
- AI 统一使用 `glm-5.3-flash`、启用 thinking 和 low reasoning effort，浏览器只访问同源 `/trashapi/api/ai`，密钥仅由 Node 服务从 `GLM_API_KEY` 读取。CiCi 对话使用 SSE 流式输出；运势、成语和飞花令等单次判断使用非流式响应。

## 应用内更新（Android）

- App 启动 3 秒后静默检查，只对高于当前 `versionCode` 的版本弹窗；「我的 → 关于 → 检查更新」可手动检查，支持下载进度、取消、跳过此版本和失败重试。
- 版本源：`https://obs.chimu-claw.xyz/APK/update.json`。该文件不存在时回退读取同一 OBS 的 `APK/` 对象列表，所以只上传新 APK 也能被发现。
- `node build.js release` 会生成 `../APK/update.json`，**请和 APK 一起上传**。更新说明每条一行写在 `flutter/update_notes.txt`（可选）；需要强制更新时在生成的 JSON 里把 `force` 改为 `true`。
- 下载完成后通过 FileProvider 拉起系统安装器；Android 8+ 首次需在系统设置中允许 Citro 安装未知应用。

## 应用内更新（Windows）

- 版本源：`https://obs.chimu-claw.xyz/exe/update.json`；`node tool/build_windows.js` 会生成 `../exe/update.json`，与安装包一起上传。
- 应用下载到临时目录后校验 `size` 与 SHA-256，再以 PowerShell 启动 Inno Setup；确认安装器已启动后应用退出，Setup 静默安装并自动拉起新版本。
- 安装包按用户级安装到 `%LOCALAPPDATA%\Programs\Citro`，无需管理员；便携版触发更新时会更新到该目录。
- 未配置代码签名，SmartScreen 可能提示未知发布者；正式分发建议接入 SignTool。
- 详细构建、发布与验证记录见根目录 [`README.md`](../README.md#windows-构建)。

## iOS / IPA

`ios/` 工程已生成并完成非 Mac 配置：Bundle ID `com.chimu.crew`、iPhone 竖屏 + iPad 横竖屏、
定位/麦克风/相机/相册权限文案、通知前台展示、120Hz ProMotion 开关、App 图标、
启动屏、`PrivacyInfo.xcprivacy`、CocoaPods Podfile，以及基于 geolocator/geocoding 的 iOS 定位实现。
首页/游戏/社区/我的/游戏页已加入 iPad 宽屏最大宽度与居中约束，iPad 上保持手机比例的内容区。

最终 IPA 必须在 macOS + Xcode 上签名构建，剩余步骤见
[`../docs/ios-mac-checklist.md`](../docs/ios-mac-checklist.md)。快捷构建脚本：
`bash ios/build_ipa.sh`（需先设置 Team、CocoaPods 与 GLM Key）。

- 后端：`https://chimu-claw.xyz/trashapi`（`lib/services/api.dart`）
- 包名 / Bundle ID：`com.chimu.crew`；Android minSdk 24 / targetSdk 36；iOS 15.0+
- 字体子集：Kalam / ZCOOL KuaiLe / Caveat / Noto Sans SC（`assets/fonts`，按代码字符集裁剪）
- 测试：`flutter test`（截图测试脚本已移除，避免 CI 依赖 goldens）
