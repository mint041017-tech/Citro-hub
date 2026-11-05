# Citro 2.0.8

> 版本号 `2.0.8+2008` · 2026-11-05

## 本次更新

### 高刷新率

- **全局高刷**：`main()` 启动即 `RefreshRate.acquire()` 并常驻，首页、列表、弹层与游戏
  都向系统申请屏幕最高刷新率；游戏页的 acquire 叠加在计数器上，退出游戏不会释放全局请求。
- **显示模式**：Android 侧同时写 `preferredRefreshRate` 与 `preferredDisplayModeId`
  （同分辨率下的最高刷新率模式），没有同分辨率高刷模式时只设刷新率，绝不切分辨率。
- **生命周期重申请**：去掉「attributes 相同就 return」，并在 `onResume`、`onPostResume`、
  `onWindowFocusChanged(true)` 重新申请，缓解 HyperOS / MIUI 在切前台后把刷新率重置回 60Hz。
- **诊断**：显示通道新增 `currentRefreshRate`，返回实际 `refresh` / `mode` / `powerSave`。

### 保留 2.0.7 优化

- 退后台暂停社区 / 未读轮询，回前台补齐；
- 「我的 → 通知与外观 → 后台运行设置」入口；
- `ImageStore` 24MB、`GameSfx` 12MB 缓存上限与 `onTrimMemory` 清理；
- 定位兜底回调不再持有 `MainActivity`。

### 说明

- 系统侧仍可能锁 60Hz：省电模式、设置里的刷新率选项、HyperOS 的“应用单独刷新率”。
  LTPO 屏在静态画面降到 60Hz 属于正常行为，应在滚动 / 动画中观察。
- 若一帧 build+raster 超过 8.3ms，实际帧率也会低于 120；可用
  `--profile --dart-define=CITRO_PERF_PROBE=true` 查看 `rasterP90`。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.8-release.apk` | 95,238,671 B |
| Windows | `Citro-v2.0.8-win64-setup.exe` | 23,584,261 B |
| Web | `Citro-web-2.0.8.zip` | 30,925,004 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`523325b975274e9fdb0dd354d6cbf95697982a5896152e6a8dca8cee1136ba0f`
- EXE：`d3e8db218936307080ea6841d9af8e1153fbfd50b3bf3148b86cabec9364eba4`
- WEB：`15be023f82e3bebfefa7407aff745fad2ec76ddac2d7f44b88f3513c9a5dd043`
- 下载站整包：`c29dd7772fa92097f5b2c5accbbd9f27ade887dcb619659f74e3e7f1eca46119`

## 发布状态

- OBS 已上传并校验：`APK/Citro-v2.0.8-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.8-win64-setup.exe`、`exe/update.json`、
  `web/Citro-web-2.0.8.zip`、`web/latest.json`、
  `web/Citro-downloads-2.0.8.zip`、`web/downloads.json`。
- 下载站源码与 `dist/` 已更新到 v2.0.8，整包已上传 OBS `web/`。
- 公网 `dl.chimu-claw.xyz` 需用整包覆盖站点根后生效（由运营者手动执行）。

## 说明

- Windows 安装包暂未做代码签名，SmartScreen 可能提示“未知发布者”；安装到当前用户目录，无需管理员权限。
- iOS 2.0.8 已完成预打包配置与清单，IPA 需在 macOS + Xcode 上执行 `flutter/ios/build_ipa.sh` 生成。
- 应用内更新清单：`APK/update.json`、`exe/update.json`、`web/latest.json`。