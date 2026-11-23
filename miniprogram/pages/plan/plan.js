// 计划 · 小程序端
// 对应 flutter/lib/pages/plan_page.dart 的移动端：今天卡 + 待办卡 + 记账卡。
// 约定：登录门禁 ready 之前不读取任何数据；每张卡单独 try/catch，
// 模块缺失或数据异常时只把该卡降级成占位文案，不影响其它卡片。
const session = require("../../utils/session");
const WEEKDAY_CHARS = ["日", "一", "二", "三", "四", "五", "六"];
const WEEKDAY_FULL = [
  "星期日",
  "星期一",
  "星期二",
  "星期三",
  "星期四",
  "星期五",
  "星期六",
];
const DAY_MS = 86400000;

/* ---------------- 基础工具 ---------------- */

function pad2(n) {
  return n < 10 ? "0" + n : String(n);
}

function asInt(value, fallback) {
  if (typeof value === "number" && isFinite(value)) return Math.floor(value);
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = parseInt(value, 10);
    if (!isNaN(parsed)) return parsed;
  }
  return fallback;
}

function textOf(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" && isFinite(value)) return String(value);
  if (value && typeof value === "object") {
    if (typeof value.name === "string") return value.name.trim();
    if (typeof value.label === "string") return value.label.trim();
    if (typeof value.title === "string") return value.title.trim();
    if (typeof value.text === "string") return value.text.trim();
  }
  return "";
}

function clampPercent(value) {
  const n = Number(value);
  if (!isFinite(n)) return 0;
  return Math.round(Math.min(100, Math.max(0, n)));
}

function groupDigits(value) {
  const raw = String(Math.max(0, Math.floor(value)));
  let out = "";
  for (let i = 0; i < raw.length; i += 1) {
    if (i > 0 && (raw.length - i) % 3 === 0) out += ",";
    out += raw[i];
  }
  return out;
}

// 页面约定：金额一律按分传入，展示成两位小数的元。
function money2(cents) {
  const n = asInt(cents, 0);
  const abs = Math.abs(n);
  return (
    (n < 0 ? "-" : "") +
    "¥" +
    groupDigits(Math.floor(abs / 100)) +
    "." +
    pad2(abs % 100)
  );
}

