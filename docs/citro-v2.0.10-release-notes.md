# Citro 2.0.10

> 版本号 `2.0.10+2010` · 2026-11-05

## 本次更新

### 切 Tab 掉帧（继续修复）

- **页面实例缓存**：RootShell 在 `initState` 中 `_pages = List.generate(5, _pageAt)`，
  页面 Widget 只创建一次。此前每次切 Tab 都会新建 `HomePage` / `CommunityPage`
  实例，导致所有已挂载页面被 update 并重新 `build()`；现在只有 `TickerMode`
  依赖者会刷新。
- **空闲预热**：启动后错开时间预挂载其余 Tab（1.2s 游戏 / 2.0s 我的 / 2.8s 社区），
  以 `Offstage` 完成首次 build/layout，首次切过去不再现场构建。
  预热定时器在 `dispose` 统一取消。
- **保留 2.0.9**：切页去掉整页 `Opacity`（避免每帧全屏 `saveLayer`）、
  先 `endOfFrame` 再启动动画；我的页卡片加入 `RepaintBoundary`。

### 验证

- `flutter analyze`：0 error / 0 warning。
- `home_layout_smoke`、`windows_layout` 通过。
- `flutter build apk --release` 编译通过。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.10-release.apk` | 95,238,675 B |
| Windows | `Citro-v2.0.10-win64-setup.exe` | 23,590,864 B |
| Web | `Citro-web-2.0.10.zip` | 30,925,450 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`118bf08775b06846facd0cae6d18ab02174909d2f1bc59fb4ce266e20bfd79d6`
- EXE：`5540c7cae18443428ef6461ae07bcf163661584857227d23fbb28efbbcaab0c6`
- WEB：`5923defca575eccd2d5da8849abc0d9980fbff653244d38abbc0792713ff4442`
- 下载站整包：`cd0e7c1e3524521de0fabb2a75ef93fa5397b535490c925f1a5f212acad69656`

## 发布状态

- OBS 已上传并校验：`APK/Citro-v2.0.10-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.10-win64-setup.exe`、`exe/update.json`、
  `web/Citro-web-2.0.10.zip`、`web/latest.json`、
  `web/Citro-downloads-2.0.10.zip`、`web/downloads.json`。
- 下载站源码与 `dist/` 已更新到 v2.0.10，整包已上传 OBS `web/`。
- 公网 `dl.chimu-claw.xyz` 需用整包覆盖站点根后生效。

## 说明

- 预热社区页会顺带预取动态；游客不会发请求。
- 若仍有掉帧，用 `--profile --dart-define=CITRO_PERF_PROBE=true` 查看
  `tab_*` 的 `buildP90` / `rasterP90`，区分构建还是绘制瓶颈。
- Windows 安装包未做代码签名，SmartScreen 可能提示“未知发布者”。
- iOS 2.0.10 已完成预打包配置与清单，IPA 需在 macOS 上生成。
- 应用内更新清单：`APK/update.json`、`exe/update.json`、`web/latest.json`。