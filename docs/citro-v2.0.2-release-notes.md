# Citro 2.0.2

> 版本号 `2.0.2+2002` · 2026-11-03

## 本次更新

### 听隅
- 修正手机端顶栏在时钟右侧错误预留 118px 窗控空白的问题，时钟与呼吸按钮现在贴齐屏幕最右侧。
- 该间距只对非 Windows 端生效；Windows 桌面端仍为右上角悬浮窗控保留避让空间。
- 听隅手机横屏顶栏的同类留白一并修正，桌面端布局不变。

### 小游戏
- 首页小游戏卡和游戏页游戏卡改用与听隅一致的纸页软转场：打开时轻沉、缩放淡入，卡片快照抬起后淡出。
- 关闭时反向收回，卡片快照从页面方向落回原卡片位置。
- 桌面 Web 的游戏卡沿用与听隅入口相同的命名路由转场。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.2-release.apk` | 95,058,427 B |
| Windows | `Citro-v2.0.2-win64-setup.exe` | 23,628,534 B |
| Web | `Citro-web-2.0.2.zip` | 30,913,483 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`6e1aefde764e7baa27cd49bdbf95d5b2f724c5e6d24f454ec133d6f0aa1c9b65`
- EXE：`9b34107b58e02c3031e0a36f329c86e35ab08342e08ce186615eee7815697e11`
- WEB：`3e921254eb30437707097f4ce1bac6e6c6c858c39ff772b6103fbaec822d732d`

## 说明

- Windows 安装包暂未做代码签名，SmartScreen 可能提示“未知发布者”；安装到当前用户目录，无需管理员权限。
- iOS 2.0.2 已完成预打包配置与清单，IPA 需在 macOS + Xcode 上执行 `flutter/ios/build_ipa.sh` 生成。
- 线上镜像：<https://obs.chimu-claw.xyz/>，应用内更新清单为 `APK/update.json`、`exe/update.json`、`web/latest.json`。
- 下载站整包 `Citro-downloads-2.0.2.zip`（1,088,227 B，sha256 `4e890b3e…`）已生成并上传 OBS `web/`；公网 `dl.chimu-claw.xyz` 需用整包覆盖 nginx 站点根后生效。