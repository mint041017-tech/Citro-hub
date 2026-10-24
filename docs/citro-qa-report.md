> **收尾补记（2026-10-19 03:00）**：本报告基于 02:33 冻结快照。之后用户又追加了
> 「logo 换回指定两枚且一律不加白底 / 删除柑橘小屋字样 / 去掉照片壁纸 / 深色改为纯平近黑」
> 四项修订，Lead 已完成并复验：全站 68 用例（21 路由 × 桌面/手机 × 浅/深）横向溢出 0、
> 资源 404 0、旧品牌文字 0、logo 白底 0；深色整页 `#17171A` 纯平近黑。
> 报告中的「暖可可夜」深色与旧 logo 截图仅为当时快照，以 `效果预览/citro-2026/` 最新截图为准。

# Citro 品牌升级 · 全站视觉验收总报告

- 验收员：verifier-citro（只读审计；未修改 index.html / styles / 素材 / fonts）
- 最终快照：2026-10-19 02:33:52（styles/*.css）、02:34:07（index.html）
- 验收方式：Chrome CDP 无头全页截图 + 页面内 DOM/计算样式审计 + console/Network 捕获 +
  「隐藏文字后采样背景」的像素级 WCAG 对比度 + 正常截图二次复核（剔除动态/遮挡误报）+ 静态 CSS/资源体检
- 脚本：`_tmp/team/verifier/audit.js`（矩阵/截图/审计）、`inpage-audit.js`、`filter-contrast.js`（对比度复核）、
  `lib/staticlint.js`（静态体检）；用法见 `_tmp/team/verifier/README.md`
- 覆盖：21 路由（9 主页面 + 搜索页 + 12 游戏页）× 1440×1000 / 1280×800 / 390×844 × 浅/深 = 126 用例；
  加 8 类弹层状态 17 例、登录态 25 例；报告 1 与报告 2 各一轮，共约 240 用例截图。

## 一、最终结论

| 级别 | 数量 | 结论 |
| --- | --- | --- |
| P0（产品） | **0** | 所有路由/断点/主题正常渲染；无本地 404、无 JS 异常、无文档级横向溢出、无页面容器缺失 |
| P0（环境） | 1 | `/trashapi/api/history/today` 503（后端缺 Python/kerykeion 环境）导致每页 console 报错；非前端/样式问题 |
| P1（剩余） | 3 | 深色顶栏 logo 白底残留；gslide 深色 tile 数字对比度 3.25–3.30:1；gmem 卡面浅色 3.11:1 + 深色在线面板 3.66:1 |
| P2 | 若干 | 设计文档令牌过期；mod-badge 10px/临界；drv-tag 特异性；素材/APK 清理；水印 cover 等 |

用户收尾要求核验：① logo 为透明字标版本、页面内无白底 —— 仅深色顶栏 1 处残留（P1）；
② 「柑橘小窝」字样页面内 0 处；③ 照片壁纸已移除，浅色纯奶油渐变、深色暖可可夜渐变；
④ 深色暖可可夜 `#322A1B` 系（bg/bg-2/surface/ink/ink-soft/mint 全部生效）；⑤ 薄荷 `#8CC79E / #2F7357`（dark `#9ADDB8`）生效。

## 二、P1 明细（需修复）

| # | 页面 | 断点/主题 | 证据 | 现象 | 建议 |
| --- | --- | --- | --- | --- | --- |
| P1-1 | home/res/games 顶栏 | 深色 | `shots/home__1440x1000__dark.png`；computed `rgb(245,241,227)` | `.brand-chip img` 深色档仍有奶油白底 `#F5F1E3`（`citro-core.css:234`），其余 logo 均透明 | 删除该背景或 `background:transparent` |
| P1-2 | gslide 数字华容道 | 390×844 · 深色（桌面同源） | `shots/gslide__390x844__dark.png`；渲染采样 3.25–3.30:1 | `.gslide-tile` 深色渐变 `#8FB85C→#2F7357` + 白字 `#F3F9EA`；亮端理论 ≈2.2:1，23.4px 需 4.5 | 加深渐变（如 #5E8F3E→#24402F）或字号 ≥24px 加粗 |
| P1-3 | gmem 记忆卡牌 | 390×844 浅色；桌面/手机 深色 | `shots/gmem__390x844__light.png`、`shots/gmem__1440x1000__dark.png` | 卡面 `#9A5606` on `#F7B354` = 3.11:1（23.4px）；深色「正在玩」`.gl-prog` `#CCBFA4` on `#715837` = 3.66:1（12px） | 卡面字压深/底提亮；面板进度字提亮 |

> 环境 P0：`/trashapi/api/history/today` 503（正文：没有找到装了 kerykeion 的 Python）。若「console 无报错」为硬验收项需修后端或前端静默；其余接口/资源全清。

## 三、通过项（最终快照实测）

- 路由与容器：21/21 路由 × 6 组合正常，页面容器可见率 100%；无路由跳转失败。
- 手机端：390×844 下 home/res/games/cook/trash/me/gmem/gslide 及 8 类弹层均无横向溢出、无文字裁切、无底栏遮挡；搜索页/我的/抽签/灵敏度桌面与手机正常。
- 404/console：除上述 `/trashapi/api/history/today` 外，本地 4xx/5xx=0、资源 404=0、JS 异常=0、console.error=0（外部天气 API 偶发失败属环境网络）。
- 设计令牌：与 `styles/citro-core.css` 当前实现逐项一致（浅色 mint #8CC79E/#2F7357/#E8F4EA/#CFE7D6、ink-soft #6E6A56；
  深色 bg #322A1B/#3B3220/#453A26、ink #FBF3E0、ink-soft #CCBFA4、mint #9ADDB8）；无页面级深色漏做大块。
- 旧品牌/旧路径：index.html `迟暮`=0、`Crew`=0；`citro-mark` / `Citro Backend` / 旧 `图/` 引用=0；
  APK 链接全部 `/APK/Citro-v1.9.apk`；**唯一 logo** `素材/citro-logo.png`（768×768 RGBA，四角 alpha=0）被引用 38 处，无其它 logo 资产引用。
- 旧色残留：8 个 CSS + index.html 中旧薄荷字面量（#7FC49C/#2F7357/#E3F3E7/#C9E6D3/#9ADDB8/#8FD6B2 及 rgba 变体）= **0**；
  旧金 #B8924A 系仅在 index 内联旧规则中存留 67 处（全部被新皮肤覆盖，计算样式无可视残留）；无衬线字体残留、无死选择器（0）、无未定义 CSS 变量（0）。
- 字体：ZCOOL KuaiLe 以 `font-weight:100 900` 单面声明，消除 700 合成粗体；Noto Sans 300/400/500/700 全部加载；标题 400 字重生效。
- 壁纸/材质：照片壁纸引用已移除；浅色奶油渐变 + 橙/薄荷柔光、深色暖可可夜渐变；玻璃卡材质/圆角（22/16/12）按规范。
- 弹层：摸鱼日历/天气/运势·打卡/抛硬币/番茄钟/赞赏码/吃什么 8 类浅+深正常打开、无遮挡与溢出；登录/注册、发帖 composer 正常。
- 登录态：社区三栏、食谱日记（登录后）完整布局正常，桌面与手机、浅深均无溢出/报错。
- 资源完整性：样式加载顺序正确、8 个页面 CSS 均已实现（无占位）、manifest 正常、关键素材/字体 0 缺失。

## 四、P2 建议（不阻塞）

1. `docs/citro-design.md` §2 仍写旧令牌（--mint #7FC49C / #2F7357 / #E3F3E7 / #C9E6D3、dark #C9E39B/#D6E9B4、--ink-soft #76715E）且含「柑橘小窝」字样，
   与当前 core 不一致，建议同步文档（否则后续验收口径冲突）。
2. `.mod-badge` 实际字号 10px（预期 11px，旧内联 index:668 仍生效）；浅色档实测 4.1–4.4:1 临界，建议提升到 11–12px 并用更高特异性覆盖。
3. `.drv-tag`：旧内联 `.drv-item .drv-tag`（0,2,0）覆盖 home 的 `.drv-tag`（0,1,0），实测 `border-radius:6px`、文字 `--ink-2`；
   且 home.css 仍写 `#F0F6E1/#D8E7BC`（上一版中间色），建议改 `.tile-drivers .drv-tag` + 当前令牌。
4. `素材/_未使用旧素材/` 目录不存在；`CiCi.jpg / Citro logo.jpg / Citro logo（无底色）.png / 迟暮壁纸.jpeg / 迟暮手机壁纸.jpg` 仍在 `素材/` 根目录（页面未引用）；
   `APK/` 仍有 10 个旧品牌安装包（页面已不引用，建议归档/删除）。
5. `.page-g::after` 品牌水印用 `background-size:cover` 裁掉 logo 透明留白（未切到可见笔画，严格口径可改 contain + 放大容器）。
6. 游戏榜单/在线面板 11px 小字等 <11.5px 文本 16 条（P2 可读性）。

## 五、交付物与证据

- 报告：`_tmp/team/verifier/report-1.md`、`_tmp/team/verifier/report-2.md`
- 汇总数据：`_tmp/team/verifier/results-full-r1.json`（126 用例基线）、`results-full-r2.json`、`results-verify-r3.json`、
  `results-overlays-r2.json`、`results-logged-r3.json`；单页原始数据 `_tmp/team/verifier/raw/*.json`
- 对比度复核：`_tmp/team/verifier/contrast-verified.json`
- 截图：`_tmp/team/verifier/shots/`（约 400 张：每用例 视口/全页/隐藏文字背景图；局部取证 `_crop-*.png`）
- 脚本与说明：`_tmp/team/verifier/audit.js`、`inpage-audit.js`、`filter-contrast.js`、`lib/*.js`、`README.md`

## 六、复验建议

1. 修完 P1 后跑 `node _tmp/team/verifier/audit.js --suite=verify --tag=verify-final` + `node _tmp/team/verifier/filter-contrast.js results-verify-final.json`，
   确认 P1-1/P1-2/P1-3 消失。
2. 若需最终存证，再跑一次 `--suite=full`（126 用例，约 11 分钟）并归档截图。
3. 验收红线：`/trashapi/api/history/today` 503 需由 Lead 书面确认按环境豁免，或修后端/前端静默。
