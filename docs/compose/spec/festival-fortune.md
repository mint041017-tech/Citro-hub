---
feature: festival-fortune
status: delivered
updated: 2026-09-25
branch: feature/festival-fortune
commits: e343a68..HEAD
---

# 传统节日特别签

## Report

**What was built** — 幸运签支持 12 个传统节日（春节/元宵/龙抬头/清明/端午/七夕/中元/中秋/重阳/腊八/小年/除夕）的「节日特别签」。节日当天（UTC+8）全员固定抽该签，UI 显示「{节日}特别签」；已抽过的本地缓存与服务端 `zodiacDraws` 会在打开/请求时迁移为节日签。非节日仍走原 8 签随机 + 当日锁定。日期表覆盖 2025–2029，与站内 `FISH_OFF` 的端午/中秋一致；今日 2026-09-25 命中中秋「月满人圆」。

**Verification** — `node --check trash/trash.js` 通过；前端幸运签模块抽出后：FORTUNES=8、FESTIVAL_FORTUNES=12 字段齐全、日期表 57 条、`2026-09-25→zhongqiu`、端午/中秋与 FISH_OFF 对齐、非节日无映射；DOM id 齐全；隔离测试 `lockFestivalDraw` 首抽 first=true、已抽迁移 prevIdx、再次访问 first=false、非节日 null。独立评审：CRITICAL 0 / NON-CRITICAL 6 / approve；已修动画竞态（`stopDrawAnim`）与小年/除夕农历标注。

**Journey log**
- 农历节日日期用标准 lunarInfo 离线预生成，运行时不引农历库；2030 起需同步扩 `FESTIVAL_DATE_MAP`（前端 + `trash.js` 两处）。
- 评审指出迁移路径上 `drawAnim` 会被服务端 `first:false` 的 `showFortune` 打断导致签级滚动残留——已用 `stopDrawAnim` 统一收口。
- 旧缓存前端对 `idx:null` 会当错误回落；协议字段不能当兼容层。

## [S1] Problem

幸运签目前只有 8 条通用签文，每天随机抽。传统节日当天没有节日氛围，已经抽过通用签的用户也只能看到旧结果。今天是中秋（2026-09-25），需要：为每个传统节日设计固定特别签；节日当天所有人都抽到该签；已抽过的人打开后也看到节日签。

## [S2] Design

### 范围
- 改 `index.html`（前端幸运签）与 `trash/trash.js`（`/api/draw`）。
- 不改通用 8 签随机逻辑（非节日）；不改星座运势、摸鱼日历。
- 日期表按公历硬编码 2025–2029（与 `FISH_OFF` 同风格）；农历换算用标准 lunarInfo 预生成，运行时不依赖农历库。
- 时区：当日以 **UTC+8** 计算（与服务端 `dayStr()` 一致）；前端 `drawTodayKey` 同步改为 UTC+8。

### 节日集合（12）
春节、元宵、龙抬头、清明、端午、七夕、中元、中秋、重阳、腊八、小年、除夕。

### 节日签数据结构（与 FORTUNES 兼容 + 节日元数据）
```
{
  id: "zhongqiu",          // 稳定 id
  festival: "中秋节",       // 展示名
  lunar: "八月十五",        // 农历标注
  lv, color, num, name, poem[], desc, yi, ji  // 同 FORTUNES 字段
}
```
另：`FESTIVAL_DATE_MAP = { "YYYY-MM-DD": festivalId }`，由 2025–2029 预生成表展开。

