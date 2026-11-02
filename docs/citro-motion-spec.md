# Citro 动效规范（四端统一）

> 适用于 Web / Android / iOS / Windows。代码入口：`flutter/lib/theme/motion.dart`，
> 通用组件：`flutter/lib/widgets/motion_widgets.dart`。

## 1. 原则

1. **每段动画都要有理由**：空间延续、状态确认、避免突兀变化；纯装饰只在首次出现或低频场景使用。
2. **进场慢一点、退场快一点**：同一个弹层/页面，关闭总比打开更快。
3. **只用强曲线**：不用 `ease-in`、不用系统默认弱曲线；统一 `easeOut / easeInOut / drawer / exit`。
4. **不凭空出现**：缩放起点 ≥ 0.9，配合透明度；缩放到 0 的入场一律不用。
5. **键盘触发与高频操作不做动画**（如快捷键、命令面板）。
6. **减少动态**：`MediaQuery.disableAnimations` 下时长归零、只保留透明度，位移全部去掉。
7. **性能**：优先 `transform` / `opacity`；Windows 上避免整页位移与大面积阴影重绘。

## 2. 曲线

| 名称 | 值 | 用途 |
| --- | --- | --- |
| `easeOut` | `cubic-bezier(0.23, 1, 0.32, 1)` | 进场、页面推入 |
| `easeInOut` | `cubic-bezier(0.77, 0, 0.175, 1)` | 屏内移动、共享元素 |
| `easeColor` | `cubic-bezier(0.33, 1, 0.68, 1)` | 悬停、颜色、状态 |
| `drawer` | `cubic-bezier(0.32, 0.72, 0, 1)` | 底部弹层 |
| `exit` | `cubic-bezier(0.4, 0, 1, 1)` | 所有退场 |
| `emphasized` | `cubic-bezier(0.05, 0.7, 0.1, 1)` | 指示器滑动 |
| `settle` | `cubic-bezier(0.34, 1.56, 0.64, 1)` | 徽标、贴纸等轻微回弹 |

## 3. 时长

| Token | 值 | 用途 |
| --- | --- | --- |
| `press` | 120ms | 按下缩放反馈 |
| `hover` | 160ms | 悬停、聚焦、颜色 |
| `popover` | 180ms | 小气泡、计时胶囊 |
| `modal` / `modalReverse` | 240 / 170ms | 居中弹窗 |
| `sheet` / `sheetReverse` | 280 / 200ms | 底部弹层 |
| `pageTouch` / `pageTouchReverse` | 260 / 200ms | 移动端整页 |
| `pageDesktop` / `pageDesktopReverse` | 180 / 150ms | Windows / Web 整页 |
| `tab` / `tabDesktop` | 240 / 190ms | Tab 页切换 |
| `indicator` | 260 / 200ms | Tab 胶囊、侧栏高亮 |
| `staggerItem` + `staggerStep` | 220ms + 40ms | 首屏卡片交错 |
| `badge` | 180ms | 未读数弹入 |

> 除首屏交错与庆祝类浮层外，UI 动效总时长不超过 300ms。

## 4. 结构

### 4.1 页面转场（`theme/app_theme.dart`）

- 四端共用 `_citroPageTransition`：新页淡入 + 横向轻推（触屏 4.5%，桌面/网页 2.8%）。
- 旧页不额外压暗或位移：弹层只盖局部，若让下层常驻变灰，浮层打开期间整页会一直是灰的。
- iOS/macOS 保留 `CupertinoPageTransitionsBuilder`（边缘返回手势），时长与其它端一致。
- 退场由路由的 `reverseTransitionDuration` 控制，比进场短。

### 4.2 Tab 切换（`pages/root_shell.dart`）

- 四端统一壳内切换，Web 不再整页 `pushNamed`，导航栏与页面壳不会重挂载。
- **旧页在切换的同一帧立即撤下**，屏幕上永远只出现当前页：不做两页对推、
  不做交叉淡化，因此没有残页、重影、接缝或空白条。
- 新页做一个 10px 的归位 + 90%→100% 淡入（160–200ms），足以表达"切换发生了"。
- **结构必须稳定**：隐藏页与显示页都返回同一棵 `Positioned → Offstage → IgnorePointer
  → Opacity → Transform → RepaintBoundary → TickerMode → page`。一旦在不同状态下换成别的
  widget 类型，Flutter 会整页重建，入场动画/数据请求会在每次切 Tab 时重放并闪屏。
- 允许打断：切换中再次点击会先收尾再从当前位置开始。
- 动画结束后撤下离场层；未访问页保持挂载但不绘制（`Offstage` + `TickerMode`）。
- Web 用 `syncWebRoute` 同步地址栏 hash（`replaceState`，不新增历史条目）。

### 4.3 导航指示器（`widgets/tab_bar.dart`、`widgets/tablet_shell.dart`）

- Tab 高亮是一颗共享胶囊：`AnimatedAlign` 在等分槽位间滑动，任何时刻只有一颗。
- 侧栏高亮是一整块纸片：`AnimatedPositioned` 在导航项之间滑动。
- 图标轻微放大（1.06）与颜色渐变；未读徽标用 `CitroPop` 弹入。
- 内容与高亮分离：高亮先到、文字/图标随后变色，形成引导。

