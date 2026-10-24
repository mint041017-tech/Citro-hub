# Citro Android v1.7.7 发版记录

- 日期：2026-10-24
- 版本：`1.7.7` / versionCode `1707`
- APK：`APK/Citro-v1.7.7-release.apk`（72.8 MB / 76,380,394 bytes）
- SHA-256：`A6F5811D96FA4D81456FD69CEB6C3CCB9F25AFC9C3C5F464E0EBF8A780835230`

## 摸鱼详情

- 「距上班还有 N 分钟」与「距下个休息日 N 天」两行字号由 12 放大到 16，
  改用 600 字重；距上班为墨色，休息日倒计时为强调色，行距同步放宽。
- 只放大这两行；已下班、午休、工时进度、假期第 N 天等说明文字保持原样。

## 星象卡片

- 移除「✨ AI 深度解读」按钮及其弹层（含相关状态与缓存代码）。
- 主卡片的今日星语、四项指数、总分、幸运色 / 数字 / 幸运物仍全部由 AI 生成，
  刷新运势与生成中 / 失败重试逻辑不变。

## 验证

- `flutter analyze lib`：0 error / 0 warning。
- APK：`unzip -t` 通过；`aapt2 dump badging` 显示 versionCode `1707` / versionName `1.7.7`；
  签名 `CN=Citro`，与 v1.1.1 相同，可直接覆盖升级。
- AOT 产物确认启动页为 `v1.7.7`，AI 密钥已打入。
- 按用户要求，未启动模拟器验证界面。
