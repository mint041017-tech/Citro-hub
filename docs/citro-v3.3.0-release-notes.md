# Citro 3.3.0 发版记录

> 版本号：`3.3.0+3300` · 2026-11-22
> 汇总区间：3.2.1 → 3.3.0

## MBTI 人格测试

- 上线 96 题 MBTI 测试，入口只保留单套测试，不再展示快速版 / 标准版 / 完整版等版本措辞。
- 结果页按实际维度分生成“专属人格切片”，补充更细的行为倾向与关系提示。
- 结果分享改为一键生成 PNG 长图，卡面包含测试链接二维码与五维数据，可直接调起系统分享。
- 图鉴、历史记录与类型详情接入轻量转场：进入 210ms、返回 140ms，退出不再拖沓。
- 历史记录按账号同步：同 id 按 `updatedAt` 合并，最多保留 30 条；登录、扫码登录、注册后拉取，退出时清理本机记录。
- 首页 MBTI 卡移动到卡面收藏上方。

## 每日打卡与每日一签

- 每日打卡升级为“抽签 → 行动 → 回签 → 七日成卷”的轻量记录链路。
- 手机版抽签页重做：顶部收敛为“今日一签 + 日期/星期”，标签最多三项，层级更清楚。
- 今日签从圆角渐变卡片改为独立的朱砂色文字印记，去掉外层卡片、内边框与阴影。
- 签印放大到手机 96、宽屏 84；页签高度提升到 46，补上图标与“今日小事”完整标签。
- 签文与今日卡片使用 280ms 的 `AnimatedCrossFade`，切换时高度平滑过渡。
- 今日一小步改为“图标标题 + 状态胶囊 + 大正文 + 42 高主按钮”，去掉重复标题。
- 趣签筒改为手机 118×40、宽屏 108×32 的描边按钮。

## 首页与交互

- 首页默认布局重排，MBTI、卡面收藏与每日一言顺序调整。
- 天气、定位与首页入口同步整理，窄屏和宽屏保持同一套最大宽度约束。
- 图鉴、历史记录等二级页面的返回动画统一缩短，减少等待感。

## 四端打包

- Android：`Citro-v3.3.0-release.apk`，arm64-v8a，Citro 发布签名，可直接覆盖 3.2.x。
- Windows：`Citro-v3.3.0-win64-setup.exe`，用户级安装，更新清单带 SHA-256 与静默更新。
- Web：`Citro-web-3.3.0.zip`，CanvasKit 本地分发、预压缩产物，`latest.json` 同步。
- 下载站：`Citro-downloads-3.3.0.zip`，Windows / Android 入口与更新日志同步到 3.3.0。
- iOS：完成预打包，版本号、`Generated.xcconfig`、`flutter_export_environment.sh` 与文档同步到 `3.3.0 / 3300`；IPA 由 TestFlight CI 在 macOS 构建。

## 产物

| 平台 | 文件 |
| --- | --- |
| Android | `APK/Citro-v3.3.0-release.apk`、`APK/update.json` |
| Windows | `exe/Citro-v3.3.0-win64-setup.exe`、`exe/update.json`、`WIN/Citro-v3.3.0-win64/` |
| Web | `web/Citro-web-3.3.0.zip`、`web/latest.json` |
| 下载站 | `web/Citro-downloads-3.3.0.zip`、`web/downloads.json` |
| iOS | `docs/ios-预打包清单.md`（IPA 待 TestFlight CI 生成） |

## 部署注意

- 服务端需部署最新 `trash/trash.js` 并重启 PM2：MBTI 历史依赖 `/api/mbti`，打卡回签与成卷依赖 `/api/checkin/*`。
- Web 与下载站需用对应整包覆盖站点根；`latest.json` / `downloads.json` 已写入 OBS 与本地清单。
- iOS 推送 `main` 后由 `.github/workflows/ios-testflight.yml` 自动构建并上传 TestFlight。

## 校验

| 文件 | SHA-256 |
| --- | --- |
| Citro-v3.3.0-release.apk | `5bcc5f7db402a59daa490020b206191a19a8af8a83a86a56e5fba2d40c4b0975` |
| Citro-v3.3.0-win64-setup.exe | `7732b54f60f902aeaa55e7cda5246cd4b6c6d1998d5737ada52ebb595350be47` |
| Citro-web-3.3.0.zip | `14ba905719145da8d3fefcc4a99eb3691b1380a38703057d47142203006cb0be` |
| Citro-downloads-3.3.0.zip | `978324e1fafeaa578c3f7814116321ea6011f474d5f3056c575c3c2b1de64461` |
