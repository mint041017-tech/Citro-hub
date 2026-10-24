# Citro Android APK · v1.0.4 更新说明（2026-10-19）

> ⚠️ **已被 v1.0.5 取代**：v1.0.4 能正常打开，但用户机上仍无启动动画（打开一片空白）。
> v1.0.5 已彻底放弃视频播放，改用 JPEG 帧序列播放启动动画。
> 真机请安装 **`APK/Citro-v1.0.5-release.apk`**；详见 `docs/citro-android-v1.0.5-release.md`。

> 关联：v1.0.3 修复「启动动画不显示」后，用户反馈 **App 装上后直接无法打开**（启动即崩溃）。
> v1.0.4 定位为「v1.0.3 回归修复 + 启动页防崩自愈」，目标是先保证 **App 一定能打开**，
> 再让启动动画正常播放。

## 1. 版本与产物

| 项 | 值 |
| --- | --- |
| 版本 | `versionName 1.0.4` / `versionCode 1004`（与 v1.0.3 同签名，可直接覆盖安装） |
| 正式包 | `APK/Citro-v1.0.4-release.apk`（11,026,452 字节 ≈ 10.52 MiB） |
| 网站下载入口 | `index.html` 两处 APK 链接已更新为 `/APK/Citro-v1.0.4-release.apk`，文案 `Android · v1.0.4 · 10.5MB` |
| 构建命令 | `cd kotlin && node build.js release` |

## 2. v1.0.3 为什么打不开（已定位 / 已回退）

v1.0.3 启动动画改动里唯一涉及平台生命周期的是 **Android 12+ SplashScreen 退场监听**：
`Activity.getSplashScreen().setOnExitAnimationListener { provider -> provider.remove() }`。
在部分 ROM / 系统版本上，这个「手动接管系统启动页退场」的路径会触发
**平台层 SurfaceControl 相关的崩溃**（系统启动页 view provider 的 remove 路径已知不稳定），
表现为启动瞬间闪退、App 完全打不开。v1.0.4 已**整段回退**该 API，改回
「窗口焦点 + 1.2s 定时」起播，不接管系统启动页。

同时，v1.0.4 对所有新加的 Surface / MediaPlayer / 焦点回调都套了 `runCatching`：
任何异常只降级成静态字标，绝不让异常冒到主线程导致闪退。

## 3. 启动页防崩自愈（新）

即使未来某个机型的硬件解码器在播放启动视频时发生 **native 崩溃**（Java 层 catch 不到），
App 也不会「装上就再也打不开」：

- 启动时写标记文件 `splash_incomplete.flag`，启动页正常收掉时删除；
- 下次启动发现标记还在（上次启动在启动页阶段崩溃 / 卡死）→ 记一次连续失败；
- **连续失败 ≥ 2 次** → 写 `splash_video_off.flag`（内容 = 当前 versionCode），
  之后启动**不再创建播放器**、只显示「字标 + 副标」静态启动页，保证 App 一定能进站；
- off 标记只对写入时的 versionCode 生效：**装上新版本会自动重新尝试动画**；
- 正常用户（启动动画播完）永远不会触发这套降级。

## 4. 保留的 v1.0.3 有效改动

- 播放器仍是 **TextureView + MediaPlayer**（解决 VideoView / SurfaceView 图层被窗口内容盖住）；
- 启动视频仍是 **720×1280 / H.264 Constrained Baseline / Level 3.1 / 24fps / 无音轨 / 862KB**
  （解决 1080p Main@L5.0 在老机型 / 低端解码器上解码失败）；
- 静态字标**等视频真正解码出第一帧后才淡出**（解码失败时字标仍在，不空屏）；
- 所有启动页相关回调异常都只降级、不崩溃；
- `buildSplash()` 自身失败时退回「只有奶油底」的最小 View，绝不闪退。

## 5. 自检

```powershell
cd C:\网站web\Citro\kotlin
node build.js release
# 期望：✅ stable APK: ...Citro-v1.0.4-release.apk (10.52 MB) / ✅ 根目录 HTML 未被改动

aapt2 dump badging APK\Citro-v1.0.4-release.apk | Select-String "package:"
# package: name='com.chimu.crew' versionCode='1004' versionName='1.0.4'
```

APK 内 `classes.dex` 已不再包含 `setOnExitAnimationListener`；仍含 `TextureView`；
启动视频仍为 861,711 字节（H.264 Baseline / L3.1 / 720×1280 / 无音轨）。

真机启动日志：

```powershell
adb install -r APK\Citro-v1.0.4-release.apk
adb logcat -c
adb logcat -s CitroSplash AndroidRuntime
```

正常应看到 `splash inflate done → texture available → video prepared → window focused → video start → fade static logo → video completed → dismiss splash`；
如果看到 `splash video disabled ...` 说明自愈降级生效（静态启动页），App 仍可正常进站。

## 6. 升级与回退

- 覆盖安装 v1.0.4 即可（同签名、versionCode 1004 > 1003，无需卸载 v1.0.3）。
- 若 v1.0.3 处于崩溃状态，直接安装 v1.0.4 覆盖即可；个别 ROM 若提示降级/签名异常，可先卸载再装（会丢 WebView 本地缓存，账号 token 在 localStorage 里也会丢，需重新登录）。
- 兜底回退包：`APK/Citro-v1.0.2-release.apk`（可正常打开、无启动动画）与 `APK/Citro-v1.0.1-release.apk`。
- 若 v1.0.4 仍闪退，请提供 `adb logcat -b crash` 或 `adb logcat -s AndroidRuntime CitroSplash` 的完整输出。

## 7. 已知边界

- 本机无 Android 真机 / 模拟器，v1.0.4 只做到构建通过 + dex / 资源 / 版本号校验；
  开屏观感与稳定性需要真机覆盖安装确认。
- 启动页自愈降级后只显示静态字标（无动画）；要恢复动画需安装新版本（versionCode 变化）或清除 App 数据。
