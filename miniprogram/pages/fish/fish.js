// 摸鱼日历 · 小程序端
// 配置与 Flutter 端 flutter/lib/services/fish.dart 同一套：
// 云端 GET/PUT /api/moyu/config，休息日 0=周日；内置 2026 法定节假日与补班表。
const api = require("../../utils/api");
const session = require("../../utils/session");

const CACHE_KEY = "citro_fish_config";
const DEFAULT_CONFIG = {
  rest: [0, 6],
  start: "09:00",
  end: "18:00",
  breakStart: "",
  breakEnd: "",
};

// 周一起始展示，value 仍按 Date.getDay() 的 0=周日。
const WEEKDAYS = [
  { key: "w1", value: 1, label: "一" },
  { key: "w2", value: 2, label: "二" },
  { key: "w3", value: 3, label: "三" },
  { key: "w4", value: 4, label: "四" },
  { key: "w5", value: 5, label: "五" },
  { key: "w6", value: 6, label: "六" },
  { key: "w0", value: 0, label: "日" },
];
const DAY_NAMES = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
const WEEKDAY_LABELS = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
const REST_ORDER = [1, 2, 3, 4, 5, 6, 0];

// 与 fish.dart:69-83 同源，只列 2026 年确定的假期；不自行编造。
const HOLIDAYS = [
  { name: "元旦", start: "2026-01-01", end: "2026-01-03" },
  { name: "春节", start: "2026-02-15", end: "2026-02-22" },
  { name: "清明", start: "2026-04-04", end: "2026-04-06" },
  { name: "劳动节", start: "2026-05-01", end: "2026-05-05" },
  { name: "端午", start: "2026-06-19", end: "2026-06-21" },
  { name: "中秋", start: "2026-09-25", end: "2026-09-27" },
  { name: "国庆", start: "2026-10-01", end: "2026-10-07" },
];
const MAKEUP = ["2026-02-14", "2026-02-28", "2026-05-09", "2026-10-10"];
const CHIP_TEXT = {
  holiday: "法定假期",
  makeup: "调休补班",
  rest: "休息日",
  work: "工作日",
};

function pad2(n) {
  return (n < 10 ? "0" : "") + n;
}

function dateKey(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function dayNo(key) {
  const p = String(key).split("-");
  return Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2])) / 86400000;
}

function hm(v) {
  return typeof v === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(v) ? v : "";
}

function minutes(t) {
  const p = String(t || "").split(":");
  const h = parseInt(p[0], 10);
  const m = parseInt(p[1], 10);
  if (!isFinite(h) || !isFinite(m)) return -1;
  return h * 60 + m;
}

function addDays(d, n) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
}

function toast(title) {
  wx.showToast({ title: title, icon: "none" });
}

function normalizeConfig(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  let rest = DEFAULT_CONFIG.rest.slice();
  if (Array.isArray(src.rest)) {
    rest = [];
    for (let i = 0; i < src.rest.length; i += 1) {
      const n = Number(src.rest[i]);
      if (isFinite(n) && n >= 0 && n <= 6 && rest.indexOf(n) < 0) rest.push(n);
    }
  }
  let start = hm(src.start) || DEFAULT_CONFIG.start;
  let end = hm(src.end) || DEFAULT_CONFIG.end;
  if (minutes(start) >= minutes(end)) {
    start = DEFAULT_CONFIG.start;
    end = DEFAULT_CONFIG.end;
  }
  const startM = minutes(start);
  const endM = minutes(end);
  let bs = hm(src.breakStart);
  let be = hm(src.breakEnd);
  if (
    !bs ||
    !be ||
    minutes(bs) >= minutes(be) ||
    minutes(bs) < startM ||
    minutes(be) > endM
  ) {
    bs = "";
    be = "";
  }
  return { rest: rest, start: start, end: end, breakStart: bs, breakEnd: be };
}

