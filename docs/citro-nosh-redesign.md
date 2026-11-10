# Citro · nosh 风格重设计（2026-11）

> 用户要求：抛弃手账风、参考 nosh（`com.chaochaoshishi.nosh`，AI 饮食记录 App）、
> 尽量多圆角、不要忽略深色模式、顺手修遗留 bug。
>
> 本文档记录新的设计系统、迁移范围与已知后续项。代码真相在
> `flutter/lib/theme/tokens.dart`、`flutter/lib/theme/app_theme.dart`、
> `flutter/lib/widgets/paper.dart`。

---

## 1. 设计方向

| 维度 | 旧（手账拼贴 / Paper Desk） | 新（nosh 式干净圆润） |
| --- | --- | --- |
| 表面 | 奶油纸 + 24px 网格 + 纸纹 + 暖光 | 暖白 / 近黑纯色，无纹理 |
| 卡片 | 1px 发丝描边 + 暖棕投影 + 14 圆角 + 胶带 + 折角 | 无描边 + 柔和纯黑阴影 + 24-28 圆角 |
| 字体 | Kalam / ZCOOL KuaiLe / Caveat（手写） | Resource Han Rounded CN（圆体）+ Xiaolai Mono（数字） |
| 强调 | 荧光笔底 + 橙色短横 + 印章红圆点 | 品牌橙只用于选中 / 图标 / 链接 / 进度 |
| 主按钮 | 品牌橙实底 + 深字 | 近黑（深色主题近白）胶囊 + 反色字 |
| 分隔 | 虚线 | 1px 发丝线 |
| 装饰 | 胶带 / 拍立得 / 便签 / 装订孔 / 水印 | 无（仅照片可用 StickerFrame 虚线框） |

参考截图（nosh App Store）显示：白/暖白卡片、超大圆角、黑胶囊按钮、
按场景切换的粉彩底（#E7E7E7 / #E0EDF5 / #FEF3D5 / #FFEBE0 / #F5FCEA），
数字用等宽字体。这也是本轮的调色与组件来源。

---

## 2. 设计令牌

### 2.1 颜色（`CitroColors`）

浅色（默认）：

```
bg #F4F3EF   bg2 #E9E7E1   surface #FFFFFF   surface2 #F4F3EF
ink #171614  ink2 #57544D  inkSoft #78756C（白底 4.6:1，过 AA）
line #ECEAE4 line2 #DDD9D0
accent #FF8A1F  accent2 #E5730F  accentLt #FFD9AE
accentInk #8A4A0B  onAccent #2E2C22（橙底上的深字）
mint #2F9E6B  mintInk #1F7A50  mintSoft #E6F5EC  mintLine #CBE7D8
stamp #C4452C（朱砂红，日历「宜」/强调）
danger #DE3B40  dangerSoft #FDECEC
hl #66FFD166（荧光黄，标记重点）
tintYellow #FEF3D5  tintPink #FDECEF  tintBlue #E9F2F9
tintGreen #F0F8EA   tintNeutral #F1F1F1
```

深色（近黑表面 + 同一强调色）：

```
bg #0E0F11   bg2 #090A0C   surface #17181B   surface2 #1F2125
ink #F2F1EC  ink2 #C7C5BD  inkSoft #8E8C84
line #1AFFFFFF  line2 #29FFFFFF（白色透明，不用灰）
accent #FF9E45  accent2 #FF8A1F  accentLt #FFC890
accentInk #FFB877  onAccent #1A1206
mint #5CC98E  mintInk #8FE0B4  mintSoft #17281F  mintLine #2A4034
stamp #E0796A  danger #FF6E73  dangerSoft #2A1718
hl #40FFD166  tintYellow #241F11  tintPink #251719
tintBlue #152029  tintGreen #16211A  tintNeutral #17181B
```

深色的粉彩底是「压暗的同色相」，不是浅色版本的透明度叠加，避免暗面上发灰。

### 2.2 圆角（`AppRadii`）

