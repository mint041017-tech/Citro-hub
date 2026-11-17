// 日历「倒数日 / 纪念日」数据层 · 小程序端
// 对应 flutter/lib/calendar/calendar_models.dart 与 calendar_store.dart。
//
// 本地优先：整包快照 {marks:[...]} 存在 citro_calendar_marks_v1，更新时间戳
// 单独存在 citro_calendar_marks_v1_at。登录后与 /api/calendar 整包同步：
// 云端 at 比本地时间戳新就覆盖本地，否则把本地推上去（last writer wins）。
// 网络失败、429 等都在这里吞掉，页面始终可以使用本地数据。
const api = require("./api");
const session = require("./session");

const STORAGE_KEY = "citro_calendar_marks_v1";
const AT_KEY = "citro_calendar_marks_v1_at";
const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
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

function ymd(p) {
  return p.y + "-" + pad2(p.m) + "-" + pad2(p.d);
}

function parseDateKey(value) {
  const match = DATE_RE.exec(String(value || "").trim());
  if (!match) return null;
  const y = Number(match[1]);
  const m = Number(match[2]);
  const d = Number(match[3]);
  const probe = new Date(y, m - 1, d);
  if (
    probe.getFullYear() !== y ||
    probe.getMonth() !== m - 1 ||
    probe.getDate() !== d
  ) {
    return null;
  }
  return { y: y, m: m, d: d };
}

// 统一取本地年月日，避免 toISOString / UTC 把日期挪到前一天。
function partsOf(value) {
  try {
    if (value === undefined || value === null || value === "") return null;
    let date = null;
    if (value instanceof Date) {
      date = value;
    } else if (typeof value === "number") {
      date = new Date(value);
    } else if (typeof value === "string") {
      const key = parseDateKey(value);
      if (key) return key;
      date = new Date(value);
    } else {
      return null;
    }
    if (!date || isNaN(date.getTime())) return null;
    return {
      y: date.getFullYear(),
      m: date.getMonth() + 1,
      d: date.getDate(),
    };
  } catch (e) {
    return null;
  }
}

function dayNumber(p) {
  return Math.floor(Date.UTC(p.y, p.m - 1, p.d) / DAY_MS);
}

function diffDays(from, to) {
  return dayNumber(to) - dayNumber(from);
}

function lastDayOfMonth(year, month) {
  return new Date(year, month, 0).getDate();
}

// 把月 / 日落到指定年份；2/29 在非闰年落到 2/28。
function sameMonthDay(year, base) {
  const day = Math.min(base.d, lastDayOfMonth(year, base.m));
  return { y: year, m: base.m, d: day };
}

/* ---------------- 容错清洗（保留未知字段） ---------------- */

function sanitizeMark(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const id = String(raw.id || "").trim();
  const title = String(raw.title || "").trim();
  const date = parseDateKey(raw.date);
  if (!id || !title || !date) return null;
  const mark = Object.assign({}, raw);
  mark.id = id;
  mark.title = title;
  mark.date = ymd(date);
  mark.kind = raw.kind === "anniversary" ? "anniversary" : "countdown";
  mark.yearly = raw.yearly === true;
  mark.note = typeof raw.note === "string" ? raw.note : "";
  mark.createdAt = asInt(raw.createdAt, 0);
  return mark;
}

