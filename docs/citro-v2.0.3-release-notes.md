# Citro 2.0.3

> 版本号 `2.0.3+2003` · 2026-11-03

## 本次更新

### 全端性能

- **Web 首屏**：CanvasKit 的 `canvaskit.js` / `canvaskit.wasm` 在 HTML 解析阶段就按正确变体
  （Blink 用 `canvaskit/chromium/`）加入预加载队列，与启动脚本并行下载；听隅音频引擎改为
  `defer`，不再阻塞启动脚本发起；OBS 增加 `dns-prefetch` / `preconnect`。
- **列表**：食材库、成语链、飞花令诗句链由一次性构建改为 `ListView.builder`，打开弹层与
  每秒计时的对局不再重建全部条目。
- **图片**：补齐听隅封面、赞赏码、硬币 logo 的解码尺寸；图片磁盘缓存增加启动期 LRU 清理
  （保留最近使用，超过 256 MB 或 60 天未访问的删除）。
- **Android**：新增 `onLowMemory()`，系统整体内存不足时同步清理 Flutter 图片缓存。
- **Web 性能探针**：`perf_probe_web.dart` 从空实现补齐为与原生一致的帧耗时采样，
  传入 `--dart-define=CITRO_PERF_PROBE=true` 即可在控制台查看。

### 数独

- 新增计分明细，结算时可查看基础分、时间与难度等构成。
- 新增对局续玩：暂停退出或被系统回收后可继续上一局。
- 新增最佳用时记录，与最佳分分开保存。

### 其它

- 纸张背景画笔补充 `highlight` / `wallpaper` 比较，主题与壁纸切换不再漏重绘。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.3-release.apk` | 95,238,651 B |
| Windows | `Citro-v2.0.3-win64-setup.exe` | 23,640,063 B |
| Web | `Citro-web-2.0.3.zip` | 30,922,265 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`e2fd753a2dbe0f8f6cae9d365719cfc6f4714ce56e91b74665b902606efe8cbf`
- EXE：`745c7bc4e006b18b7d377513bbad2ba2e2c518b6a8a4e4a0287a4ec128acd860`
- WEB：`f15b6b7da1ef1ec1b4f153c42a705c3917253aab38fafcd5a574e997ed8b9cac`
- 下载站整包：`e626e3b590957e390d2d0f042881f67168ff67da3bac84f8f55d425430fbd10f`

## 说明

- Windows 安装包暂未做代码签名，SmartScreen 可能提示“未知发布者”；安装到当前用户目录，无需管理员权限。
- iOS 2.0.3 已完成预打包配置与清单，IPA 需在 macOS + Xcode 上执行 `flutter/ios/build_ipa.sh` 生成。
- 线上镜像：<https://obs.chimu-claw.xyz/>，应用内更新清单为 `APK/update.json`、`exe/update.json`、`web/latest.json`。
- 下载站整包 `Citro-downloads-2.0.3.zip`（1,088,357 B）已生成并上传 OBS `web/`；
  公网 `dl.chimu-claw.xyz` 需用整包覆盖站点根后生效。