`page 28` / `card 24` / `inner 16` / `field 16` / `button 999` /
`modal 28` / `chip 999` / `small 12` / `xs 8` / `avatar 999`。

比旧体系（16/14/12）整体放大一档，所有可见容器都带明显圆角。

### 2.3 字阶与字重（`CitroType`）

`micro 9` / `small 11` / `caption 12` / `meta 13` / `label 14` /
`body 15` / `bodyLg 16` / `title 18` / `titleLg 20` / `subtitle 22` /
`heading 26` / `display 32` / `hero 40` / `poster 56`。
字重三档：`regular 400` / `medium 500` / `strong 700`。

### 2.4 字体资源

来源：nosh APK 内置的 **Resource Han Rounded CN**（OFL 1.1）与
**Xiaolai Mono**（OFL 1.1），按 Citro 的字符集子集化后放入
`flutter/assets/fonts/`：

| 文件 | 用途 |
| --- | --- |
| `rounded-400-app.ttf` / `rounded-500-app.ttf` / `rounded-700-app.ttf` | 正文 / 标签 / 标题（圆体） |
| `mono-app.ttf` | 数字与数据读出（等宽） |

旧字体（Kalam / ZCOOL / Caveat / Noto Sans SC）已从 pubspec 与仓库移除。
重新生成：`python devtools/build-rounded-fonts.py --src-dir <nosh 字体目录>`。

---

## 3. 组件层（`flutter/lib/widgets/paper.dart`）

| 组件 | 说明 |
| --- | --- |
| `CitroBackground` | 页面底，纯色或极轻渐变，无网格 |
| `CitroCard` | 卡片基座：24 圆角、柔和阴影、无描边、无胶带、无折角 |
| `CitroButton` + `CitroButtonStyle` | 胶囊按钮；`primary`=近黑，`accent`/`mint`/`danger`/`outline`/`ghost`/`surface` |
| `CitroChip` / `CitroSectionHeader` / `CitroTextField` | 胶囊标签 / 分区标题 / 输入框 |
| `CitroStat` | 指标块（小标签 + 等宽数字） |
| `StickerFrame` | 虚线贴纸相框（只用于照片/插画） |
| `CitroAvatar` / `CitroProgressBar` / `CitroDivider` | 头像 / 胶囊进度 / 发丝线 |
| `Pressable` / `AppIcon` / `AppIcons` / `AppToast` / `copyText` | 风格无关，保留 |

旧组件（`PaperCard` / `PaperBackground` / `Tape` / `SectionTitle` /
`HandChip` / `DashedLine` / `HighlightedText`）保留为**弃用替身**，
渲染新风格或直接不渲染，供迁移期兜底；新代码不应再引用。

---

## 4. 深色模式

- `AppState.themeMode` 持久化到 Prefs `cm-theme-mode`，`MaterialApp` 用
  `theme` / `darkTheme` 分别构建 `CitroColors.light` / `darkColors`，
  经 `CitroSkin` ThemeExtension 由 `context.c` 下发。
- 所有颜色走 token，不再有「浅色 + 滤镜」。
- 本轮修掉的深色缺口：
  - 日历月份箭头硬编码棕色（深色下不可见）→ `c.inkSoft`；
  - 「今天」格子 accentLt 底 + ink 字（对比度 1.2:1）→ accent 底 + onAccent 字；
  - 搜索面板硬编码暖棕底 + 荧光黄标签 → `c.surface` + `c.surface2`；
  - 启动页 / 崩溃页 / 友好错误页硬编码奶油底 → `context.c.*`；
  - Windows 原生窗口背景硬编码浅色 → 透明；
  - 窗控 hover 用荧光黄/印章红 → 中性半透白 + 系统红；
  - TabBar 选中胶囊深色用荧光黄 → 品牌橙。

---

## 5. 本轮顺带修掉的 bug