### 行为契约
1. **节日判定** `festivalOfToday()`：UTC+8 当日 `YYYY-MM-DD` 命中 `FESTIVAL_DATE_MAP` → 返回节日签对象，否则 `null`。
2. **当日固定**：节日当天 `openFortune` 不走随机/`idx`，直接展示节日签；`drawAnim` 仍播放抽签动画后落到节日签。
3. **已抽覆盖**：展示节日签后 `saveDrawLocal` 写入含 `festivalId` 的节日签对象，覆盖当日旧缓存；再次打开仍显示节日签。服务端 `GET/POST /api/draw` 在节日日将已存 `zodiacDraws[ck]` 迁移为节日签标记，并返回 `{ festival: id, first: false|true }`（同时保留 `idx: null` 以兼容旧前端）。
4. **非节日**：行为与现状一致（服务端锁定 idx，失败本地随机；当日固定不重抽）。
5. **UI**：
   - 节日时 `.fortune-kick` 改为 `Festival Sign`，标题旁/副标题显示「{节日}特别签」，`fr-date` 后缀「· {节日}特别签」。
   - 结果卡样式不变，签文/宜忌/幸运数字色用节日签数据。
6. **API 响应扩展**（非节日保持原字段）：
   - 节日：`{ idx: null, festival: "<id>", festivalName: "中秋节", first: false, date: dayStr() }`
   - 前端若收到 `festival`，用本地 `FESTIVAL_FORTUNES[id]` 渲染（内容以本地为准，避免前后端文案漂移）。
   - 说明：仍缓存旧版脚本的客户端会把 `idx:null` 当错误，回落到本地随机/节日覆盖；刷新后对齐。不算协议兼容层。

### 日期表（预生成，UTC+8 日历日）
| id | 2025 | 2026 | 2027 | 2028 | 2029 |
|----|------|------|------|------|------|
| chunjie | 01-29 | 02-17 | 02-06 | 01-26 | 02-13 |
| yuanxiao | 02-12 | 03-03 | 02-20 | 02-09 | 02-27 |
| longtaitou | 03-01 | 03-20 | 03-09 | 02-26 | 03-16 |
| qingming | 04-04 | 04-05 | 04-05 | 04-04 | 04-04 |
| duanwu | 05-31 | 06-19 | 06-09 | 05-28 | 06-16 |
| qixi | 08-29 | 08-19 | 08-08 | 08-26 | 08-16 |
| zhongyuan | 09-06 | 08-27 | 08-16 | 09-03 | 08-24 |
| zhongqiu | 10-06 | **09-25** | 09-15 | 10-03 | 09-22 |
| chongyang | 10-29 | 10-18 | 10-08 | 10-26 | 10-16 |
| laba | (次年)01-26 | 01-26 | 01-15 | 01-04 | 01-22 |
| xiaonian | (次年)02-10 | 02-10 | 01-30 | 01-19 | 02-06 |
| chuxi | (次年)02-16 | 02-16 | 02-05 | 01-25 | 02-12 |

（腊八/小年/除夕落在农历年尾，归属该农历年；表中按公历年归组。端午/中秋已与站内 `FISH_OFF` 对齐。）

## [S3] Out of Scope
- 不引入农历运行时库；2030 及以后日期需按同样方式扩表（注释标明）。
- 不批量改写生产 `zodiac-draws.json`（用户选择打开时覆盖）。
- 不改玩法抽签、星盘、摸鱼日历。
- 不做节日主题皮肤/弹窗动效大改。

## Tasks
- [x] T1: 前端节日签数据与日期表 — acceptance: `FESTIVAL_FORTUNES` 12 条齐全，`FESTIVAL_DATE_MAP` 含 2025–2029，今日 `2026-09-25 → zhongqiu` (covers: S2)
- [x] T2: 前端当日固定抽签 + 已抽覆盖 — acceptance: 节日 `openFortune` 展示节日签并覆盖 localStorage；非节日路径不变；`drawTodayKey` 为 UTC+8 (covers: S2)
- [x] T3: 节日特别签 UI 标识 — acceptance: 节日时 kick/副标题/日期线显示节日特别签 (covers: S2)
- [x] T4: 后端 `/api/draw` 节日固定与迁移 — acceptance: 节日日返回 `festival` 字段并迁移已存 draw；非节日响应不变 (covers: S2; depends: T1)
- [x] T5: 验证 — acceptance: 节点语法检查通过；节日/非节日逻辑用例通过；日期与 FISH_OFF 端午中秋一致 (covers: S2)
