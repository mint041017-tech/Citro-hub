# Citro 3.6.0 发版记录

> 版本号：`3.6.0+3600` · 2026-11-28
> 汇总区间：3.5.2 → 3.6.0

## 依恋测试（十二系亲密关系测评）接入 CiCi 分析与分享

- 新增 `KeiAi.insight`：调用 `AiService.complete` 结合当前依恋主型/次型、四维得分与依恋记录生成个性化解读，并持久化回 `KeiRecord.aiInsight`（`KeiStore.update`）。
- 新增 `KeiShareCard` 与结果长图分享：在结果页新增「分享结果」按钮，支持将测评结果长图（含二维码与 `keiTestUrl`）截图导出/分享，并支持预览分享卡片。

## MBTI 测评接入作答效度审计

- 新增 `MbtiAudit` 与 `MbtiScoring.score(..., timingsMs)`：基于 Curran 测量效度指标（答题速度/过快比例、作答连续重复率等）评估答题有效性与可信度。
- `MbtiPage` 采集每题作答耗时，并在结果页新增「测量效度审计」卡片，直观展示作答节奏、效度等级与异常提示。

## 全局毛玻璃视觉调校

- 将全局液态玻璃（`LiquidGlass`、`PaperDialog`、`PaperSheet`、`AiChat`、`WeatherSheet`、`TodoMood` 等）向柔和毛玻璃质感调校。
- 保持浅色模式通透度（`0x8CFFFFFF` / `.58-.44`），并单独提升深色模式下的玻璃通透与层次感。

## 四端打包

| 平台 | 文件 |
| --- | --- |
| Android | `APK/Citro-v3.6.0-release.apk`（arm64-v8a）、`APK/update.json` |
| Windows | `exe/Citro-v3.6.0-win64-setup.exe`、`exe/update.json`、`WIN/Citro-v3.6.0-win64/` |
| Web | `web/Citro-web-3.6.0.zip`、`web/latest.json` |
| 下载站 | `web/Citro-downloads-3.6.0.zip`、`web/downloads.json` |
| iOS | 预打包完成，IPA 待 macOS / TestFlight CI 生成 |

## 校验

| 文件 | 字节 | SHA-256 |
| --- | --- | --- |
| Citro-v3.6.0-release.apk | 65,774,356 | `968d884db03cfd70fdc8423a7a4eae3871dcdd0892ad6cd9c00f597a087f619a` |
| Citro-v3.6.0-win64-setup.exe | 82,433,917 | `8e27c19e4bf71c7217a39b146f480db0e9557b3b7bb9346ce6e5bb34143d93b1` |
| Citro-web-3.6.0.zip | 45,719,460 | `e5c177a0c687f2bafbc6d1e07277aa6e1b8438b1df95d5d8ac0fe583907490be` |
| Citro-downloads-3.6.0.zip | 1,088,846 | `b15e10e1b5a3cb529adf1c023813f1ccfb6d3a584ea506138bf99792d2067a04` |

- `flutter analyze lib`：0 error（152 条既有 warning / info）。
- Android：arm64-v8a 单 ABI，versionCode 3600，`CN=Citro` 签名，Impeller 开启；APK 65,774,356 字节（62.7 MB）。
- Windows：便携版 188.1 MB，Inno Setup 用户级安装包 82,433,917 字节（78.6 MB），更新清单含 SHA-256。
- Web：CanvasKit 本地分发与预压缩产物，`build_id` = `main.dart.js` MD5 `317065abdf2885411dac250ca3ddede4`。
- 下载站：版本号、大小、SHA-256 与 3.6.0 更新日志同步。
- iOS：Windows 环境完成版本、工程配置、权限文案与预打包清单核对，IPA 由 macOS / TestFlight CI 生成。
