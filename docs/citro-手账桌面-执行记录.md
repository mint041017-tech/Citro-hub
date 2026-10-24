# Citro · 手账桌面改造执行记录（Lead）

> 本轮把站点从「奶油柑橘玻璃卡」改成 **Paper Desk 手账桌面**。
> 参考：<https://yanchenhao.com/> 的 scrapbook 语言（网格纸 / 纸胶带 / 拍立得 / 便签 / 荧光笔 / 手写体 / 虚线）。

## 设计判读

Reading this as: 个人向工具 + 社区单页站（首页=桌面手账，二级页=纸页），
面向「同好玩家 + 自己」，用 **scrapbook / paper-craft** 语言，
落地为 **原生 CSS 覆盖层 + 本地手写体子集（Kalam / Caveat）+ 网格纸纹理 + 胶带/拍立得装饰**。

Dials：`DESIGN_VARIANCE 8 / MOTION_INTENSITY 5 / VISUAL_DENSITY 5`

## 三层纸面（本轮核心结构）

| 层 | 角色 | 令牌 | 表现 |
| --- | --- | --- | --- |
| 桌 | `.site-wallpaper` / `body` | `--bg` `--bg-2` | 暖灰纸 + 24px 网格 + 纸纹 + 极淡暖光 |
| 纸页 | `.main-root::before` / `.page-*` / `#pageMe` | `--surface` | 最亮一层 + 网格 + 纸张阴影 + 1px 暖白 hairline + 16px 圆角 |
| 卡纸 | `.tile` / `.gcard` / `.mod-card` / 便签 | `--surface-2` | 抬一档白 + 14px 圆角 + 暖调轻影 |

深色 = **夜手账**：`--bg #0E0E11` → `--surface #191920` → `--surface-2 #202028`，
纸页同样带网格（不再是纯平），阴影一律黑色系，禁止彩色光晕。

## 圆角锁

`--r-page:16 / --r-card:14 / --r-inner:10 / --r-chip:999`，全站统一。

## 字体分工

| 令牌 | 字体 | 用途 |
| --- | --- | --- |
| `--font-d` | Kalam → ZCOOL KuaiLe → Noto | 品牌字、英文/数字标题、大数字 |
| `--font-h` | ZCOOL KuaiLe | 中文手写标题 |
| `--font-hand` | Caveat | 英文斜体注释、脚注 |
| `--font-b` | Noto Sans SC | 正文 / 按钮 / 表单 / 表格 |

Kalam 与 Caveat 为本地子集（`devtools/build-hand-fonts.py` 生成，各 11KB / 66KB），
只含拉丁与常用标点，**中文由 ZCOOL KuaiLe / Noto 回退**，不要用于中文长句。

## 文件改动

| 文件 | 改动 |
| --- | --- |
| `styles/citro-core.css` | **重写**：新令牌体系；`--glass-*` / `--shadow-*` / `--r-*` 全部重定义为纸感值（其他页面文件的 var() 引用自动跟随）；顶栏纸带、品牌荧光笔、时钟手写、Tab 纸条 |
| `styles/citro-notebook.css` | **新建**：手账原件（网格/胶带/便签/拍立得/荧光笔/印章/装订孔）+ 全站压平玻璃 + 桌面手账收口 + 手机 App 壳手账 + 入场动效 |
| `styles/citro-home.css` | 首页 Bento（非手账断点）纸化 |
| `styles/citro-scrapbook.css` | 桌面手账布局纸化（版式保留，材质换纸） |
| `styles/citro-refine.css` | 收口层重写为纸感 |
| `styles/citro-glass.css` | 玻璃层改为纸面 |
| `styles/citro-community.css` `citro-cook.css` | 社区 + 食谱页手账化（队员 community） |
| `styles/citro-games.css` `citro-arcade.css` `citro-pages.css` `citro-overlays.css` | 游戏/街机/二级页/浮层手账化（队员 games） |
| `index.html` | 新增 Kalam/Caveat 的 `@font-face`；末尾追加 `citro-notebook.css` 链接 |
| `devtools/build-hand-fonts.py` | 新建：手写体子集构建脚本 |

## 回退方法

删除 `index.html` 里这一行即可回到上一版皮肤（其余文件仍兼容旧令牌）：

```html
<link rel="stylesheet" href="styles/citro-notebook.css?v=20261019p">
```

## 验收

- 桌面 1440×1000 / 1280×800、手机 390×844
- 浅色 + 深色
- 页面：#/home #/res #/games #/cook #/trash #/me #/search #/sens #/play + 2048/数独/羊了个羊
- 检查项：无横向溢出、无文字裁切、按钮不换行、对比度过 AA、圆角一致、console 无报错

## 回归修复清单（本轮顺带修掉的历史问题）

