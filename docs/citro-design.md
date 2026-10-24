# Citro 品牌升级 · 视觉执行规范（团队共用）

> 站点品牌从「迟暮·Crew」升级为 **Citro**。
> 设计方向：**Citrus Soda（柑橘汽水）** —— 奶油纸底、鲜橙主色、薄荷副色、大圆角、手绘贴纸感；
> 干净明亮、活泼但不幼稚。旧的「暖纸 + 衬线 + 金色」体系全部退役。

---

## 1. 关键文件与归属

| 文件 | 归属 | 说明 |
| --- | --- | --- |
| `index.html` | **仅 Lead 可改** | 巨型的单页应用（HTML+CSS+JS 全部内联）。其他成员如需改结构，发消息给 Lead 并给出精确的旧/新片段。 |
| `styles/citro-core.css` | 仅 Lead | 设计令牌 / 基础 / 壁纸 / 顶栏 / Hero / 共享弹层按钮 / 底部 Tab。 |
| `styles/citro-home.css` | 仅 Lead | 首页 Bento 各模块。 |
| `styles/citro-community.css` | 社区视觉负责人 | `.page-trash`、登录注册弹窗、发帖/评论/消息。 |
| `styles/citro-cook.css` | 食谱视觉负责人 | `.page-cook` 全部。 |
| `styles/citro-games.css` | 游戏视觉 A | `.page-g` 公共框架 + 2048 / 记忆卡牌 / 数独 / 数织 / 数字华容道 / 贪吃蛇。 |
| `styles/citro-arcade.css` | 游戏视觉 B | 羊了个羊 / 跳一跳 / 淘气小球 / 极限刹车 / 成语接龙 / 飞花令。 |
| `styles/citro-pages.css` | 页面视觉负责人 | 我的、资源、搜索、抽签、灵敏度、手机 Tab 细节。 |
| `styles/citro-overlays.css` | 浮层视觉负责人 | 运势 / 星盘 / 天气 / 摸鱼日历 / 打卡 / 笔记 / 吃什么 / 抛硬币 / 赞赏 / 番茄钟 / 日历天气卡。 |
| `素材/` | 素材负责人 | 壁纸、logo、favicon、OG 图。 |
| `fonts/` | 素材负责人 | 字体子集。 |

加载顺序（写在 `</head>` 前）：core → home → community → cook → games → arcade → pages → overlays。
后加载的同优先级规则生效，因此**页面文件必须在自己的作用域内覆盖**，不要去改 core/home。

---

## 2. 设计令牌（只可使用这些语义色；页面文件里也不要再写新的品牌色）

### 浅色（默认）
```
--bg:#EDE6D6          柔和奶油纸（降白一档）
--bg-2:#E6DFCF        次级纸
--surface:#F6EFDF
--ink:#2E2C22         主墨（深橄榄）
--ink-2:#575446
--ink-soft:#67634F
--line:#E8E1D0
--line-2:#D8D0BB
--accent:#F2A43C      品牌橙（填充）
--accent-2:#DE8A1F
--accent-lt:#FFC873
--accent-ink:#9A5606  浅底上的橙色文字（过 AA）
--mint:#7FC49C        品牌薄荷
--mint-ink:#2F7357    浅底上的绿色文字（过 AA）
--mint-soft:#E3F3E7
--mint-line:#C9E6D3
--glass-card-bg:rgba(255,253,247,.76)
--shadow-sm / --shadow-md / --shadow-lg
--r-lg:22px / --r-md:16px / --r-sm:12px
```

### 深色 `html[data-theme="dark"]`（中性炭夜，深灰不偏色，只留极轻暖调）
```
--bg:#0C0C0F   --bg-2:#121216   --surface:#18181D
--ink:#EFEDE6  --ink-2:#C6C2B8  --ink-soft:#A09C92
--accent:#FFA94D  --accent-2:#E08A24  --accent-lt:#FFD2A0  --accent-ink:#FFBE6A
--mint:#C9D3B2  --mint-ink:#D8DFC4  --mint-soft:rgba(201,211,178,.11)
--glass-card-bg:rgba(22,22,26,.94)
```

