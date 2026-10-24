# Citro 品牌升级说明（2026-10-19）

> 站点：**Citro**（原「迟暮·Crew」）  
> 范围：首页 + 全部二级页 / 弹层 / 浅色 + 深色 / 桌面 + 手机  
> 设计方向：**Citrus Soda 柑橘汽水** —— 奶油纸底、鲜橙主色、黄绿（薄荷）副色、大圆角、手绘贴纸感。

---

## 1. 一句话总结

旧站的「暖纸 + 衬线 + 金色 + 深棕社区暗卡」体系整体退役，换成与新手绘字标同源的
「奶油白 / 鲜橙 / 黄绿」配色、ZCOOL KuaiLe 手绘标题字体、白玻璃卡片与 22px 大圆角；
全站所有页面（含 13 个游戏页、社区、食谱、我的、资源、搜索、抽签、灵敏度、各类弹层）
统一到同一套设计令牌，桌面/手机、浅色/深色全部覆盖。

---

## 2. 品牌资产

| 项 | 结果 |
| --- | --- |
| 唯一 logo | **用户最终指定的两枚同源资产**：`素材/citro-logo.png`（透明字标，页面内所有展示位；不加白底/白边）与 `素材/citro-logo-square.jpg`（奶油底方图，favicon / PWA 图标 / OG）。旧的圆形 CITRO 徽章 / `citro-mark*` / Backend 素材已移出 `素材/`（`_backup/citro-old-logo-assets/`），页面零引用。 |
| 背景 | **不再使用照片壁纸**：改纯奶油渐变 + 橙/薄荷柔光（浅色）/ 暖可可渐变（深色）。`素材/citro-wallpaper*.jpg` 仅留存备查，页面不再请求。 |
| 图标 | `favicon-32/64`、`apple-touch-icon`、`icon-192/512`、`manifest.json` 均由唯一字标生成。 |
| 社交分享 | `素材/citro-og.jpg`（1200×630），`og:image` 使用绝对地址 `https://chimu-claw.xyz/素材/citro-og.jpg`。 |
| 旧文件夹 | `图/` 已改名为 **`素材/`**，全部页面 / CSS / manifest / 电容构建脚本 / `.gitignore` / 文档引用已同步；旧空目录已清理。 |

---

## 3. 设计系统（写在 `styles/citro-core.css`）

- **浅色**：`--bg:#EDE6D6` 柔和奶油纸、`--surface:#F6EFDF`、`--ink:#2E2C22`；
  主色 `--accent:#F5A233`（橙，按钮字用深墨 `#2E2C22`）、副色 `--mint:#A9CD78`（黄绿）、
  `--mint-ink:#46752A`（浅底绿字，过 AA）、`--accent-ink:#9A5606`（浅底橙字，过 AA）。
- **深色（pure dark）**：整页纯平近黑 `--bg:#0C0C0F` / `--bg-2:#121216` / `--surface:#18181D`，`--ink:#EFEDE6`、`--accent:#FFA94D`、`--mint:#C9D3B2`（低饱和暖鼠尾草，避免冷绿阴间感）；无壁纸、无彩色背景光晕。
- **字体**：标题/数字 = `ZCOOL KuaiLe`（手绘圆体，weight 400）；正文/UI = `Noto Sans SC`。
  衬线体 Noto Serif SC 与书法体 Ma Shan Zheng 已停用。
- **形状**：卡片 22px、卡内小卡 16px、输入/小按钮 12px、主按钮/胶囊 999px；
  卡片材质 = 白奶油半透明 + 1px 白色高光边 + 暖投影；浮层 = 更实的奶油白 + 深投影。
- **页面结构**：`<link>` 分层加载（在旧内联样式之后）：
  `citro-core.css → citro-home.css → citro-community.css → citro-cook.css →
   citro-games.css → citro-arcade.css → citro-pages.css → citro-overlays.css`。
  每个页面文件只覆盖自己的作用域，令牌集中在 core。

---

## 4. 各页面改了什么

