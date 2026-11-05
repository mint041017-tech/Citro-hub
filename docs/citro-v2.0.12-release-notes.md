# Citro 2.0.12

> 版本号 `2.0.12+2012` · 2026-11-05

## 本次更新

### 动效恢复

- 切页恢复 **`Opacity .82→1` + `scale .992→1` + `translate 8/6px`**（280ms），
  与 2.0.8 及之前的观感一致。
- 底部导航栏图标恢复 **缩放 + `Color.lerp` 颜色渐变**，所有动画参数还原。

### 保留的非视觉优化

- 页面 Widget 只创建一次（`_pages` 缓存），切 Tab 不再新建页面实例；
- 启动后空闲预热游戏 / 我的 / 社区（1.2s / 2.0s / 2.8s）；
- 切页前 `endOfFrame` 等新页完成首帧再启动动画（只调整时序）；
- 我的页卡片 `RepaintBoundary`；
- 全局 120Hz 申请与 `preferredDisplayModeId` 双写。

### 说明

原动画的整页 `Opacity`（saveLayer）与 `scale`（raster cache 失效）有固定绘制成本，
120Hz 下部分机型仍可能偶发掉帧。若需要进一步优化，可在「减弱动态效果」开关下
使用简化动效，或把切页时长从 280ms 缩短——这两项都会改变动效，需单独确认。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.12-release.apk` | 95,238,675 B |
| Windows | `Citro-v2.0.12-win64-setup.exe` | 23,588,324 B |
| Web | `Citro-web-2.0.12.zip` | 30,925,476 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`cf0ba66450a7f89655f0c54dd583ee8209f06fedf26bafb9066b89d04132ad8a`
- EXE：`a2e4f634f99894b3c5529ca7900eaac0ecd7b9c3e44d55a03abe1317ffdd8eea`
- WEB：`f1e08f4a1ea14a0c07d2393392ddbc50e3654d5964a42051d44fdab505109843`
- 下载站整包：`18a4d5ca5de0065fb849ea59f7146e9d3efdeca1264fd999dfa2988e27f61da6`

## 发布状态

- OBS 已上传并校验：`APK/Citro-v2.0.12-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.12-win64-setup.exe`、`exe/update.json`、
  `web/Citro-web-2.0.12.zip`、`web/latest.json`、
  `web/Citro-downloads-2.0.12.zip`、`web/downloads.json`。
- 下载站源码与 `dist/` 已更新到 v2.0.12，整包已上传 OBS `web/`。
- 公网 `dl.chimu-claw.xyz` 需用整包覆盖站点根后生效。

## 说明

- Windows 安装包未做代码签名，SmartScreen 可能提示“未知发布者”。
- iOS 2.0.12 已完成预打包配置与清单，IPA 需在 macOS 上生成。
- 应用内更新清单：`APK/update.json`、`exe/update.json`、`web/latest.json`。