function dayKey(value) {
  const d = value instanceof Date ? value : new Date(value);
  if (isNaN(d.getTime())) return "";
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function sameDay(a, b) {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

// 一周格里的农历只留两个字的日名；初一保留完整月名，便于看出换月。
function shortLunar(text) {
  const chars = Array.from(text || "");
  if (!chars.length) return "";
  if (chars.length <= 3 || text.slice(-2) === "初一") return text;
  return chars.slice(-2).join("");
}

/* ---------------- 只读模块（缺失时降级） ---------------- */

function getTodoStore() {
  try {
    return require("../../utils/todo-store");
  } catch (e) {
    return null;
  }
}

function getCalendarStore() {
  try {
    return require("../../utils/calendar-store");
  } catch (e) {
    return null;
  }
}

function getLunar() {
  try {
    return require("../../utils/lunar");
  } catch (e) {
    return null;
  }
}

function lunarInfoFor(lunar, date) {
  const empty = { lunar: "", term: "", festival: "", label: "" };
  if (!lunar || typeof lunar.todayInfo !== "function") return empty;
  try {
    const info = lunar.todayInfo(date);
    if (typeof info === "string") {
      return { lunar: info, term: "", festival: "", label: info };
    }
    return info && typeof info === "object" ? info : empty;
  } catch (e) {
    return empty;
  }
}

/* ---------------- 今天卡 ---------------- */

function buildDateView(now, lunar) {
  const info = lunarInfoFor(lunar, now);
  const festival = textOf(info.festival);
  const term = textOf(info.term);
  const lunarText = textOf(info.lunar);
  const fallbackLabel = textOf(info.label);

  const pieces = [];
  if (lunarText) pieces.push("农历 " + lunarText);
  if (term) pieces.push("节气 " + term);
  if (festival) pieces.push("节日 " + festival);
  const metaText = pieces.length
    ? pieces.join(" · ")
    : fallbackLabel || "农历信息暂不可用";

  // 周一起始，与「一~日」的阅读顺序一致。
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const offset = (start.getDay() + 6) % 7;
  start.setDate(start.getDate() - offset);

  const week = [];
  for (let i = 0; i < 7; i += 1) {
    const date = new Date(
      start.getFullYear(),
      start.getMonth(),
      start.getDate() + i
    );
    const dayInfo = lunarInfoFor(lunar, date);
    const dayFestival = textOf(dayInfo.festival);
    const dayTerm = textOf(dayInfo.term);
    const dayLunar = textOf(dayInfo.lunar);
    const dayFallback = textOf(dayInfo.label);
    const label =
      dayFestival ||
      dayTerm ||
      (dayLunar ? shortLunar(dayLunar) : dayFallback);
    let labelClass = "week-label is-empty";
    if (dayFestival) labelClass = "week-label is-festival";
    else if (dayTerm) labelClass = "week-label is-term";
    else if (dayLunar) labelClass = "week-label is-lunar";
    const isToday = sameDay(date, now);
    week.push({
      key: dayKey(date),
      wd: WEEKDAY_CHARS[date.getDay()],
      day: date.getDate(),
      label: label,
      cellClass: isToday ? "week-cell is-today" : "week-cell",
      labelClass: labelClass,
    });
  }

  return {
    dateText: now.getMonth() + 1 + " 月 " + now.getDate() + " 日",
    headline: festival || term || WEEKDAY_FULL[now.getDay()],
    metaText: metaText,
    week: week,
  };
}

/* ---------------- 最近一个倒数日 ---------------- */

function firstCountdown(result) {
  if (!result) return null;
  if (Array.isArray(result)) return result.length ? result[0] : null;
  if (Array.isArray(result.items)) return result.items.length ? result.items[0] : null;
  if (result.mark && typeof result.mark === "object") {
    if (result.days != null && result.mark.days == null) {
      return Object.assign({}, result.mark, { days: result.days });
    }
    return result.mark;
  }
  if (result.next && typeof result.next === "object") return result.next;
  if (typeof result === "object") {
    if (result.title || result.name || result.label) return result;
  }
  return null;
}

function countdownDays(item, now) {
  const fields = ["days", "daysLeft", "daysRemain", "remain", "remaining", "left"];
  for (let i = 0; i < fields.length; i += 1) {
    const rawValue = item[fields[i]];
    if (rawValue === undefined || rawValue === null || rawValue === "") continue;
    const n = Number(rawValue);
    if (isFinite(n)) return Math.round(n);
  }
  const raw = textOf(item.date) || textOf(item.day);
  const match = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(raw);
  if (!match) return null;
  const target = new Date(
    Number(match[1]),
    Number(match[2]) - 1,
    Number(match[3])
  );
  if (isNaN(target.getTime())) return null;
  const from = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const to = new Date(target.getFullYear(), target.getMonth(), target.getDate());
  return Math.round((to.getTime() - from.getTime()) / DAY_MS);
}

function buildCountdownView(result, now) {
  const item = firstCountdown(result);
  if (!item) {
    return {
      countdownHas: false,
      countdownLabel: "",
      countdownText: "还没有倒数日，去日历记一个",
      countdownClass: "countdown-text is-empty",
    };
  }
  const rawTitle = textOf(item.title) || textOf(item.name);
  const labelText = textOf(item.label);
  const title = rawTitle || labelText || "记下的日子";
  // calendar-store 的 upcoming() 会带上 label（还有 N 天 / 已经 N 天 / 就是今天），
  // 有标题时用它，纪念日的文案才不会算反；只有 label 没有标题时它只是标题。
  let dayPhrase =
    textOf(item.daysText) ||
    textOf(item.dayText) ||
    (rawTitle ? labelText : "");
  const days = countdownDays(item, now);
  if (!dayPhrase && days !== null) {
    if (days === 0) dayPhrase = "就是今天";
    else if (days > 0) dayPhrase = "还有 " + days + " 天";
    else dayPhrase = "已过 " + Math.abs(days) + " 天";
  }
  const kind =
    textOf(item.kindLabel) ||
    (item.kind === "anniversary" ? "纪念日" : "倒数日");
  return {
    countdownHas: true,
    countdownLabel: "最近的" + kind,
    countdownText: title + (dayPhrase ? " · " + dayPhrase : ""),
    countdownClass: "countdown-text",
  };
}

/* ---------------- 待办卡 ---------------- */

function buildTodoView() {
  const empty = {
    todoOk: false,
    todoTotal: 0,
    todoDone: 0,
    todoRemaining: 0,
    todoPercent: 0,
    todoPercentText: "—",
    todoHeadText: "待办暂不可用",
    todoUnitText: "件待办",
    todoHasOverdue: false,
    todoOverdueCount: 0,
    todoOverdueText: "",
    todoItems: [],
    todoHasItems: false,
    todoEmptyText: "待办数据暂时读不到，下拉刷新试试",
  };
  const store = getTodoStore();
  if (!store || typeof store.summary !== "function") return empty;

  let sum = null;
  try {
    sum = store.summary();
  } catch (e) {
    return empty;
  }
  if (!sum || typeof sum !== "object") return empty;

  const sourceItems = Array.isArray(sum.items) ? sum.items : [];
  const total = Math.max(0, asInt(sum.today, 0));
  let done = Math.max(0, asInt(sum.done, 0));
  if (done > total) done = total;
  const remaining = Math.max(0, total - done);
  const overdue = Math.max(0, asInt(sum.overdue, 0));
  const percent = clampPercent(
    asInt(sum.percent, total > 0 ? Math.round((done * 100) / total) : 0)
  );

  const items = sourceItems.slice(0, 3).map(function (task, index) {
    const raw = task && typeof task === "object" ? task : {};
    const isDone = raw.done === true;
    return {
      id: String(raw.id || "todo-" + index),
      title: textOf(raw.title) || "未命名任务",
      kindLabel: textOf(raw.kindLabel),
      dueText: textOf(raw.dueText),
      done: isDone,
      rowClass: isDone ? "todo-row is-done" : "todo-row",
      checkClass: isDone ? "todo-check is-done" : "todo-check",
      checkText: isDone ? "✓" : "",
      titleClass: isDone ? "todo-title is-done" : "todo-title",
    };
  });

  let emptyText = "";
  if (!items.length) {
    if (total === 0) emptyText = "今天还没有任务，先写一件小事";
    else if (remaining === 0) emptyText = "今天的都做完了，去休息一下";
    else emptyText = "还有 " + remaining + " 件没做完，点开看看";
  }

  return {
    todoOk: true,
    todoTotal: total,
    todoDone: done,
    todoRemaining: remaining,
    todoPercent: percent,
    todoPercentText: percent + "%",
    todoHeadText:
      total === 0 ? "今天空着" : "完成 " + done + "/" + total,
    todoUnitText: total === 0 ? "件待办" : "件没做完",
    todoHasOverdue: overdue > 0,
    todoOverdueCount: overdue,
    todoOverdueText: overdue > 0 ? "逾期 " + overdue + " 件，记得处理" : "",
    todoItems: items,
    todoHasItems: items.length > 0,
    todoEmptyText: emptyText,
  };
}

/* ---------------- 记账卡 ---------------- */

function buildLedgerView() {
  const empty = {
    ledgerOk: false,
    ledgerLabel: "",
    ledgerExpenseText: "—",
    ledgerExpenseCents: 0,
    ledgerIncomeLine: "收入 —",
    ledgerBalanceLine: "结余 —",
    ledgerIncomeClass: "ledger-side-text is-empty",
    ledgerBalanceClass: "ledger-side-text is-empty",
    ledgerHasBudget: false,
    ledgerBudgetText: "",
    ledgerPercent: 0,
    ledgerProgressClass: "plan-progress-fill",
    ledgerBudgetSummary: "",
    ledgerBudgetNoteClass: "ledger-budget-note",
    ledgerDays: [],
    ledgerHasData: false,
    ledgerEmptyText: "记账数据暂时读不到，下拉刷新试试",
  };
  const store = getLedgerStore();
  if (!store || typeof store.summary !== "function") return empty;

  let sum = null;
  try {
    sum = store.summary();
  } catch (e) {
    return empty;
  }
  if (!sum || typeof sum !== "object") return empty;

  const now = new Date();
  const expense = Math.max(0, asInt(sum.expense, 0));
  const income = Math.max(0, asInt(sum.income, 0));
  const balance = asInt(sum.balance, income - expense);
  const budget = Math.max(0, asInt(sum.budget, 0));
  const hasBudget = budget > 0;
  const percent = hasBudget
    ? clampPercent(asInt(sum.percent, Math.round((expense * 100) / budget)))
    : 0;
  const over = hasBudget && expense > budget;

  const sourceDays = Array.isArray(sum.days) ? sum.days : [];
  let maxValue = 0;
  sourceDays.forEach(function (day) {
    const value = Math.max(0, asInt(day && day.value, 0));
    if (value > maxValue) maxValue = value;
  });
  const days = sourceDays.slice(-7).map(function (day, index) {
    const value = Math.max(0, asInt(day && day.value, 0));
    const height = maxValue > 0 ? Math.round((value / maxValue) * 84) : 0;
    return {
      key: "day-" + index,
      label: textOf(day && day.label),
      height: value > 0 ? Math.max(8, height) : 0,
    };
  });

  const budgetNote = over
    ? "超 " + money2(expense - budget)
    : "剩 " + money2(budget - expense);

  return {
    ledgerOk: true,
    ledgerLabel:
      textOf(sum.label) ||
      now.getFullYear() + "年" + (now.getMonth() + 1) + "月",
    ledgerExpenseText: money2(expense),
    ledgerExpenseCents: expense,
    ledgerIncomeLine: "收入 " + money2(income),
    ledgerBalanceLine: "结余 " + money2(balance),
    ledgerIncomeClass: "ledger-side-text is-mint",
    ledgerBalanceClass:
      balance < 0 ? "ledger-side-text is-danger" : "ledger-side-text",
    ledgerHasBudget: hasBudget,
    ledgerBudgetText: money2(budget),
    ledgerPercent: percent,
    ledgerProgressClass: over
      ? "plan-progress-fill is-over"
      : "plan-progress-fill",
    ledgerBudgetSummary: hasBudget
      ? "已用 " + percent + "% · " + budgetNote
      : "预算未设置，点开记一笔",
    ledgerBudgetNoteClass: over
      ? "ledger-budget-note is-over"
      : "ledger-budget-note",
    ledgerDays: days,
    ledgerHasData: maxValue > 0,
    ledgerEmptyText: "还没有支出，记账后就能看到近 7 天",
  };
}

// 单独成函数，确保只有记账模块的 require 出错时影响这一张卡。
function getLedgerStore() {
  try {
    return require("../../utils/ledger-store");
  } catch (e) {
    return null;
  }
}

/* ---------------- 今日小结 ---------------- */

function buildTodaySummary(todo, ledger) {
  const fail = !todo.todoOk || !ledger.ledgerOk;
  const total = todo.todoOk ? todo.todoTotal : 0;
  const remaining = todo.todoOk ? todo.todoRemaining : 0;
  const overdue = todo.todoOk ? todo.todoOverdueCount : 0;
  const spent = ledger.ledgerOk ? ledger.ledgerExpenseCents : 0;
  let note = "把今天安排好，剩下的交给时间。";
  if (fail) {
    note = "部分数据暂时读不到，下拉刷新试试。";
  } else if (total === 0 && overdue > 0) {
    note = "有 " + overdue + " 件逾期了，慢慢补上就好。";
  } else if (total === 0 && spent === 0) {
    note = "今天还很空，慢慢来，先写一件小事。";
  } else if (total === 0) {
    note = "花销已经记下，今天还空着，给自己留一点时间。";
  } else if (remaining === 0) {
    note = "今天的待办都完成了，去休息一下。";
  } else if (remaining <= 2) {
    note = "只剩 " + remaining + " 件了，收个尾吧。";
  } else {
    note = "还有 " + remaining + " 件待办，一件一件来。";
  }
  return {
    summaryRateText: todo.todoOk ? todo.todoPercent + "%" : "—",
    summaryTodoText: todo.todoOk ? String(remaining) : "—",
    summaryLedgerText: ledger.ledgerOk ? ledger.ledgerExpenseText : "—",
    summaryNote: note,
  };
}

/* ---------------- 初始占位 ---------------- */

function buildInitialView() {
  return {
    dateText: "",
    headline: "",
    metaText: "",
    week: [],
    countdownHas: false,
    countdownLabel: "",
    countdownText: "",
    countdownClass: "countdown-text is-empty",
    todoOk: false,
    todoTotal: 0,
    todoDone: 0,
    todoRemaining: 0,
    todoPercent: 0,
    todoPercentText: "—",
    todoHeadText: "待办暂不可用",
    todoUnitText: "件待办",
    todoHasOverdue: false,
    todoOverdueCount: 0,
    todoOverdueText: "",
    todoItems: [],
    todoHasItems: false,
    todoEmptyText: "待办数据暂时读不到，下拉刷新试试",
    ledgerOk: false,
    ledgerLabel: "",
    ledgerExpenseText: "—",
    ledgerExpenseCents: 0,
    ledgerIncomeLine: "收入 —",
    ledgerBalanceLine: "结余 —",
    ledgerIncomeClass: "ledger-side-text is-empty",
    ledgerBalanceClass: "ledger-side-text is-empty",
    ledgerHasBudget: false,
    ledgerBudgetText: "",
    ledgerPercent: 0,
    ledgerProgressClass: "plan-progress-fill",
    ledgerBudgetSummary: "",
    ledgerBudgetNoteClass: "ledger-budget-note",
    ledgerDays: [],
    ledgerHasData: false,
    ledgerEmptyText: "记账数据暂时读不到，下拉刷新试试",
    summaryRateText: "—",
    summaryTodoText: "—",
    summaryLedgerText: "—",
    summaryNote: "部分数据暂时读不到，下拉刷新试试。",
  };
}

/* ---------------- 页面 ---------------- */

Page({
  data: Object.assign(
    {
      ready: false,
      user: null,
    },
    buildInitialView()
  ),

  onLoad() {
    this.alive = true;
    this.countdownToken = 0;
  },

  onShow() {
    // 从日历 / 待办 / 记账页返回时重新读取，跨天后日期也会刷新。
    this.syncGate();
    if (this.data.ready) this.loadPage();
  },

  // 在别的 tab 退出/登录后，本页门禁可能还停在旧状态。
  syncGate() {
    const gate = this.selectComponent("#gate");
    if (!gate) return;
    if (!session.token() && this.data.ready) {
      this.onGateExpired();
      if (typeof gate.boot === "function") gate.boot();
      return;
    }
    if (
      session.token() &&
      gate.data &&
      gate.data.stage === "auth" &&
      typeof gate.boot === "function"
    ) {
      gate.boot();
    }
  },

  onUnload() {
    this.alive = false;
    this.countdownToken += 1;
  },

  onPullDownRefresh() {
    if (this.data.ready) this.loadPage();
    wx.stopPullDownRefresh();
  },

  /* ---------------- 登录门禁 ---------------- */

  onGateReady(e) {
    const user = (e && e.detail && e.detail.user) || null;
    this.setData({ ready: true, user: user });
    this.loadPage();
  },

  onGateUser(e) {
    const user = (e && e.detail && e.detail.user) || null;
    if (user) this.setData({ user: user });
  },

  onGateExpired() {
    this.countdownToken += 1;
    this.setData(
      Object.assign(
        {
          ready: false,
          user: null,
        },
        buildInitialView()
      )
    );
  },

  /* ---------------- 数据 ---------------- */

  loadPage() {
    if (!this.data.ready) return;
    const now = new Date();
    const dateView = buildDateView(now, getLunar());
    const todoView = buildTodoView();
    const ledgerView = buildLedgerView();
    const summaryView = buildTodaySummary(todoView, ledgerView);
    if (!this.alive) return;
    this.setData(
      Object.assign({}, dateView, todoView, ledgerView, summaryView)
    );
    this.loadCountdown(now);
  },

  loadCountdown(now) {
    const token = this.countdownToken + 1;
    this.countdownToken = token;
    const store = getCalendarStore();
    if (!store || typeof store.upcoming !== "function") {
      this.setData(buildCountdownView(null, now));
      return;
    }

    let result = null;
    try {
      result = store.upcoming(now, 1);
    } catch (e) {
      this.setData(buildCountdownView(null, now));
      return;
    }

    // 本地 store 正常是同步返回；兼容返回 Promise 的实现。
    if (result && typeof result.then === "function") {
      const self = this;
      result
        .then(function (value) {
          if (!self.alive || token !== self.countdownToken) return;
          self.setData(buildCountdownView(value, now));
        })
        .catch(function () {
          if (!self.alive || token !== self.countdownToken) return;
          self.setData(buildCountdownView(null, now));
        });
      return;
    }
    this.setData(buildCountdownView(result, now));
  },

  /* ---------------- 跳转 ---------------- */

  openCalendar() {
    this.go("/pages/calendar/calendar");
  },

  openTodo() {
    this.go("/pages/todo/todo");
  },

  openLedger() {
    this.go("/pages/ledger/ledger");
  },

  go(url) {
    if (!this.data.ready) return;
    const fail = function () {
      wx.showToast({ title: "页面还没有准备好", icon: "none" });
    };
    try {
      wx.navigateTo({ url: url, fail: fail });
    } catch (e) {
      fail();
    }
  },
});