### 4.4 弹窗与弹层（`widgets/modal.dart`）

- `showCitroDialog`：居中缩放 0.965→1 + 上浮 2.2% + 淡入；退场 170ms。
- `showCitroSheet`：所有底部弹层统一走 `AnimationStyle(drawer, 280ms, exit, 200ms)`。
- 工具栏提示、抽卡、运势、番茄钟等全屏浮层使用同一组时长与退场曲线。
- `prefers-reduced-motion` 下直接使用 `AnimationStyle.noAnimation`。

### 4.5 共享元素与卡片形变

组件：`widgets/shared_element.dart` 的 `CitroHero`、`widgets/card_morph.dart` 的 `CitroCardMorph`。

**Hero（有对应视觉元素时）**
- **只在 PageRoute 之间飞行**：Flutter 的 Hero 不跨 Dialog/PopupRoute。
  因此看图、卡面放大、我的浮窗都改成了 `opaque: false` 的透明 PageRoute，
  视觉上仍是浮层，但 Hero 能正常工作。
- 现有共享元素：
  | 场景 | tag | 说明 |
  | --- | --- | --- |
  | 游戏卡片标题 → 游戏页顶栏 | `game-title::<gameKey>` | 竖屏游戏页 |
  | 社区图片 → 全屏看图 | `post::<postId>:<index>` / `comment::<commentId>:0` | 缩略图与看大图共用 `cacheWidth`，飞行中不重新解码 |
  | 卡面收藏 → 卡面放大 | `card::<cardId>` | 未解锁卡面不参与 |
  | 侧栏头像 → 我的浮窗头像 | `profile::me` | Windows / iPad / Duo |
- 飞行时用 92%→100% 透明度收尾并包一层透明 `Material`，避免文本样式丢失；
- 减少动态时 `CitroHero` 直接返回 child，不注册 Hero，完全降级为普通切换；
- tag 必须全局唯一：同一路由里出现两个相同 tag 会直接抛异常。

**Card Morph（目标没有可复用元素时）**
- 卡片纸面从它自己的屏幕矩形扩展到目标矩形（圆角 + 纸色 + 投影），
  内容在 45% 之后淡入，读作"这张卡片长成了详情页"。
- `CitroCardMorph.pushPage`：卡片 → 整页（游戏卡片、食谱卡已接入）。
- `CitroCardMorph.showPreview`：没有详情的卡片 → 居中放大预览，点任意处收回。
- 接入方式：卡片 onTap 里取自身 `RenderBox` 矩形，传 `source`；
  拿不到矩形时自动退回普通路由，不会崩。
- 减少动态时直接返回页面，不做形变。

**Card Flight（目标是非全屏 Sheet 时的备用方案，当前未启用）**
- `CitroCardFlight.run(context, open: () => showXxxSheet(context))` 会：
  1. 截取卡片自身快照（按卡片矩形裁切，避免把同一 RepaintBoundary 里的邻卡一起复制）；
  2. 用 OverlayEntry 抬起并**在 150ms 内撤掉**，不拖到面板展开之后；
  3. 面板关闭后重新插入快照，淡入并缩回卡片原位。
- 实测非全屏面板里"卡片消失"的尾段会与面板展开打架，因此天气 / 摸鱼 / 星象卡
  **已改回面板自身的抽屉动画**；Card Flight 保留给以后需要"从卡片长成非全屏面板"的场景。
- 全屏目标仍走 `CitroCardMorph.pushPage`（游戏卡、食谱卡）。

> 覆盖计划：游戏卡（已完成）→ 首页卡片（食谱/偏鱼/星象/日历/每日一言）→
> 资源卡 → 社区帖子卡 → 我的页入口卡。逐组替换，失败即退回原转场。

### 4.6 入场与反馈

- `CitroStagger`：一组元素共用单个 ticker，间隔 28–40ms；结束时移除 `Opacity`，回到普通渲染路径。
- `CitroReveal`：不插 Column，可直接包住滚动视图；首帧上浮 6–10px + 淡入。
- `CitroPop`：徽标/未读数出现时从 0.72 弹到 1，只做一次。
- `Pressable`：按下 0.97 缩放（120ms），桌面悬停抬升 2.5px，触摸端不触发悬停样式。

### 4.6 Windows 桌面壳

- 窗口淡入 160ms、关闭 120ms，透明度按 `easeOut` 递进，避免线性变化的生硬感。
- 悬浮窗控：悬停 160ms 颜色过渡、按下 0.94 缩放，整组按钮在鼠标进入时从 55% 提到 100%。

## 5. 自检清单

- 是否有 `scale(0)`、`ease-in`、`transition: all` 之类的反模式？
- 同一类操作（弹窗、弹层、切页）在四端是否使用同一曲线与相近时长？
- 退场是否比进场快？
- 是否有元素在弹层打开后仍保持"变灰/位移"的残留状态？
- 低频页面（首屏、庆祝）才有交错/回弹；高频操作是否保持瞬时？
- 减少动态时是否仍能看懂状态变化（只去掉位移，保留透明度）？