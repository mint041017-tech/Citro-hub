# Citro · 素材与字体清单（asset-forge 交付）

> 归属：素材负责人（asset-forge）+ Lead 收尾修订。本文件记录 `素材/` 位图与 `fonts/` 字体子集的
> 尺寸 / 体积 / 用途 / 生成方式 / 覆盖检查结果。
>
> **★ 唯一 logo 政策（用户明确要求）**：全站只使用一份品牌 logo ——
> 用户提供的「Citro 手绘字标」（橙脚本字 + 黄绿叶片）。源文件 `素材/Citro-logo-source.png`，
> 网页用 `素材/citro-logo.png`（由源图去白底/裁边/缩放而来）。
> 旧的圆形 CITRO 徽章（Backend logo）、旧 `citro-mark*.png` 已全部退役并移入
> `素材/_未使用旧素材/`，任何页面/CSS 都不得再引用。
> 规范见 `docs/citro-design.md`；这些文件的**文件名与路径已被 `index.html`、
> `manifest.json`、`styles/*.css` 引用，不可改名**。

---

## 1. 素材清单

源图（只读，构建输入）：

| 源文件 | 尺寸 | 说明 |
| --- | --- | --- |
| `素材/Citro壁纸.png` | 2720x1536 | 柑橘水彩插画原图（palette PNG） |
| `素材/Citro-logo-source.png` | 2048x2048 | **唯一品牌字标源图**（用户提供；橙色脚本 Citro + 黄绿叶）。`citro-logo.png` 由它去白底/裁边得到 |

产出（全部被页面引用）：

| 文件 | 尺寸 | 体积 | 用途 / 生成方式 |
| --- | --- | --- | --- |
| `citro-wallpaper.jpg` | 2160x1220 | 393 KB | 桌面壁纸（CSS `.site-wallpaper` + `<link rel=preload>`）。源图缩到 2160 宽，JPEG q84、4:2:0、progressive。1440/1920 屏显示时缩比 1.23x/1.12x，不发糊 |
| `citro-wallpaper-mobile.jpg` | 800x1536 | 237 KB | ≤1024px 视口壁纸。源图 **1:1 像素中央裁切**（x=1100..1900）→ 中央橙子切片 + 两只猫完整保留，不放大、不二次缩放；JPEG q85 |
| `citro-logo.png` | 768x768 | 320 KB | **全站唯一 logo**（透明 RGBA，去白底 + 裁透明边）。用于 Hero 头像/水印、顶栏品牌、游戏侧栏、底栏、社区/食谱贴纸、CSS 装饰（含 `citro-logo-512.png` 备选）。显示一律 `object-fit:contain` + 白底贴纸，不做圆形裁切 |
| `citro-logo-512.png` | 512x512 | 118 KB | 同源 512 版（备用） |
| `citro-logo-square.jpg` | 1024x1024 | 89 KB | 用户提供的奶油底方图，favicon/PWA/OG 用 |
| `favicon-32.png` | 32x32 | 1.5 KB | 标签页图标：奶油圆角底 + 唯一 logo |
| `favicon-64.png` | 64x64 | 4.8 KB | 同上，64px 版 |
| `apple-touch-icon.png` | 180x180 | 24 KB | iOS 主屏图标：奶油圆角底 + 唯一 logo |
| `icon-192.png` | 192x192 | 26 KB | PWA 图标（`manifest.json`） |
| `icon-512.png` | 512x512 | 109 KB | PWA 图标 / 安卓安装图 |
| `citro-og.jpg` | 1200x630 | 113 KB | OG / Twitter 分享图（`og:image`、`twitter:image`，HTML 里为绝对地址）。奶油底 + 唯一 logo + 「Citro · 随缘开黑」+ 壁纸右侧渐变卡 |

体积合计：**约 1.23 MB**（首屏直接会拉：桌面壁纸 393K / logo 225K；手机端换 237K 竖版壁纸，
不拉桌面壁纸）。`citro-og.jpg` 只在分享抓取时读取，不进页面渲染路径。

> 注：`素材/` 下其余文件（迟暮壁纸、启动页、赞赏码、猫猫贴纸等）为历史素材，
> 不在本次 Citro 升级范围内，未改动。

### 生成方式（可重复执行）

```powershell
$py='C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
& $py _tmp/team/asset-forge/build-citro-assets.py                 # 全部重建
& $py _tmp/team/asset-forge/build-citro-assets.py --only og       # 只重建 OG
& $py _tmp/team/asset-forge/build-citro-assets.py --only icons,logos
```

脚本读上面三张源图，按表内参数输出到 `素材/`（同名覆盖）。壁纸重建已验证与旧文件
**逐字节一致**；PNG 全部以 Pillow `optimize=True, compress_level=9` 无损压缩，JPEG 按表内
质量参数编码。

