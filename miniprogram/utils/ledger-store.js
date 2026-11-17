// 记账数据层 · 小程序端
// 对应 flutter/lib/ledger/ledger_store.dart 与 ledger_models.dart。
// 数据先落本地（citro_ledger_v1），登录后按时间戳与 /api/ledger 整包同步：
// 本地更新则上传，云端更新则覆盖本地，最后写入者胜出（与 App 端一致）。
//
// 金额一律是「分」的整数，绝不用浮点保存；只有展示层才转成元。
const api = require("./api");
const session = require("./session");

const STORAGE_KEY = "citro_ledger_v1";
const AT_KEY = "citro_ledger_v1_at";
const FLUSH_DELAY = 900;
const MONTH_RE = /^(\d{4})-(\d{2})$/;
const WEEKDAY_LABELS = ["日", "一", "二", "三", "四", "五", "六"];
const FALLBACK_COLOR = 0xff8a7f6a;

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

function isMonthKey(key) {
  const match = MONTH_RE.exec(String(key || ""));
  if (!match) return false;
  const month = Number(match[2]);
  return month >= 1 && month <= 12;
}

function toDate(value) {
  if (value instanceof Date) return value;
  return new Date(asInt(value, 0));
}

function currentMonthKey(base) {
  const d = base instanceof Date && !isNaN(base.getTime()) ? base : new Date();
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1);
}

function monthKeyOf(value) {
  const d = toDate(value);
  if (isNaN(d.getTime())) return "";
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1);
}

function dayKeyOf(value) {
  const d = toDate(value);
  if (isNaN(d.getTime())) return "";
  return (
    d.getFullYear() +
    "-" +
    pad2(d.getMonth() + 1) +
    "-" +
    pad2(d.getDate())
  );
}

function shiftMonth(key, delta) {
  const match = MONTH_RE.exec(String(key || ""));
  const now = new Date();
  const year = match ? Number(match[1]) : now.getFullYear();
  const month = match ? Number(match[2]) - 1 : now.getMonth();
  return currentMonthKey(new Date(year, month + (delta || 0), 1));
}

// 任务规定的标题格式：2026年11月
function monthLabel(key) {
  const match = MONTH_RE.exec(String(key || ""));
  if (!match) return "";
  return Number(match[1]) + "年" + Number(match[2]) + "月";
}

function groupDigits(value) {
  const raw = String(Math.max(0, Math.floor(value)));
  let out = "";
  for (let i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 === 0) out += ",";
    out += raw[i];
  }
  return out;
}

// 展示用金额：整数元不补 .00，千分位分组，负数保留负号。
function fmtMoney(cents, options) {
  const opts = options || {};
  const n = asInt(cents, 0);
  const abs = Math.abs(n);
  const yuan = Math.floor(abs / 100);
  const fen = abs % 100;
  const body =
    fen === 0 ? groupDigits(yuan) : groupDigits(yuan) + "." + pad2(fen);
  return (n < 0 ? "-" : "") + (opts.symbol === false ? "" : "¥") + body;
}

// 输入框回填：不带 ¥、不带千分位，整数元不补小数。
function yuanText(cents) {
  const n = Math.max(0, asInt(cents, 0));
  const yuan = Math.floor(n / 100);
  const fen = n % 100;
  return fen === 0 ? String(yuan) : yuan + "." + pad2(fen);
}

// 字符串直接转分，避免 parseFloat 的浮点误差。
function parseAmount(raw) {
  let text = String(raw === undefined || raw === null ? "" : raw).trim();
  text = text.replace(/[¥￥,，]/g, "");
  if (!text) return null;
  if (!/^\d+(\.\d{0,2})?$/.test(text)) return null;
  const parts = text.split(".");
  const yuan = parseInt(parts[0], 10);
  if (!isFinite(yuan)) return null;
  let fen = 0;
  if (parts.length > 1 && parts[1]) {
    fen = parseInt((parts[1] + "00").slice(0, 2), 10);
  }
  const cents = yuan * 100 + fen;
  return cents >= 0 ? cents : null;
}

/* ---------------- 默认分类 ---------------- */

