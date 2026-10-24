# Citro · 手账桌面（Paper Desk）视觉改版简报

> 本轮目标：把站点从「奶油柑橘卡片」升级为 **一张摊开的纸质手账 / 剪贴本**。
> 参考站点：<https://yanchenhao.com/>（scrapbook personal portfolio）。
> 参考的是**语言**，不是排版：网格纸底、纸胶带、拍立得、便签、马克笔高亮、手写体、虚线边框、
> 极轻微旋转、三层纸面（桌 → 纸页 → 卡纸）。

---

## 0. Design Read（一句话）

Reading this as: 个人向工具/社区单页站（首页是桌面手账，二级页是纸页），
面向「同好玩家 + 自己」，用 **scrapbook / paper-craft** 语言，
落在 **原生 CSS 覆盖层 + 手写体（Kalam / Caveat）+ 网格纸纹理 + 胶带/拍立得装饰**。

Dials：`DESIGN_VARIANCE: 8` / `MOTION_INTENSITY: 5` / `VISUAL_DENSITY: 5`

---

## 1. 硬约束（所有人都必须遵守）

1. **不改 `index.html` 的 DOM 结构**（除了 Lead 负责的那一处装饰层插入）。
   只写 CSS 覆盖。选择器一律带上自己的页面前缀，禁止去改 `.tile-meta` / `.main-root` 这类首页共享块。
2. **只改自己负责的文件**，见第 2 节表格。不要动别人的文件，也不要新建 styles/ 下的新文件（Lead 统一建）。
3. **不新增外链**（不引 Google Fonts、不引 CDN、不引 npm 包）。字体已本地子集化。
4. **不写 em-dash（—）** 到任何可见文案里；中文破折号用「·」或直接断句。
5. **深浅双主题都必须过**：`html[data-theme="light"]` 与 `html[data-theme="dark"]`。
6. **对比度**：正文 ≥ 4.5:1，大字号 ≥ 3:1。浅底橙字用 `--accent-ink`，浅底绿字用 `--mint-ink`。
7. **圆角体系锁死**（见第 3 节），不要出现「直角卡 + 圆角按钮」混搭。
8. 动效克制：只做 hover / 入场 / 按压反馈，不加常驻无限循环动画（原有游戏动效除外）。

---

## 2. 文件归属

| 文件 | 归属 | 说明 |
| --- | --- | --- |
| `index.html` | **仅 Lead** | 单页应用本体；其他成员**不要碰** |
| `styles/citro-core.css` | 仅 Lead | 令牌 / 基础 / 纸面 / 顶栏 / 底栏 / 通用材质 |
| `styles/citro-home.css` | 仅 Lead | 首页 Bento（非手账断点） |
| `styles/citro-scrapbook.css` | 仅 Lead | 桌面手账布局（≥1025×880） |
| `styles/citro-refine.css` | 仅 Lead | 收口层，会整体重写 |
| `styles/citro-glass.css` | 仅 Lead | 玻璃/材质覆盖层 |
| **`styles/citro-notebook.css`（新建）** | 仅 Lead | 本轮新增：纸面网格 + 胶带/拍立得装饰 + 全站纸感收口 |
| `styles/citro-community.css` | **队员 community** | 社区页 + 登录注册弹窗 + 发帖/评论/消息 |
| `styles/citro-cook.css` | **队员 community** | 食谱日记全站 |
| `styles/citro-games.css` | **队员 games** | 游戏公共框架 + 6 款益智游戏 |
| `styles/citro-arcade.css` | **队员 games** | 羊了个羊 / 跳一跳 / 淘气小球 / 极限刹车 / 成语接龙 / 飞花令 |
| `styles/citro-pages.css` | **队员 games** | 我的 / 资源 / 搜索 / 抽签 / 灵敏度 / 手机 Tab |
| `styles/citro-overlays.css` | **队员 games** | 运势 / 星盘 / 天气 / 摸鱼 / 打卡 / 笔记 / 吃什么 / 抛硬币 / 赞赏 / 番茄钟 |

---

## 3. 设计令牌（Lead 已写进 `citro-core.css`，其他人**只读不写**）

