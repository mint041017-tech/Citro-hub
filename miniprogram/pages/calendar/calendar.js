// 日历页 · 小程序端
// 对应 flutter/lib/calendar/calendar_page.dart：
// 月视图（周一开头、42 格）+ 未来 60 天的「即将到来」+ 全部标记。
// 数据来自 utils/calendar-store.js；农历 / 节气 / 节日来自 utils/lunar.js。
// 新增 / 编辑用页内浮层，删除走确认框；保存后本地立即生效，云端同步静默进行。
const session = require("../../utils/session");
const store = require("../../utils/calendar-store");
const lunar = require("../../utils/lunar");

const WEEK_NAMES = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];
const WEEK_SHORT = ["一", "二", "三", "四", "五", "六", "日"];
const UPCOMING_DAYS = 60;
const MAX_UPCOMING = 8;

/* ---------------- 日期工具（全部用本地年月日） ---------------- */

function pad2(n) {
  return n < 10 ? "0" + n : String(n);
}

function parseKey(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || "").trim());
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

function ymdOf(p) {
  return p.y + "-" + pad2(p.m) + "-" + pad2(p.d);
}

function todayParts() {
  const now = new Date();
  return { y: now.getFullYear(), m: now.getMonth() + 1, d: now.getDate() };
}

function weekdayIndex(p) {
  return (new Date(p.y, p.m - 1, p.d).getDay() + 6) % 7;
}

function fullDateText(value) {
  const p = parseKey(value);
  if (!p) return "";
  return (
    p.y + "年" + p.m + "月" + p.d + "日 " + WEEK_NAMES[weekdayIndex(p)]
  );
}

function shortDateText(p) {
  return p.m + "月" + p.d + "日 " + WEEK_NAMES[weekdayIndex(p)];
}

/* ---------------- 月视图 ---------------- */

// 周一开头，固定 42 格；上一月 / 下一月的格子仍可点击，点了就翻到那个月。
function buildCells(year, month, marks, todayKey, selectedKey) {
  const first = new Date(year, month, 1);
  const lead = (first.getDay() + 6) % 7;
  const cells = [];
  for (let i = 0; i < 42; i++) {
    const date = new Date(year, month, 1 - lead + i);
    const key =
      date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate());
    const dim = date.getMonth() !== month;
    const isToday = key === todayKey;
    const isSelected = key === selectedKey;

    let hasCountdown = false;
    let hasAnniversary = false;
    for (let j = 0; j < marks.length; j++) {
      if (!store.hits(marks[j], date)) continue;
      if (marks[j].kind === "anniversary") hasAnniversary = true;
      else hasCountdown = true;
    }

    let className = "cal-cell";
    if (dim) className += " dim";
    if (isToday) className += " today";
    if (isSelected) className += " sel";

    cells.push({
      key: key,
      day: date.getDate(),
      dim: dim,
      isToday: isToday,
      className: className,
      hasCountdown: hasCountdown,
      hasAnniversary: hasAnniversary,
    });
  }
  return cells;
}

/* ---------------- 列表展示 ---------------- */

function upcomingViewOf(item) {
  const p = parseKey(item.occurDate);
  const dateText = p
    ? p.y + "年" + p.m + "月" + p.d + "日"
    : "";
  return {
    key: item.id,
    id: item.id,
    title: item.title,
    dayText: p ? String(p.d) : "",
    monthText: p ? p.m + "月" : "",
    metaText: dateText + (item.yearly ? " · 每年" : ""),
    kindLabel: item.kind === "anniversary" ? "纪念日" : "倒数日",
    kindClass: item.kind === "anniversary" ? "up-tag tag-anniv" : "up-tag",
    label: item.label,
    labelClass:
      item.kind === "anniversary" ? "up-label label-anniv" : "up-label",
  };
}

function markViewOf(item, today) {
  const p = parseKey(item.date);
  let yearText = "";
  if (item.kind === "anniversary" && item.yearly && p) {
    const years = today.y - p.y;
    if (years > 0) yearText = "第 " + (years + 1) + " 年";
  }
  const dateText = p
    ? p.y + "年" + p.m + "月" + p.d + "日"
    : item.date;
  return {
    key: item.id,
    id: item.id,
    title: item.title,
    kindLabel: item.kind === "anniversary" ? "纪念日" : "倒数日",
    dotClass: item.kind === "anniversary" ? "dot-anniv" : "dot-countdown",
    metaText: dateText + (item.yearly ? " · 每年" : ""),
    note: item.note || "",
    yearText: yearText,
    label: item.label,
    labelClass:
      item.kind === "anniversary" ? "mark-label label-anniv" : "mark-label",
  };
}

