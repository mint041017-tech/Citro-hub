# Citro 3.3.5 发版记录

> 版本号：`3.3.5+3305` · 2026-11-28
> 汇总区间：3.3.1 → 3.3.5（含 3.3.2 Web 专项）

## 测试中心与十二系测评

- 新增「测试」中心，聚合 16 型测试与十二系亲密关系测评。
- 十二系：40 题正反对称量表、5 个正交维度、12 个等半径原型；结果含五维雷达、原型占比、600 次蒙特卡洛稳定率、成人依恋平面与 Curran 效度审计。
- 结果页按原版结构三 Tab 展示：画像与占比 / 五维与效度 / 关系动力学；宽窄屏均无溢出。
- MBTI 图鉴入口移除，历史结果改为「测试档案」内联回顾，与十二系共用云端同步与合并策略。
- 新增 `/api/kei` 接口与 `KeiStore`，记录随账号同步；旧记录缺审计字段时保持兼容。

## 登录注册

- 登录不再手选手机号 / 邮箱，输入后自动识别。
- 注册方式改为输入框内下拉切换，注册免昵称、增加确认密码，首次进入补全资料。
- 登录 / 注册切换加入胶囊动画；全局玻璃登录卡与悬停反馈。

## 视觉与游戏

- 全局玻璃材质重新调校：浅色与深色统一通透度，深色边缘改为同色，底部标签栏加重模糊。
- 外部游戏卡片重新设计，游戏页封面下缘直角与整体圆角边界修正。
- 「我的」页深色玻璃、卡片颜色与背景铺满修复；测试 / MBTI / 十二系页背景不再露出白底。

## Web 与性能（3.3.2 并入）

- 浏览器横屏沿用 Windows 桌面版：208pt 侧栏 + 分栏首页，计划页并排卡片。
- RoundedCN 去掉 500 字重，首屏字体 400/700 preload；非首屏页面 deferred，首帧前下载量约降 31%。

## 四端打包

| 平台 | 文件 |
| --- | --- |
| Android | `APK/Citro-v3.3.5-release.apk`（arm64-v8a 完全包）、`APK/update.json` |
| Windows | `exe/Citro-v3.3.5-win64-setup.exe`、`exe/update.json`、`WIN/Citro-v3.3.5-win64/` |
| Web | `web/Citro-web-3.3.5.zip`、`web/latest.json` |
| 下载站 | `web/Citro-downloads-3.3.5.zip`、`web/downloads.json` |
| iOS | 预打包完成，IPA 待 macOS / TestFlight CI 生成 |

## 校验

| 文件 | 字节 | SHA-256 |
| --- | --- | --- |
| Citro-v3.3.5-release.apk | 65,708,636 | `be5324e6a4ca0c42754e86fdbfc7ae10c3a4cab098fcdbaf610f1fb2ebfb09f7` |
| Citro-v3.3.5-win64-setup.exe | 82,423,615 | `54664f8f20dbda770c653d56bd672ee75fc82aedea01946d25b796343ba7a1fa` |
| Citro-web-3.3.5.zip | 45,706,100 | `0eb1018d66d7d07b09d601a0cd4b7df969b35ce354e0134e2a0be2be5494ce63` |
| Citro-downloads-3.3.5.zip | 1,088,882 | `70be51ab919031fd7667b5e30e310ab5ad3683f83f03b4c2b22ced7942d939ac` |

- `flutter analyze lib`：0 error / 0 warning / 152 条既有 info。
- Android：arm64-v8a 单 ABI，versionCode 3305，`CN=Citro` 签名，Impeller 开启；APK 65,708,636 字节。
- Windows：便携版 188.1 MB，Inno Setup 用户级安装包 78.6 MiB，更新清单含 SHA-256。
- Web：CanvasKit 本地分发与预压缩产物，`build_id` = `main.dart.js` MD5 `61022f35a06422d50f864304481c9b87`。
- 下载站：版本号、大小、SHA-256 与更新日志同步到 3.3.5。
- 核心链路测试：十二系题库/算法/审计/档案合并、结果页宽窄布局、MBTI 档案与路由测试通过；全量套件中的历史预览与金样用例仍有既有失败，未纳入本次发版门禁。
- iOS：Windows 环境完成版本、工程配置、权限文案与预打包清单核对，IPA 由 macOS / TestFlight CI 生成。

## 部署注意

- 服务端需部署最新 `trash/trash.js` 并重启 PM2：十二系 `GET/POST /api/kei` 与 MBTI 档案同步依赖该版本；未部署时客户端仅保留本地记录。
- Web 与下载站用对应整包覆盖站点根；`latest.json` / `downloads.json` 随包上传 OBS。
- `web/latest.json` 的 `build_id` 使用最终 `main.dart.js` 的 MD5，与 zip 内 `.last_build_id` 一致。
- 推送 `main` 后 `.github/workflows/ios-testflight.yml` 会自动构建并上传 TestFlight。