> 该脚本目前放在 `_tmp/team/asset-forge/`（本次任务的写权限不含 `devtools/` 下的新文件）。
> 若以后还要重复出图，建议把它移到 `devtools/build-citro-assets.py` 常驻。

---

## 2. 字体子集

### 2.1 现状

`index.html` 自托管 5 个字体文件（`@font-face` + `<link rel=preload>`）：

| 文件 | 字重 | 说明 |
| --- | --- | --- |
| `fonts/zcool-kuaile-400-sub.woff2` | 400 | 品牌标题 / 数字（`--font-d`）。**本次重建** |
| `fonts/noto-sans-sc-300/400/500/700-sub.woff2` | 300/400/500/700 | 正文 UI（`--font-b`）。本次只做覆盖检查，未重建 |

`fonts/` 里的 `noto-serif-sc-*`、`ma-shan-zheng-*`、`zcool-kuaile-400-full-sub.woff2`
已不被 `index.html` 引用（Citro 规范第 3 节：衬线与书法体全站停用）；为可回滚暂留，
后续可整目录删减。**没有换字体族**，只按新文案重新子集化。

### 2.2 重建结果（`devtools/build-citro-fonts.py`）

旧子集按「迟暮·Crew」文案裁的，**新文案缺 78 个汉字**（于/传/做/减/几/剩/半/厨/听/导/
尝/必/志/批/拉/拌/播/料/早/果/柑/查/汽/油/火/爽/版/牛/状/猪/猫/直/碗/算/糊/糖/素/线/
编/聊/聚/腩/航/苏/英/藏/虾/赏/辑/锅/青/饭/香/黄/婆/宵/夜/址/待/志…），其中就包括
「**柑**」「**窝**」的邻字与新品牌文案常用字 —— 标题会掉回 Noto 造成混排。

重建字符集 = `index.html` 可见正文 ∪ 属性文案（content/alt/placeholder/aria-label/
title/value）∪ CSS `content:"…"` 字面文字 ∪ 常用中英文标点 ∪ 品牌新文案兜底
（`CitroCitro不卷段位随缘开黑游戏Mod工具食谱日记同频社区`）。

| 指标 | 旧子集 | 新子集 |
| --- | --- | --- |
| 文件 | `zcool-kuaile-400-sub.woff2` | 同名重建 |
| 体积 | 75.3 KB | **82.3 KB** |
| cmap 字数 | 802 | **876** |
| 页面必需字符覆盖 | 有 78 个汉字缺字 | **100% 覆盖**（853 个必需字符里，ZCOOL 源字体本身没有的 33 个符号除外，见下） |
| 品牌文案抽检 | 「Citro / 不卷段位，随缘开黑 / Citro」缺字 | **31/31 全部命中** |

浏览器实测（Chrome headless）：`document.fonts.check('400 40px "ZCOOL KuaiLe"',
'Citro')` / `'不卷段位，随缘开黑'` 均 `true`；首页标题计算字体为
`"ZCOOL KuaiLe","Noto Sans SC",…`、`font-weight:400`；字体请求 200（font/woff2）。

**回退说明（不是缺字事故）**：ZCOOL KuaiLe 源字体本身不含 emoji、①②、→、℃、★ 等
33 个符号（如 🌤🍅🍊🎲🏠📅、①、→、℃）。这些字符出现在可见文案里时会按字体栈回退到
Noto Sans / 系统字体 —— 任何子集都无法解决（源字体没有这些字形），观感正常。

### 2.3 Noto Sans SC 检查（未改文件）

用同一字符集核对 `noto-sans-sc-400-sub.woff2` / `700-sub.woff2`：

- **新文案汉字 722 个全部覆盖**（0 缺字），不需要重建、也没有换字体。
- 仅 23 个「必需字符」缺字形，全部是 emoji / 符号 / 上标（`²`、`♈`、`⚙`、`✕`、`✦`、
  `⭐`、`️`、`＋`、🌤🍅🍊🎳…），回退系统字体即可，不影响品牌文案。
- 另有 26 个极生僻字只出现在 JS 数据/注释里（`芫荽`、`豆蔻`、`蛤蜊`、`螃蟹`、`鳕鱼`、
  `猕猴桃`、`烹饪`、`阈值`…），Noto 子集本来就没收（旧版即如此，属 GB2312 之外的菜名/
  食材字）。这些会在食谱页/按钮上回退到系统雅黑，可读；若要求全站字体统一，需要按
  `devtools/build-fonts.py` 的流程重新从 CDN 拉 Noto 子集（本次任务约定：只报告不换字体）。

### 2.4 重建命令

```powershell
$py='C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
& $py devtools/build-citro-fonts.py            # 重建 -sub（index.html 引用的那个文件名）
& $py devtools/build-citro-fonts.py --check    # 只检查覆盖率，不写文件
& $py devtools/build-citro-fonts.py --full     # 顺带生成 GB2312 一级字全量版（备选，未引用）
& $py devtools/build-citro-fonts.py --extend   # -sub 并入 JS 动态生成的界面文案字符（体积约 219 KB）
```