### 浅色（纸面）
```
--bg:#EFE9DC           桌面/画布（暖白灰）
--bg-2:#E7E0D0         次级底
--surface:#FBF7EC      纸页（最亮的一层）
--surface-2:#F5EFE1    卡纸（纸页上的小卡）
--ink:#23211C          主墨
--ink-2:#4E4A40
--ink-soft:#6E6858
--line:#E2DAC7         发丝线（网格线用 --grid）
--line-2:#D2C8B0
--grid:rgba(90,78,58,.10)   网格纸线
--accent:#F2A43C       品牌橙（填充）
--accent-2:#DE8A1F
--accent-lt:#FFC873
--accent-ink:#8F4E05   浅底上的橙字（AA）
--mint:#8FC7A0
--mint-ink:#2C6B50
--mint-soft:#EAF2E3
--mint-line:#CFE2C9
--tape:#F3D9DC         纸胶带（默认粉）
--tape-2:#CFE3F0       纸胶带（蓝）
--tape-3:#F6E7B4       纸胶带（黄）
--hl:#FFE97A           荧光笔高亮
--paper-shadow:0 1px 2px rgba(90,74,44,.06),0 10px 26px -14px rgba(90,74,44,.35)
--paper-shadow-lg:0 2px 4px rgba(90,74,44,.07),0 24px 54px -26px rgba(90,74,44,.45)
--r-page:16px  --r-card:14px  --r-inner:10px  --r-chip:999px
--font-d:'Kalam','Noto Sans SC',...     （手写标题，仅英文/数字用）
--font-h:'ZCOOL KuaiLe',...              （中文手写标题，保留）
--font-b:'Noto Sans SC',...
--font-hand:'Caveat','Noto Sans SC',...  （斜体注释/副文案）
```

### 深色（夜手账）
```
--bg:#0E0E11   --bg-2:#141418   --surface:#191920   --surface-2:#1F1F27
--ink:#F1EEE5  --ink-2:#CFC9BC  --ink-soft:#A49E90
--line:rgba(255,246,228,.10)   --line-2:rgba(255,246,228,.16)
--grid:rgba(255,240,214,.055)
--accent:#FFAE52  --accent-2:#E08A24  --accent-lt:#FFD2A0  --accent-ink:#FFC078
--mint:#C9D3B2  --mint-ink:#D8DFC4  --mint-soft:rgba(201,211,178,.10)  --mint-line:rgba(201,211,178,.22)
--tape:rgba(226,160,170,.22)  --tape-2:rgba(150,190,220,.20)  --tape-3:rgba(226,200,120,.20)
--hl:rgba(255,214,90,.24)
--paper-shadow:0 1px 2px rgba(0,0,0,.4),0 12px 30px -16px #000
--paper-shadow-lg:0 2px 6px rgba(0,0,0,.45),0 26px 60px -26px #000
```

### 用色纪律
- **橙 = 主行动 / 高亮 / 强调**；**薄荷 = 次级语义（成功、宜、标签）**；**奶油纸 = 大面积底**。
- 一个强调色用到底。不要某页突然冒出蓝 CTA / 紫按钮。
- 纸胶带 / 荧光笔是**装饰**，不承担语义，不得用在按钮主色上。

---

## 4. 手账语言的具体做法（所有人照做）

### 4.1 三层纸面
1. **桌**（`.site-wallpaper` / `body`）：`--bg` + 细网格（24px）＋极淡径向暖光。
2. **纸页**（页面容器 `.page-trash` / `.page-cook` / `.page-g` / `.page-search` / `#pageMe` ...）：
   `--surface` 底 + 纸张阴影 + 1px 暖白 hairline + `--r-page` 圆角。
3. **卡纸**（页内卡片）：`--surface-2` 底 + `--r-card` + 轻投影，**不要再给内嵌小卡加边框+投影**。

### 4.2 网格纸
统一用 Lead 提供的 `--grid` 变量画 24px 网格，不要自己写死颜色：
```css
background-image:
  repeating-linear-gradient(0deg,  var(--grid) 0 1px, transparent 1px 24px),
  repeating-linear-gradient(90deg, var(--grid) 0 1px, transparent 1px 24px);
```
深色下 `--grid` 已经是极淡暖线，**不要**在深色里再写死 `rgba(255,255,255,...)`。