### 用色规则
- **橙色 = 主行动 / 强调**；**薄荷 = 次级 / 成功 / 收藏 / 标签**；**奶油/白 = 大面积底**。
- 禁止再出现金色、黄铜色、深棕「暖纸」大色块（旧的 `--gold` 已改挂薄荷深色）。
- 深色模式必须逐块照顾：不要只改浅色，`html[data-theme="dark"]` 作用域下写完并用截图验证。
- 文字对比度：正文 ≥ 4.5:1；大字号 ≥ 3:1。浅底橙字用 `--accent-ink`，浅底绿字用 `--mint-ink`。
- 纯橙色按钮上的字用 `#2E2C22`（深墨），不要白字。

---

## 3. 字体与形状

- 标题 / 数字 / 品牌字：`var(--font-d)` = **ZCOOL KuaiLe**（手绘感圆体）。它只有 400 字重，
  统一用 `font-weight:400`，不要再写 700（会触发合成粗体发糊）。
- 正文 / UI：`var(--font-b)` = Noto Sans SC。正文 400，强调 600/700。
- 衬线体（Noto Serif SC）与书法体（Ma Shan Zheng）**全站不再使用**。
- 形状规则：**卡片 22px 圆角；卡内小卡/图片 16px；输入框/小按钮 12px；主按钮/胶囊一律 999px**。
  同一页面内不要混用直角与圆角。
- 卡片材质：白奶油半透明（`--glass-card-bg`）+ 1px 白色高光边 + 柔和暖投影；
  浮层用 `--glass-pop-bg` + `--glass-pop-shadow`；不要用重色玻璃或黑色投影。
- 装饰：可用 `素材/citro-logo.png`（唯一 logo） 做低透明度贴纸/水印（≤0.16），
  或橙色/薄荷色 radial-gradient 光斑。**不要手绘新的 SVG 路径图标**；图标沿用页面已有 SVG。
- 动效克制：保留原有交互反馈即可，不加常驻无限动画。

---

## 4. 页面地图（SPA hash 路由）

| 路由 | 页面 | 容器 |
| --- | --- | --- |
| `#/home` | 首页 | `.main-root`（Lead 负责） |
| `#/res` | 资源（Mod / 工具 / 驱动） | 复用 `.tile-mods/.tile-tools/.tile-drivers` |
| `#/games` | 游戏中心（手机壳） | `body.view-games` |
| `#/cook` | 食谱日记（Nombook） | `.page-cook` |
| `#/trash` | Citro 社区 | `.page-trash` |
| `#/me` | 我的（手机壳） | `.tile-me#pageMe` |
| `#/search` | 聚合搜索 | `.page-search` |
| `#/play` | 玩法抽签 | `.page-play` |
| `#/sens` | 灵敏度转换 | `.page-sens` |
| `#/g2048 #/gmem #/gsudoku #/gnono #/gslide #/gsnake` | 小游戏 | `.page-g` |
| `#/gsheep #/gjump #/gpeng #/gbrake #/gidiom #/gfeihua` | 小游戏 | `.page-g` |

弹层（不改变路由）：登录/注册、发帖、评论、消息、运势 2.0（每日/本命/行运）、天气、摸鱼日历、
打卡、笔记、吃什么、抛硬币、赞赏码、番茄钟、跳转确认。

---

## 5. 本地验证方法（必须做）

本地静态服务器已经跑在 **http://127.0.0.1:8019/**（含 `/trashapi` 反向代理，社区 API 可用）。
Chrome 无头截图（每人均可使用；请在 config 里给**不同端口**避免冲突）：

```powershell
$node='C:\Program Files\nodejs\node.exe'
$chrome='C:\Program Files\Google\Chrome\Application\chrome.exe'
$base='http://127.0.0.1:8019/'
$light="document.documentElement.setAttribute('data-theme','light');localStorage.setItem('cm-theme-mode','light');"
$shots=@(
  [ordered]@{name='x-home-light'; url=$base+'#/home'; w=1440; h=1000; wait=2600; after=1000; prep=$light}
)
$cfg=@{outDir=(Join-Path (Get-Location).Path '_tmp\team\<你的名字>'); port=9350; browser=$chrome; shots=$shots}
[System.IO.File]::WriteAllText((Join-Path (Get-Location).Path '_tmp\team\<你的名字>\cfg.json'),($cfg|ConvertTo-Json -Depth 5),(New-Object System.Text.UTF8Encoding($false)))
& $node devtools\_tmp\shot.js '_tmp\team\<你的名字>\cfg.json'
```