function defaultCategories() {
  return [
    {
      id: "food",
      name: "餐饮",
      kind: "expense",
      color: 0xffc08a4a,
      icon: "fork",
      builtIn: true,
      active: true,
    },
    {
      id: "transport",
      name: "交通",
      kind: "expense",
      color: 0xff6f8ca8,
      icon: "location",
      builtIn: true,
      active: true,
    },
    {
      id: "shopping",
      name: "购物",
      kind: "expense",
      color: 0xffb5717a,
      icon: "cart",
      builtIn: true,
      active: true,
    },
    {
      id: "home",
      name: "居住",
      kind: "expense",
      color: 0xff6e9a78,
      icon: "home",
      builtIn: true,
      active: true,
    },
    {
      id: "fun",
      name: "娱乐",
      kind: "expense",
      color: 0xff9a8fa6,
      icon: "games",
      builtIn: true,
      active: true,
    },
    {
      id: "health",
      name: "健康",
      kind: "expense",
      color: 0xffc4855d,
      icon: "heart",
      builtIn: true,
      active: true,
    },
    {
      id: "study",
      name: "学习",
      kind: "expense",
      color: 0xff8fa6be,
      icon: "book",
      builtIn: true,
      active: true,
    },
    {
      id: "other_expense",
      name: "其他",
      kind: "expense",
      color: FALLBACK_COLOR,
      icon: "flag",
      builtIn: true,
      active: true,
    },
    {
      id: "salary",
      name: "工资",
      kind: "income",
      color: 0xff6e9a78,
      icon: "note",
      builtIn: true,
      active: true,
    },
    {
      id: "gift",
      name: "红包",
      kind: "income",
      color: 0xffb5717a,
      icon: "heart",
      builtIn: true,
      active: true,
    },
    {
      id: "invest",
      name: "理财",
      kind: "income",
      color: 0xff6f8ca8,
      icon: "board",
      builtIn: true,
      active: true,
    },
    {
      id: "other_income",
      name: "其他",
      kind: "income",
      color: FALLBACK_COLOR,
      icon: "flag",
      builtIn: true,
      active: true,
    },
  ];
}

function defaultSnapshot() {
  return { entries: [], categories: defaultCategories(), plans: {} };
}

/* ---------------- 容错清洗（保留未知字段） ---------------- */

function sanitizeEntry(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const id = String(raw.id || "").trim();
  const amount = asInt(raw.amount, 0);
  if (!id || amount <= 0) return null;
  const out = Object.assign({}, raw);
  out.id = id;
  out.kind = raw.kind === "income" ? "income" : "expense";
  out.amount = amount;
  out.category = typeof raw.category === "string" ? raw.category : "";
  out.note = typeof raw.note === "string" ? raw.note : "";
  let occurredAt = asInt(raw.occurredAt, 0);
  let createdAt = asInt(raw.createdAt, occurredAt);
  if (occurredAt <= 0) occurredAt = createdAt > 0 ? createdAt : Date.now();
  if (createdAt <= 0) createdAt = occurredAt;
  out.occurredAt = occurredAt;
  out.createdAt = createdAt;
  out.source =
    typeof raw.source === "string" && raw.source ? raw.source : "manual";
  return out;
}

function sanitizeCategory(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const id = String(raw.id || "").trim();
  const name = String(raw.name || "").trim();
  if (!id || !name) return null;
  const out = Object.assign({}, raw);
  out.id = id;
  out.name = name;
  out.kind = raw.kind === "income" ? "income" : "expense";
  out.color = asInt(raw.color, FALLBACK_COLOR);
  out.icon =
    typeof raw.icon === "string" && raw.icon ? raw.icon : "flag";
  out.builtIn = raw.builtIn === true;
  out.active = raw.active !== false;
  return out;
}

function sanitizePlan(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { budget: 0, income: 0, categoryBudgets: {} };
  }
  const out = Object.assign({}, raw);
  out.budget = Math.max(0, asInt(raw.budget, 0));
  out.income = Math.max(0, asInt(raw.income, 0));
  const budgets = {};
  const source = raw.categoryBudgets;
  if (source && typeof source === "object" && !Array.isArray(source)) {
    Object.keys(source).forEach(function (key) {
      const value = asInt(source[key], 0);
      if (key && value > 0) budgets[key] = value;
    });
  }
  out.categoryBudgets = budgets;
  return out;
}

function normalizeSnapshot(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return defaultSnapshot();
  }
  const snap = Object.assign({}, raw);

  const entries = [];
  if (Array.isArray(raw.entries)) {
    raw.entries.forEach(function (item) {
      const entry = sanitizeEntry(item);
      if (entry) entries.push(entry);
    });
  }
  entries.sort(function (a, b) {
    return b.occurredAt - a.occurredAt;
  });
  snap.entries = entries;

  const categories = [];
  if (Array.isArray(raw.categories)) {
    raw.categories.forEach(function (item) {
      const category = sanitizeCategory(item);
      if (category) categories.push(category);
    });
  }
  snap.categories = categories.length ? categories : defaultCategories();

  const plans = {};
  if (raw.plans && typeof raw.plans === "object" && !Array.isArray(raw.plans)) {
    Object.keys(raw.plans).forEach(function (key) {
      if (isMonthKey(key)) plans[key] = sanitizePlan(raw.plans[key]);
    });
  }
  snap.plans = plans;

  return snap;
}

/* ---------------- 本地读写 ---------------- */

function load() {
  let stored = null;
  try {
    stored = wx.getStorageSync(STORAGE_KEY);
  } catch (e) {
    stored = null;
  }
  let raw = null;
  if (typeof stored === "string" && stored) {
    try {
      raw = JSON.parse(stored);
    } catch (e) {
      raw = null;
    }
  } else if (stored && typeof stored === "object") {
    raw = stored;
  }
  return normalizeSnapshot(raw);
}

