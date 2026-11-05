# Citro 2.0.7

> 版本号 `2.0.7+2007` · 2026-11-05

## 本次更新

### HyperOS / MIUI 适配

- **前后台轮询**：App 退到后台暂停未读与社区动态轮询，回前台立即补一次；
  社区页同时结合 `TickerMode` 与 `AppLifecycleState`（新增 `WidgetsBindingObserver`），
  后台不再每 60 秒请求收件箱。
- **后台运行设置**：「我的 → 通知与外观」新增 Android 专属入口，先说明 HyperOS 省电策略，
  再跳转系统「应用信息」页，用户可按需设为「无限制」。
- **手势返回**：Manifest 启用 `enableOnBackInvokedCallback="true"`，适配 Android 预测性返回。
- 已有能力保持：高刷新率申请（`preferredRefreshRate` + `onResume` 重申请）、
  精确闹钟不可用时降级 `inexactAllowWhileIdle`、通知渠道 `Importance.high`、
  字体缩放 clamp（0.9–1.15）。

### 内存

- `ImageStore` 内存图片缓存增加 **24MB 总字节上限**（原来只限 80 条）。
- `GameSfx` 合成音缓存增加 **12MB 总字节上限**，超限按插入顺序淘汰。
- `onTrimMemory` / `onLowMemory` 时连同自建图片缓存一起释放（原来只清 Flutter `imageCache`）。
- 修复 `MainActivity` 定位兜底回调（8 秒 `postDelayed`）持有 Activity 的问题，
  `onDestroy` 中移除回调并清空 `pendingResult` / `memoryChannel`。

### 说明

- Android / Windows / Web 三端均已重新构建；iOS 完成预打包（见 `docs/ios-预打包清单.md`）。
- 保留 2.0.6 的 const 补齐、铃渡选关懒加载、切页局部重建与听隅后台暂停刷新。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.7-release.apk` | 95,238,671 B |
| Windows | `Citro-v2.0.7-win64-setup.exe` | 23,586,825 B |
| Web | `Citro-web-2.0.7.zip` | 30,924,889 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`d9561b95cec127ac3b02640cfc4f4979d6bc033fdb364231c0a03a63b44f388e`
- EXE：`243cbddb098ab9f60e3d95ca9c64d24359aa65387eded62b5d5f39c8ce329dc9`
- WEB：`aa295c09edea2ae6973690d054b926349b8cafbc016efade6f508222f1b84fc6`
- 下载站整包：`3907225acdd2dbdca2ff2da00ca1a5228f0d3ced182fbd0faab76681a35d66d7`

## 发布状态

- OBS 已上传并校验：`APK/Citro-v2.0.7-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.7-win64-setup.exe`、`exe/update.json`、
  `web/Citro-web-2.0.7.zip`、`web/latest.json`、
  `web/Citro-downloads-2.0.7.zip`、`web/downloads.json`。
- 下载站源码与 `dist/` 已更新到 v2.0.7，整包已上传 OBS `web/`。
- 公网 `dl.chimu-claw.xyz` 需用整包覆盖站点根后生效（由运营者手动执行）。

## 说明

- Windows 安装包暂未做代码签名，SmartScreen 可能提示“未知发布者”；安装到当前用户目录，无需管理员权限。
- iOS 2.0.7 已完成预打包配置与清单，IPA 需在 macOS + Xcode 上执行 `flutter/ios/build_ipa.sh` 生成。
- 应用内更新清单：`APK/update.json`、`exe/update.json`、`web/latest.json`。