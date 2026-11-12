# Citro 三端 UI / 排版优化清单

> 评估对象：手机（iPhone 6.3" / 6.9" 竖屏）、iPad（11" / 13"，横竖屏）、Windows 桌面端（780×560 ~ 1600×900+）
> 评估方式：**代码审查 + 实际渲染截图**两条线互相印证，不单独依赖任何一条。
> 截图目录：`docs/shots-ui-review/`（23 张，Web 构建产物在 headless Chrome 中按真实尺寸渲染）

---

## 0. 方法和局限（先看这段，避免误读结论）

**渲染环境**：Linux 容器里没有 Flutter / Windows / iOS 构建链，所以「Windows 原生」和「真机 iPad」无法在本机跑起来。这次实际渲染的是仓库里已有的 `flutter/build/web/` 产物（Flutter 3.47 Web 构建，与移动端共享同一套 `flutter/lib/` 页面代码），在 headless Chrome 中按以下尺寸出图：

- 手机：375×812、390×844、430×932（iPhone UA）
- 桌面窗口：780×560（Windows 最小尺寸）、900×600、1024×768、1200×720、1600×900

**真机参考**：仓库内 `app dist/screenshots/final/` 有 iPhone 6.3"（1206×2622）和 iPad 13"（2064×2752）的 ASC 截图，用于校验 Web 渲染看不出的一些原生差异（状态栏、安全区、真实字体）。

**必须注意的两处「渲染结果 ≠ 真机结果」**：

1. **Web 宽屏 ≠ Windows / iPad 原生**。`flutter/lib/widgets/home_layout.dart:276` 用 `if (kIsWeb)` 把默认首页布局分成两套：Web 是 12 列密集版（`277-293`），Windows / iPad 原生是两列大卡版（`295-307`）。所以本文档里所有 1200 / 1600 宽的截图看到的是 **Web 版布局**，不能直接当作 Windows 真机效果；Windows 原生一列的结论以代码为准。
2. **iPad 的 ASC 截图（v1.9.9）用的是用户自定义布局**，不是代码默认布局。截图里是「天气+食谱 → 摸鱼+星象 → 日历+一言」，而代码默认是「四小卡 → 待办+天气 → 食谱+日历 → 星象+一言 → 心情」。所以那张截图能说明视觉风格，**不能**用来判断默认布局的栅格行为。

---

## 1. 结论速览

| 端 | 最该先解决的 3 件事 | 优先级 |
| --- | --- | --- |
| 手机 | ① 底部 Tab 栏固定 520 宽，375 屏贴边；② 装饰胶带和 CiCi 悬浮钮压住卡片内容；③ 默认首页 11 张卡排到 27 行，首屏只能看到 2~3 张 | P0 / P0 / P1 |
| iPad | ① 11" 竖屏（内容 612）走 6 列紧凑栅格、13" 竖屏（内容 824）走 12 列宽屏栅格，同尺寸段体验割裂；②「我的」浮窗 720×760 在 13" 横屏几乎顶满，内部还强制双列；③ 侧栏 208pt 在 834 宽上占 25%，但只放 4 个入口 + 2 个二级入口 | P1 |
| Windows | ① 780~899 宽区间出现「底部 Tab 栏（手机导航）+ 12 列密集栅格（桌面导航语言）」混用；② 顶部 30pt 窗控留白与页面自身 48pt 顶部留白叠加，首屏被压低 78pt；③ 窗控 32×32 固定尺寸，在 125%/150% 缩放下命中区偏小 | P1 / P1 / P2 |
| 三端共性 | ① 断点阈值散落在 560/620/680/700/760/780/834/900/920/1025/1180 十余处，同一窗口宽度在不同页面会切换不同的导航/栅格语言；② 阅读宽度有 760/840/900/1040/1120/1180/1200 七档以上且无统一标尺；③ 字号下限压到 8~9.5px，低于正文字号建议；④ 胶带系统形状/颜色/位置/尺寸四个维度全部单一，小卡上胶带占卡宽 53% | P0 / P1 |

---

## 2. 三端共性问题（建议先做，收益最大）

### 2.1 断点阈值各自为政 —— 结构性问题

`flutter/lib/` 里宽度判断的取值分布（grep 统计）：

```
width >= 900    ×13    width >= 780   ×1
width >= 1100   ×4     width >= 760   ×3
width >= 1025   ×3     width >= 700   ×3
width >= 560    ×2     width >= 680   ×1
shortestSide >= 600 ×4
```

同一个 900 在三个地方含义不同：

- `theme/breakpoints.dart:31-32`：`tabletNav`（是否显示侧栏）
- `pages/cook_page.dart:504`：`tablet`（是否显示食谱页侧栏）
- `ledger/ledger_page.dart:70`：`wide`（是否显示记账侧栏）

而 780（`pages/home_page.dart:91` 决定首页是否 12 列宽屏栅格）、700（`pages/me_page.dart:128` 决定是否双列）、680/920/1180（`pages/games_page.dart:38` 决定游戏列数）又是另外四套。

**后果**：Windows 窗口在 780~899 之间（含最小窗口 780×560），RootShell 走「底部 Tab 栏」（因为 `tabletNav` 要 900），但首页走「12 列宽屏栅格」（因为 `width >= 780`），记账/食谱页走「手机版式」。用户在同一个窗口里会同时看到手机导航和桌面栅格。

**建议**：把断点收敛成一套常量，放在 `theme/breakpoints.dart`：

```dart
class CitroBreakpoint {
  static const double phone = 600;   // 手机 → 平板
  static const double compact = 780; // 窄桌面窗口下沿
  static const double sideBar = 900; // 侧栏出现
  static const double wide = 1025;   // 宽屏网页 / 桌面
}
```

所有页面只读这套常量，不再各自写魔数。这是本次审查里**性价比最高的一处改动**。

### 2.2 阅读宽度没有统一标尺

`maxWidth` 实际取值（grep 结果，摘关键项）：

