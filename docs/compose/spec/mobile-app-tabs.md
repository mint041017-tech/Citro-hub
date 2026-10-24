---
feature: mobile-app-tabs
status: delivered
updated: 2026-09-17
branch: (no-git — direct edit on main workspace)
commits: n/a
---

# 手机端 App 化：底部 Tab 独立页

## Report

**What was built** — `index.html` 在 ≤1024px 启用 App 壳：底部 4 Tab（首页/资源/社区/我的），hash 路由 `#/home` `#/res` `#/trash` `#/me`；`#/play` `#/sens` 仍为沉浸二级页并隐藏底栏。新增 `#pageMe`（账号、运势、摸鱼、天气、笔记、联系、退出）。桌面 Bento 不变。清理了 `_edge_p3/p4/profile2` 浏览器残留（约 119MB）。

**Verification** — 3 段内联 JS `new Function` 通过；新 DOM id 齐全；CSS 花括号平衡；Edge headless 430×900 截图确认首页/资源/我的/社区/抽签，1440×900 确认桌面无 Tab 栏、Bento 完整。

**Journey log**
- 无 git，直接改主工作区（与既往 liquid-glass 规格一致）。
- `data-reveal` 卡片在 `display:none` 切换后可能不触发 IO，App 壺在 `route()` 里强制 `revealAppTiles()`。
- headless `--window-size` 与真实 CSS 视口不一致，截图可能裁掉底栏最右 Tab；DOM 诊断确认 4 个 Tab 均为 flex:1。

## [S1] Problem

现站 `index.html` 手机端（≤1024px）把桌面 Bento 拍平成长页滚动：顶栏两行 + 搜索 + Hero + Mod + 工具 + 社区入口 + 驱动 + 底栏。信息密、触控目标小、找功能要长滑，不像原生 App。用户要求改成手机 App 样式，更便于操作。

## [S2] Design

### 范围
- 仅 ≤1024px 手机/平板生效；桌面 Bento 布局与交互不变。
- 不改后端 `/trashapi`、不改数据结构、不引入框架/构建。
- 直接改 `index.html`（本项目无 git，沿用既有 compose 约定）。

### 信息架构（4 Tab）
| Tab | 路由 | 内容 |
|-----|------|------|
| 首页 | `#/` 或 `#/home` | 紧凑顶栏（头像/品牌/时钟）、搜索、Hero（幸运签/吃什么/快捷球）、每日一言、点歌台迷你条 |
| 资源 | `#/res` | 游戏 Mod、小工具、外设驱动 |
| 社区 | `#/trash` | 进入既有社区全屏页；底栏 Tab 常驻，顶栏返回改为「回首页」 |
| 我的 | `#/me` | 账号卡片、运势入口、摸鱼日历摘要、天气、联系复制、我的笔记、退出 |

二级栈页（保持现有 hash，盖住 Tab 栏）：
- `#/play` 玩法抽签
- `#/sens` 灵敏度转换

### 手机壳结构
```
┌─────────────────────┐
│ 顶栏（48–56px）        │  头像 | 页面标题 | 时钟/消息
├─────────────────────┤
│                     │
│  内容区（可滚动）      │  当前 Tab 对应面板
│                     │
├─────────────────────┤
│ 底栏 Tab（56–64px）   │  首页 · 资源 · 社区 · 我的
│ + safe-area-inset     │
└─────────────────────┘
```

### 实现契约
1. **路由**
   - 扩展 `route()`：解析 `#/home|#/res|#/trash|#/me|#/play|#/sens|空`。
   - body class：`view-home|view-res|view-me|view-trash|view-play|view-sens` + 移动端标记 `app-shell`（仅 matchMedia ≤1024px）。
   - hash → Tab 映射；从社区/二级页返回时回到上次主 Tab 或默认首页。
2. **DOM**
   - 新增 `#tabBar`（4 按钮，图标+文字，≥44px 触控）。
   - 新增 `#pageMe`（我的）：头像/昵称、运势、摸鱼、天气详情、联系、笔记、退出。
   - 首页/资源复用现有 `.tile-*`，用 CSS 按 Tab 显示/隐藏，不拆坏桌面 grid。
   - 社区：点 Tab → `location.hash='#/trash'`；`view-trash` 时底栏仍显示。
3. **样式边界**
   - 所有 App 壳规则包在 `@media (max-width:1024px)` 与/或 `html.app-shell` 下。
   - 底栏 `position:fixed; bottom:0; padding-bottom:env(safe-area-inset-bottom); z-index:80`。
   - 内容区 `padding-bottom` 预留底栏高度，避免遮挡。
   - `#/play` `#/sens` 时隐藏底栏（沉浸全屏）。
4. **触控**
   - Tab / 列表主按钮 / 胶囊：高度 ≥44px（或 min 44 视触）。
   - 现有底部弹层（收件箱/摸鱼/天气）保留，z-index 高于底栏。
   - `hover:none` 继续禁用卡片悬停位移。
5. **桌面**
   - `min-width:1025px`：不渲染/不显示 `#tabBar` 与 `#pageMe`，路由行为与现状一致（社区/play/sens 仍全屏）。

### 动效
- Tab 切换：内容 `opacity` + 轻微 `translateY(6px)`，180–240ms。
- 底栏 active：颜色 + 轻微 scale(1.06)，不做横向长动画。
- `prefers-reduced-motion`：沿用全站降级。

## [S3] Out of Scope
- 不重写桌面 Bento、不改视觉主色/纸质风。
- 不做 PWA 安装清单、不做离线缓存。
- 不改 `/trashapi` 协议与社区业务逻辑。
- 不把抽签/灵敏度收进 Tab（仍为二级栈页）。
- 不清理备份/源资料（本轮只删了 Edge 浏览器残留）。

## Tasks
- [x] T1: 写规格与路由/Tab 契约 — acceptance: 本文件与实现决策一致 (covers: S2)
- [x] T2: 注入底栏 + 首页/资源分区 CSS/路由 — acceptance: ≤1024px 可切换首页/资源，桌面无感 (covers: S2)
- [x] T3: 我的页 + 社区 Tab + play/sens 隐藏底栏 — acceptance: #/me 可操作账号相关；社区底栏常驻；抽签/灵敏度全屏 (covers: S2)
- [x] T4: 语法/结构/响应式抽查 — acceptance: JS 可解析；关键 id 存在；桌面与手机规则不互相污染 (covers: S1; depends: T2, T3)
