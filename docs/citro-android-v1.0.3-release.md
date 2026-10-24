# Citro Android APK · v1.0.3 更新说明（2026-10-19）

> ⚠️ **已被 v1.0.4 取代**：v1.0.3 的启动动画改动在部分机型上导致「App 装上直接打不开」
> （Android 12+ SplashScreen 退场监听触发平台崩溃）。v1.0.4 已回退该 API 并加上
> 「启动页防崩自愈」；真机请安装 **`APK/Citro-v1.0.4-release.apk`**。
> 详见：`docs/citro-android-v1.0.4-release.md`。

> 关联：v1.0.2 曾尝试修复「开屏动画不显示」，但用户覆盖安装 v1.0.2 后反馈
> **仍然只显示 logo、启动动画没出来**。v1.0.3 按「图层 / 解码兼容 / 起播时机」
> 三条线同时加固，并重新转码启动视频。

## 1. 版本与产物

| 项 | 值 |
| --- | --- |
| 版本 | `versionName 1.0.3` / `versionCode 1003`（与 v1.0.2 同签名，可直接覆盖升级） |
| 正式包 | `APK/Citro-v1.0.3-release.apk`（11,026,379 字节 ≈ 10.52 MiB） |
| 网站下载入口 | `index.html` 两处 APK 链接已更新为 `/APK/Citro-v1.0.3-release.apk`，文案 `Android · v1.0.3 · 10.5MB` |
| 构建命令 | `cd kotlin && node build.js release` |

## 2. 这次到底改了什么

### 2.1 播放器：VideoView → TextureView + MediaPlayer

`VideoView` 是 `SurfaceView` 系：视频画面在独立的 Surface 层，默认位于窗口内容之下。
启动页是「全屏不透明奶油底 + 静态字标覆盖层」的结构，在部分机型 / 系统启动页过渡
过程中，视频层会被窗口内容整块盖住 —— 用户看到的就是静态 logo，动画完全不出现。

v1.0.3 改为 `TextureView + MediaPlayer`：TextureView 是普通 View，随窗口内容一起
合成，不存在 Surface 图层被盖住的问题；画面用 `Matrix` 做 center-crop 铺满，
不会出现黑边/变形。

### 2.2 视频转码：兼容低端 / 老机型解码器

旧启动视频：1080×1920、H.264 **Main**、**Level 5.0**、24fps、13.6 Mbps、AAC 立体声。
部分手机 / 系统解码器对声明的 Level 上限更严格，或码率过高，会直接回调
`MediaPlayer.OnErrorListener` → 触发「回退静态 logo」分支，表现同样是动画不显示。

新启动视频（`kotlin/app/src/main/res/raw/splash_portrait.mp4`，5.2MB → 862KB）：

| 参数 | 旧 | 新 |
| --- | --- | --- |
| 分辨率 | 1080×1920 | **720×1280**（同 9:16） |
| 编码 / Profile | H.264 Main | **H.264 Constrained Baseline** |
| Level | 5.0 | **3.1** |
| 帧率 | 24 fps | 24 fps |
| 码率 | 13.6 Mbps | **2.27 Mbps** |
| 音轨 | AAC 立体声 | **无**（启动页本来就静音） |
| 时长 | 3.04s | 3.042s（不变） |
| 大小 | 5,235,936 B | 861,711 B |

### 2.3 起播时机：Android 12+ 等系统启动页真正退场

Android 12+ 的系统 SplashScreen 会盖在应用窗口上；窗口焦点回调在部分机型上
早于系统启动页退场，3 秒动画会在启动页背后播完。v1.0.3：

- API 31+ 注册 `splashScreen.setOnExitAnimationListener`，在系统启动页退场回调里
  调用 `provider.remove()` 并起播；
- 保留 `onWindowFocusChanged` 与 1.2s 定时器兜底（低版本 / 回调异常）；
- 静态字标不再「start() 后 200ms 就淡出」，改为**等 TextureView 真正解码出第一帧**
  （`onSurfaceTextureUpdated`）才淡出，700ms 兜底 —— 解码失败时字标仍在，不会空屏。

### 2.4 其他

- 版本号 1.0.2 → 1.0.3（覆盖安装 / 侧载不会因同版本被拦）。
- 网站 `index.html` 两处 APK 下载链接与体积文案同步更新。
- `docs/citro-部署上传清单.md` 同步新 APK 文件名与体积。

## 3. 自检方法

```powershell
cd C:\网站web\Citro\kotlin
node build.js release
```

构建日志末尾应为 `✅ stable APK: ...Citro-v1.0.3-release.apk (10.52 MB)` 且
`✅ 根目录 HTML 未被改动`。

APK 参数核对（aapt2 在 `C:\Android\Sdk\build-tools\<版本>\`）：

```powershell
aapt2 dump badging APK\Citro-v1.0.3-release.apk | Select-String "package:"
# package: name='com.chimu.crew' versionCode='1003' versionName='1.0.3'
```

启动视频已随 APK 更换：解包 `res/` 下的 mp4 应为 861,711 字节、H.264 profile 66
（Baseline）/ level 31（3.1）、720p 左右、无 `mp4a` 音轨。

真机验证（覆盖安装 v1.0.3 后）：

```powershell
adb install -r APK\Citro-v1.0.3-release.apk
adb logcat -c
adb logcat -s CitroSplash
```

正常应依次看到：

```
sdk=xx, splash inflate done
texture available 1080x1920            ← TextureView 就绪
video prepared
system splash exit / window focused ... ← 起播时机
video start
fade static logo                       ← 视频真正出帧后才淡出字标
video completed
dismiss splash after 2400+ms
```

若仍未出现动画，请保留 `adb logcat -s CitroSplash` 的完整输出（重点看有没有
`video error what=...` / `prepare player failed` / `video waiting surface`），
按日志继续定位。

## 4. 已知边界

- 本次没有真机 / 模拟器可用，Android 端只做到「构建通过 + APK 资源/参数校验」；
  实际开屏观感需要覆盖安装后在手机上确认。
- 启动动画为 3.04s，启动页最短展示 2.4s、最长兜底 6.5s；页面加载极慢时动画仍会
  正常先播完，不会被截断。
- 启动页视频仍只有竖屏一套（手机壳）；横屏平板沿用同一套，居中裁剪。
