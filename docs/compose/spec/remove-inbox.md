---
feature: remove-inbox
status: delivered
updated: 2026-09-25
branch: feature/remove-inbox
commits: a23e416..80adf54
---

# 移除收件箱与生日祝福

## Report

**What was built** — 完全移除「收件箱」与「生日祝福」两段功能。后端删除 `inbox.json` 存储、`/api/inbox*`、`/api/blessing`、`/api/birthday/today` 以及祝福/收件箱辅助函数；改名不再迁移收件箱。前端删除顶栏信封入口、手机端「我的→收件箱」、生日祝福弹窗与「收进收件箱」流程及相关 CSS。社区消息中心（铃铛）、社区左栏通知卡（`tkInbox`/`renderInboxCard`）、资料页生日字段均保留。`trash/data/inbox.json` 已从仓库删除。

**Verification** — `node --check trash/trash.js` 通过；两段内联 script `new Function` 通过；style 花括号 1755/1755；基线对比确认 `.pf-modal`/`.today-modal`/`.contact-*` 等未误删，`.bday-*`/`.msg-*`/`.bl-*` 已删；残留符号扫描（`pushInbox`/`inboxServerPull`/`/api/inbox` 等）为 0；`id=tkInbox/notifyBtn/pfModal` 在、`msgCap/bdayModal/meMsg` 不在。独立评审首轮回拒（CSS 过删）→ 从基线恢复样式后只删目标规则 → 复审 approve（CRITICAL 0）。

**Journey log**
- 用行匹配删 CSS 时把连续规则整段吞掉（资料弹窗/今日战报等）；花括号平衡抓不住「整块丢失」。正确做法：`git show base:file` 恢复 `<style>`，再按 `msg-`/`bday-`/`bl-` 选择器精确剥离。
- 前缀易混：`msg-*`/`bday-*`/`bl-*`（要删）≠ `pf-*`（资料，留）≠ `today-*`/`pomo-*`（无关，留）≠ `tk-ib-*`（社区通知，留）。
- 社区左栏标题叫「收件箱」的卡片实际是评论通知，用户明确不调整，勿被命名误导。

## [S1] Problem

站内「收件箱」（顶栏信封、手机端「我的→收件箱」、`/api/inbox*`、生日祝福写入）已不需要，用户要求完全移除。生日祝福功能整段删掉；社区左栏标题为「收件箱」的卡片实际是评论/回复通知，**不调整**。服务端 `trash/data/inbox.json` 一并删除。

## [S2] Design

### 范围
- 删：收件箱 UI/API/存储、生日祝福整段（弹窗 + `/api/blessing` + `/api/birthday/today` + 祝福相关后端）。
- 留：社区消息中心（铃铛 `/api/notifications`）、社区左栏 `tkInbox` 卡片及其渲染 `renderInboxCard`（名字带 inbox 但属社区通知）。
- 留：用户资料里的生日字段 `bdayOf` / 改生日。
- 删数据：`trash/data/inbox.json`（若存在）。

### 后端删除清单（`trash/trash.js`）
1. 存储与工具：`inboxFile` / `inboxes` / `saveInbox` / `INBOX_MAX` / `inboxOf` / `pushInbox` / `migrateInbox`。
2. 祝福：`BLESSING_*`、`ensureBlessingUser`（含启动调用）、`isBdayToday`、`birthdayUsersToday`、`countBlessings`、`addBlessing`。**保留 `bdayOf`**。
3. 路由：`GET/POST /api/inbox`、`POST /api/inbox/read`、`POST /api/inbox/self`、`GET/POST /api/blessing`、`GET /api/birthday/today`。
4. 改名迁移：去掉 `migrateInbox(...)` 调用（`notifRead` 迁移保留）。

### 前端删除清单（`index.html`）
1. DOM：顶栏 `#msgPop`（`#msgPanel`/`#msgCap`/`#msgBadge`…）、`#meMsg`（我的→收件箱）、整块 `#bdayModal`（含祝福表单）。
2. JS：收件箱+生日 IIFE（`renderMsgBox` / `inboxServerPull` / `closeMsgPanel` / `checkBirthdayPopup` / `collectBdayToInbox` 等）；所有调用点清除。
3. 手机端 Tab 角标：不再读 `msgBadge`。
4. CSS：仅删 `.msg-*` / `.bday-*` / `.bl-*` / `bdayBounce`；**保留** `.contact-*`、`.pf-*`、`.today-*`、社区 `.tk-ib-*`。

### 行为契约
- 收件箱入口消失；社区铃铛与左栏通知卡不受影响。
- 生日自动弹窗、祝福发送、「收进收件箱」全部消失。
- `/api/inbox*`、`/api/blessing`、`/api/birthday/today` 返回 404（路由已删）。
- 改昵称不再做收件箱迁移。

## [S3] Out of Scope
- 不改社区通知 API/数据（`notif-read.json`、`/api/notifications`）。
- 不改 `tkInbox` 卡片展示与命名。
- 不改用户资料生日编辑。
- 不清理 `效果预览/`、`zodiac-ai/devtools/out/` 里的历史 dump 副本。
- 不迁移/导出历史 inbox 消息（用户选择连文件删除）。

## Tasks
- [x] T1: 后端删除收件箱与祝福 — acceptance: `trash.js` 无 `/api/inbox*`/`/api/blessing`/`/api/birthday/today`；无 `pushInbox`/`addBlessing`/`ensureBlessingUser`；`node --check` 通过；`bdayOf` 仍在 (covers: S2)
- [x] T2: 前端删除收件箱 UI 与生日祝福 — acceptance: 无 `msgCap`/`bdayModal`/`meMsg` 节点与相关 JS；无 `inboxServerPull`/`checkBirthdayPopup` 调用；社区铃铛/`tkInbox` 仍在 (covers: S2)
- [x] T3: 删除 `inbox.json` 并验证 — acceptance: 数据文件不存在；语法与残留符号检查通过 (covers: S2)