| 问题 | 位置 | 处理 |
| --- | --- | --- |
| 侧栏共享高亮索引 clamp 错位（「我的」不高亮而不是停到最后一项） | `tablet_shell.dart` `_SidebarNav` | `index >= count` 时 opacity 0 |
| 窗控宽度 96 与预留 118 不一致 | `windows_title_bar.dart` / `desktop_shell_io.dart` | 加两段 11pt 间距，注释同步 |
| 横向滑动切 Tab 在 Web 桌面误触发 | `root_shell.dart` | 仅 Android/iOS 触屏包裹手势 |
| `CitroOrientation.sync` 在 build 里调用 | `root_shell.dart` | 移到首帧后并按尺寸去重 |
| 语音识别每次状态变化 debugPrint | `services/speech.dart` | 删除调试输出 |
| `HistoryTodayCard` 死代码 | `widgets/history_today.dart` | 删除文件 |
| 星象卡星点/星座 painter | `home_page.dart` | 删除 `_ZodiacSkyPainter` |

---

## 6. 版式重排（2026-11 第二轮）

用户要求「排版完全重排，包括 tab、所有 UI / 布局 / 分类」，在保留全部功能的前提下重排：

- **导航**：底部 Tab 从 4/5 格（Windows 多一个「资源」）统一为 **4 格：首页 / 游戏 / 社区 / 我的**，
  全平台一致；资源库不再占 Tab，收进「我的 → 资源」与首页资源卡。
- **首页**：新增 **英雄区**（`_HomeHero`）——问候语 + 日期 + 天气 / 待办 / 打卡三项状态 +
  「调整布局」按钮，取代原来只有一行日期的页眉；Bento 默认布局改为
  「状态条 → 待办/天气 → 食谱/日历 → 星象/心情 → 一言」。
- **游戏中心**：14 款游戏从一整坨平铺改为 **益智 / 休闲 / 文字 / 创意** 四类分组，
  每类带小节标题。
- **我的**：新增「资源」分组（资源库入口），版本 / 关于 / 联系分组保留。
- **深坑修复**：`CitroSectionHeader` 内含 `Expanded`，被放进无界宽度的 `Row` 时会触发
  `RenderFlex children have non-zero flex but incoming width constraints are unbounded`
  （游戏页小工具小节），已改为纯文字标题。

## 7. 迁移范围

- 外壳：`root_shell` / `tablet_shell` / `tab_bar` / `windows_title_bar` /
  `desktop_shell_io` / `main.dart`（启动与错误页）。
- 首页：`home_page.dart`（12 张卡）、`home_entries.dart`、`home_bento.dart`、
  `home_layout.dart`（默认布局重排）、`weather_widgets.dart`、
  `global_search.dart`、`todo_home_card.dart`、`mood_home_card.dart`、
  `ledger_home_card.dart`。
- 模块：社区、食谱、我的、资源、搜索、灵敏度、抽签、法律页、Web 桌面、
  overlays（抽卡/签文/金币/天气/摸鱼/番茄钟等）、待办、记账、日历、听隅、游戏。
- 尚未处理：旧版网页（根 `index.html` + `styles/`）的归档决策、
  App Store 检查单、`lib/games/gliquid*.dart` / `gbrake*.dart` 等生产已不走的原生实现
  （仅 preview/golden 测试引用，可后续删除）。
- 验证：`flutter analyze` 0 error / 0 warning；`test/preview/**` 与 `test/duo_*` 共 32 个
  视觉 golden 全部通过（批量跑会有偶发超时，单跑均通过）；
  Web 端实测浅色 / 深色、桌面 / 手机均正常，且不再出现
  `RenderBox was not laid out` / `non-zero flex ... unbounded` 断言。
- 设计系统自检：`flutter test --no-pub test/nosh_preview_test.dart`
  （light / dark 两张 golden，见 `test/goldens/nosh-{light,dark}.png`）。
  注意 `flutter_test` 不会自动加载 pubspec 字体，测试里用 `FontLoader` 显式加载。
