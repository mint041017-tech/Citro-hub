# Citro Android APK · v1.0.6 更新说明（2026-10-19）

> 关联：v1.0.5 的帧序列启动动画已在真机确认正常。v1.0.6 做两件收尾：
> ① 去掉启动页底部的诊断小字；② 给「启动动画结束 → 进入软件」加过渡动画。

## 1. 版本与产物

| 项 | 值 |
| --- | --- |
| 版本 | `versionName 1.0.6` / `versionCode 1006`（同签名，可直接覆盖安装） |
| 正式包 | `APK/Citro-v1.0.6-release.apk`（12,679,356 字节 ≈ 12.09 MiB） |
| 网站下载入口 | `index.html` 两处 APK 链接已更新为 `/APK/Citro-v1.0.6-release.apk`，文案 `Android · v1.0.6 · 12.1MB` |
| 构建命令 | `cd kotlin && node build.js release` |

## 2. 去掉诊断小字

v1.0.5 为了远程定位启动页问题，在启动页底部加了一行 `v1.0.5 · 状态` 的 10sp 小字。
现在真机确认动画正常，v1.0.6 已删除该小字及其状态更新逻辑（`splashDiag` 相关代码清零），
启动页恢复干净画面。

## 3. 新增「启动页 → 首页」过渡动画

原来启动页收起是 220ms 淡出后直接露出首页；v1.0.6 改为 380ms 的交叉过渡：

- **启动页**：透明度 1 → 0，同时轻微放大（1.0 → 1.035），像镜头推进后淡出；
- **网页**：透明度 0.35 → 1，同步淡入（`DecelerateInterpolator` 缓出）；
- 过渡结束才移除启动页 View；WebView 的位置 / 尺寸全程不变，不影响页面布局；
- 若动画 API 异常，直接移除启动页并把网页透明度恢复为 1，不会卡在过渡状态。

时长常量：`ENTER_FADE_MS = 380L`（`MainActivity.kt`）。

## 4. 启动页整体时序

1. 静态字标淡入（首帧兜底）；
2. 帧序列动画播放（46 帧 / 15fps / 约 3.0s，最后定格在小猫画面）；
3. 页面首帧可见 + 动画播完 + 至少展示 2.4s 后 → 进入 380ms 交叉过渡；
4. 过渡结束，启动页移除，进入软件。

最长兜底 6.5s；动画不可用时自动退化为静态启动页 + 同样的过渡。

## 5. 自检

```powershell
cd C:\网站web\Citro\kotlin
node build.js release
# 期望：✅ stable APK: ...Citro-v1.0.6-release.apk (12.09 MB) / ✅ 根目录 HTML 未被改动

aapt2 dump badging APK\Citro-v1.0.6-release.apk | Select-String "package:"
# package: name='com.chimu.crew' versionCode='1006' versionName='1.0.6'
```

- APK 内仍有 46 张 `assets/splash_frames/*.jpg`，无 `.mp4`；
- `classes.dex` 不再含 `splashDiag` 引用，含 `DecelerateInterpolator`（过渡动画）。

真机日志：`adb logcat -s CitroSplash`，正常应看到
`frame animation start (46 frames) → frame animation completed → dismiss splash after 2400+ms`。

## 6. 升级与回退

- 直接覆盖安装（同签名，versionCode 1006 > 1005）。
- 回退包：`APK/Citro-v1.0.5-release.apk`（动画正常、无过渡、带诊断小字）。

## 7. 已知边界

- 本机无 Android 真机 / 模拟器：v1.0.6 只验证到构建 + APK 资源 / 版本号 / dex 引用，
  过渡观感需要真机覆盖安装确认。
- 过渡时长 380ms 是经验值；若实际观感偏慢/偏快，可只改 `ENTER_FADE_MS` 一个常量再打包。
