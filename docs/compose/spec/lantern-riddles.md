---
feature: lantern-riddles
status: delivered
updated: 2026-09-25
branch: feature/lantern-riddles
commits: 43ce72f..e6b4be5
---

# 中秋猜灯谜活动

## Report

**What was built** — 中秋限定「猜灯谜」：30 题、答对 1 分；登录才能猜；猜中后全员可见是谁猜中（不露谜底）；左侧排行榜；活动窗口中秋 00:00 至次日 03:00（2026 截止 9/26 03:00）。底部「附加题 · emoji 猜成语」30 题抽取制：抽到哪题答哪题，答对才能抽下一题，每题 0.5 分并入总分。首开弹窗每日一次，入口在「联系我们」右侧。答错中央大字「菜！」约 1 秒。常驻「请豆姐帮忙的罚一个月饼！！！」。手机端猜谜/排行双 Tab，题面楷体放大。

**Verification** — 内联 script 解析 2 OK；`node --check trash.js` OK；FE/BE 各 30 题且 q 文案 30/30 一致；前端不含谜底；答案匹配（空格/大小写/标点/别解）单测通过；中秋门控 2026-09-25 开、次日关；CSS 括号平衡。首轮评审 2 critical（FE/BE 谜底不一致、ESC 未记弹窗）→ 修复后复审 approve。

**Journey log**
- 谜底只放服务端，前端只展示题面，避免 view-source 作弊与双表漂移。
- 弹窗「每日一次」必须在所有关闭路径（按钮 + ESC）写 `chimu_lantern_popup_<date>`。
- 正式灯谜替换：改 `trash.js` 的 q/a，并同步 `index.html` 占位 q（或改为完全以 GET 为准）。

## [S1] Problem

## [S1] Problem

中秋节缺少可玩的站内活动。需要「猜灯谜」：仅中秋当日开放；登录才能猜；猜中对全员可见是谁猜的（不露谜底）；左侧排行榜；23:59 截止；首次进站弹窗一次，顶栏「联系我们」右侧有入口；答错给嘲讽短句；页面固定提示「请豆姐帮忙的罚一个月饼！！！」。界面要中秋风、灯谜字偏文艺。

## [S2] Design

### 范围
- 前端 `index.html`（弹窗/入口/答题 UI）+ 后端 `trash/trash.js`（`/api/lantern*`）。
- 灯谜 30 条：**无难度分级，每题 1 分**。正文占位 `LANTERN_RIDDLES`，便于替换正式题面（用户后补）。
- 仅公历中秋日（复用 `FESTIVAL_DATE_MAP` 中 `zhongqiu`）；当日 00:00–23:59（UTC+8）可答。

### 数据契约
**谜题（前端定义，服务端校验用同一列表）**
```
{ id: 1..30, q: "题面", a: ["谜底1","别解"] }  // 比对：去空格、可含常见别解
```

**服务端存储 `trash/data/lantern.json`**
```
{
  days: {
    "2026-09-25": {
      solves: {
        "1": [{ name: "昵称", ts: 169... }, ...]  // 该题已解出的人（可多人）
      }
    }
  }
}
```

**API**
- `GET /api/lantern` → `{ date, open, closedAfter, riddles:[{id,q,solvers:[{name,ts}]}], me:{name,solved:[ids],score}, board:[{name,score,solvedCount}] }`（不含谜底）
- `POST /api/lantern/answer` body `{id, answer}`  
  - 未登录 401  
  - 非开放 403 `{err, closed:true}`  
  - 已被本人解出 409  
  - 对：200 `{ok:true, solvers}`，每人每题 +1 分  
  - 错：200 `{ok:false}`（不回谜底；嘲讽文案前端本地池随机）

### 行为
1. **门控**：`festivalOfToday()?.id==="zhongqiu"` 才显示入口与弹窗；否则全部隐藏且不请求。
2. **入口**：顶栏 `#contactPop` 右侧新增 `#lanternCap`（中秋限定）。
3. **首开弹窗**：localStorage `chimu_lantern_popup_<date>` 每天只弹一次；点进活动主界面。
4. **主界面**：左栏排行榜（昵称+得分，按分降序、同分按先解出时间）；右栏 30 张灯谜卡（题面文艺字）。已解出显示「某某猜中」；**不显示答案**；仍可继续作答。
5. **截止**：UTC+8 当日 ≥23:59 停止输入，展示「已收卷」。
6. **登录**：未登录点作答 → 拉起登录；未登录可浏览题面与榜（不可答）。
7. **答错**：本地嘲讽池随机（菜死了 / 行不行啊 / 文盲 / 加油哦~ / 重修吧 / 这都不会？ / 月饼没了 / 建议重修语文…）。
8. **固定文案**：活动区常驻「请豆姐帮忙的罚一个月饼！！！」。

### 谜题占位
`LANTERN_RIDDLES` 30 条 `{id,q,a[]}`，`q` 含「（占位·待定稿）」可识别；正式题面替换 `q`/`a` 即可，不改逻辑。

### 附加题：emoji 猜成语（抽取制）
- 位置：灯谜列表最下方独立区块。
- 题库 30 条 `{id, emoji, a}`；**每人抽取制**：当前未解出时可「抽一题」；**答对才可抽下一题**；答错留在本题（嘲讽「菜！」）。
- 每题 **0.5 分**，并入排行榜总分（`score = 灯谜分 + 0.5 * 附加题数`）。
- 未登录不可抽/不可答；与灯谜同一活动窗口（至次日 03:00）。
- 服务端存 `lantern.json` 该日 `emoji[username]={current,solved[]}`；不下发谜底。
- 题库含用户给定 30 条（含同成语不同 emoji 组合，按独立 id 计）。

## [S3] Out of Scope
- 不做难度分级/加权计分。
- 不在服务端下发嘲讽文案。
- 不改摸鱼日历、幸运签、社区通知。
- 不提供手动重开截止；不写历史数据迁移。
- 效果预览 dump 页不更新。

## Tasks
- [x] T1: 骨架与 30 题占位 + 中秋门控 — acceptance: `LANTERN_RIDDLES` 恰 30 条；非中秋不显示入口/弹窗 (covers: S2)
- [x] T2: 后端 `/api/lantern` — acceptance: GET 不含谜底；POST 登录校验、对错、积分、23:59 截止、多人 solvers (covers: S2)
- [x] T3: 前端 UI — acceptance: 弹窗一次/入口/左榜右题/嘲讽/豆姐提示/已解显示昵称不露底 (covers: S2)
- [x] T4: 验证 — acceptance: 语法与逻辑用例；中秋日 2026-09-25 门控为开 (covers: S2)
- [x] T5: emoji 附加题后端 — acceptance: 抽题/作答 API；答对 +0.5；未解不能抽下一题 (covers: S2)
- [x] T6: emoji 附加题前端 — acceptance: 列表底部区块、抽取按钮、答对才能继续 (covers: S2)
- [x] T7: 附加题验证与评审 — acceptance: 语法与抽取逻辑用例通过 (covers: S2)
