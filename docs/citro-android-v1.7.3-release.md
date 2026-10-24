# Citro Android v1.7.3 发版记录

- 日期：2026-10-24
- 版本：`1.7.3` / versionCode `1703`
- APK：`APK/Citro-v1.7.3-release.apk`（71.1 MB）
- SHA-256：`48952BF40FFAB0C98340EBA47412A9CBF22CFA237205AA3EDD119F6B0C906B0B`

## 极限刹车（内嵌原版）补两项

### 1. 排行榜入口

WebView 页面浮层右上角新增奖杯按钮（与左上返回按钮同一套暗玻璃圆形样式），
点击打开 App 自己的榜单弹层：

```dart
showGameRank(context, game: 'brake', title: '极限刹车 · 玩家排行')
```

与游戏内成绩提交（`citroScore` → `AppState.submitScore('brake', score)`）共用
同一条数据，页面内原版榜单与 App 榜单读的是同一份数据。

### 2. 加载动画

替换原来的单圈转菊花，新增 `_BrakeLoading`：

- 暗色底 + 112dp 速度表：静态底环、金色 SweepGradient 旋转弧、12 根随相位点亮的刻度；
- 中心脉动的 `speed_rounded` 图标；
- 阶段文案：`正在准备赛道资源` → `正在初始化三维场景` → `准备就绪`，
  副标题「极限刹车 · 原版赛道」；
- 加载动画会一直保留到 `onLoadStop` 里确认 `canvas` 已创建（再等 260ms 让
  首帧渲染完成）才撤掉，避免「白屏一闪」；
- 失败时切换为原有的「游戏加载失败 + 原因 + 重新加载」浮层。

## 验证

- `dart analyze lib`：0 error / 0 warning；
- `test/preview/gbrake_preview_test.dart`：通过（全量套件在高负载下偶发
  “did not complete”，单独运行均通过，属测试机资源问题）；
- aapt2：1703 / 1.7.3；APK 含 `assets/flutter_assets/assets/shache/` 四件资源。
