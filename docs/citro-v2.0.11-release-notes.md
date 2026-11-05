# Citro 2.0.11

> 版本号 `2.0.11+2011` · 2026-11-05

## 本次更新

### 切 Tab / 导航栏掉帧

- **导航栏图标预构建**：`_TabBtn` 的 `TweenAnimationBuilder` 把
  `AppIcon(strokeSvg(...))` 作为 `child` 只构建一次，builder 每帧只做
  `Transform.scale`。此前每帧都会重新生成并解析 5 个 SVG 字符串。
- **切页只平移**：由「位移 + 0.992→1 缩放」改为**只做 8px 平移**。
  整页缩放会让 `RepaintBoundary` 的 raster cache 每帧失效，动画期间等于
  反复重光栅化整页；轴对齐平移可以复用图层缓存。
- **保留 2.0.10**：页面实例缓存、空闲预热（游戏 / 我的 / 社区）。

### 验证

- `flutter analyze`：0 error / 0 warning。
- `home_layout_smoke` 通过。
- `flutter build apk --release` 编译通过。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.11-release.apk` | 95,238,679 B |
| Windows | `Citro-v2.0.11-win64-setup.exe` | 23,586,667 B |
| Web | `Citro-web-2.0.11.zip` | 30,925,435 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`eceeb2291f543d5a70791e423b1c6a3fa29fc4a6bac865cee6184adebb745d03`
- EXE：`687b2cb48923f7fa43c6bbd1c99b425b398b5d1189ea735c36b9bc2aefefff4e`
- WEB：`be811a97661a1cb549753f05c2f64793323b4e89ad3b4e1073d67ca2bade8148`
- 下载站整包：`1aede5d4ad27930a39eeed6230fa168134ebe406f6764dd0279823bb29bdaf33`

## 发布状态

- OBS 已上传并校验：`APK/Citro-v2.0.11-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.11-win64-setup.exe`、`exe/update.json`、
  `web/Citro-web-2.0.11.zip`、`web/latest.json`、
  `web/Citro-downloads-2.0.11.zip`、`web/downloads.json`。
- 下载站源码与 `dist/` 已更新到 v2.0.11，整包已上传 OBS `web/`。
- 公网 `dl.chimu-claw.xyz` 需用整包覆盖站点根后生效。

## 说明

- 导航栏图标的颜色不再逐帧插值（直接切换到目标色），缩放动画保留。
- 若仍有掉帧，用 `--profile --dart-define=CITRO_PERF_PROBE=true` 查看
  `tab_*` 的 `buildP90` / `rasterP90`，区分构建还是绘制瓶颈。
- Windows 安装包未做代码签名，SmartScreen 可能提示“未知发布者”。
- iOS 2.0.11 已完成预打包配置与清单，IPA 需在 macOS 上生成。
- 应用内更新清单：`APK/update.json`、`exe/update.json`、`web/latest.json`。