| 位置 | 值 |
| --- | --- |
| `pages/home_page.dart:92` | 1120（wide）/ 760（compact） |
| `pages/games_page.dart:31` | 1120 / 840 |
| `pages/community_page.dart:544` | 1180 / 760 |
| `pages/me_page.dart:129,147` | 1040 / 760，内部再套 1040 |
| `pages/search_page.dart:20` | 固定 760 |
| `pages/res_page.dart:43` | 1120 / 840 |
| `theme/app_theme.dart:148`（全局 bottomSheet） | 固定 760 |

**后果**：1600×900 窗口下，「我的」页内容被限制在 1040，搜索页只有限制在 760，社区 feed 却放到 1180 —— 同一屏里三种阅读宽度，视线落点反复横跳。设置类页面（搜索、我的）在宽屏下始终是单列长列表，右侧留白 400px+。

**建议**：定义 3 档阅读宽度并全局复用：

- `reading = 760`（正文/设置/搜索，手机与窄窗口）
- `readingWide = 920`（>1280 的设置页、搜索页）
- `canvas = 1120`（首页栅格、游戏、资源等卡片流）

同时把设置类页面（`me_page`、`search_page`）在 >1280 时改成双列（左导航 + 右内容），避免单列长列表。

### 2.3 字号下限过低

`theme/tokens.dart:338-386` 定义了 8 档字号（`micro 8` → `poster 48`），但代码里大量出现**超出刻度范围**的小字：

```
pages/home_page.dart:1142        size: 8.5   （日历卡里的节日标注）
widgets/ledger_home_card.dart:173  size: 8.5
pages/cook_page.dart:726,914,1086,1378,1445,1482,2738  size: 9
pages/home_page.dart:1448,1467,1528,1551                 size: 9
pages/me_page.dart:643, play_page.dart:661, res_page.dart:508  size: 9
```

8.5px 的中文在 375pt 宽的屏幕上约等于 6.4 物理像素高的笔画，已经不可读。这些小字目前主要落在「邮票/胶带/角标」这类装饰位（符合 `tokens.dart:335-337` 的设计意图），但其中一部分是**功能性文字**（cook_page 的分类标签、home_page 的日历节日），不该用装饰字号。

**建议**：

- 正文/功能性文字最小锁到 `caption = 11`；
- 装饰性小字允许到 `micro = 8`，但必须只在固定尺寸容器内（邮票、胶带），且不接受系统字体放大；
- 把散落的 8.5 / 9 / 9.5 全部归到 `micro` 或 `small` 两档。

### 2.4 系统字体放大只做了全局 clamp，栅格高度没跟上

`main.dart:318-320` 用 `MediaQuery.withClampedTextScaling(min: 0.9, max: 1.15)` 把字体锁在 1.15 倍以内。但首页栅格的高度是按固定 `rowUnit`（`widgets/home_layout.dart:43`：wide 50 / compact 48）算的，卡片高度 = `slot.h * rowUnit + (h-1)*gap`（`home_bento.dart:111-113`），**文字放大不会让卡片长高**。

实测 `docs/shots-ui-review/phone-me-115.png`：1.15 倍字体下「我的」页已经接近临界，长昵称（`me_page.dart` 的 `maxLines: 1` + `ellipsis`）会截断；社区昵称、帖子正文在 1.15 倍时更容易触发截断。

**建议**：对带长文本的卡片（社区昵称、帖子正文、食谱标题、记账备注）改用 `maxLines: 2` + `overflow: ellipsis`，或让卡片高度按内容自适应（至少允许 `h` 在 1.15 倍时 +1 行）。

### 2.5 底部弹层宽度三套标准

`theme/app_theme.dart:148` 全局 bottomSheet 限宽 760，但各页又各自设：

- `overlays/ai_chat.dart:348` → 1600
- `overlays/composer_sheet.dart:77` → 1400
- `overlays/cook_editor.dart:371,404` → 2400
- `overlays/lantern_sheet.dart:323` → compact 460 / wide 1000

在 1600 窗口里，AI 对话和发帖编辑器会被拉到 1400~2400（实际顶到全屏宽），而天气、抽签等小弹层只有 400 —— 弹层尺度差异过大，视觉重心不稳。

**建议**：统一成两档：小弹层 400~460，全宽弹层 `min(1400, 屏宽-64)`。

### 2.6 胶带系统：样式 / 颜色 / 位置 / 尺寸四个维度全都单一 —— P1

胶带是手账视觉里出现频率最高的装饰元素，一共 **30 处调用**，但四个维度的变化几乎为零：

| 维度 | 现状 | 量化 |
| --- | --- | --- |
| 形状 | 只有「斜切四边形」一种 | 4 处 clipper 定义，其中 3 处逐行几乎相同 |
| 颜色 | 只有 3 个色 | `tape` ×9、`tape2` ×9、`tape3` ×12 |
| 位置 | 只有「顶部居中」一种 | `tapeTop` 参数 0 处使用，全部吃默认 `-9` |
| 尺寸 | 只有 92×24 一种 | `tapeWidth/Height` 仅 1 处使用（`home_page.dart:1312` 的 96×22） |

**形状**：4 个 clipper 定义分散在 4 个文件，且都硬编码 `shouldReclip => false`（永不按尺寸重算）：

- `widgets/paper.dart:169-179`
- `pages/games_page.dart:546-556`
- `pages/community_page.dart:1107-1117`
- `widgets/tab_bar.dart:258-270`（唯一的多边形变体，五边）

`Tape` 组件还留了一个 `torn` 参数（`widgets/paper.dart:119,130`），但 `true` / `false` 两条分支走的是**同一个斜切路径**，并没有真撕边。

**颜色**：只有 3 个 pastel 色，且**暗色模式下更淡**（`theme/tokens.dart:161-163` vs `196-198`）：

| | 亮色 | 暗色 |
| --- | --- | --- |
| `tape`（粉） | `0x9EF0B0B8`（62%） | `0x33E2A0AA`（20%） |
| `tape2`（蓝） | `0x9496C4E2`（58%） | `0x2E96BEDC`（18%） |
| `tape3`（黄） | `0x99F4D678`（60%） | `0x2EE2C878`（18%） |

暗色下 18~20% 的不透明度基本看不见，胶带在深色模式里等于消失了。颜色也没有语义 —— 待办、记账、打卡、天气各自的颜色是随手分配的，不是按卡片语义配的。