### 4.3 纸胶带（tape）
用 `::before` / `::after` 做，尺寸 `w 64-96px × h 22-28px`，轻微旋转 `-3deg ~ 3deg`，
`background:var(--tape)`，`box-shadow:0 1px 3px rgba(0,0,0,.08)`，
`clip-path:polygon(2% 0,98% 3%,100% 95%,4% 100%)`（撕纸边）。
**每屏最多 2-3 条**，不要每条卡片都贴。

### 4.4 便签 / 拍立得
- 便签：`--surface-2` 底 + 1px 同色深线 + 轻微旋转 + 右下角折角（`linear-gradient` 三角）。
- 拍立得：白纸边 `padding:10px 10px 34px`，图 `--r-inner`，底部手写体 caption（`--font-hand`）。

### 4.5 手写体使用边界（重要）
- `--font-d`（Kalam）：**只用于英文品牌字、数字、英文标签**。中文不要用 Kalam（缺字）。
- `--font-h`（ZCOOL KuaiLe）：中文手写标题、卡片标题、品牌中文。
- `--font-hand`（Caveat）：英文/数字的**斜体注释**（日期、脚注、副标题）。中文同样不用。
- **正文、按钮、表单、表格一律 `--font-b`（Noto Sans SC）**，保证可读性。
- 中英文混排时，手写体后面紧跟的中文会自动回退到 Noto，**接受**，但不要在长句里用。

### 4.6 虚线
参考站大量使用 `1px dashed` 做「贴纸边界 / 分区线」。本站沿用：
- 分区线：`1px dashed var(--line-2)`，透明度低。
- **不要**给每个 list row 都加 `border-top` + `border-bottom`（表格感太重）。

### 4.7 旋转纪律
- 单个旋转角度绝对值 ≤ 1.2deg，只有纯装饰元素（胶带、贴纸）可以到 3deg。
- **同一行/同一列的卡片不要朝同一方向旋转**（会像整块歪掉），要么交替，要么不转。

### 4.8 圆角锁
`--r-page:16 / --r-card:14 / --r-inner:10 / --r-chip:999`。
按钮：主按钮 999 胶囊；卡片 14；图片 10。**全站统一**，不要一页圆角一页直角。

### 4.9 深色
- 深色 = 「夜手账」：纯平近黑 + 抬升面 + 暖白 hairline。**不要**彩色光晕、不要棕投影。
- 纸胶带在深色下用 `--tape*` 的半透明版本，不要用浅色纸胶带原色（会亮得刺眼）。

---

## 5. 逐页要点

### 5.1 社区 `.page-trash`（队员 community）
- 页面容器 = 纸页；页头 `Citro 社区` 用手写中文标题 + 荧光笔底。
- 未登录门禁卡 = **拍立得 + 胶带**：卡片轻微旋转、顶部一条 tape、中间 logo、下面手写体小字。
- 帖子流 = **便签卡**（不是玻璃卡）：`--surface-2` 底、`--r-card`、hover 时抬起 2px + 阴影加深。
- 分类 chips / 点赞 / 抱一抱 = 胶囊，选中态用 `--accent` 填充 + 深墨字。
- 登录/注册弹窗 = **一张撕下来的纸**：`--r-page`、顶部 tape、输入框 `--r-inner` + `--line-2` 1px 实线、
  focus 时 `--accent` 描边（2px）+ 外发光 4px。

### 5.2 食谱日记 `.page-cook`（队员 community）
- 左侧栏 = 手账目录页：竖排发丝线 + 当前项用**荧光笔**底（`--hl`）+ 左侧橙色书签条。
- 食谱卡 = 拍立得（图片白边 + 底部手写 caption + 右下角小胶带）。
- 「吃什么 / 购物清单」等工具卡 = 便签，轻微旋转交替。
- 空态 = 一张空白便签 + 手写体提示，居中但**不要**大留白到 800px。

