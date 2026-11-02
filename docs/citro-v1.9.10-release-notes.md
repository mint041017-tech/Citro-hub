# Citro 1.9.10 更新日志

2026-11-01 · 版本 1.9.10（Android versionCode 1910）· Windows 窗口外观更新，其余端源码同步

1.9.10 调整 Windows 桌面端窗口外观：移除原来的自绘标题栏，最小化 / 最大化 / 关闭改为悬浮在内容右上角的圆形按钮。其余功能与 1.9.9 一致。

## Windows：无标题栏 + 悬浮窗控

- 移除顶部 38px 标题栏（品牌字、居中装饰点与底部分隔线），页面背景通铺到窗口顶沿。
- 三枚 26px 圆形按钮悬浮在右上角：最小化、最大化 / 还原、关闭；关闭键保留红色警示色。
- 按钮默认半透明，鼠标移入按钮组后淡入为完全显形，尽量不干扰页面内容。
- 顶部保留 30px 安全区：页面 SafeArea 自动避让悬浮按钮，同时作为窗口拖动区；双击可最大化 / 还原。
- 保持既有窗口能力：无边框 + DWM 圆角阴影、四边拖拽缩放、关闭淡出、全屏自动隐藏窗控、原生主题色同步。

## 兼容说明

- 本次仅涉及 Windows 桌面端外观，Android / iOS / Web 的功能与 1.9.9 相同。
- 版本号由 `flutter/pubspec.yaml` 统一提供（1.9.10+1910），各端构建脚本自动读取；无需改动 Android / iOS / Windows 工程内的版本字段。

## 版本与分发

| 端 | 制品 | 状态 |
| --- | --- | --- |
| Windows | `Citro-v1.9.10-win64-setup.exe` + 便携版 `Citro-v1.9.10-win64/` | 源码已更新，待构建 |
| Android | `Citro-v1.9.10-release.apk`（versionCode 1910） | 源码已更新，待构建 |
| Web | `Citro-web-1.9.10.zip` | 源码已更新，待构建 |
| iOS | 源码同步 | 待 Mac / Xcode / Team 构建 |

补充说明：

- Windows 更新说明来自 `flutter/update_notes_windows.txt`，Android / Web 通用更新说明来自 `flutter/update_notes.txt`。
- 发布后需同步更新 `web/latest.json` 与 OBS 制品；本文件不预填大小与 sha256，构建完成后再补。