**位置**：30 处全部 `Alignment.topCenter`（`widgets/paper.dart:280-303`）。`tapeTop` 参数存在但没人用。没有左上斜贴、右上、双角贴、底边封条等变化。

**尺寸**：固定 92×24，导致**胶带占卡宽的比例在小卡上严重失控**。按栅格参数（`widgets/home_layout.dart:38-43`）算：

| 场景 | 卡宽 | 胶带 92 占比 |
| --- | --- | --- |
| 手机 compact，w=3 卡 | `(359-50)/6*3 + 20 ≈ 174` | **53%** |
| 手机 compact，w=6 卡 | 359 | 26% |
| 宽屏 wide，w=3 卡 | `(816-154)/12*3 + 28 ≈ 194` | **47%** |
| 宽屏 wide，w=6 卡 | 401 | 23% |

**证据**：`docs/shots-ui-review/crop-tape1.png`（375 屏「打卡」卡，粉色胶带几乎横跨卡顶一半）、`crop-tape3.png`（「待办」宽卡，黄色胶带只占 26%）。视觉上是「同一条胶带复制了 30 次」，而且在大卡上存在感不足、小卡上又过于醒目。

**材质**：胶带是纯色 `BoxDecoration`（`widgets/paper.dart:294-304`），没有和纸该有的半透明叠影、高光边、纤维毛边。全站只有 `GameTape`（`games/game_ui.dart:1367-1392`）画了一条 1px 高光线，主站的 `Tape` 没有。

**建议**：把胶带升级成一套有语义的小系统，统一放 `widgets/paper.dart`，替掉 4 处重复 clipper。

1. **形状 4 档**（`variant`）：
   - `paper`：现成的斜切四边形（默认，保持兼容）
   - `torn`：真撕边（锯齿路径，8~12 个齿）
   - `stamp`：邮票齿孔边（半圆序列）
   - `band`：无斜切的长条（用于底边封条）

2. **颜色 6 档 + 2 种材质**（`tone`）：在现有 3 色基础上新增 `tapeMint`（接 `mint`）、`tapeStamp`（接 `stamp` 红，用于提醒类卡片）、`tapeInk`（深色，用于标题条 / 封条）。暗色模式单独给值，不透明度提到 35~45%（现在是 18~20%，几乎不可见）。

3. **位置按卡片语义分配**（`align`）：

   | 卡片类型 | 位置 | 角度 |
   | --- | --- | --- |
   | 小卡（w ≤ 3 列） | 顶部居中 | -2.5° |
   | 功能卡（待办 / 记账 / 打卡） | 左上角斜贴 | -3° |
   | 信息卡（天气 / 星象 / 摸鱼） | 右上角 | +2.5° |
   | 大卡（w ≥ 6 列） | 左上短条 + 右下短条（双贴） | -2° / +2° |
   | 通栏卡（每日一言） | 底边封条 | 0° |

4. **尺寸按卡宽自适应**：`width = clamp(cardWidth * 0.3, 52, 104)`，小卡上从 53% 降到 30% 左右，大卡上从 23% 升到 30%，视觉权重趋于一致。

5. **材质细节**：给 `Tape` 加一条 1px 高光（复用 `GameTape` 的 `Colors.white.withValues(alpha: 0.12)` 做法）+ 0.5px 暗边；`torn` 档用 `MaskFilter.blur(BlurStyle.solid, 0.6)` 做纤维毛边。

---

## 3. 手机端（iPhone 6.3" / 6.9" 竖屏）

### 3.1 底部 Tab 栏固定宽度，窄屏贴边 —— P0

`widgets/tab_bar.dart:25-29`：

```dart
final barWidth = platform.isWindows ? 560.0 : 520.0;
final side = math.max(0.0, (MediaQuery.sizeOf(context).width - barWidth) / 2);
```

375pt 屏：`(375 - 520)/2 = -72.5 → side = 0`，于是 `Positioned(left: 8, right: 8)`（`tab_bar.dart:41-42`），Tab 栏宽度 359，左右各留 8pt。430pt 屏才有 5pt 缝隙。

**证据**：`docs/shots-ui-review/phone-375-home.png`、`phone-430-games.png` 对比，375 的 Tab 栏明显更贴边。

**建议**：`barWidth` 改成 `math.min(isWindows ? 560.0 : 520.0, screenWidth - 24)`，窄屏时自然收窄，而不是靠 `side` 夹紧。

### 3.2 装饰胶带悬在 Tab 栏外，压住卡片 —— P0

`widgets/tab_bar.dart:123-152`：胶带用 `Positioned(top: -9, ...)` 挂在 Tab 栏**上方** 9pt，并旋转 -1.8°。它的父级是 `SizedBox(height: AppSpacing.navBar)` 的 `Stack`（`tab_bar.dart:46-49`），`clipBehavior: Clip.none`，所以胶带会画到 Tab 栏之外，正好落在滚动内容上。

**证据**：`docs/shots-ui-review/phone-390x844.png`、`phone-375-home.png` 里，胶带正好压住「摸鱼日历」卡的标题左侧。桌面端截图（`win-1200x720.png`）因为内容区在侧栏右侧、Tab 栏不出现，所以看不到这个问题。

**建议**：胶带改成 `Positioned(top: -6)` 并只在 `width >= 400 && !sideNav` 时显示；或者直接收进 Tab 栏内部（`top: 2`），不再溢出。

### 3.3 CiCi 悬浮钮位置偏低，压住首页卡片 —— P0

`pages/home_page.dart:226-231`：

```dart
Positioned(
  right: math.max(18.0, (width - maxWidth) / 2 + 18),
  bottom: MediaQuery.paddingOf(context).bottom + 92,
  child: const AiHomeButton(),   // 56×56，ai_chat.dart:1603-1640
)
```

`bottom: 92` 是按「Tab 栏高 64 + 间距」估的，但 Tab 栏自身还额外下移了 `bottom + AppSpacing.x1`（`tab_bar.dart:43`），实际 Tab 栏顶边在 `safeBottom + 8 + 64 = safeBottom + 72`。92 只比 72 高 20pt，而按钮高 56 → 按钮底边落在 Tab 栏顶边上方 20pt，**按钮本身覆盖了 Tab 栏上方的卡片区域**。