| 页面 | 视觉重做内容 |
| --- | --- |
| **首页**（`#/home`） | 纯渐变奶油底（无照片壁纸）；顶栏品牌胶囊/打卡/主题/摸鱼/天气/星象/时钟全套换肤；Hero 用唯一字标贴纸 + ZCOOL 标题 + Citro薄荷胶囊 + 橙色数据；Mod / 工具 / 驱动白玻璃卡与橙薄荷细节；社区入口改「薄荷汽水」卡、食谱入口改「蜂蜜橘子」卡并加字标贴纸；底栏搜索与每日一言重做；小游戏入口卡片重绘。 |
| **社区**（`#/trash`） | 门禁页、登录/注册弹层、注册资料确认弹层、已登录三栏（个人卡/时钟/菜单/收件箱 / 发帖 composer / 动态流 / 天气 + 日历侧栏）、消息中心、手机端朋友圈模式与发布面板，全部换 Citro 皮肤（白玻璃+橙按钮+薄荷标签）。 |
| **食谱日记**（`#/cook`） | 侧栏品牌与导航、食谱库/广场/找菜/购物清单/吃什么、食谱卡、新建/编辑浮层、封面裁切、时间滚轮、食材选择器、计时器、冰箱食材、空状态，全部奶油纸 + 橙/薄荷。 |
| **游戏中心 + 13 款游戏** | 统一白玻璃侧栏 / 手机顶栏 / HUD / 胶囊按钮 / 排行榜 / 分段器 / 结算浮层；2048、记忆卡牌、数独、数织、华容道、贪吃蛇、羊了个羊、跳一跳、淘气小球、极限刹车、成语接龙、飞花令逐款重绘棋盘/卡槽/输入区/仪表盘。 |
| **我的**（`#/me`） | 资料卡、菜单行、下载 App、公众号、退出、桌面居中面板与字标贴纸。 |
| **资源**（`#/res`） | 搜索胶囊、Mod/工具/驱动分节与卡片细节（不污染首页）。 |
| **搜索 / 抽签 / 灵敏度** | 奶油纸面 + 橙色短下划线标题 + 胶囊按钮 + 白玻璃卡 + 字标贴纸；灵敏度结果卡改薄荷奶昔。 |
| **浮层与彩蛋** | 运势 2.0 / 星盘、天气详情、摸鱼日历、打卡、大日历、历史上的今天、笔记、吃什么、抛硬币、赞赏码、番茄钟、跳转确认，全部换肤。 |
| **手机 Tab** | 奶油白玻璃悬浮底栏，选中态橙色胶囊 + 指示条，深色模式同步。 |

---

## 5. 文件清单

新增：

```
styles/citro-core.css          ← 设计令牌 / 基础 / 壁纸 / 顶栏 / Hero / 共享弹层 / 底部 Tab
styles/citro-home.css          ← 首页 Bento
styles/citro-community.css     ← 社区 + 登录/注册/资料弹层
styles/citro-cook.css          ← 食谱日记全部
styles/citro-games.css         ← 游戏公共框架 + 6 款游戏
styles/citro-arcade.css        ← 6 款游戏
styles/citro-pages.css         ← 我的/资源/搜索/抽签/灵敏度/游戏中心
styles/citro-overlays.css      ← 运势/星盘/天气/日历/笔记/吃什么/彩蛋
manifest.json                  ← PWA manifest（新图标 / 主题色）
素材/citro-logo.png            ← 唯一 logo（768，透明）
素材/citro-logo-512.png / citro-logo-source.png
素材/citro-wallpaper.jpg / citro-wallpaper-mobile.jpg
素材/favicon-32.png / favicon-64.png / apple-touch-icon.png / icon-192.png / icon-512.png
素材/citro-og.jpg
fonts/zcool-kuaile-400-sub.woff2   ← 重建的 ZCOOL 子集（覆盖新文案）
devtools/build-citro-fonts.py      ← 字体子集重建脚本（文案变更后重跑）
docs/citro-design.md / docs/citro-assets.md / 本文件
```

修改：

```
index.html        ← 品牌文案 / title / meta / OG / favicon / preload / 壁纸 / 顶栏品牌胶囊 /
                    Hero 结构 / 社区入口与食谱入口文案 / 唯一 logo 引用 / 分层样式 <link> /
                    小游戏卡「柑橘」/ 成语接龙水印 / APK 下载文件名（显示名 Citro-v1.9.apk）等
.gitignore        ← 图/_原图备份 → 素材/_原图备份
capacitor/sync-www.js      ← 同步 素材/ + styles/ + manifest.json，排除备份与开发残留
capacitor/capacitor.config*.json  ← appName = Citro
capacitor/build-apk.js     ← 注释品牌
devtools/optimize-images.py / docs 引用 ← 路径改名
```