- 源字体：`_tmp/fonts-src/ZCOOLKuaiLe.ttf`（Google Fonts 单文件）。
- **改动 `index.html` 文案后需要重跑一次**，否则新加的字可能不在子集里。
- 详细覆盖率报告（UTF-8 JSON）：`_tmp/team/asset-forge/font-build-report.json`。

---

## 3. 验证记录（本地 8019 静态服务 + Chrome headless）

- **资源请求**：下列文件 HTTP 200，MIME 正确（图片 `image/jpeg|png`，字体 `font/woff2`）：
  壁纸×2、logo、favicon×2、apple-touch、icon×2、og、5 个字体、
  `manifest.json`、`styles/*.css`。
- **首页 console**：无报错。**失败请求**：仅 `GET /trashapi/api/history/today`
  → 503/429（社区后端接口，非静态资源；后端返回「没有找到装了 kerykeion 的 Python」，
  属本机后端环境问题，与本次素材/字体改动无关，交 Lead 知会社区负责人）。
- **两档探针**（1440x1000 桌面 / 390x844 手机，`_tmp/team/asset-forge/final-probe-*.json`）：
  请求到的 `素材/` 与 `fonts/` 资源（桌面 17 个 / 手机 12 个，含 MOD 缩略图、猫猫贴纸）
  **全部 200**；`brokenImgs=[]`；`overflowX=0`；`document.fonts.status=loaded`；
  桌面只拉 `citro-wallpaper.jpg`、手机只拉 `citro-wallpaper-mobile.jpg`（media 分工正确）。
- **字体加载**：ZCOOL 新文案抽检（Citro / 不卷段位，随缘开黑 / Citro）全部 `true`（见 2.2）。
- 截图（`_tmp/team/asset-forge/shots/`）：
  - `home-light-desktop.png` / `home-dark-desktop.png`（1440x1000，壁纸 + hero 字标水印）
  - `home-light-mobile.png` / `home-dark-mobile.png`（390x844，手机竖版壁纸 + 顶栏徽章）
  - `home-light-compact-1280.png`（1280x800）
  - `g2048-light-desktop.png`（1440x1000，游戏页底纹/侧栏 logo 展示）
- 注：`_tmp/team/asset-forge/` 内旧截图与预览可能仍是徽章版；以当前 `素材/` 源码与线上页面为准。

---

## 4. 遗留 / 需 Lead 决策

1. `素材/` 与 `fonts/` 整个目录在工作区仍是 **git untracked**（`?? 素材/`、`?? fonts/...`），
   上线前要随仓库一起提交/部署；`font-build-report.json` 等检查产物只在 `_tmp/` 里，不进仓库。
2. ZCOOL 品牌字体不含符号/emoji（见 2.2），标题里若出现 ①②/℃/→ 会回退 Noto，属预期。
3. Noto 子集缺 26 个生僻食材/菜名字（见 2.3），会回退系统字体；要彻底统一需重拉
   Noto 子集（`devtools/build-fonts.py`，需要外网 CDN）。
4. `citro-og.jpg` 在 `index.html` 里是绝对地址 `https://chimu-claw.xyz/素材/citro-og.jpg`，
   部署后需确认该域名下能取到新图（抓取器不认相对路径，这是对的）。


## 5. 最终修订（2026-10-19 晚）

- **logo 换回用户最终指定的两枚**：透明版 `citro-logo.png`（页面/水印/Coin/登录弹窗），奶油底方图 `citro-logo-square.jpg`（favicon-32/64、apple-touch-icon、icon-192/512、OG 图）。
- **logo 展示不加白底**：所有页面展示位只放透明字标，立体感只用 `drop-shadow`；不再用白底贴纸/白边框。
- **不再使用照片壁纸**：页面背景改为纯奶油渐变 + 橙/薄荷柔光；`citro-wallpaper*.jpg` 只保留在素材目录备查，页面不引用。
- 调色板回到与 logo 同源的鼠尾草绿：`--mint:#8CC79E`、`--mint-ink:#2F7357`、`--accent:#F2A43C`；深色 mint `#9ADDB8`。


## 6. 最终状态（2026-10-19 收尾）

- 页面展示统一使用 `citro-logo.png`（透明、无白底）；`citro-logo-square.jpg` 用于图标与 OG。
- 不再使用照片壁纸：页面背景为纯 CSS 渐变（浅：奶油+橙/绿柔光；深：中性炭灰+淡橙/绿光）。
  `citro-wallpaper.jpg` / `citro-wallpaper-mobile.jpg` 保留备查，但 index.html 与 CSS 均不再引用。
- 调色板回鼠尾草绿：`--mint:#8CC79E / --mint-ink:#2F7357`，橙 `--accent:#F2A43C`；深色中性炭夜。
