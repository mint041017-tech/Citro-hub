# Citro 2.0.13

> 版本号 `2.0.13+2013` · 2026-11-05

## 本次更新

### 我的页回弹

`MePage` 的 `SingleChildScrollView` 改为
`BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())`，与首页一致，
Android 上也会出现下拉/上拉回弹。

### 登录 / 注册重设计

- 新增品牌行、标题（「欢迎回来」/「加入 Citro」）与说明文案；
- 保留登录/注册分段，新增 **手机号 / 邮箱** 切换；
- 移除邀请码输入与「邀请码请找站长」提示；
- 错误提示带图标，注册按钮改为「创建账号」；
- 保留协议勾选、隐私政策/用户协议链接、注册后资料确认。

### 邮箱注册（前后端）

- 前端 `Api.login(account, password)`、`Api.register(phone/email, name, password)`；
- 服务端 `trash/trash.js`：
  - 注册支持手机号或邮箱二选一，用户对象按需写入 `phone`/`email`；
  - 登录支持 `account`，自动识别手机号或邮箱，兼容旧 `phone` 字段；
  - 移除 `INVITE_CODE` 校验与配置常量；
  - 登录错误文案改为「账号或密码不对」。

### 文档同步

`README`、`docs/citro-部署上传清单.md`、`trash/config.local.example.json`、
`app dist/metadata.md`、`review-notes.md`、`legal-and-backend.md`、`mac-handoff.md`
以及应用内用户协议中的邀请码说明均已更新。

### ⚠️ 后端必须先部署

登录接口从 `phone` 改为 `account`，注册改为 `phone`/`email` 二选一。
只更新 App、不部署新版 `trash/trash.js` 时，登录会返回 400。
正确顺序：备份线上 `trash/data` → 替换 `trash.js` → `pm2 restart trash` → 再放开 App 更新。

## 安装包

| 平台 | 文件 | 大小 |
| --- | --- | --- |
| Android | `Citro-v2.0.13-release.apk` | 95,238,679 B |
| Windows | `Citro-v2.0.13-win64-setup.exe` | 23,588,828 B |
| Web | `Citro-web-2.0.13.zip` | 30,925,676 B |
| iOS | 预打包完成，IPA 待 macOS 构建 | — |

SHA-256：

- APK：`6230994ad1e14baf5fc9656fbe22ae57484adeb2e1ec4b104005ea59b22b3f25`
- EXE：`a23e295d33464719be56b6854972833055ee65eb8db7a737fccf8e717317e924`
- WEB：`af8450328733947c5c1bd13bbe6f2b4a5f79924cbec2b7e177a3a7c62064e48b`
- 下载站整包：`8b91826414d30a3a4b2aee8feef6f67989d0cd5e38ce049a9a447ce94c4fb534`

## 发布状态

- OBS 已上传并校验：`APK/Citro-v2.0.13-release.apk`、`APK/update.json`、
  `exe/Citro-v2.0.13-win64-setup.exe`、`exe/update.json`、
  `web/Citro-web-2.0.13.zip`、`web/latest.json`、
  `web/Citro-downloads-2.0.13.zip`、`web/downloads.json`。
- 下载站源码与 `dist/` 已更新到 v2.0.13，整包已上传 OBS `web/`。
- 公网 `dl.chimu-claw.xyz` 需用整包覆盖站点根后生效。
- **服务端 `trash/trash.js` 需同步部署**（本次未自动部署）。

## 说明

- Windows 安装包未做代码签名，SmartScreen 可能提示“未知发布者”。
- iOS 2.0.13 已完成预打包配置与清单，IPA 需在 macOS 上生成。
- 应用内更新清单：`APK/update.json`、`exe/update.json`、`web/latest.json`。