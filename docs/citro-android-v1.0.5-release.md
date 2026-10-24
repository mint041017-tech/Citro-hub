# Citro Android APK · v1.0.5 更新说明（2026-10-19）

> ✅ 真机已确认：v1.0.5 的帧序列启动动画正常。后续收尾版为
> **v1.0.6**（去掉启动页诊断小字 + 新增「启动页 → 首页」过渡动画），
> 详见 `docs/citro-android-v1.0.6-release.md`。

> 关联：v1.0.4 已能正常打开，但用户反馈 **仍然没有启动动画，打开 App 一片空白后直接进软件**。
> v1.0.5 彻底放弃「视频播放」路线，改用 **JPEG 帧序列 + ImageView 换帧** 播放启动动画。

## 1. 版本与产物

| 项 | 值 |
| --- | --- |
| 版本 | `versionName 1.0.5` / `versionCode 1005`（与前版同签名，可直接覆盖安装） |
| 正式包 | `APK/Citro-v1.0.5-release.apk`（12,679,306 字节 ≈ 12.09 MiB） |
| 网站下载入口 | `index.html` 两处 APK 链接已更新为 `/APK/Citro-v1.0.5-release.apk`，文案 `Android · v1.0.5 · 12.1MB` |
| 构建命令 | `cd kotlin && node build.js release` |

## 2. 为什么不再用视频

v1.0.1 → v1.0.4 依次尝试了 VideoView、TextureView + MediaPlayer（1080p → 720p 转码）、
等系统启动页退场后再起播，但用户机上始终「只看到静态 logo / 空白」：

- VideoView / SurfaceView 的视频层在启动页这种「全屏不透明底 + 覆盖层」结构上
  可能被窗口内容盖住；
- TextureView + MediaPlayer 在用户机上表现为黑屏 / 空白（本机无 Android 真机 / 模拟器，
  无法复现具体解码器行为）；
- v1.0.3 的 Android 12+ SplashScreen 退场回调还会在个别 ROM 上直接闪退（v1.0.4 已回退）。

v1.0.5 改为 **完全不依赖视频 / 编解码器 / Surface / 系统启动页 API** 的方案：
把竖屏启动动画逐帧导出成 46 张 JPEG（540×960、15fps、3.04s、共约 2.4MB），
放在 `assets/splash_frames/f_001.jpg … f_046.jpg`；启动时后台单线程逐帧解码，
主线程按 15fps 时间轴贴到全屏 `ImageView`，只保留当前一帧（内存约 2MB）。

任何机型都能画；最差情况（帧资源缺失 / 解码失败）自动回退为「字标 + 副标」静态启动页，
仍然不会白屏或黑屏。

## 3. 启动页行为（v1.0.5）

- 首帧先显示静态字标（淡入上浮），帧图一画出就自然盖住静态层；
- 动画 15fps、约 3 秒；页面首帧可见 + 动画播完 + 至少展示 2.4 秒后才淡出（最长 6.5s 兜底）；
- 启动页底部有一行很淡的 `v1.0.5 · <状态>` 小字（10sp、55% 透明度）：
  - `启动动画播放中`：帧动画正在播放；
  - `动画完成`：动画正常播完；
  - `静态启动页(...)`：动画不可用，已降级（括号内是原因）。
  这行字用于远程反馈定位，后续版本可视情况去掉；
- 自愈守卫保留：连续两次启动没走完启动页，就对当前版本永久降级为静态启动页
  （装新版本自动重试），确保 App 一定能打开。

## 4. 移除 / 保留

| 项 | 变化 |
| --- | --- |
| `res/raw/splash_portrait.mp4` | **移除**（5.2MB 原视频 → 862KB 转码版都不再使用） |
| TextureView / MediaPlayer 播放代码 | **移除**（`classes.dex` 中已无相关引用） |
| `assets/splash_frames/` | 新增 46 张 JPEG（540×960，约 2.4MB） |
| 静态字标 / 启动页兜底 / 自愈守卫 / 版本信息 | 保留 |

## 5. 自检

```powershell
cd C:\网站web\Citro\kotlin
node build.js release
# 期望：✅ stable APK: ...Citro-v1.0.5-release.apk (12.09 MB) / ✅ 根目录 HTML 未被改动
```

APK 校验：

```powershell
aapt2 dump badging APK\Citro-v1.0.5-release.apk | Select-String "package:"
# package: name='com.chimu.crew' versionCode='1005' versionName='1.0.5'

# APK 内应有 46 张 assets/splash_frames/*.jpg，且不再有 .mp4
# dex 中不再包含 MediaPlayer / TextureView / VideoView / setOnExitAnimationListener 引用
```

真机启动日志：

```powershell
adb install -r APK\Citro-v1.0.5-release.apk
adb logcat -c
adb logcat -s CitroSplash AndroidRuntime
```

正常应看到 `frame animation start (46 frames) → frame animation completed → dismiss splash`。
若仍无动画，请把启动页底部那行 `v1.0.5 · ...` 的文字内容截图发回，并附上 logcat。

## 6. 升级与回退

- 直接覆盖安装（同签名，versionCode 1005 > 1004）。
- 回退包：`APK/Citro-v1.0.4-release.apk`（可打开、无动画）、`APK/Citro-v1.0.2-release.apk`。
- 若 v1.0.5 仍异常，请提供 `adb logcat -s CitroSplash AndroidRuntime` 与启动页截图。

## 7. 已知边界

- 本机无 Android 真机 / 模拟器，只验证到「构建通过 + APK 资源/版本号校验 + 帧图资源有效」；
  开屏观感需要真机覆盖安装确认。
- 帧动画为 540×960 @15fps，在 2K 屏上会有轻微放大感（启动页 3 秒，可接受）。