- 桌面：`1440x1000`（另建议 `1280x800` 看紧凑屏）
- 手机：`w=390 h=844 mobile=true`
- 浅色 / 深色各截一次（`prep` 里切 `data-theme`）。
- 需要 DOM / 计算样式 / console 错误 / 404 时，可用 `_tmp/tools/probe.js`：
  `node _tmp/tools/probe.js 'http://127.0.0.1:8019/#/trash' '@_tmp/expr.js' 1440 1000`
  （表达式也可以直接传单行 JS；`@文件` 从文件读脚本）
- 社区页未登录只显示门禁。可注册测试号查看完整 Layout：注册接口
  `POST /trashapi/api/auth/register`，邀请码 `MinT`（参考 `trash/trash.js` 的路由）。
  或在页面上用 UI 注册：昵称随意、密码 ≥ 6 位。
- 改完必须亲自看截图，确认：无横向溢出、无文字被裁切、浅深色都协调、按钮/输入可读。

---

## 6. 验收清单（交回时逐条确认）

- [ ] 只改了自己负责的文件，没有改 `index.html` / core / home / 别人的文件。
- [ ] 浅色 + 深色、桌面 + 手机截图各至少 1 张，存放于 `_tmp/team/<名字>/`。
- [ ] 页面内不再出现旧品牌「迟暮 / Crew」、旧金色 / 深棕纸色。
- [ ] 标题使用 `--font-d` 且 `font-weight:400`；正文对比度过 AA。
- [ ] 圆角/按钮/材质遵循第 3 节。
- [ ] console 无新增报错，资源无 404。
- [ ] 在回复里给出：改了什么、截图路径、发现但未解决的跨范围问题。


## 8. 用户后续修订（2026-10-19 晚）