**证据**：`phone-390x844.png` 中，CiCi 圆钮正好叠在「摸鱼日历」卡右下角，遮住了卡片里的箭头按钮。

**建议**：`bottom` 改成 `MediaQuery.paddingOf(context).bottom + AppSpacing.navBar + AppSpacing.x2`（即 safeBottom + 80），并在滚动时隐藏（监听 `_scroll` 的 offset）。

### 3.4 默认首页排布过长，首屏信息量少 —— P1

`widgets/home_layout.dart:309-322` 的 compact 默认布局一共 11 张卡，从 row 0 排到 row 27（`mood` 在 row 27，h=4 → 底部 row 31）。栅格高度 `_y(31) - gap = 31*58 - 10 = 1788pt`（compact rowUnit 48 + gap 10）。iPhone 6.3" 可视高度约 780pt，**首屏只能看到前 27%**。

**证据**：`phone-375-home.png` 首屏只到「待办」卡的中部；ASC 真机截图 `iphone-6.3-01-home.jpg` 首屏也只到「日历」。

**建议**：把 compact 默认布局里三张高卡压矮：

- `calendar` h: 6 → 4
- `zodiac` h: 5 → 3
- `quote` h: 4 → 3

这样栅格高度从 1788 降到约 1450pt，首屏能多露出 1~2 张卡。

### 3.5 游戏页列数阈值过宽，卡片偏小 —— P1

`pages/games_page.dart:36-39`：

```dart
final gameColumns = duo
    ? (width >= 900 ? 6 : (width >= 640 ? 5 : (width >= 460 ? 4 : 3)))
    : (width >= 1180 ? 7 : (width >= 920 ? 6 : (width >= 680 ? 5 : 3)));
```

非 Duo 分支从 680 直接跳到 5 列，375/390/430 全部落 3 列。375 屏卡片宽约 `(359-20)/3 ≈ 113pt`，图标区（`childAspectRatio: 1.06`，`games_page.dart:196-199`）高约 107pt，上下结构（图标 + 标题）显得局促。

**证据**：`phone-375-games.png` 对比 `ipad-games.png`（5 列），手机端的图标相对标题明显更小。

**建议**：非 Duo 改成 `width >= 920 ? 6 : (width >= 620 ? 5 : (width >= 400 ? 4 : 3))`，让 400pt 以上的大屏手机（6.7"）也能吃到 4 列。

### 3.6 社区登录空态的 CTA 过宽 —— P2

`pages/community_page.dart:796` 把空态卡限制在 `maxWidth: 600`，卡内「登录 / 注册」按钮是通栏 `AccentButton`。iPad 上这条按钮约 560pt 宽，视觉上是一块巨大的橙色矩形。

**证据**：`ipad-trash.png`、`win-trash.png`。

**建议**：给按钮单独加 `constraints: BoxConstraints(maxWidth: 360)` + `Center` 包裹。

### 3.7 「我的」页在手机上是整页路由 + 返回胶囊，与 iPad/Windows 浮窗不一致 —— P2

`pages/me_page.dart:93-103`：只有 Windows 和 iPad（`padSize`）走 `showMeWindow` 浮窗，手机走 `pushNamed('/me')` 整页。整页顶部再放一个 32pt 的「返回」胶囊（`me_page.dart:215-224`）。

**证据**：`phone-me.png` 顶部左侧的「← 返回」胶囊。

**建议**：手机端底部已有 Tab 栏，「返回」胶囊是冗余的。要么去掉（点底部 Tab 即可回首页），要么把它做成与状态栏对齐的顶部返回箭头，而不是一个带文字的胶囊。

### 3.8 首页顶栏层级偏平 —— P2

`pages/home_page.dart:130-181`：日期用 `heading(size: 20)`、星期用 `body(size: 11)`，两者间距 2pt；紧接着 `SizedBox(height: 12)` 就是卡片（`home_page.dart:181`）。375pt 屏上日期行高 48（固定 `SizedBox(height: 48)`），与卡片之间只有 12pt，层级偏挤。

**建议**：把 `SizedBox(height: 48)` 改成按内容高度，并把卡片间距拉到 16；或者给日期行加一个极淡的底色分隔。

---

## 4. iPad（11" / 13"，横竖屏）

### 4.1 同尺寸段体验割裂：11" 竖屏 vs 13" 竖屏 —— P1

`pages/home_page.dart:91` 用 `width >= 780` 判断是否走 12 列宽屏栅格，这里的 `width` 是**内容区宽度**（已减去 208pt 侧栏）：

| 设备 | 竖屏宽 | 内容宽 | `wide` | 实际栅格 |
| --- | --- | --- | --- | --- |
| iPad 11" | 820 | 612 | false | 6 列紧凑栅格 |
| iPad 13" | 1032 | 824 | true | 12 列宽屏栅格 |

**后果**：同样竖屏，11" 每张卡约 94pt 宽（6 列），13" 每张卡约 49pt 宽（12 列，但卡片跨 3 列 → 约 178pt）。两者卡片尺寸差一倍，视觉密度完全不同。

**建议**：把 `wide` 阈值下移到 600（`width >= 600`），让 11" 竖屏也走宽屏栅格；或者反过来把 13" 的卡片改为跨 4 列，让两档的卡片物理尺寸接近。

### 4.2 「我的」浮窗在横屏几乎顶满，内部还强制双列 —— P1

`pages/me_page.dart:46-47`：

```dart
final width = math.min(720.0, media.size.width - 48);
final height = math.min(760.0, media.size.height - 48);
```

iPad 13" 横屏逻辑尺寸 1376×1032 → 浮窗 720×760，上下各留 136pt，尚可。但 iPad 11" 横屏 1180×820 → 浮窗高 760，上下只剩 **30pt**；竖屏 820×1180 → 浮窗高 760，上下剩 210pt。

同时浮窗内 `MediaQuery` 被改写成 `Size(width, height)`（`me_page.dart:66`），于是 `twoColumn = width >= 700`（`me_page.dart:128`）在浮窗内恒为 true → 强制双列：左列 288pt（`me_page.dart:158`）+ 22pt 间距 + 右列 `Expanded`。720 宽下右列只有约 410pt，设置项（`隐私政策`、`用户协议`、`账号注销说明`）文字加右侧箭头会显得拥挤。

