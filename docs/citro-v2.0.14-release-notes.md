# Citro 2.0.14

> 版本号 `2.0.14+2014` · 2026-11-05

## 本次改动

- **扫码登录**：Web 电脑端、Windows、iPad 登录弹窗新增「扫码登录」，展示 5 分钟有效的一次性二维码；手机 App「我的 → 扫一扫」扫码确认后，电脑端立即登录。
- **手机号 / 邮箱居中**：登录子标签文字严格居中，图标仅作左侧装饰。
- **主题下拉重设计**：「深浅色」改名为「主题」；触发胶囊固定宽度、左对齐，下拉菜单改为圆角卡片和强调色选中态。
- **后台运行设置对齐**：设置行内边距、图标尺寸与其它行统一，右侧 trailing 右对齐。
- 未改动任何已确认的切页动效。

## 产物

| 平台 | 文件 | 大小 | SHA-256 |
| --- | --- | --- | --- |
| Android | `APK/Citro-v2.0.14-release.apk` | 109,845,843 B | `76d22b1312b93686f302181d189faa502b4d390d2a71d6648778d3fa0ed6983e` |
| Windows | `exe/Citro-v2.0.14-win64-setup.exe` | 23,614,902 B | `56438cf8ab3c41e1b3cc24ceab80fa3e070007de7376a0dace0dcb259aead29c` |
| Web | `web/Citro-web-2.0.14.zip` | 39,110,071 B | `901e75b316d0ab2ad4b649be8bff0198d7c372bf0e2ddb3504b3e99989c1280f` |
| 下载站 | `web/Citro-downloads-2.0.14.zip` | 1,088,326 B | `18b10b0839eec55aa7f6b617f14bab968941b7c78b5f87221bd386eac8d894d7` |
| iOS | `docs/ios-预打包清单.md` | — | IPA 待 macOS 生成 |

## 校验

- OBS 已上传并校验：`APK/Citro-v2.0.14-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.14-win64-setup.exe`、`exe/update.json`、
  `web/Citro-web-2.0.14.zip`、`web/latest.json`、
  `web/Citro-downloads-2.0.14.zip`、`web/downloads.json`。
- 所有对象 `Content-Length` 与本地文件一致，ETag（MD5）核对通过。
- 下载站源码与 `dist/` 已更新到 v2.0.14，整包已上传 OBS `web/`。
- `flutter analyze`：0 error / 0 warning；`compliance_smoke_test`、`routes_test` 通过。

## 注意

- 扫码登录依赖新版后端接口，发布前需部署 `trash/trash.js` 并 `pm2 restart trash`。
- Android 引入 mobile_scanner（bundled MLKit），APK 从约 95 MB 增至约 105 MB；国内无 GMS 设备也能扫码。
- iOS 2.0.14 已完成预打包配置与清单，IPA 需在 macOS 上生成。