- **唯一 logo 不加白底**：所有 `<img>`/CSS 展示位均改为透明直放（Hero、品牌胶囊、游戏侧栏、底栏、社区/食谱空状态、登录弹窗、水印）。
- **删除中文副品牌**：全站不再出现「柑橘小窝 / 柑橘小屋」字样（标题、Hero、底栏、coin、manifest、社区页脚均改回 Citro 或删除）。
- **深色模式多次调整**：绿黑(#1B241E)→暖可可(#322A1B)→中性炭(#232327)→最终**纯粹近黑** `#17171A / #1D1D21 / #242429`（整页纯平背景、无彩色光晕/渐变脏底；卡片用 rgba(30,30,34,.92) 抬一档；橙色与鼠尾草绿只作点缀）。


## 9. 最终状态补充（2026-10-19 收尾）

- **背景**：不使用任何照片壁纸，浅色为奶油渐变 + 橙/鼠尾草绿柔光；深色为中性炭灰渐变 + 极淡橙/绿光，壁纸文件仅留存备查。
- **logo**：最终使用用户指定的两枚同源资产：`素材/citro-logo.png`（透明，页面展示）与 `素材/citro-logo-square.jpg`（奶油底方图，favicon/PWA/OG）。页面内一律透明直放、无白底。
- **调色板**：回到与 logo 同源的鼠尾草绿 `--mint:#8CC79E / --mint-ink:#2F7357`，橙 `--accent:#F2A43C`；深色 mint `#A8D5B5`、橙 `#FFB25C`。


## 10. 用户最终审美修订

- 深色模式改为 **pure dark**：整页 `#17171A` 纯平近黑、无壁纸、无彩色背景光晕；页面容器统一压成纯平底；卡片 `#1E1E22` 系抬一档；文字 `#F3F1EA`；橙 `#FFAE52`、鼠尾草绿 `#A8D5B5` 只作点缀。
- 深色顶栏 logo 白底问题已修复：`html[data-theme="dark"] .brand-chip img` 背景透明；所有 logo 展示位统一透明直放。


## 11. 最终视觉微调（用户反馈后）

- **浅色降白**：页面底 #EDE6D6、卡片 #F6EFDF、浮层 #F7F1E5；全站白色高光/描边换成暖奶油白，减少刺眼感；ink-soft 压到 #67634F 保证小字仍过 AA。
- **深色再加深**：背景 #0C0C0F、卡面 #16161A、浮层 #1A1A1F；深色里的绿色改为**低饱和暖鼠尾草** `#C9D3B2 / #D8DFC4`，不再用冷亮薄荷，消除「阴间」感；橙色 #FFA94D 作唯一高饱和点缀。

---

## 12. 视觉精修层（2026-10-19，`styles/citro-refine.css`）

在以上皮肤之后**最后加载**的一层覆盖样式，只做视觉收口、不改结构。要点：

- **三级表面**：画布（#EFE8D8 / #0E0E10）→ 卡片（rgba 暖白半透 + 1px hairline + 轻暖影）→ 内嵌（ink 5% 底、无描边、无阴影）。禁止再给内嵌小卡加边框/投影。
- **字体分工**：`--font-d`（ZCOOL KuaiLe）只用于品牌位（logo、Hero、社区/食谱入口卡标题、一言、Hero 统计数字）；界面标题/条目名/正文统一 `--font-b`，标题 13px/500/.12em，条目 12.5–13.5px/500，正文 12px/400/1.6。
- **橙色纪律（用户 10-19 口径）**：橘色为主；工具图标、驱动圆点、小游戏底、入口卡、链接、聚焦、登录 tabs 选中均为橙色系。薄荷只做小面积语义点缀（宜/忌、状态徽章、Mod 角标），不得再出现大面积薄荷卡。
- **顶栏**：「今天也要开心」保留带边框胶囊（宽度 `min(32vw,340px)`，居中）；休息/天气/星象为无底色文字；日期 12.5px 表格数字。
- **深色**：近黑 + 三级抬升面 + 暖白 hairline；浮层阴影一律黑色系，不允许暖棕投影或彩色光晕。
- **圆角体系**：页面卡 22 / 浮层 24 / popover 20 / 内嵌 14 / 小件 10。
- **短屏**：`max-height:880px` 起小游戏入口压到 2 行，`max-height:770px` 压到 1 行，保证 Mod 卡完整。
- **审计回修**：天气卡小字对比度、深色「我的」、auth 遮罩/阴影、空态居中、手机发帖色带、分类 chips 渐隐均已在此层处理。
- 详细说明见 `docs/citro-视觉精修说明.md`；发布 APK 前需把 `citro-refine.css` 与 `index.html` 的 link 同步进 `capacitor/www/` 等打包副本。

---

## 13. 手账拼贴首页（2026-10-19，桌面）

用户选定方向：首页从「四栏等权卡片」改为**一页摊开的手账**。实现为独立层 `styles/citro-scrapbook.css`（最后加载）。

- **生效范围**：`min-width:1025px` 且 `min-height:880px`；短窗口自动回落 `citro-refine` 的 Bento；手机 ≤1024px 本轮不动。
- **结构**：`main-root` 栅格（首页 `auto repeat(8,1fr)`、资源页 `auto repeat(7,1fr)`）。
  - 顶部不再有固定顶栏：账号 + 打卡 + 主题 + 首页/资源 收成一排胶囊；下面是五块大小不一的手机小组件（时间 / 天气 / 日历 / 摸鱼 / 星象），天气与日历复用社区页已渲染的详情卡，摸鱼显示倒计时。
  - 首页：封面 1–4 列 × 5 行；小游戏 5–12 列 × 5 行，12 个游戏 4 × 3 全部展开；底部搜索便签 + 社区/食谱小卡 + 每日一言。
  - 资源页（`#/res`）：左 1–6 列为 Mod 2 列网格（6 张全显示、不滚动），右侧小工具在上、外设驱动在下；底部搜索便签。
- **二级菜单**：胶囊「首页 / 资源」切换；Mod / 小工具 / 外设驱动全部从首页移入资源页；手机端沿用底部「资源」Tab。
- **语言**：奶油纸 + 纸纤维 + 33% 装订边线；圆角手账（页面 16 / 海报 18 / 拍立得 10–14 / 便签 14 / 一言 12）；纸胶带、白边拍立得、KuaiLe 手写标签配橙色荧光笔底；深色为「夜手账」。
- **交互**：照片悬停摆正；轮播、工具、社区、搜索均沿用原 JS；搜索卡保持无 transform（避免 fixed 浮层错位）。
- **回退**：删除 `index.html` 中 `<link rel="stylesheet" href="styles/citro-scrapbook.css">` 一行即可。
- 详见 `docs/citro-手账布局说明.md`。

---

## 14. 手账桌面 Paper Desk（2026-10-19 新一轮，**当前生效**）

> 参考 <https://yanchenhao.com/> 的 scrapbook 语言重做整站视觉。
> **本节覆盖上面第 2~13 节的配色与材质结论**；版式结构仍沿用第 13 节的手账布局。

### 14.1 三层纸面（新的结构骨架）

| 层 | 角色 | 令牌 | 表现 |
| --- | --- | --- | --- |
| 桌 | `.site-wallpaper` / `body` | `--bg` `--bg-2` | 暖灰纸 + 24px 网格 + 纸纹 + 极淡暖光 |
| 纸页 | `.main-root::before` / `.page-*` / `#pageMe` | `--surface` | 最亮一层 + 网格 + 纸张阴影 + 1px 暖白 hairline |
| 卡纸 | `.tile` / `.gcard` / `.mod-card` / 便签 | `--surface-2` | 抬一档白 + 轻影 |

浅色：`#E7E0D0` → `#FBF7EC` → `#FFFDF8`
深色（夜手账）：`#0E0E11` → `#191920` → `#202028`

### 14.2 令牌（全部在 `styles/citro-core.css`）

配色、字体、投影、圆角见 `styles/citro-core.css` 顶部注释，关键几条：

```css
/* 圆角锁：页面 16 / 卡片 14 / 内嵌 10 / 胶囊 999 */
--r-page:16px; --r-card:14px; --r-inner:10px; --r-chip:999px;

/* 字体：Kalam(西文手写) → ZCOOL KuaiLe(中文手写) → Noto Sans SC */
--font-d:'Kalam','ZCOOL KuaiLe','Noto Sans SC',...;   /* 品牌/数字/英文标题 */
--font-h:'ZCOOL KuaiLe',...;                          /* 中文手写标题 */
--font-hand:'Caveat',...;                             /* 英文斜体注释 */
--font-b:'Noto Sans SC',...;                          /* 正文/按钮/表单 */
```

**旧令牌全部保留并重定义**，所以老页面文件里的 `var(--glass-card-bg)` 之类自动变成纸感：
`--glass-card-bg` → `--surface-2`、`--glass-pop-bg` → `--surface`、`--glass-blur` → `none`、
`--glass-pop-shadow` → `--paper-shadow-lg`、`--r-lg/md/sm` → 16/14/10。

### 14.3 手账原件（`styles/citro-notebook.css`，最后加载）

`.nb-grid` 网格纸、`.nb-tape` 纸胶带（`--blue/--yellow/--sm/--lg` 与 `--top/--tl/--tr/--bl` 定位）、
`.nb-hl` 荧光笔、`.nb-note` 便签（`--pink/--blue/--green`，带右下折角）、
`.nb-polaroid` 拍立得、`.nb-stamp` 印章、`.nb-dash` 虚线、`.nb-holes` 装订孔、`.nb-sheet` 纸页容器。

这层同时负责：全站压平玻璃（去掉所有 `backdrop-filter`）、桌面手账收口、
手机 App 壳手账、深色棋盘对比兜底、入场动效。

### 14.4 纪律

- **圆角锁死** 16/14/10/999，全站不分叉。
- **一个强调色**：橙 = 主行动 / 高亮；薄荷只做小面积语义（宜、成功、标签）。
- **便签色只做材质**，不承担语义。
- **深色禁止**彩色光晕与棕色投影，阴影一律 `--paper-shadow*`。
- **手写体边界**：中文长句、正文、按钮、表单**一律** `--font-b`；
  手写体只出现在品牌字、标题、大数字、英文注释。
- **旋转纪律**：单卡旋转 ≤ 1.2deg，装饰件（胶带/贴纸）≤ 3deg，同行不朝同一方向。

### 14.5 回退

删除 `index.html` 里 `<link rel="stylesheet" href="styles/citro-notebook.css">` 一行，
其余层仍兼容旧令牌，可逐层回退。

详细执行记录与回归修复清单见 `docs/citro-手账桌面-执行记录.md`，
协作简报见 `docs/citro-手账桌面-改版简报.md`。