**证据**：`ipad-me.png`、`win-me.png` 的双列布局；11" 横屏的 30pt 边距在代码里可直接推出来。

**建议**：浮窗尺寸改成按短边比例（`height = media.size.height * 0.86`），并在浮窗内 `twoColumn = width >= 760`（让 720 宽的浮窗走单列滚动）。

### 4.3 侧栏信息密度低 —— P1

`widgets/tablet_shell.dart`：侧栏宽 208（`pages/root_shell.dart:40`），内容只有：

- 顶部 Logo + 标语（`100-140`）
- 「逛一逛」分组：首页 / 游戏 / 社区（+ Windows 的资源库）（`150-196`）
- 非 Web 追加「全站搜索」（`197-204`）
- 「我的 Citro」分组：食谱日记 / CiCi AI（`216-241`）
- 底部账号卡（`247-309`）

在 13" 竖屏（内容高 1376pt）里，侧栏只用了约 700pt，**下方约 600pt 是空白网格背景**。ASC 截图 `ipad-13-01-home.jpg` 也能看到侧栏底部只有一张账号卡，大片空白。

**建议**：把侧栏改成可滚动后，在中间补一个「快捷入口」分组（待办、记账、日历、星象），或者把账号卡固定在底部、中间用 `Spacer()` 撑开（现在已经有 `Expanded` 包着 `SingleChildScrollView`，`tablet_shell.dart:143-245`，但账号卡在 `Expanded` 外面、`SizedBox(height: 8)` 之上，所以确实贴底了 —— 空白其实来自分组本身太少）。补 4 个快捷入口即可填满。

### 4.4 游戏页在 iPad 用 5 列，图标偏小 —— P2

`pages/games_page.dart:38`：iPad 横屏内容宽 816 → `width >= 680` → 5 列，卡片约 `(816-40)/5 = 155pt`。竖屏内容宽 824 同样 5 列。

**证据**：`ipad-games.png`（5 列）对比 `win-games.png`（7 列，1200 窗口）。

**建议**：iPad 固定 4 列 + 更大图标（把 `childAspectRatio` 从 1.06 降到 1.15），或按 `padSize` 单独判断。

### 4.5 社区 feed 在 iPad 被拉宽 —— P2

`pages/community_page.dart:544-552`：`maxFeed = 1180`，iPad 上 `side = max(8, (824-1180)/2) = 8`，于是双列 feed 占满 824 宽 → 每列约 404pt。图片类帖子会被拉到 404pt 宽，像素和加载体积都不划算。

**建议**：`maxFeed` 在 `pad` 分支降到 `820`，与内容宽对齐。

### 4.6 侧栏分组标题字号过小 —— P2

`widgets/tablet_shell.dart:150-159`、`218-226`：分组标题用 `size: 11` + `letterSpacing: .8` + `w700`。11pt 加 0.8 字距的侧栏分组标题，在 iPad 的 2x 屏幕上约 22 物理像素高，接近可读性下限。

**建议**：提到 12（`CitroType.meta`），字距降到 0.5。

---

## 5. Windows 桌面端

### 5.1 780~899 宽区间导航语言混用 —— P1

`widgets/desktop_shell_io.dart:36-37`：默认 1200×720，最小 **780×560**。
`theme/breakpoints.dart:31-32`：`tabletNav` 要 `width >= 900`。

**后果**：窗口在 780~899（含最小窗口）时，RootShell 走**底部 Tab 栏**（`root_shell.dart:417-432`），但首页因为 `home_page.dart:91` 的 `width >= 780` 成立，走 **12 列宽屏栅格**。同一屏里手机导航 + 桌面栅格并存。

**证据**：`docs/shots-ui-review/win-780x560.png`（底部 Tab 栏 + 4 小卡横排）对比 `win-900x600.png`（侧栏 + 卡片）。

**建议**：把 `tabletNav` 下移到 `width >= 760`，与桌面壳最小宽度对齐；或把首页 `wide` 阈值提到 900，与侧栏一致。

### 5.2 顶部留白叠加，首屏被压低 —— P1

`widgets/desktop_shell_io.dart:20, 88-93` 把 `MediaQuery.padding.top` 强制抬到 `titleBarHeight = 30`，供 SafeArea 避开悬浮窗控。但各页又自己加顶部留白：

- `pages/home_page.dart:101`：`topPadding = width >= 700 ? 48 : 8`
- `pages/games_page.dart:120`：`AppSpacing.pageTop(width)` = 48
- `pages/calendar/calendar_page.dart:75`：同样 48
- `pages/search_page.dart:24`：`AppSpacing.pageTop(...)` = 48

Windows 内容宽 ≥780 恒为 48 → **实际顶部留白 = 30（SafeArea）+ 48（页面）= 78pt**，占 720 窗口高度的 **11%**。iPad 上 SafeArea 顶是状态栏（约 20~54），叠加后更明显但 iPad 更高所以不突兀；Windows 720 高就很吃紧。

**建议**：`CitroDesktopShell` 注入的 30pt 应该替代页面自己的 `pageTop`，而不是叠加。做法：页面改成 `AppSpacing.pageTop(width) - (isWindows ? titleBarHeight : 0)`，或把 `titleBarHeight` 从 `MediaQuery.padding.top` 里扣除。

### 5.3 默认首页布局在 Windows 上信息密度低于 Web —— P1

同一窗口尺寸（1200×720）：

- **Web**（`home_layout.dart:277-293`）：12 列 4 排，栅格高 `_y(13) - 14 = 13*64 - 14 = 818pt`，720 高基本一屏看完。
- **Windows / iPad 原生**（`home_layout.dart:295-307`）：12 列但卡片跨 6 列，排到 row 18（`mood` row 14 h4），栅格高 `_y(18) - 14 = 1138pt`，**720 高要滚 1.6 屏**。

**证据**：`win-1200x720.png`（Web，一屏看完）对比代码里的原生默认布局行数。

**建议**：Windows 默认布局直接复用 Web 的 12 列版本（把 `if (kIsWeb)` 的分支判断改成按 `platform.isWindows || kIsWeb`），或在 Windows 上把 `rowUnit` 从 50 降到 44。

