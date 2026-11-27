# Citro 3.5.2 发版记录

> 版本号：`3.5.2+3502` · 2026-11-28
> 汇总区间：3.5.1 → 3.5.2（含 3.5.1 的天气/弹窗与字号调整）

## 横屏 Tab 切换

- 横屏（宽 > 高）时 Tab 切换改为上下翻页：新页从下方推入，旧页向上退出。
- 竖屏保持左右滑动；Web 横向窗口同样使用上下切换。

## Android 动画优化

- 待办、记账：切页不再对整页做 `Opacity`，只保留轻微位移，避免全页 `saveLayer`。
- 食谱：Android 下取消整页淡入/横移，直接换页，页面内部动效保留。
- 听隅呼吸页：去掉两枚超大 `MaskFilter` 每帧高斯模糊，Android 改用径向渐变光晕；核心光球不再叠加逐帧模糊。
- 我的、记账、食谱等二级页：Android 路由转场去掉整页缩放，只保留位移，减少玻璃/模糊层重建。
- 底栏玻璃：滚动、切 Tab 时临时降低实时模糊并补填充，静止 140ms 后恢复完整模糊。
- 以上优化只作用于 Android，其他端视觉与动效保持原样。

## 弹窗与天气

- 所有 `PaperDialog` 弹窗默认模糊提高到 `sigma: 36`，深色模式统一加约 25% 白色填充，正文更清晰。
- 天气详情、心情详情沿用同一档模糊；天气卡标签、城市、描述与体感/湿度字号延续 3.5.1 的放大效果。
- 首页天气卡在手机、平板、桌面与 669×951 / 824×1366 等比例下均通过布局测试。

## 3.5.1 及更早累计

- 3.5.1：天气/心情弹窗模糊与天气卡字号；3.5.0 系列：测试中心与十二系测评、MBTI 测试档案、登录注册改版、全局玻璃与游戏卡片视觉。
- 每日一签完全随机与七段流式签文、社区长文五行折叠、Web 桌面横屏与首屏延迟加载。
- 对比 3.2.1 的完整累计更新见 `docs/citro-v3.5.1-release-notes.md`。

## 四端打包

| 平台 | 文件 |
| --- | --- |
| Android | `APK/Citro-v3.5.2-release.apk`（arm64-v8a）、`APK/update.json` |
| Windows | `exe/Citro-v3.5.2-win64-setup.exe`、`exe/update.json`、`WIN/Citro-v3.5.2-win64/` |
| Web | `web/Citro-web-3.5.2.zip`、`web/latest.json` |
| 下载站 | `web/Citro-downloads-3.5.2.zip`、`web/downloads.json` |
| iOS | 预打包完成，IPA 待 macOS / TestFlight CI 生成 |

## 校验

| 文件 | 字节 | SHA-256 |
| --- | --- | --- |
| Citro-v3.5.2-release.apk | 65,708,636 | `0cf0325ec31b55128a64ddd3e2e1ae5f62365fe66f429f1f9b38039871ff63dc` |
| Citro-v3.5.2-win64-setup.exe | 82,419,779 | `63f73d4a585b2f91dd9048e03c1ec9a8d7b61fac097b169adb51540b121e7336` |
| Citro-web-3.5.2.zip | 45,707,564 | `cb5439328a001f58cecc8eb042676713cd617d468f5a60eba4ba939e5ab139fa` |
| Citro-downloads-3.5.2.zip | 1,088,981 | `54a352fe51d00dadd75bc8ad2efaba683ab78c38be30e045a9d0e32c7ba3c3a9` |

- `flutter analyze lib`：0 error / 0 warning / 152 条既有 info。
- Android：arm64-v8a 单 ABI，versionCode 3502，`CN=Citro` 签名，Impeller 开启；APK 65,708,636 字节。
- Windows：便携版 188.1 MB，Inno Setup 用户级安装包 78.6 MiB，更新清单含 SHA-256。
- Web：CanvasKit 本地分发与预压缩产物，`build_id` = `main.dart.js` MD5 `48d3d2303a8d95dee34489a9c7aee486`。
- 下载站：版本号、大小、SHA-256 与 3.5.2 更新日志同步。
- iOS：Windows 环境完成版本、工程配置、权限文案与预打包清单核对，IPA 由 macOS / TestFlight CI 生成。

## 部署注意

- 服务端需部署最新 `trash/trash.js` 并重启 PM2：`/api/kei`、MBTI 档案与卡面/打卡同步依赖该版本；未部署时客户端仅保留本地记录。
- Web 与下载站用对应整包覆盖站点根；`latest.json` / `downloads.json` 随包上传 OBS。
- `web/latest.json` 的 `build_id` 使用最终 `main.dart.js` 的 MD5，与 zip 内 `.last_build_id` 一致。
- 推送 `main` 后 `.github/workflows/ios-testflight.yml` 自动构建并上传 TestFlight。