备份：`index.html.bak-before-citro-20261019`（改版前原文件），可随时回滚。

---

## 6. 验证

- 全站路由截图矩阵（桌面 1440×1000 / 1280×800、手机 390×844，浅/深色）：
  `_tmp/shots-final1/`、`_tmp/shots-login3/`、`_tmp/shots-r2/`、各成员 `_tmp/team/*/`。
- 控制台：0 报错；资源：0 个 404（`/trashapi/api/history/today` 的 429/503 是本机后端
  AI 历史接口缺 kerykeion 环境，改版前即存在，与前端无关）。
- 手机端 13 条路由 `documentElement.scrollWidth === window.innerWidth`，无横向溢出。
- 未登录 / 登录（本地测试账号）/ 空状态 / 深色模式均截图检查。
- 字体：ZCOOL 子集覆盖全部可见新文案（含「Citro」「不卷段位，随缘开黑」等），
  Noto Sans 400/700 对 722 个新文案汉字 0 缺字。

## 7. 上线注意

1. 部署时需带上：`index.html`、`styles/`、`素材/`、`fonts/`、`manifest.json`。
   `og:image` 是绝对地址 `https://chimu-claw.xyz/素材/citro-og.jpg`，需保证该地址可访问。
2. 安卓离线包：先 `cd capacitor && node sync-www.js` 再打包（脚本已同步新皮肤与素材）。
3. 测试期间在本地 `trash/data` 写过测试账号，提交前已清理（如部署数据是另一份则不受影响）。
4. 旧 `index.html.bak-*`、`_backup/`、`_tmp/` 为本地备份与过程产物，不必部署。
5. 以后改 `index.html` 文案后，重跑 `python devtools/build-citro-fonts.py`
   让 ZCOOL 子集包含新字。
6. 已知边界：跳一跳方块、淘气小球球体/圆环、刹车 3D 场景与制动曲线的颜色由 index.html
   内 JS 的 canvas 绘制写死，CSS 只重绘了舞台/HUD/浮层；如需画布内也换色，属下一阶段 JS 改动。
   `#/search` 页面结构保留但当前无入口（原站即如此）。


## 8. 用户追加修订（当日晚）

1. **logo 展示去白底**：Hero、顶栏品牌胶囊、游戏侧栏、底栏、社区/食谱空状态、登录弹窗、各处水印——全部改为透明字标直放，需要立体感只加 `drop-shadow`。
2. **去掉中文副品牌**：全站删除「柑橘小窝 / 柑橘小屋」相关字样（title/description/Hero/底栏/coin 背面/manifest/社区页脚）。
3. **深色模式最终改为纯平近黑（pure dark）**：#17171A / #1D1D21 / #242429，整页无彩色背景光晕/渐变，卡片抬一档，橙色与鼠尾草绿只作点缀；深色顶栏 logo 白底问题已修掉。


9. **再次换 logo（用户指定两枚）**：页面内统一使用 `素材/citro-logo.png`（用户新给的透明底字标，鼠尾草绿），
   `素材/citro-logo-square.jpg`（同款奶油底方图）用于 favicon / PWA 图标 / OG 图。调色板的薄荷同步回鼠尾草绿
   `--mint:#8CC79E / --mint-ink:#2F7357`，橙色回 `#F2A43C`。


10. **最终修订补充**：
- 页面内 logo 全部透明直放，**不再加白底/白贴纸/白边框**（必要时只用 drop-shadow）。
- 背景不使用照片壁纸：浅色奶油渐变 + 橙/鼠尾草绿柔光，深色中性炭灰渐变；壁纸文件仅留存备查。
- 调色板回鼠尾草绿 `#8CC79E / #2F7357` 与橙 `#F2A43C`。


11. **最终观感微调**：浅色整体降白（bg #EDE6D6 / 卡片 #F6EFDF），深色再加深（#0C0C0F）并把深色里的绿色换成暖鼠尾草 #C9D3B2；橙色 #FFA94D 作深色唯一高饱和点缀。