function readCache() {
  try {
    const v = wx.getStorageSync(CACHE_KEY);
    if (!v) return null;
    if (typeof v === "string") {
      try {
        return JSON.parse(v);
      } catch (e) {
        return null;
      }
    }
    if (typeof v === "object") return v;
  } catch (e) {
    return null;
  }
  return null;
}

function writeCache(config) {
  try {
    wx.setStorageSync(CACHE_KEY, config);
  } catch (e) {
    // 本地缓存失败不影响页面使用。
  }
}

function dayInfo(date, config) {
  const key = dateKey(date);
  for (let i = 0; i < HOLIDAYS.length; i += 1) {
    const h = HOLIDAYS[i];
    if (key >= h.start && key <= h.end) {
      return {
        type: "holiday",
        name: h.name,
        idx: dayNo(key) - dayNo(h.start) + 1,
        total: dayNo(h.end) - dayNo(h.start) + 1,
      };
    }
  }
  if (MAKEUP.indexOf(key) >= 0) {
    return { type: "makeup", name: "", idx: 0, total: 0 };
  }
  const rest = config && Array.isArray(config.rest) ? config.rest : DEFAULT_CONFIG.rest;
  if (rest.indexOf(date.getDay()) >= 0) {
    return { type: "rest", name: "", idx: 0, total: 0 };
  }
  return { type: "work", name: "", idx: 0, total: 0 };
}

function nextRestDays(date, config) {
  for (let i = 1; i <= 366; i += 1) {
    const t = dayInfo(addDays(date, i), config).type;
    if (t === "rest" || t === "holiday") return i;
  }
  return 0;
}

function mondayOf(date) {
  const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const off = (d.getDay() + 6) % 7;
  return addDays(d, -off);
}

function durationText(mins) {
  const m = Math.max(0, mins);
  const h = Math.floor(m / 60);
  const mm = m % 60;
  if (h <= 0) return m + " 分钟";
  if (mm === 0) return h + " 小时";
  return h + " 小时 " + mm + " 分";
}

function restLabel(rest) {
  const list = Array.isArray(rest) ? rest : [];
  if (!list.length) return "未设置";
  if (list.length >= 7) return "每天都休息";
  const ordered = REST_ORDER.filter(function (v) {
    return list.indexOf(v) >= 0;
  });
  return ordered
    .map(function (v) {
      return WEEKDAY_LABELS[v];
    })
    .join("、");
}

function editWeekOf(rest) {
  return WEEKDAYS.map(function (w) {
    const on = rest.indexOf(w.value) >= 0;
    return { key: w.key, value: w.value, label: w.label, on: on, cls: weekCls(on) };
  });
}

function weekCls(on) {
  return on ? "wchip wchip-on" : "wchip";
}