### 5.4 窗控命中区在高 DPI 下偏小 —— P2

`widgets/windows_title_bar.dart:180-183`：`_WindowControl` 固定 `SizedBox(width: 32, height: 32)`，内部圆钮 28×28。Windows 用户常用 125%/150% 缩放，1200 逻辑宽的窗口在 150% 下物理尺寸只有 800px，32pt 的按钮物理上只有约 21px。

另外注释写「三枚 26px 圆钮 + 间距 + 右边距」（`desktop_shell_io.dart:22`），但实际是 28px 圆钮且**三个按钮之间没有间距**（`Row` 直接排三个 `_WindowControl`，`windows_title_bar.dart:110-130`），相邻圆钮之间只有 4pt 空隙，容易误点。

**建议**：

- 按钮之间加 `SizedBox(width: 4)`，整体宽度常量同步更新；
- 命中区按 `MediaQuery.devicePixelRatio` 或 `textScaler` 放大到 ≥40。

### 5.5 无边框窗口缩放边与 Win11 Snap 手势冲突 —— P2

`widgets/desktop_shell_io.dart:97-98`：`DragToResizeArea(resizeEdgeSize: 6)`。Win11 的贴靠布局在鼠标拖到屏幕边缘时触发，与 Flutter 的 6pt 缩放边同时响应，拖拽时会出现「窗口一边被拉伸、一边触发系统贴靠」的抖动。

**建议**：`resizeEdgeSize` 降到 4，并在 `_maximized` 时跳过（`CitroWindowControls` 已经知道 `_maximized`，把它传给外层即可）。

### 5.6 桌面端快捷键不足 —— P2

`widgets/desktop_shell_io.dart:177-182` 只绑定了返回（Esc / BrowserBack / Alt+←）。桌面用户预期至少还有：

- `Ctrl + K` / `Ctrl + F` → 全站搜索
- `Alt + 1~5` → 切 Tab
- `F5` / `Ctrl + R` → 刷新当前页数据

**建议**：在 `_DesktopShortcuts` 里补齐，并把 `Ctrl+K` 作为全局搜索入口（目前搜索只在侧栏，`tablet_shell.dart:197-204`）。

### 5.7 资源 Tab 只在 Windows 原生存在（潜在脆弱点）

`pages/root_shell.dart:56-57`：`_showResources => !kIsWeb && platform.isWindows`，`_tabCount` 随之在 4/5 之间变。但路由同步写死了一个 4 元素列表：

```dart
// root_shell.dart:240
syncWebRoute(const ['/home', '/games', '/trash', '/me'][i]);
```

目前不会崩，因为 `syncWebRoute` 只在 `kIsWeb` 时调用，而 Web 上 `_showResources` 恒为 false（`i` 最大 3）。但 `_pages` 固定 `List.generate(5, _pageAt)`（`root_shell.dart:67`）、`_visited` 也是 5 个（`root_shell.dart:64`），非 Windows 时 `index 3` 和 `index 4` 都会构造出 `MePage(embedded: true)`（`root_shell.dart:329-333`）。

**现状**：非 Windows 时 `index 4` 永远不会被 `_warmPage` 预热（只热 1/2/3，`root_shell.dart:91-93`），所以第 5 个 MePage 不会真正挂载，**暂时无害**。

**风险**：如果以后 Web 加第 5 个 Tab，`i = 4` 会直接 `RangeError`。

**建议**：把路由表改成 `_tabRoutes` 按 `_showResources` 动态生成，`_pages` / `_visited` 也按 `_tabCount` 生成，去掉硬编码的 5。

---

## 6. 优先级汇总

### P0（影响可用性 / 正确性，建议本周改）

| # | 问题 | 位置 | 端 |
| --- | --- | --- | --- |
| 1 | 断点阈值散落 10+ 处，同一窗口宽度在不同页面切换导航/栅格语言 | 全局 | 三端 |
| 2 | 底部 Tab 栏固定 520 宽，375 屏贴边 | `widgets/tab_bar.dart:25-29` | 手机 |
| 3 | 装饰胶带悬于 Tab 栏外，压住卡片 | `widgets/tab_bar.dart:123-152` | 手机 |
| 4 | CiCi 悬浮钮压住「摸鱼日历」卡 | `pages/home_page.dart:226-231` | 手机 |
| 5 | 阅读宽度七档并存，设置页在宽屏仍是 760 单列 | `pages/me_page.dart:129`、`pages/search_page.dart:20` 等 | 三端 |

### P1（明显观感问题）

| # | 问题 | 位置 | 端 |
| --- | --- | --- | --- |
| 6 | 默认首页 11 张卡排到 row 27，首屏只见 27% | `widgets/home_layout.dart:309-322` | 手机 |
| 7 | 游戏列数阈值过宽，大屏手机仍是 3 列 | `pages/games_page.dart:36-39` | 手机 |
| 8 | iPad 11" 竖屏 6 列 / 13" 竖屏 12 列，卡片尺寸差一倍 | `pages/home_page.dart:91` | iPad |
| 9 | 「我的」浮窗 760 高在 11" 横屏几乎顶满，内部强制双列 | `pages/me_page.dart:46-47,66,128` | iPad / Windows |
| 10 | 侧栏只填了 700pt，下方 600pt 空白 | `widgets/tablet_shell.dart` | iPad |
| 11 | 780~899 窗口「底部 Tab 栏 + 12 列栅格」混用 | `theme/breakpoints.dart:31-32` vs `pages/home_page.dart:91` | Windows |
| 12 | 顶部 30pt + 页面 48pt 叠加，占 720 高的 11% | `widgets/desktop_shell_io.dart:20,88-93` + `home_page.dart:101` | Windows |
| 13 | Windows 原生默认布局 1138pt 高，720 高要滚 1.6 屏 | `widgets/home_layout.dart:295-307` | Windows |
| 14 | 胶带系统形状/颜色/位置/尺寸四维度全单一，小卡上胶带占卡宽 53% | `widgets/paper.dart:111-167,280-303`、`theme/tokens.dart:161-163,196-198` | 三端 |

