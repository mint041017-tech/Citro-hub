# Citro 2.0.1

> 版本号 `2.0.1+2001` · 2026-11-03

## 本次更新

### 社区与图片
- 社区信息流、评论缩略图、头像和全屏看图统一接入 `AppImage` 本地磁盘缓存。
- 原生端首次下载后写入应用缓存目录，二次打开直接读本地文件，不再每次重新下载。
- 首屏前 4 条动态图片预取，滚动与 Hero 动画不再闪白。
- Web 端继续使用浏览器 HTTP 缓存；首次打开仍需下载原图。

### 界面与交互
- 首页星象卡重新设计，与首页其他卡片视觉统一。
- 我的页深浅色切换改为主题下拉菜单，并补充联系邮箱 `mint10177@outlook.com`。
- 打卡页视觉精修；听隅手机端顶栏时钟与呼吸按钮靠右显示。
- 恢复咕噜果冻网页版入口。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.1-release.apk` | 95,058,427 B |
| Windows | `Citro-v2.0.1-win64-setup.exe` | 23,577,031 B |
| Web | `Citro-web-2.0.1.zip` | 30,915,907 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`75315de0fc864dce5cc9430fd6cc8a6aefc7a5b3340715d9f040bcd54e6afebd`
- EXE：`2a3246de35988aec608aff4cdf5cac951298658c58e8ab82db30ebd4b5ebd31c`
- WEB：`f70884b98dbae5d33fb0d3c99ca6e83abdefda5f2abaf6f83b6b2bf79bb06804`

## 说明

- Windows 安装包暂未做代码签名，SmartScreen 可能提示“未知发布者”；安装到当前用户目录，无需管理员权限。
- iOS 2.0.1 已完成预打包配置与清单，IPA 需在 macOS + Xcode 上执行 `flutter/ios/build_ipa.sh` 生成。
- 线上镜像：<https://obs.chimu-claw.xyz/>，应用内更新清单为 `APK/update.json`、`exe/update.json`、`web/latest.json`。
- 下载站整包 `Citro-downloads-2.0.1.zip` 已生成并上传 OBS `web/`；公网 `dl.chimu-claw.xyz` 需用整包覆盖站点根后生效。