Page({
  data: {
    dateText: "",
    syncNote: "",

    chipText: "工作日",
    chipCls: "chip-work",
    statusTitle: "摸鱼日历",
    statusSub: "正在读取作息…",
    configText: "09:00 – 18:00",
    showCountdown: false,
    countdownText: "",

    weekFish: 0,
    weekFishDone: 0,
    monthRest: 0,
    monthRestLeft: 0,

    monthTitle: "",
    weekdays: WEEKDAYS,
    cells: [],
    canNext: false,
    navNextCls: "nav-btn nav-off",
    showTodayBtn: false,
    viewYear: 0,
    viewMonth: 0,

    scheduleText: "",
    restText: "",

    showSettings: false,
    editStart: "09:00",
    editEnd: "18:00",
    editBreakOn: false,
    editBreakStart: "12:00",
    editBreakEnd: "13:00",
    editWeek: editWeekOf(DEFAULT_CONFIG.rest),
    saving: false,
    saveText: "保存",
    saveDisabled: false,
  },

  onLoad() {
    this.destroyed = false;
    this.saving = false;
    this.loadingRemote = false;
    this._timer = null;

    const token = session.token();
    if (!token) {
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    this.token = token;

    const now = new Date();
    this._dayKey = dateKey(now);
    this._today = now;
    this.config = normalizeConfig(readCache());
    this.setData({ viewYear: now.getFullYear(), viewMonth: now.getMonth() });
    this.renderAll(now);
    this.refresh();
  },

  onShow() {
    const token = session.token();
    if (!token) {
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    this.token = token;
    this.startTimer();
    if (this.config) this.tick();
  },

  onHide() {
    this.stopTimer();
  },

  onUnload() {
    this.destroyed = true;
    this.stopTimer();
  },

  onPullDownRefresh() {
    this.refresh();
  },

  startTimer() {
    this.stopTimer();
    this._timer = setInterval(() => {
      this.tick();
    }, 60000);
  },

  stopTimer() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
    }
  },

  tick() {
    if (this.destroyed || !this.config) return;
    const now = new Date();
    const key = dateKey(now);
    if (key !== this._dayKey) {
      const prev = this._today || now;
      const viewingPrevMonth =
        this.data.viewYear === prev.getFullYear() &&
        this.data.viewMonth === prev.getMonth();
      this._dayKey = key;
      if (viewingPrevMonth) {
        this.setData({ viewYear: now.getFullYear(), viewMonth: now.getMonth() });
      }
      this.renderAll(now);
      return;
    }
    this.renderStatus(now);
  },

  refresh() {
    const token = this.token || session.token();
    if (!token) {
      wx.stopPullDownRefresh();
      return Promise.resolve();
    }
    this.token = token;
    if (this.loadingRemote) {
      wx.stopPullDownRefresh();
      return Promise.resolve();
    }
    this.loadingRemote = true;
    return api
      .moyuGet(token)
      .then((res) => {
        if (this.destroyed) return;
        const raw = res && res.config;
        const config = normalizeConfig(raw || null);
        this.config = config;
        writeCache(config);
        this.setData({
          syncNote: raw ? "" : "云端还没有设置，先用默认作息，点右上角设置。",
        });
        this.renderAll(new Date());
      })
      .catch((err) => {
        if (this.destroyed) return;
        const failedLogin = err && err.code === 401;
        this.setData({
          syncNote: failedLogin
            ? "登录已失效，当前按本地设置显示"
            : "云端暂时连不上，当前按本地设置显示",
        });
      })
      .then(() => {
        this.loadingRemote = false;
        if (!this.destroyed) wx.stopPullDownRefresh();
      });
  },

  renderAll(now) {
    const cfg = this.config;
    const breakText =
      cfg.breakStart && cfg.breakEnd
        ? " · 午休 " + cfg.breakStart + " – " + cfg.breakEnd
        : "";
    this.setData({
      configText: cfg.start + " – " + cfg.end,
      scheduleText: cfg.start + " – " + cfg.end + breakText,
      restText: restLabel(cfg.rest),
    });
    this.renderStatus(now);
    this.renderStats(now);
    this.renderCalendar(now);
  },

  renderStatus(now) {
    const cfg = this.config;
    const info = dayInfo(now, cfg);
    const nowMin = now.getHours() * 60 + now.getMinutes();
    const startM = minutes(cfg.start);
    const endM = minutes(cfg.end);
    const hasBreak = !!(cfg.breakStart && cfg.breakEnd);
    const bsM = hasBreak ? minutes(cfg.breakStart) : 0;
    const beM = hasBreak ? minutes(cfg.breakEnd) : 0;
    const isWorkType = info.type === "work" || info.type === "makeup";
    let phase = "off";
    if (isWorkType) {
      if (nowMin < startM) phase = "before";
      else if (nowMin >= endM) phase = "done";
      else if (hasBreak && nowMin >= bsM && nowMin < beM) phase = "break";
      else phase = "working";
    }
    const showCountdown = isWorkType && phase !== "done" && nowMin < endM;
    let title = "";
    let sub = "";
    if (info.type === "holiday") {
      title = info.name + "假期中";
      sub = "第 " + info.idx + " / " + info.total + " 天，安心休息";
    } else if (info.type === "makeup") {
      title = "补班中";
      if (phase === "done") {
        sub = "补班结束，去休息吧";
      } else {
        const n = nextRestDays(now, cfg);
        sub = n ? "距下一个休息日 " + n + " 天" : "再坚持一下";
      }
    } else if (info.type === "rest") {
      title = "今天休息";
      sub = "工作先放一放，慢慢过";
    } else if (phase === "before") {
      title = "还没上班";
      sub = "先给自己倒杯水";
    } else if (phase === "break") {
      title = "午休中";
      sub = "吃好睡好，下午再战";
    } else if (phase === "done") {
      title = "已下班";
      sub = "今天的鱼摸够了";
    } else {
      title = "上班中";
      sub = "忙里偷闲，记得喝水";
    }
    this.setData({
      dateText:
        now.getMonth() + 1 + "月" + now.getDate() + "日 · " + DAY_NAMES[now.getDay()],
      chipText: CHIP_TEXT[info.type] || CHIP_TEXT.work,
      chipCls: "chip-" + (info.type || "work"),
      statusTitle: title,
      statusSub: sub,
      showCountdown: showCountdown,
      countdownText: showCountdown ? durationText(endM - nowMin) : "",
    });
  },

  renderStats(now) {
    const cfg = this.config;
    const todayKey = dateKey(now);
    const monday = mondayOf(now);
    let weekFish = 0;
    let weekFishDone = 0;
    for (let i = 0; i < 7; i += 1) {
      const d = addDays(monday, i);
      const t = dayInfo(d, cfg).type;
      if (t === "rest" || t === "holiday") {
        weekFish += 1;
        if (dateKey(d) <= todayKey) weekFishDone += 1;
      }
    }
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    let monthRest = 0;
    let monthRestLeft = 0;
    for (let d = 1; d <= daysInMonth; d += 1) {
      const date = new Date(now.getFullYear(), now.getMonth(), d);
      const t = dayInfo(date, cfg).type;
      if (t === "rest" || t === "holiday") {
        monthRest += 1;
        if (dateKey(date) > todayKey) monthRestLeft += 1;
      }
    }
    this.setData({
      weekFish: weekFish,
      weekFishDone: weekFishDone,
      monthRest: monthRest,
      monthRestLeft: monthRestLeft,
    });
  },

  renderCalendar(now, y, m) {
    const year = typeof y === "number" ? y : this.data.viewYear;
    const month = typeof m === "number" ? m : this.data.viewMonth;
    const todayKey = dateKey(now);
    const first = new Date(year, month, 1);
    const offset = (first.getDay() + 6) % 7;
    const total = new Date(year, month + 1, 0).getDate();
    const cells = [];
    for (let i = 0; i < offset; i += 1) {
      cells.push({ key: "b-" + i, day: "", tag: "", cls: "cell-in cell-blank" });
    }
    for (let d = 1; d <= total; d += 1) {
      const date = new Date(year, month, d);
      const info = dayInfo(date, this.config);
      let cls = "cell-in cell-" + info.type;
      if (dateKey(date) === todayKey) cls += " cell-today";
      let tag = "";
      if (info.type === "holiday") tag = info.name;
      else if (info.type === "rest") tag = "休";
      else if (info.type === "makeup") tag = "班";
      cells.push({
        key: year + "-" + (month + 1) + "-" + d,
        day: String(d),
        tag: tag,
        cls: cls,
      });
    }
    while (cells.length < 42) {
      cells.push({ key: "p-" + cells.length, day: "", tag: "", cls: "cell-in cell-blank" });
    }
    const nowY = now.getFullYear();
    const nowM = now.getMonth();
    const canNext = year * 12 + month < nowY * 12 + nowM;
    this.setData({
      viewYear: year,
      viewMonth: month,
      monthTitle: year + "年" + (month + 1) + "月",
      cells: cells,
      canNext: canNext,
      navNextCls: canNext ? "nav-btn" : "nav-btn nav-off",
      showTodayBtn: !(year === nowY && month === nowM),
    });
  },

  onPrevMonth() {
    let y = this.data.viewYear;
    let m = this.data.viewMonth - 1;
    if (m < 0) {
      m = 11;
      y -= 1;
    }
    this.renderCalendar(new Date(), y, m);
  },

  onNextMonth() {
    if (!this.data.canNext) return;
    let y = this.data.viewYear;
    let m = this.data.viewMonth + 1;
    if (m > 11) {
      m = 0;
      y += 1;
    }
    this.renderCalendar(new Date(), y, m);
  },

  onToday() {
    const now = new Date();
    this.renderCalendar(now, now.getFullYear(), now.getMonth());
  },

  onOpenSettings() {
    if (!this.config) return;
    this.saving = false;
    this.setData({
      showSettings: true,
      editStart: this.config.start,
      editEnd: this.config.end,
      editBreakOn: !!(this.config.breakStart && this.config.breakEnd),
      editBreakStart: this.config.breakStart || "12:00",
      editBreakEnd: this.config.breakEnd || "13:00",
      editWeek: editWeekOf(this.config.rest),
      saving: false,
      saveText: "保存",
      saveDisabled: false,
    });
  },

  onCloseSettings() {
    if (this.saving) return;
    this.setData({ showSettings: false });
  },

  noop() {},

  onEditStart(e) {
    this.setData({ editStart: e.detail.value });
  },

  onEditEnd(e) {
    this.setData({ editEnd: e.detail.value });
  },

  onEditBreakStart(e) {
    this.setData({ editBreakStart: e.detail.value });
  },

  onEditBreakEnd(e) {
    this.setData({ editBreakEnd: e.detail.value });
  },

  onEditBreakToggle(e) {
    this.setData({ editBreakOn: !!(e.detail && e.detail.value) });
  },

  onToggleWeek(e) {
    const value = Number(e.currentTarget.dataset.value);
    const items = this.data.editWeek.map(function (it) {
      if (it.value !== value) return it;
      const on = !it.on;
      return { key: it.key, value: it.value, label: it.label, on: on, cls: weekCls(on) };
    });
    this.setData({ editWeek: items });
  },

  onSave() {
    if (this.saving) return;
    const token = session.token();
    if (!token) {
      toast("登录已失效，请重新登录");
      return;
    }
    const start = this.data.editStart;
    const end = this.data.editEnd;
    if (minutes(end) <= minutes(start)) {
      toast("下班时间要晚于上班时间");
      return;
    }
    let breakStart = null;
    let breakEnd = null;
    if (this.data.editBreakOn) {
      const bs = this.data.editBreakStart;
      const be = this.data.editBreakEnd;
      if (minutes(be) <= minutes(bs)) {
        toast("午休开始要早于结束");
        return;
      }
      if (minutes(bs) < minutes(start) || minutes(be) > minutes(end)) {
        toast("午休要放在上班时间内");
        return;
      }
      breakStart = bs;
      breakEnd = be;
    }
    const rest = this.data.editWeek
      .filter(function (it) {
        return it.on;
      })
      .map(function (it) {
        return it.value;
      });
    const payload = {
      rest: rest,
      start: start,
      end: end,
      breakStart: breakStart,
      breakEnd: breakEnd,
    };
    this.token = token;
    this.saving = true;
    this.setData({ saving: true, saveText: "保存中…", saveDisabled: true });
    api
      .moyuSave(token, payload)
      .then((res) => {
        if (this.destroyed) return;
        this.saving = false;
        const saved = normalizeConfig(res && res.config ? res.config : payload);
        this.config = saved;
        writeCache(saved);
        this.setData({
          showSettings: false,
          saving: false,
          saveText: "保存",
          saveDisabled: false,
          syncNote: "",
        });
        this.renderAll(new Date());
        wx.showToast({ title: "已保存", icon: "success" });
      })
      .catch((err) => {
        if (this.destroyed) return;
        this.saving = false;
        this.setData({ saving: false, saveText: "保存", saveDisabled: false });
        toast(
          err && err.code === 401
            ? "登录已失效，修改已保留"
            : "保存失败，修改已保留"
        );
      });
  },
});