### P2（打磨项）

| # | 问题 | 位置 |
| --- | --- | --- |
| 14 | 字号下限压到 8~9.5px，含功能性文字 | `tokens.dart:338-386` + 散落各处 |
| 15 | 1.15 倍字体下卡片高度不跟上，长文本截断 | `main.dart:318-320` + `home_bento.dart:111-113` |
| 16 | 底部弹层宽度三套标准（400~2400） | `theme/app_theme.dart:148` 等 |
| 17 | 社区登录 CTA 通栏 560pt 宽 | `pages/community_page.dart:796` |
| 18 | 手机「我的」整页 + 返回胶囊与浮窗不一致 | `pages/me_page.dart:93-103,215-224` |
| 19 | 游戏页 iPad 5 列，图标偏小 | `pages/games_page.dart:38` |
| 20 | 社区 feed 在 iPad 被拉到 824 宽 | `pages/community_page.dart:544` |
| 21 | 侧栏分组标题 11pt + 0.8 字距偏小 | `widgets/tablet_shell.dart:150-159` |
| 22 | 窗控 32×32 无间距，高 DPI 下命中区偏小 | `widgets/windows_title_bar.dart:110-130,180-183` |
| 23 | 缩放边 6pt 与 Win11 Snap 冲突 | `widgets/desktop_shell_io.dart:97-98` |
| 24 | 缺 Ctrl+K / Alt+1~5 等桌面快捷键 | `widgets/desktop_shell_io.dart:177-182` |
| 25 | `_pages`/`_visited` 硬编码 5，路由表硬编码 4 | `pages/root_shell.dart:64,67,240` |
| 26 | 胶带 clipper 4 处重复定义且 `shouldReclip` 全硬编码 `false` | `paper.dart:169`、`games_page.dart:546`、`community_page.dart:1107`、`tab_bar.dart:258` |
| 27 | 暗色模式胶带不透明度仅 18~20%，近乎不可见 | `theme/tokens.dart:196-198` |
| 28 | `Tape.torn` 参数名存实亡，两分支同一形状 | `widgets/paper.dart:119,130,136` |

---

## 7. 建议的落地顺序

1. **先收断点**（P0-#1）：在 `theme/breakpoints.dart` 定义统一常量，把 `tabletNav`、`home_page`、`cook_page`、`ledger_page`、`games_page`、`community_page` 的魔数全部替换。这一步会同时修掉 P1-#11，是投入产出比最高的改动。
2. **再修手机两处遮挡**（P0-#3、#4）：胶带和 CiCi 按钮都是几行改动，用户感知最强。
3. **然后统一阅读宽度**（P0-#5）：定义 3 档 `reading / readingWide / canvas`，替换 15 处 `maxWidth`。
4. **补齐 iPad / Windows 的默认布局**（P1-#8、#9、#10、#13）：iPad 侧栏补快捷入口、浮窗高度按比例、Windows 默认布局复用 Web 版本。
5. **升级胶带系统**（P1-#14）：统一 `CitroTape` 组件（4 档形状 / 6 档语义色 / 5 种位置 / 尺寸按卡宽自适应），替掉 4 处重复 clipper，顺带补暗色模式色值（P2-#26、#27、#28）。胶带是手账视觉里出现频率最高的元素，改一处组件就能同时影响 30 个调用点。
6. **最后做 P2 打磨**：字号归档、窗控间距、快捷键、弹层宽度。

---

## 8. 验证方式

改完后建议按同一套尺寸重新出图对比，仓库里已有 `flutter/tool/build_web.sh` 可以产出 `flutter/build/web/`。本文档的截图就是用该产物在 headless Chrome 中渲染的，脚本逻辑可复用：

| 端 | 尺寸 | 重点看 |
| --- | --- | --- |
| 手机 | 375×812 / 390×844 / 430×932 | Tab 栏边距、胶带是否压卡、CiCi 位置、首屏卡片数 |
| 平板 | 834×1194 / 1024×768 | 侧栏占比、卡片列数、浮窗边距 |
| 桌面 | 780×560 / 900×600 / 1200×720 / 1600×900 | 断点切换点、顶部留白、栅格密度、窗控 |
| 胶带专项 | 375 / 834 / 1200 各一张 | 胶带占卡宽比例（目标 ≤30%）、同一屏内胶带颜色/位置是否有变化、暗色模式是否可见 |

真机（Windows / iOS）建议在改完后各跑一次，重点验证：Windows 最小窗口下的导航形态、iPad 横竖屏切换时首页栅格是否跳变、iPhone 系统字体调到「较大」时卡片是否截断。

---

## 9. 执行记录（2026-11-10 已改）

### 9.1 改了什么

**P0**

| 项 | 改动 | 位置 |
| --- | --- | --- |
| 断点收敛 | 新增 `CitroBreakpoint`（sideBar 760 / wideGrid 780 / desktopCanvas 1025 / twoColumn 700 / readingWide 1120）与 `CitroReading`（reading 760 / readingWide 920 / canvas 1120 / feed 1180） | `theme/breakpoints.dart` |
| 断点替换 | cook / ledger / calendar / todo / gnono / gsheep / gsnake / card_collection 的 900 与 760 全部改用常量；community / games 的 1025、760 也改用常量 | 12 个文件 |
| Tab 栏边距 | `side` 保底 `AppSpacing.x1`，375 屏从 8pt 边距变成 16pt | `widgets/tab_bar.dart` |
| Tab 栏胶带 | 从 `top: -9`（探出栏外压住卡片）改成 `top: 2`（收进栏内顶部） | `widgets/tab_bar.dart` |
| CiCi 悬浮钮 | 移除压在「摸鱼日历」数字上的 56pt 悬浮按钮，改成页头右侧的 40pt 圆形按钮 | `pages/home_page.dart` |
| 阅读宽度 | home / games / community / res / search / me 统一走 `CitroReading`；设置类页面在 >1120 放宽到 920 | 6 个文件 |

**P1**