// 与 Flutter CalendarStore.sorted 一致：先倒数日再纪念日，
// 同类按天数绝对值由近到远，最后按标题。
function sortedMarkViews(marks, today) {
  const infos = marks.map(function (mark) {
    return store.describe(mark, today);
  });
  infos.sort(function (a, b) {
    const ka = a.kind === "anniversary" ? 1 : 0;
    const kb = b.kind === "anniversary" ? 1 : 0;
    if (ka !== kb) return ka - kb;
    const da = Math.abs(a.days);
    const db = Math.abs(b.days);
    if (da !== db) return da - db;
    if (a.title < b.title) return -1;
    if (a.title > b.title) return 1;
    return 0;
  });
  return infos.map(function (info) {
    return markViewOf(info, today);
  });
}

/* ---------------- 页面 ---------------- */

Page({
  data: {
    ready: false,
    monthLabel: "",
    isCurrentMonth: true,
    showBackToday: false,
    weekdays: WEEK_SHORT,
    cells: [],

    selectedDateText: "",
    selectedIsToday: false,
    selectedInfoText: "",
    selectedMarks: [],
    hasSelectedMarks: false,

    upcoming: [],
    hasUpcoming: false,
    upcomingEmpty: false,

    marks: [],
    hasMarks: false,
    countText: "",

    // 新增 / 编辑浮层
    sheetOpen: false,
    sheetEditing: false,
    sheetTitle: "新增标记",
    formTitle: "",
    formKind: "countdown",
    formDate: "",
    formDateText: "",
    formYearly: false,
    formNote: "",
    countdownTabClass: "kind-tab on",
    annivTabClass: "kind-tab",
  },

  onLoad() {
    this.destroyed = false;
    this.leaving = false;
    this.saving = false;
    this.syncing = false;
    this.seq = 0;
    this.editingId = "";

    // 子页面沿用计划页的登录门禁：没有 token 直接回首页。
    if (!session.token()) {
      this.leaving = true;
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }

    const today = todayParts();
    this.cursor = { year: today.y, month: today.m - 1 };
    this.selectedKey = ymdOf(today);
    this.snap = store.load();
    this.refreshView();
    this.pullRemote(false);
  },

  onShow() {
    if (this.leaving || this.destroyed) return;
    if (!session.token()) {
      this.leaving = true;
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    if (!this.snap) return;
    // 回到页面时重读本地，兼容其它入口 / 账号同步后的修改。
    this.snap = store.load();
    this.refreshView();
    this.pullRemote(false);
  },

  onUnload() {
    this.destroyed = true;
  },

  onPullDownRefresh() {
    if (!session.token()) {
      wx.stopPullDownRefresh();
      this.leaving = true;
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    const self = this;
    this.pullRemote(true).then(function () {
      wx.stopPullDownRefresh();
    });
  },

  pullRemote(showToast) {
    if (this.syncing || !session.token()) return Promise.resolve();
    this.syncing = true;
    const self = this;
    return store
      .sync(session.token())
      .then(function (snap) {
        self.syncing = false;
        // 页面销毁或离线时 sync 也会返回本地快照，照常渲染即可。
        if (self.destroyed) return;
        self.snap = snap;
        self.refreshView();
        if (showToast) {
          wx.showToast({ title: "已刷新", icon: "none" });
        }
      })
      .catch(function () {
        self.syncing = false;
        if (showToast) {
          wx.showToast({ title: "暂时连不上云端，已用本地数据", icon: "none" });
        }
      });
  },

  /* ---------------- 视图刷新 ---------------- */

  refreshView() {
    if (this.destroyed) return;
    const today = todayParts();
    const todayKey = ymdOf(today);
    if (!this.cursor) this.cursor = { year: today.y, month: today.m - 1 };
    if (!this.selectedKey) this.selectedKey = todayKey;
    const selectedKey = this.selectedKey;

    const marks =
      this.snap && Array.isArray(this.snap.marks) ? this.snap.marks : [];
    const cursor = this.cursor;
    const cells = buildCells(
      cursor.year,
      cursor.month,
      marks,
      todayKey,
      selectedKey
    );

    // 选中日的小条：农历 / 节气 / 节日 + 当天命中的标记。
    const selectedParts = parseKey(selectedKey) || today;
    const info = lunar.todayInfo(
      new Date(selectedParts.y, selectedParts.m - 1, selectedParts.d)
    );
    const selectedMarks = marks
      .filter(function (mark) {
        return store.hits(mark, selectedKey);
      })
      .map(function (mark) {
        return { key: mark.id, title: mark.title };
      });

    const upcoming = store
      .upcoming(today, UPCOMING_DAYS)
      .slice(0, MAX_UPCOMING)
      .map(upcomingViewOf);

    const markViews = sortedMarkViews(marks, today);
    const hasMarks = marks.length > 0;

    this.setData({
      ready: true,
      monthLabel: cursor.year + "年" + (cursor.month + 1) + "月",
      isCurrentMonth:
        cursor.year === today.y && cursor.month === today.m - 1,
      showBackToday:
        cursor.year !== today.y || cursor.month !== today.m - 1,
      cells: cells,

      selectedDateText: shortDateText(selectedParts),
      selectedIsToday: selectedKey === todayKey,
      selectedInfoText: info.label,
      selectedMarks: selectedMarks,
      hasSelectedMarks: selectedMarks.length > 0,

      upcoming: upcoming,
      hasUpcoming: upcoming.length > 0,
      upcomingEmpty: hasMarks && upcoming.length === 0,

      marks: markViews,
      hasMarks: hasMarks,
      countText: marks.length + " 个标记",
    });
  },

  /* ---------------- 月切换 ---------------- */

  onPrevMonth() {
    const date = new Date(this.cursor.year, this.cursor.month - 1, 1);
    if (date.getFullYear() < 1900) return;
    this.cursor = { year: date.getFullYear(), month: date.getMonth() };
    this.refreshView();
  },

  onNextMonth() {
    const date = new Date(this.cursor.year, this.cursor.month + 1, 1);
    if (date.getFullYear() > 2100) return;
    this.cursor = { year: date.getFullYear(), month: date.getMonth() };
    this.refreshView();
  },

  onBackToday() {
    const today = todayParts();
    this.cursor = { year: today.y, month: today.m - 1 };
    this.selectedKey = ymdOf(today);
    this.refreshView();
  },

  onCellTap(e) {
    const index = Number(e.currentTarget.dataset.index);
    const cell = this.data.cells[index];
    if (!cell) return;
    const parts = parseKey(cell.key);
    if (!parts) return;
    // 点到上 / 下月的灰格子时，视图跟着翻过去。
    if (cell.dim) {
      this.cursor = { year: parts.y, month: parts.m - 1 };
    }
    this.selectedKey = cell.key;
    this.refreshView();
  },

  /* ---------------- 新增 / 编辑浮层 ---------------- */

  onAdd() {
    const fallback = todayParts();
    const cursor = this.cursor || { year: fallback.y, month: fallback.m - 1 };
    let baseKey = this.selectedKey || ymdOf(fallback);
    const selected = parseKey(baseKey);
    // 翻月后选中日可能已经不在当前网格里，新增默认落在可见月份。
    if (
      !selected ||
      selected.y !== cursor.year ||
      selected.m !== cursor.month + 1
    ) {
      baseKey = ymdOf({
        y: cursor.year,
        m: cursor.month + 1,
        d: 1,
      });
    }
    this.editingId = "";
    this.setData({
      sheetOpen: true,
      sheetEditing: false,
      sheetTitle: "新增标记",
      formTitle: "",
      formKind: "countdown",
      formDate: baseKey,
      formDateText: fullDateText(baseKey),
      formYearly: false,
      formNote: "",
      countdownTabClass: "kind-tab on",
      annivTabClass: "kind-tab",
    });
  },

  onEditMark(e) {
    const id = e.currentTarget.dataset.id;
    if (!id) return;
    const marks =
      this.snap && Array.isArray(this.snap.marks) ? this.snap.marks : [];
    let mark = null;
    for (let i = 0; i < marks.length; i++) {
      if (marks[i].id === id) {
        mark = marks[i];
        break;
      }
    }
    if (!mark) return;

    const anniversary = mark.kind === "anniversary";
    this.editingId = id;
    this.setData({
      sheetOpen: true,
      sheetEditing: true,
      sheetTitle: "编辑标记",
      formTitle: mark.title,
      formKind: anniversary ? "anniversary" : "countdown",
      formDate: mark.date,
      formDateText: fullDateText(mark.date),
      formYearly: mark.yearly === true,
      formNote: mark.note || "",
      countdownTabClass: anniversary ? "kind-tab" : "kind-tab on",
      annivTabClass: anniversary ? "kind-tab on" : "kind-tab",
    });
  },

  onCloseSheet() {
    this.editingId = "";
    this.setData({ sheetOpen: false });
  },

  onTitleInput(e) {
    this.setData({ formTitle: (e.detail && e.detail.value) || "" });
  },

  onKindTap(e) {
    const anniversary = e.currentTarget.dataset.kind === "anniversary";
    this.setData({
      formKind: anniversary ? "anniversary" : "countdown",
      countdownTabClass: anniversary ? "kind-tab" : "kind-tab on",
      annivTabClass: anniversary ? "kind-tab on" : "kind-tab",
    });
  },

  onDateChange(e) {
    const value = (e.detail && e.detail.value) || "";
    if (!parseKey(value)) return;
    this.setData({
      formDate: value,
      formDateText: fullDateText(value),
    });
  },

  onYearlyChange(e) {
    this.setData({
      formYearly: !!(e.detail && e.detail.value),
    });
  },

  onNoteInput(e) {
    this.setData({ formNote: (e.detail && e.detail.value) || "" });
  },

  onSaveMark() {
    if (this.saving) return;
    const title = String(this.data.formTitle || "").trim().slice(0, 20);
    if (!title) {
      wx.showToast({ title: "请填写标题", icon: "none" });
      return;
    }
    const date = this.data.formDate;
    if (!parseKey(date)) {
      wx.showToast({ title: "请选择日期", icon: "none" });
      return;
    }
    const note = String(this.data.formNote || "").slice(0, 40);
    const kind =
      this.data.formKind === "anniversary" ? "anniversary" : "countdown";
    const yearly = !!this.data.formYearly;
    const editing = this.editingId;

    const marks =
      this.snap && Array.isArray(this.snap.marks)
        ? this.snap.marks.slice()
        : [];
    let found = -1;
    for (let i = 0; i < marks.length; i++) {
      if (marks[i].id === editing) {
        found = i;
        break;
      }
    }
    if (editing && found < 0) {
      this.onCloseSheet();
      this.refreshView();
      return;
    }
    if (found >= 0) {
      // 保留 id / createdAt 与其它端写入的未知字段。
      marks[found] = Object.assign({}, marks[found], {
        title: title,
        date: date,
        kind: kind,
        yearly: yearly,
        note: note,
      });
    } else {
      const now = Date.now();
      marks.push({
        id: "cal-" + now + "-" + this.seq++,
        title: title,
        date: date,
        kind: kind,
        yearly: yearly,
        note: note,
        createdAt: now,
      });
    }

    const snap = Object.assign({}, this.snap || store.load(), {
      marks: marks,
    });
    this.saving = true;
    try {
      this.snap = store.save(snap);
    } catch (e) {
      this.saving = false;
      wx.showToast({ title: "保存失败，请稍后再试", icon: "none" });
      return;
    }
    this.saving = false;
    this.editingId = "";
    this.setData({ sheetOpen: false });
    this.refreshView();
    wx.showToast({
      title: editing ? "已保存" : "已添加到日历",
      icon: "none",
    });
    this.pushAfterChange();
  },

  onSheetDelete() {
    if (!this.editingId) return;
    const id = this.editingId;
    const marks =
      this.snap && Array.isArray(this.snap.marks) ? this.snap.marks : [];
    let title = "";
    for (let i = 0; i < marks.length; i++) {
      if (marks[i].id === id) {
        title = marks[i].title;
        break;
      }
    }
    const self = this;
    wx.showModal({
      title: "删除标记",
      content: title ? "删除「" + title + "」？" : "删除这个标记？",
      confirmText: "删除",
      confirmColor: "#B05A4A",
      success(res) {
        if (res.confirm) self.removeMark(id);
      },
    });
  },

  removeMark(id) {
    if (!id) return;
    const marks =
      this.snap && Array.isArray(this.snap.marks)
        ? this.snap.marks.slice()
        : [];
    const next = marks.filter(function (mark) {
      return mark.id !== id;
    });
    if (next.length === marks.length) return;
    const snap = Object.assign({}, this.snap || store.load(), {
      marks: next,
    });
    this.snap = store.save(snap);
    if (this.editingId === id) {
      this.editingId = "";
      this.setData({ sheetOpen: false });
    }
    this.refreshView();
    wx.showToast({ title: "已删除", icon: "none" });
    this.pushAfterChange();
  },

  // 保存 / 删除后触发一次云端校验；失败在 store 内静默。
  pushAfterChange() {
    if (!session.token()) return;
    const self = this;
    store.sync(session.token()).then(function (snap) {
      if (self.destroyed) return;
      self.snap = snap;
      self.refreshView();
    });
  },

  noop() {},
});