# Citro 2.0.5

> 版本号 `2.0.5+2005` · 2026-11-05

## 本次更新

### 全端性能

- **Tab 切换**：底部 Tab / 侧栏切页时只有当前页参与动画，页面作为 `AnimatedBuilder`
  的 child 复用；后台页面改用常量动画占位，不再逐帧 build / layout，也不重挂 Element。
- **听隅后台**：页面被其他路由或 Tab 遮挡（`TickerMode` 关闭）时跳过控制器通知触发的
  重建，播放计时与 Web 轮询不再持续重建整页；回到前台由 `didChangeDependencies` 补齐。
- **静态透明层**：清理正常状态下多余的 `Opacity`（胶带 `opacity: 1`、日历格、未解锁关卡格、
  禁用按钮），滚动时减少离屏图层创建。
- **性能探针**：`PerfProbe` 判定从 `!kDebugMode` 改为 `kReleaseMode`，
  `--profile --dart-define=CITRO_PERF_PROBE=true` 可采集真实帧耗时（p50/p90/jank）。

### 说明

- Android / Windows / Web 三端均已重新构建；iOS 完成预打包（见 `docs/ios-预打包清单.md`）。
- 听隅、数独等既有功能与视觉参数未改动。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.5-release.apk` | 95,238,651 B |
| Windows | `Citro-v2.0.5-win64-setup.exe` | 23,587,770 B |
| Web | `Citro-web-2.0.5.zip` | 30,923,240 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`e808d4411cde969f6f6718f968b755c63427204296ca8c225f6af8eb00174e58`
- EXE：`f6fd20bdcb9971aa35a3a0ae688a388664014c99f35fad4ff9ca62b2da058a34`
- WEB：`e20d44f4ca6a0c576cca83168659f5e7e1c0b3ee51bea38d3d7c5892769cff8c`
- 下载站整包：`4b3cd429d301c3d28158437d8161e540965b16a78b187e25736d162b3a8ecf49`

## 发布状态

- OBS 已上传并校验：`APK/Citro-v2.0.5-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.5-win64-setup.exe`、`exe/update.json`、`web/Citro-web-2.0.5.zip`、
  `web/latest.json`、`web/Citro-downloads-2.0.5.zip`、`web/downloads.json`。
- 下载站源码（`download-site/app.js`、`index.html`）已更新到 v2.0.5，`dist/` 已重新构建，
  整包 `Citro-downloads-2.0.5.zip` 已上传 OBS `web/`。
- 公网 `dl.chimu-claw.xyz` 当前仍为 2.0.3，需用整包覆盖站点根后生效（本机无该服务器
  SSH 凭证，未自动执行）。
- 线上 Web 站点如需更新，同样用 `Citro-web-2.0.5.zip` 覆盖站点根（保留 `/trashapi` 与 `/api` 反代）。

## 说明

- Windows 安装包暂未做代码签名，SmartScreen 可能提示“未知发布者”；安装到当前用户目录，无需管理员权限。
- iOS 2.0.5 已完成预打包配置与清单，IPA 需在 macOS + Xcode 上执行 `flutter/ios/build_ipa.sh` 生成。
- 应用内更新清单：`APK/update.json`、`exe/update.json`、`web/latest.json`。