| 问题 | 根因 | 处理 |
| --- | --- | --- |
| 桌面 `#/games` 卡片互相重叠 | `view-games` 在桌面上没有专属版式，`.tile-mods` 与 `.tile-tools` 网格坐标冲突 | `citro-notebook.css` 3.19 给桌面游戏中心一整页版式：小游戏 4×3 + 工具/驱动索引 + 页脚 |
| 桌面首页「小游戏」标题被问候 toast 横穿 | `.greet-toast` 固定 `top:84px`，手账版面没有它的安全位置 | 桌面断点内收起 toast（问候语由页脚一言承担），手机保留 |
| 手机二级页出现 494px 横向溢出 | `citro-scrapbook.css` 里有一批**不带 `body.view-home`** 的 `.tile-meta .w-star` 规则，把星象卡铺到了食谱/社区/搜索/抽签/灵敏度 | 非首页视图重新 `display:none` |
| 手机外设驱动名被截成「铝厂 IQ…」 | `.drv-item` flex 行把名称压到 68px | 名称 `flex:1` + 允许换行，标签/箭头固定右对齐 |
| 2048 / 数独格子几乎看不见 | `--glass-card-bg` 从奶油半透明变成卡纸白，棋盘底与空格子同色 | 深色：棋盘底压近黑 + 内阴影，空格子 `#242430`；浅色由 `citro-games.css` 处理 |
| 食谱侧栏深色头像字糊掉 | 深色下 `--accent-lt → --accent` 渐变被压暗，深墨字对比度只剩 1.25:1 | 深色单独给 `--accent` 纯色底 |
| 首页问候 toast 遮住搜索卡 | 同上（固定定位） | 同第一项 |

## 用户反馈修订（2026-10-19 晚 · 首页版式）

用户口径：**搜索框太长、小游戏卡太大占了太多位置**。

改动（全部在 `styles/citro-notebook.css` §3.22，只影响桌面手账断点 ≥1025×880）：

| 元素 | 改前 | 改后 |
| --- | --- | --- |
| 首页搜索框 | `grid-column:1/6`，宽 **698px**，高 60px | `1/4`，宽 **342px**，高 40px 胶囊 |
| 小游戏卡 | 3 列 × 3 行，每张 **219×175px** | 4 列 × 3 行，每张 **163×61px** |
| Mod 照片带 | 首页**隐藏**，空间全给游戏 | 恢复为 **4×2 拍立得**（每张约 160×150px） |

腾出的空间还给 Mod 照片带：现在首页既能看 6 张 Mod 封面，也能一屏放下 12 个小游戏。
小游戏卡内部同步收紧（插画 `.gcard-art` 缩到 `scale(.72)`，标题 11px 单行省略）。

顺带修的窄高屏问题（`@media (min-width:1025px) and (max-height:879px)`）：
- 落回 Bento 时 `.tile-hero` 独占 1/4 屏高但内容很少，中间空一大块 → 内容居中 + 字号收紧。
- 308px 窄栏里 Mod 描述被裁 8px、驱动名被压成省略号 → 窄屏隐藏描述、驱动名允许换行。

### 第二轮修订（同日稍晚）

| 用户反馈 | 根因 | 处理 |
| --- | --- | --- |
| 「mod 在首页显示了，资源页就不显示了」 | 首页把 `.mod-rail` 改成 4 列 grid，JS 的 `isGrid()` 判到 grid 就停掉滚动动画；资源页 `.mod-scroll` 仍是 `flex`，两边规则重叠 | 把「首页照片带」和「资源页 Mod 网格」**彻底分开写**：资源页固定 `2 列 grid` + `overflow-y:auto`，与 JS 的 grid 分支一致 |
| 「小游戏卡片太扁了」 | 第一轮为了塞下 12 个，行高压到 58px | 行高 **58 → 84px**，插画 `scale(.72) → .9`，首页只留 4×2 = 8 张 Mod 腾高度 |
| 「左侧卡片有点太拥挤了」 | 日历 446px 塞 7 行、卡间距只有 12-13px | 日历行高放松 + 允许内部收敛；天气/摸鱼/星象/入口卡内边距加大；**日历不再盖住天气卡**（`.wg-body{overflow:hidden}` + `min-height:0`） |

修这一轮时抓到的两个自伤 bug：
- 首页 4×2 网格的第 2 行被**克隆卡**填满（自动滚动循环用的副本）→ 补 `.mod-clone{display:none}`。
- 日历卡内容溢出压住天气卡 → 给日历收敛高度、天气卡 `overflow:visible`。



## 验证结果

用 `_tmp/tools/qa.js` 跑全量无障碍/布局检查（9 个路由 × 浅深 × 桌面/手机）：

| 检查项 | 结果 |
| --- | --- |
| 横向溢出（docWidth = viewport） | 全部通过 |
| 文字被裁切（scrollWidth/Height 溢出） | 全部通过 |
| 正文对比度 < 4.5:1 | 全部通过 |
| 字号 < 9.5px | 全部通过 |
| console 报错 / 资源 404 | 全部通过 |

截图存放：
- 改造前：`_tmp/team/lead/before/`
- 参考站：`_tmp/team/lead/ref/`
- 过程中：`_tmp/team/lead/wip1..22/`
- 手机终稿：`_tmp/team/lead/final-mobile/`