function storedAt() {
  try {
    return asInt(wx.getStorageSync(AT_KEY), 0);
  } catch (e) {
    return 0;
  }
}

let flushTimer = null;

function cancelFlush() {
  if (flushTimer) {
    clearTimeout(flushTimer);
    flushTimer = null;
  }
}

// 保存后延迟整包上传；短时间内的连续修改只推最后一次。
function scheduleFlush(snap) {
  cancelFlush();
  if (!session.token()) return;
  flushTimer = setTimeout(function () {
    flushTimer = null;
    const token = session.token();
    if (!token) return;
    api.ledgerSave(token, snap).catch(function () {
      // 网络失败静默，下次修改会再次推送。
    });
  }, FLUSH_DELAY);
}

function save(snap) {
  const data = normalizeSnapshot(snap);
  try {
    wx.setStorageSync(STORAGE_KEY, data);
  } catch (e) {
    // 本地存储写失败时仍继续走云端推送。
  }
  try {
    wx.setStorageSync(AT_KEY, Date.now());
  } catch (e) {}
  scheduleFlush(data);
  return data;
}

/* ---------------- 云端同步 ---------------- */

// GET /api/ledger -> { ledger, at }。整包覆盖，last writer wins。
// 网络失败或未登录时直接回退本地，不抛出异常。
function sync(token) {
  const tok = token || session.token();
  const local = load();
  const localAt = storedAt();
  if (!tok) return Promise.resolve(local);
  cancelFlush();
  return api
    .ledgerGet(tok)
    .then(function (body) {
      const remote = body && body.ledger;
      const at = body ? asInt(body.at, 0) : 0;
      const hasRemote =
        !!remote && typeof remote === "object" && !Array.isArray(remote);
      if (!hasRemote || localAt > at) {
        // 云端为空或本地更新：把本地整包推上去。
        return api
          .ledgerSave(tok, local)
          .catch(function () {})
          .then(function () {
            return local;
          });
      }
      const snap = normalizeSnapshot(remote);
      try {
        wx.setStorageSync(STORAGE_KEY, snap);
        wx.setStorageSync(AT_KEY, at);
      } catch (e) {}
      return snap;
    })
    .catch(function () {
      return local;
    });
}

/* ---------------- 汇总 ---------------- */

// 返回 { monthKey, label, expense, income, balance, budget, percent, days }。
// 月切页会传入第二个参数 monthKey；不传时默认本月。
// days 是截止当月最后一天（本月则截止今天）的最近 7 天支出，单位分。
function summary(snap, monthKey) {
  const data = snap && typeof snap === "object" ? snap : load();
  const now = new Date();
  const key = isMonthKey(monthKey) ? String(monthKey) : currentMonthKey(now);
  const entries = Array.isArray(data.entries) ? data.entries : [];
  const plans =
    data.plans && typeof data.plans === "object" ? data.plans : {};
  const plan =
    plans[key] && typeof plans[key] === "object" ? plans[key] : {};

  let expense = 0;
  let income = 0;
  const dayExpense = {};
  entries.forEach(function (entry) {
    if (!entry) return;
    const amount = asInt(entry.amount, 0);
    if (amount <= 0) return;
    // 每日支出独立于所选月份统计：月初的「近 7 日」会跨到上个月。
    if (entry.kind !== "income") {
      const dayKey = dayKeyOf(entry.occurredAt);
      if (dayKey) dayExpense[dayKey] = (dayExpense[dayKey] || 0) + amount;
    }
    if (monthKeyOf(entry.occurredAt) !== key) return;
    if (entry.kind === "income") income += amount;
    else expense += amount;
  });

  const budget = Math.max(0, asInt(plan.budget, 0));
  const percent = budget > 0 ? Math.round((expense / budget) * 100) : 0;

  let end;
  if (key === currentMonthKey(now)) {
    end = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  } else {
    const match = MONTH_RE.exec(key);
    end = new Date(Number(match[1]), Number(match[2]), 0);
  }
  const days = [];
  for (let i = 6; i >= 0; i--) {
    const day = new Date(end.getFullYear(), end.getMonth(), end.getDate() - i);
    days.push({
      label: WEEKDAY_LABELS[day.getDay()],
      value: dayExpense[dayKeyOf(day.getTime())] || 0,
    });
  }

  return {
    monthKey: key,
    label: monthLabel(key),
    expense: expense,
    income: income,
    balance: income - expense,
    budget: budget,
    percent: percent,
    days: days,
  };
}

/* ---------------- 导出 ---------------- */

module.exports = {
  STORAGE_KEY: STORAGE_KEY,
  load: load,
  save: save,
  sync: sync,
  summary: summary,
  // 额外 helper：页面展示与输入解析共用，不参与快照字段。
  fmtMoney: fmtMoney,
  yuanText: yuanText,
  parseAmount: parseAmount,
  currentMonthKey: currentMonthKey,
  monthKeyOf: monthKeyOf,
  dayKeyOf: dayKeyOf,
  shiftMonth: shiftMonth,
  monthLabel: monthLabel,
};