### 5.3 游戏页 `.page-g`（队员 games）
- 游戏外壳 = **纸页上的画框**：`--surface` 底 + 内描边 + 顶部居中一条 tape。
- 分数 / 计时 / 状态 = 印章感小胶囊（`--accent` 描边 + 手写数字）。
- 棋盘/格子：**不要**改成纸色，保留游戏可玩性对比；只换外壳与标题。
- 按钮：主按钮橙底深墨字；次按钮纸底 + 1px 实线。

### 5.4 街机页 `.page-g*`（队员 games）
- 羊了个羊 / 跳一跳 / 淘气小球 / 极限刹车：统一「纸页 + tape + 手写分数」。
- 成语接龙 / 飞花令：**竖排纸笺**感（宣纸底 + 朱红印章色只用在极小的点缀，不要大面积）。

### 5.5 我的 / 资源 / 搜索 / 抽签 / 灵敏度（队员 games）
- 我的 = 手账封底：头像拍立得 + 手写名字 + 列表用 `1px dashed` 分隔（不要卡片套卡片）。
- 资源 = 目录页：Mod 卡拍立得化；工具列表用「索引卡」两列。
- 搜索 = 索引卡输入框 + 结果用便签浮层。

### 5.6 浮层（队员 games）
- 所有 popover / 弹窗 = 纸片：`--surface` + `--r-page` + `--paper-shadow-lg` + 1px hairline。
- 遮罩 = `rgba(35,33,28,.28)` + `blur(6px)`（浅色）/ `rgba(0,0,0,.6)`（深色）。
- 运势 / 星盘卡：保留内容结构，只换材质与标题字体。

---

## 6. 验收（每个人交回前逐条自查）

- [ ] 只改了自己负责的文件（`git status` 确认）
- [ ] 浅色 + 深色、桌面 1440×1000 + 手机 390×844 各至少 1 张截图，放在 `_tmp/team/<你的名字>/`
- [ ] 没有横向溢出、文字没有被裁切、按钮文字不换行
- [ ] 正文对比度过 AA；浅底橙字用 `--accent-ink`
- [ ] 圆角体系一致（16/14/10/999）
- [ ] 没有 em-dash；没有 emoji 新增（原有保留）
- [ ] console 无新增报错，无 404
- [ ] 回复里写：改了什么、截图路径、发现但未解决的跨范围问题

---

## 7. 截图方法（已备好脚本）

本地静态服务器已在 <http://127.0.0.1:8019/>（只跑前端，`/trashapi` 404 属正常）。

```powershell
# 1) 写一份 cfg（每人用自己的端口，避免冲突）
$base='http://127.0.0.1:8019/'
$light="document.documentElement.setAttribute('data-theme','light');localStorage.setItem('cm-theme-mode','light');"
$dark ="document.documentElement.setAttribute('data-theme','dark');localStorage.setItem('cm-theme-mode','dark');"
$shots=@(
  [ordered]@{name='x-light'; url=$base+'#/trash'; w=1440; h=1000; wait=2600; after=900; prep=$light},
  [ordered]@{name='x-dark';  url=$base+'#/trash'; w=1440; h=1000; wait=2600; after=900; prep=$dark},
  [ordered]@{name='x-mobile';url=$base+'#/trash'; w=390;  h=844;  wait=2600; after=900; prep=$light; mobile=$true}
)
$cfg=@{outDir=(Join-Path (Get-Location).Path '_tmp\team\<你的名字>'); port=9360; shots=$shots}
[System.IO.File]::WriteAllText((Join-Path (Get-Location).Path '_tmp\team\<你的名字>\cfg.json'),($cfg|ConvertTo-Json -Depth 5),(New-Object System.Text.UTF8Encoding($false)))

# 2) 跑（每人端口不同：community 用 9360，games 用 9370）
& node _tmp\tools\shot.js '_tmp\team\<你的名字>\cfg.json'
```

- 社区页需要登录才看得到完整版式。注册接口：
  `POST http://127.0.0.1:8019/trashapi/api/auth/register`（本地未起后端时不可用，
  此时只验收「未登录门禁」版式即可，其余靠 DOM/静态推断）。
- 需要看计算样式时：`node _tmp/tools/probe.js '<url>' '<js表达式>'`（见该文件用法）。
