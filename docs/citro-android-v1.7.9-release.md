# Citro Android v1.7.9 发版记录

- 日期：2026-10-24
- 版本：`1.7.9` / versionCode `1709`
- APK：`APK/Citro-v1.7.9-release.apk`（72.9 MB / 76,396,782 bytes）
- SHA-256：`D73A4C738F62A8A5C87F80C9FDD2A4BBE4982BCD43C4127DF0E298AA86217A58`

本轮为**流畅度专项**，不新增功能、不改版式。

## 1. 帧循环：从 16ms 定时器改为屏幕 vsync

- 跳一跳、淘气小球原来用 `Timer.periodic(16ms)` 推进物理，在 120Hz 屏上最高只有约 60fps，
  且与屏幕 vsync 错位，容易出现半帧抖动。
- 现改为 Flutter `Ticker`（Choreographer 驱动）：60Hz 设备跑 60fps，120Hz 设备直接跑 120fps；
  `dt` 上限 50ms，切后台回来不会瞬移。
- 蓄力、起跳、落点压缩、粒子、镜头跟随、圆环惯性等全部按真实帧间隔推进。

## 2. 小游戏：画布重绘与整页重建分离

- 跳一跳 / 淘气小球的游戏状态写入可变画布快照，`CustomPainter` 通过 `repaint` 通知每帧重绘；
  HUD、标题、按钮、底栏只在落点 / 得分 / 开始 / 结束时重建。
  - 淘气小球的比分与时间 HUD 约 1Hz 更新，时间条用独立 `ValueNotifier` 平滑推进。
- 淘气小球的径向暗角原来是**每帧画 400 个圆**（120Hz 下约 4.8 万次/秒），现按逻辑尺寸 × DPR
  离屏烘焙成一张图，每帧只做一次 `drawImageRect`。
- 极限刹车（原生 3D 场景）同样改为场景每帧重绘、HUD 约 30Hz / 菜单态 4Hz 重建。
- 羊了个羊每张牌加 `RepaintBoundary`：三消幽灵缩放淡出时只重绘那几张牌，不再整盘重绘。
- 所有游戏棋盘在 `GameScaffold` 内统一包裹 `RepaintBoundary`，物理帧不再带着 HUD 一起重绘。
- 游戏结束后停止 ticker，结算浮层下面不再空转渲染。

## 3. App 级无谓重建

- `MaterialApp` 不再监听整个 `AppState`：只有主题模式变化才重建；天气、未读、弹层状态变化不再重建导航器与主题。
- 弹窗开关改用独立的 `popupActiveNotifier`。此前每开/关一个弹层都会让处于后台的社区页、首页卡片全部重建。
- 首页时钟原来每秒 `setState` 重建整个首页（含天气 / 食谱 / 黄历 / 星象 / 每日一言），现在时钟自己按**整分钟**刷新。
- 首页主要卡片、底部导航、三个 Tab 页、游戏棋盘均增加 `RepaintBoundary`。
- 纸面网格背景标记为静态复杂绘制，交给引擎光栅缓存，滚动与切页时不再重画网格。

## 4. 图片 / 元素加载

- 社区评论里的 base64 图片原来在每次 build 都重新解码并生成新的 `MemoryImage`
  （字节对象不同，命中不了图片缓存）；现在只解码一次并保留字节。
- 启动完成后的空闲阶段预解码 logo 与 9 张猫猫贴纸（288px），打开星象 / AI 对话不再首帧临时解码。
- 游戏顶栏 logo 补齐 `cacheWidth`（120），避免按原始尺寸解码。
- 极限刹车内嵌原版约 800KB 的内联 HTML（HTML + three.js + CSS）：
  - 静态缓存拼装结果，第二次进入直接复用；
  - 启动空闲阶段预拼一次，首次打开不再现场读包 + 字符串拼接。
- 图片缓存维持 120 张 / 48MB，低内存与切后台时清理逻辑不变。

## 5. Android 15–17 / 高刷特调

- `compileSdk = targetSdk = 36`（Android 16），minSdk 24。
- 游戏页打开时通过 `WindowManager.LayoutParams.preferredRefreshRate` 申请屏幕最高刷新率
  （通常 120Hz），退出游戏恢复“无偏好”，后台回来自动重新申请；原生与内嵌原版刹车都接入。
- `zipalign -c -P 16` 校验通过；`libflutter.so` / `libapp.so` 的 LOAD 段为 0x10000（64KB）对齐。
- 未启用 Impeller：仓库现有注释已记录部分老 GPU 在 Impeller 下黑屏，本轮保持 Skia，避免未验证的渲染后端切换。

### 16KB 页设备说明

`shared_preferences_android` / `path_provider_android` 的 `libdartjni.so` 与 DataStore 的
`libdatastore_shared_counter.so` 目前仍是 4KB 段对齐（上游预编译产物）。4KB 页设备不受影响；
若在开启 16KB 页的 Android 15+ 设备上安装失败，需要等上游插件发布 16KB 版本后升级依赖。

## 验证

- `flutter analyze`：0 error / 0 warning（131 条既有 info，未新增）。
- `flutter test test/perf_frame_smoke_test.dart`：2/2 通过（跳一跳 ticker + 按压/松手，淘气小球 ticker + 拖拽）。
- 既有 golden 截图对比：所有页面均有 0.21% 的顶栏 logo 抗锯齿差异（基线早于 logo 资源更新，属既有漂移）；
  淘气小球额外 2.49%（暗角改为离屏烘焙后的亚像素取整），叠图目检无可感知差异。未更新基线。
- APK：`unzip -t` 通过；`aapt2 dump badging` 显示 versionCode `1709` / versionName `1.7.9`；
  `apksigner verify` 通过，签名 `CN=Citro`，与 v1.1.1 相同，可直接覆盖升级。
- 按用户要求未启动模拟器，界面与手感请在真机上验证。
