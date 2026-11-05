# Citro 2.0.15

> 版本号 `2.0.15+2015` · 2026-11-05

## 本次改动

- **我的页**：移除「编辑资料」快捷卡片；顶部头像卡片仍可进入「更改信息」。
- **主题下拉**：触发胶囊缩短到 118（Web）/ 110（移动端），下拉菜单缩短到 152/144。
- **Windows 左下角头像**：侧栏底部与 Duo 右侧栏改用 `AppImage`，优先读磁盘缓存；加载中显示昵称首字，失败回落首字母，不再空白。
- 2.0.14 的扫码登录、手机端扫一扫、登录子标签居中、后台设置行对齐全部保留。
- 未改动任何已确认的切页动效。

## 产物

| 平台 | 文件 | 大小 | SHA-256 |
| --- | --- | --- | --- |
| Android | `APK/Citro-v2.0.15-release.apk` | 109,845,847 B | `ee221fd500f4721c39a0120022faa40e3a8d66a470d50d3128bb56585a3c9b58` |
| Windows | `exe/Citro-v2.0.15-win64-setup.exe` | 23,613,100 B | `e07f87c0f2533aab718ffdb4a34f04f848c29d4dc8235eced0ce9c3b246accff` |
| Web | `web/Citro-web-2.0.15.zip` | 39,109,975 B | `9a4cd5f87796c396999c061b2429cedb98f75639ed78c89a17b96de759dc49ef` |
| 下载站 | `web/Citro-downloads-2.0.15.zip` | 1,088,752 B | `8e5ed3268936867d9cbbb1df1f7914c9c48d1b269cef90640eacb36a094ff744` |
| iOS | `docs/ios-预打包清单.md` | — | IPA 待 macOS 生成 |

## 校验

- OBS 已上传并校验：`APK/Citro-v2.0.15-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.15-win64-setup.exe`、`exe/update.json`、
  `web/Citro-web-2.0.15.zip`、`web/latest.json`、
  `web/Citro-downloads-2.0.15.zip`、`web/downloads.json`。
- 所有对象 `Content-Length` 与本地文件一致，ETag（MD5）核对通过。
- `flutter analyze`：0 error / 0 warning；`compliance_smoke_test`、`routes_test` 通过。

## 注意

- 扫码登录依赖新版后端接口，若线上尚未部署 `trash/trash.js`，需先部署并 `pm2 restart trash`。
- iOS 2.0.15 已完成预打包配置与清单，IPA 需在 macOS 上生成。