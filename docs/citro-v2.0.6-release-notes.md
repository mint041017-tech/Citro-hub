# Citro 2.0.6

> 版本号 `2.0.6+2006` · 2026-11-05

## 本次更新

### 性能（按 Flutter 10 条性能清单补漏）

- **const**：启用 `prefer_const_constructors` 审计后自动修复 125 处静态 Widget，
  并清理 32 处冗余 `const`，减少重复构建与对象分配。
- **列表懒加载**：铃渡选关页由「一次铺开 78 关」改为 `ListView.builder`，
  按 4 列切成行，只构建当前可见行；章节标题、间距与进度显示保持原样。
- **保留 2.0.5 优化**：Tab 切换只重建当前页（页面作为动画 child 复用）、
  听隅后台暂停刷新、静态 `Opacity` 层清理、性能探针支持 profile 模式。

### 说明

- Android / Windows / Web 三端均已重新构建；iOS 完成预打包（见 `docs/ios-预打包清单.md`）。
- 本次不改变布局、颜色、动画时长与交互。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.6-release.apk` | 95,238,651 B |
| Windows | `Citro-v2.0.6-win64-setup.exe` | 23,584,641 B |
| Web | `Citro-web-2.0.6.zip` | 30,923,835 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`dd1384d003bd9947543f4cfdf0cb65d90319fbdf0eda0a2870e9366f24b67a8d`
- EXE：`5edb571289e95d62d642d6919e72a361ee295b732a832a0a155eb441a8011d96`
- WEB：`1c067e67087e31002fa5d1e1d02943abc5007e40294853d621fd831d5421dbdf`
- 下载站整包：`beaaa485917763919b0c802f794eefb7e85e480db5cec95863b4de597be66292`

## 发布状态

- OBS 已上传并校验（大小一致、整包 SHA-256 回验一致）：
  `APK/Citro-v2.0.6-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.6-win64-setup.exe`、`exe/update.json`、
  `web/Citro-web-2.0.6.zip`、`web/latest.json`、
  `web/Citro-downloads-2.0.6.zip`、`web/downloads.json`。
- 下载站源码与 `dist/` 已更新到 v2.0.6，整包已上传 OBS `web/`。
- 公网 `dl.chimu-claw.xyz` 需用整包覆盖站点根后生效（本机无该服务器 SSH 凭证，由运营者手动执行）。

## 说明

- Windows 安装包暂未做代码签名，SmartScreen 可能提示“未知发布者”；安装到当前用户目录，无需管理员权限。
- iOS 2.0.6 已完成预打包配置与清单，IPA 需在 macOS + Xcode 上执行 `flutter/ios/build_ipa.sh` 生成。
- 应用内更新清单：`APK/update.json`、`exe/update.json`、`web/latest.json`。