function normalizeSnapshot(raw) {
  const source =
    raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const snap = Object.assign({}, source);
  const marks = [];
  if (Array.isArray(source.marks)) {
    source.marks.forEach(function (item) {
      const mark = sanitizeMark(item);
      if (mark) marks.push(mark);
    });
  }
  snap.marks = marks;
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

function save(snap) {
  const data = normalizeSnapshot(snap);
  const at = Date.now();
  try {
    wx.setStorageSync(STORAGE_KEY, data);
  } catch (e) {
    // 本地存储写失败时仍继续尝试云端。
  }
  try {
    wx.setStorageSync(AT_KEY, at);
  } catch (e) {}
  // 异步整包上传，失败静默；下次保存会再次推送。
  const token = session.token();
  if (token) {
    api.calendarSave(token, data).catch(function () {});
  }
  return data;
}

/* ---------------- 云端同步 ---------------- */

// GET /api/calendar -> {calendar, at}。
// 云端更新则覆盖本地；否则把本地整包推上去。任何失败都回退本地快照。
function sync(token) {
  const tok = token || session.token();
  const local = load();
  const localAt = storedAt();
  if (!tok) return Promise.resolve(local);

  return api
    .calendarGet(tok)
    .then(function (body) {
      const remote = body && body.calendar;
      const at = body ? asInt(body.at, 0) : 0;
      const hasRemote =
        !!remote && typeof remote === "object" && !Array.isArray(remote);

      if (hasRemote && at > localAt) {
        const snap = normalizeSnapshot(remote);
        try {
          wx.setStorageSync(STORAGE_KEY, snap);
          wx.setStorageSync(AT_KEY, at);
        } catch (e) {}
        return snap;
      }

      // 与 Flutter 一致：本地有标记就把本地推上去；空快照不主动覆盖云端。
      if (local.marks.length > 0 || localAt > at) {
        return api
          .calendarSave(tok, local)
          .catch(function () {})
          .then(function () {
            return local;
          });
      }
      return local;
    })
    .catch(function () {
      // 离线 / 401 / 429：继续用本地数据，不把异常抛给页面。
      return local;
    });
}

/* ---------------- 展示计算 ---------------- */

// 某标记的「下一次发生日」：单次就是原日期；每年重复取今年或明年的同月日。
function occurrenceOf(mark, today) {
  const base = parseDateKey(mark.date);
  if (!base) return null;
  if (!mark.yearly) return base;
  let next = sameMonthDay(today.y, base);
  if (diffDays(today, next) < 0) next = sameMonthDay(today.y + 1, base);
  return next;
}

function labelFor(kind, days) {
  if (days === 0) return "就是今天";
  const abs = Math.abs(days);
  if (kind === "anniversary") {
    return (days > 0 ? "已经 " : "还有 ") + abs + " 天";
  }
  return (days > 0 ? "还有 " : "已过 ") + abs + " 天";
}

// 返回 { ...mark, days, label, occurDate }：
// 倒数日 days 距下一次发生日的天数，纪念日 days 是从起始日到今天的天数。
function describe(mark, today) {
  const t = partsOf(today) || partsOf(new Date());
  const base = parseDateKey(mark && mark.date);
  const occurrence = base ? occurrenceOf(mark, t) : null;
  if (!base || !occurrence) {
    return Object.assign({}, mark, { days: 0, label: "", occurDate: "" });
  }
  const days =
    mark.kind === "anniversary"
      ? diffDays(base, t)
      : diffDays(t, occurrence);
  return Object.assign({}, mark, {
    days: days,
    label: labelFor(mark.kind, days),
    occurDate: ymd(occurrence),
  });
}

// 日期是否命中标记：每年重复按月日匹配；2/29 的年度标记在非闰年命中 2/28。
function hits(mark, date) {
  const base = parseDateKey(mark && mark.date);
  const p = partsOf(date);
  if (!base || !p) return false;
  if (mark.yearly) {
    if (base.m === 2 && base.d === 29) {
      return p.m === 2 && p.d === lastDayOfMonth(p.y, 2);
    }
    return base.m === p.m && base.d === p.d;
  }
  return base.y === p.y && base.m === p.m && base.d === p.d;
}

// 未来 n 天（含今天）内会发生的标记，按发生日排序。
function upcoming(today, n) {
  const t = partsOf(today) || partsOf(new Date());
  const horizon = Math.max(0, asInt(n, 60));
  const marks = load().marks;
  const list = [];
  marks.forEach(function (mark) {
    const info = describe(mark, t);
    const occurrence = parseDateKey(info.occurDate);
    if (!occurrence) return;
    const ahead = diffDays(t, occurrence);
    if (ahead < 0 || ahead > horizon) return;
    list.push(info);
  });
  list.sort(function (a, b) {
    const da = diffDays(t, parseDateKey(a.occurDate));
    const db = diffDays(t, parseDateKey(b.occurDate));
    if (da !== db) return da - db;
    const ka = a.kind === "anniversary" ? 1 : 0;
    const kb = b.kind === "anniversary" ? 1 : 0;
    if (ka !== kb) return ka - kb;
    if (a.title < b.title) return -1;
    if (a.title > b.title) return 1;
    return 0;
  });
  return list;
}

module.exports = {
  STORAGE_KEY: STORAGE_KEY,
  load: load,
  save: save,
  sync: sync,
  upcoming: upcoming,
  // 页面展示共用：标记是否命中某天 / 天数与文案计算。
  hits: hits,
  describe: describe,
};