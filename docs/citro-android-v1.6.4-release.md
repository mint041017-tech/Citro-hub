# Citro Android v1.6.4 发版记录

- 日期：2026-10-23
- 版本：`1.6.4` / versionCode `1604`
- APK：`APK/Citro-v1.6.4-release.apk`（70.8 MB）
- SHA-256：`400125B85DC20B947E764F4AA0FA24EDF56EF1105B6634F851F2E81D064BBA77`

## 1. 成语接龙 / 飞花令：键盘抬起时始终显示最新一条

- 新增 `KeyboardObserver`（`game_ui.dart`，`WidgetsBindingObserver.didChangeMetrics`）。
- 两个页面在 `initState` 注册监听并给输入框 `FocusNode` 加监听：键盘弹出 /
  输入框获得焦点时调用 `_scrollBottom()`，链表自动滚到最新一条（此前键盘抬起后
  停在旧词上）。
- 监听在 `dispose` 中移除，无泄漏。

## 2. 极限刹车：去掉「中间的大光团」并重新按原版取色

用户提供原版游戏内截图（492×869）后逐项修：

- **删除「夕阳反光带」**：这是旧版（Citro web 版）独有的元素，原始 three.js
  场景没有，正是画面正中那团大面积暖光的来源。
- **灯头光晕收敛**：半径封顶 22px、只画 180m 内，远处灯只剩小亮点（旧实现
  92px 级光晕在消失点连成一片亮雾）。
- **天空重建**：去掉全屏径向 glow，改为按截图实测色的垂直渐变
  `(97,49,51) → (132,71,71) → (220,152,113)`，地平线上方只留一层薄暖雾。
- 路面/路缘石改为 24m 分段投影，地面改屏幕空间渐变铺满。

已知仍与原版有差距（下一轮继续）：原版是**全屏暗色游戏页**（没有应用顶栏/
标题/纸背景，舞台铺满整屏），车模是精细 SUV 模型 + 实时阴影/Bloom；本版仍是
卡片式舞台 + 低多边形车模，车道虚线的可见度也还在调。

## 验证

- `dart analyze lib test`：0 error / 0 warning。
- `flutter test --concurrency=1`：13 张 golden 通过（刹车基线随天空/灯光重建）。
- aapt2：versionCode 1604 / versionName 1.6.4。
