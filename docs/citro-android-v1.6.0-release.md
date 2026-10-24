# Citro Android v1.6.0 发版记录

- 日期：2026-10-23
- 版本：`1.6.0` / versionCode `1600`
- 包名：`com.chimu.crew`（minSdk 24 / targetSdk 36）
- APK：`APK/Citro-v1.6.0-release.apk`（通用 ABI，70.7 MB）
- SHA-256：`F2B1AD55285AD8BA62677ADA71F833616CCC950346D13CE0CF43F22F815B9D7F`
- 签名：与 v1.1.1 相同的 release key，可覆盖升级
- 针对 v1.5.9 试用反馈的 8 项问题逐项修复。

## 1. 音效收缩：只保留跳一跳 / 极限刹车

`GameSfx` 新增全局 `soundsEnabled` 开关（默认关闭）：tone/noise 在关闭时直接跳过，
语义化快捷方式（merge/match/eat/win/lose/move/flip/miss…）内置的震动不受影响；
`move/flip/miss` 三个纯音效补上了震动。跳一跳 / 极限刹车在 initState 打开、
dispose 恢复。结果：其余 10 个游戏全部只剩震动反馈（移动=selectionClick、
合成/吃子/翻牌=light、失误=medium、胜利=heavy），刹车/跳一跳音效齐全。

## 2. 2048 合并动画

根因：`_Tile24` 的 pop 分支是 `Tween(1.0→1.0)` 的占位，根本不会动。现按 web
`.g-tile.merged` 实现 220ms 脉冲（scale 1→1.18→1，正弦包络）；新生成的块
同步补上 scale 0.4→1 的 appear 动画（原来只有淡入）。

## 3. 跳一跳蓄力音

蓄力期间每 70ms 一格上行节拍音（音高/音量随力度 300→920Hz），按下即响第一声，
起跳/松手即停（仅跳一跳页开启音效）。

## 4. 羊了个羊三消动画

三消不再瞬时清空：被消的三张牌在原槽位以幽灵形式放大 1.45 倍 + 淡出 360ms
（`_fading` 批次 400ms 后回收，换关清空），连锁三消逐批播放。

## 5. 贪吃蛇棋盘居中（真正的根因）

v1.5.9 的 Center 修复只对内容区 ≥ 370 的机型有效：格子尺寸写死 20px
（17×20+16 间隙+左右留白=370），内容区 < 370 的机型上棋盘被右侧裁掉一截、
看起来左偏。现在格子边长随棋盘宽度缩放 `(boardW - 30) / 17`（370 宽时恰为
web 的 20px），任何屏宽都严格左右对称。

## 6. 成语接龙 / 飞花令 错误提示不再被键盘遮挡

错误 / AI 判定提示行从输入行下方移到输入行上方（页面最底栏的顶部），键盘弹出
时提示仍贴在可视区内。

## 7. 记忆卡牌底部留白

纸卡高度 `boardH + 18` 时底排卡牌距下缘只有 1px；改为 `boardH + 34`，
与顶部 17px 对称。

## 8. 「正在玩」条目头像

`_LiveChip` 对齐 web `gl-av` / `gl-row.you`：有头像显示头像图（NetworkImage，
72px 预缩放），无头像显示昵称末字；自己的条目橙色高亮 + 「你」小标签。

## 验证

- `dart analyze lib`：0 error / 0 warning。
- `flutter test --concurrency=1`：13 张 golden 全部通过（gmem 底部留白基线已更新）。
- 正式包 aapt2：versionCode 1600 / versionName 1.6.0 / 三 ABI。