| 项 | 改动 | 位置 |
| --- | --- | --- |
| 胶带系统 | 新增 `CitroTape`（4 形状 × 6 语义色 × 自定义角度/尺寸/阴影）+ `_CitroTapePainter`（高光边、真撕边、邮票齿孔）；`PaperCard` 胶带宽度按卡宽 `clamp(卡宽*.3, 52, 104)` 自适应 | `widgets/paper.dart` |
| 胶带去重 | 删掉 5 份重复的 `_TapeClipper` / `_TapeClip`，全部改用 `CitroTape` | paper / games_page / community_page / modal / tab_bar |
| 暗色胶带 | 暗色下 `tape` / `tape2` / `tape3` 不透明度从 18~20% 提到 35% | `theme/tokens.dart` |
| 紧凑首页默认布局 | 日历 6→4、星象 5→3、一言 4→3，栅格从 1788pt 压到 1498pt | `widgets/home_layout.dart` |
| 游戏列数 | 非 Duo 增加 400~619 档（4 列），大屏手机不再只有 3 列 | `pages/games_page.dart` |
| 小工具列数 | Web 与原生统一成 `(all.length/2).ceil()`，原生不再 7 列挤成一行 | `pages/games_page.dart` |
| 侧栏密度 | 新增「快捷入口」分组（待办清单 / 记账本 / 日历 / 听隅），分组标题 11→12 | `widgets/tablet_shell.dart` |
| Windows 顶部留白 | `AppSpacing.chromeTopInset` 让 `pageTop()` 扣掉壳注入的 30pt，首屏从 78pt 降到 48pt | `theme/tokens.dart`、`widgets/desktop_shell_io.dart` |
| 我的浮窗 | 高度按 `min(760, 屏高*.86)`，浮窗内强制单列滚动 | `pages/me_page.dart` |
| iPad 侧栏 | `tabletNav` 从 900 降到 760 后，iPad 11" 竖屏（820pt）也有侧栏了，和 13" 一致 | `theme/breakpoints.dart` |

**P2**

| 项 | 改动 | 位置 |
| --- | --- | --- |
| 窗控间距 | 三枚窗控之间加 4pt，整体宽度 118→116 | `widgets/windows_title_bar.dart`、`desktop_shell_io.dart` |
| 桌面快捷键 | 补 Ctrl/⌘+K 搜索、Alt+1~5 切 Tab | `widgets/desktop_shell_io.dart` |
| 缩放边 | `resizeEdgeSize` 6→4，减少与 Win11 贴靠抢鼠标 | `widgets/desktop_shell_io.dart` |
| Tab 路由 | `_tabRoutes` 动态取，`_pages` / `_visited` 按 `_tabCount` 生成 | `pages/root_shell.dart` |
| 弹层宽度 | ai_chat 1600→1400、cook_editor 2400→1400 | `overlays/ai_chat.dart`、`overlays/cook_editor.dart` |
| 登录 CTA | 社区空态按钮从通栏 560pt 收到 360 居中 | `pages/community_page.dart` |

### 9.2 三处与原清单估计不同的地方（修正）

1. **「375 屏 Tab 栏贴边」没有那么严重。** 实测 375 屏下 `side = 0`，但 `Positioned` 两侧还有 `x1 = 8`，所以实际是左右各 8pt 边距，不是完全贴边。改动后保底 16pt，属于打磨而非修复。
2. **Windows 窗控不需要按 DPR 放大。** Windows 的显示缩放会体现在 `devicePixelRatio` 上（150% → 1.5），固定 32 逻辑像素的按钮在 150% 下是 48 物理像素，和 Windows 原生标题栏按钮（100% 下 30px → 150% 下 45px）基本一致。原清单「高 DPI 下命中区偏小」的判断是错的，只保留了按钮间距的改动。
3. **Windows 默认首页布局故意和 Web 不同，不该改。** README 明确写「Windows 桌面端采用 iPad 同款界面与动效；Web 宽屏继续使用手账桌面布局」，所以两列大卡（Windows / iPad）与 12 列密集（Web）的差异是设计意图。原清单 P1-#13 把它当成密度 bug 是误判，未改。

### 9.3 刻意保留的行为

- **Windows 最小窗口 780×560 仍是底部 Tab 栏。** `tabletNav` 除了宽度还要求 `shortestSide >= 600`（否则横握手机也会弹出侧栏）。560 高不满足，所以最小窗口没有侧栏。这是有意的折中：560pt 高的窗口塞 208pt 侧栏，内容区只剩 572×560，过于局促。改动后 800×600 及以上的窗口都会显示侧栏。
- **手机「我的」页仍有返回胶囊。** 底部 Tab 栏已在同一屏，胶囊和 Tab 语义重复；但它同时承担「返回顶部」的视觉锚点作用，且改动会牵涉 `popOrHome` 的所有调用方，本次未动。

### 9.4 未完成的项

| 项 | 原因 |
| --- | --- |
| 字号下限归档（P2-#14） | 涉及 20+ 处 `size: 8.5 / 9 / 9.5`，部分在固定尺寸容器里，改动后需要逐屏核对是否溢出，留待下一轮 |
| 1.15 倍字体下卡片高度（P2-#15） | 栅格高度由 `rowUnit` 固定，改动会影响拖拽吸附逻辑，风险较高 |
| 社区 feed 在 iPad 收窄（P2-#20） | 实测双列各 404pt，可读性可接受，收益不大 |
| iPad 游戏 4 列（P2-#19） | 5 列在 816pt 内容宽下每张卡 155pt， already 合理 |

### 9.5 验证

- `flutter analyze`：改动前后均为 **162 issues / 3 errors**，3 个 error 全部在 `test/web_desktop_test.dart`（引用已删除的 `lib/pages/web_home.dart`），**属改动前就存在**，非本次引入。
- `flutter build web --release`：通过（Flutter 3.47.7，与项目 `.metadata` 的 revision 一致）。
- 截图对比：改动前在 `docs/shots-ui-review/`，改动后在 `docs/shots-ui-review/after/`（21 张，含手机 375/390/430、平板 834/1024、桌面 780/900/1200/1600，以及暗色模式）。
- **需要真机复核的两点**：① iPad 11" 竖屏现在会显示侧栏（原先没有），这是有意的变更，请在真机确认首页栅格在 626pt 内容宽下是否拥挤；② Windows 最小窗口仍是底部 Tab 栏，确认这个折中可接受。
