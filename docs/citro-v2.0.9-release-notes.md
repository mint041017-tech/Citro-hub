# Citro 2.0.9

> 版本号 `2.0.9+2009` · 2026-11-05

## 本次更新

### 流畅度

- **切 Tab**：去掉整页 `Opacity` 淡入（280ms 动画里每帧一次全屏 `saveLayer`），
  只保留 8px 位移 + 0.992→1 缩放；切页前先把 `_tabAnim.value` 归零，再
  `await endOfFrame` 等新页完成首帧 build/layout，最后启动动画，避免
  “构建整页 + 动画”挤在同一帧，也避免先显示 t=1 再跳回起点的闪动。
- **我的页滑动**：`_rows` 设置卡片（Web / 非 Web 两个分支）、个人资料卡、
  快捷入口分别加入 `RepaintBoundary`。滚动时只平移图层，不再重绘阴影、
  边框与文字。
- **保留 2.0.8**：全局 120Hz 申请、`preferredDisplayModeId`、回前台/切焦点重申请。

### 验证

- `flutter analyze`：0 error / 0 warning。
- `home_layout_smoke`、`windows_layout`、`motion`、`web_desktop` 通过。
- `flutter build apk --release` 编译通过。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.9-release.apk` | 95,238,671 B |
| Windows | `Citro-v2.0.9-win64-setup.exe` | 23,585,576 B |
| Web | `Citro-web-2.0.9.zip` | 30,924,927 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`df37437c3c87bf89d2d6db6bcbd224966138970e8b9d9c318e284184d8e230ba`
- EXE：`7dc2f87f95d83c4af363e28bff3a18149db569b900bf0f4e0bdae93f0873c8ca`
- WEB：`78374f61a61c59f1917054717ea2967e959dc084ddb2943bd06f84f5fee102ba`
- 下载站整包：`1736a0780e4ccb367cc24dc41032db335e48059c80a009f78577ac2fd816ec55`

## 发布状态

- OBS 已上传并校验：`APK/Citro-v2.0.9-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.9-win64-setup.exe`、`exe/update.json`、
  `web/Citro-web-2.0.9.zip`、`web/latest.json`、
  `web/Citro-downloads-2.0.9.zip`、`web/downloads.json`。
- 下载站源码与 `dist/` 已更新到 v2.0.9，整包已上传 OBS `web/`。
- 公网 `dl.chimu-claw.xyz` 需用整包覆盖站点根后生效。

## 说明

- 首次切到社区/我的时，页面首次挂载仍有一次构建成本；本版已把这次构建
  提前到动画开始前完成。若仍偶发掉帧，可继续做启动后空闲预热页面。
- Windows 安装包未做代码签名，SmartScreen 可能提示“未知发布者”。
- iOS 2.0.9 已完成预打包配置与清单，IPA 需在 macOS 上生成。
- 应用内更新清单：`APK/update.json`、`exe/update.json`、`web/latest.json`。