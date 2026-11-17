// 记账页 · 小程序端
// 对应 flutter/lib/ledger/ledger_page.dart、ledger_home_tab.dart 与 ledger_add_tab.dart。
// 数据全部来自 utils/ledger-store.js，页面只做展示与交互，金额始终按分计算。
const session = require("../../utils/session");
const store = require("../../utils/ledger-store");

const PRESET_COLORS = [
  { argb: 0xffc08a4a, hex: "#C08A4A" },
  { argb: 0xff6f8ca8, hex: "#6F8CA8" },
  { argb: 0xffb5717a, hex: "#B5717A" },
  { argb: 0xff6e9a78, hex: "#6E9A78" },
  { argb: 0xff9a8fa6, hex: "#9A8FA6" },
  { argb: 0xffc4855d, hex: "#C4855D" },
  { argb: 0xff8fa6be, hex: "#8FA6BE" },
  { argb: 0xff8a7f6a, hex: "#8A7F6A" },
];

const WEEK_FULL = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];

function pad2(n) {
  return n < 10 ? "0" + n : String(n);
}

function dateValueOf(ms) {
  const d = new Date(ms);
  return (
    d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
  );
}

function dateTextOf(ms) {
  const d = new Date(ms);
  return (
    d.getFullYear() +
    "年" +
    (d.getMonth() + 1) +
    "月" +
    d.getDate() +
    "日 " +
    WEEK_FULL[d.getDay()]
  );
}

// "YYYY-MM-DD" -> 当天中午 12 点的时间戳，避免时区边界把账单挪到前一天。
function dateValueToMs(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || ""));
  if (!match) return 0;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(year, month - 1, day, 12, 0, 0);
  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    return 0;
  }
  return date.getTime();
}

function colorHex(argb) {
  const value = Number(argb);
  const n = isFinite(value) ? value : 0xff8a7f6a;
  return "#" + ((n >>> 0) & 0xffffff).toString(16).toUpperCase().padStart(6, "0");
}

function initialOf(name) {
  const text = String(name || "");
  return text ? text.slice(0, 1) : "·";
}

function groupTitleOf(ms) {
  const now = new Date();
  const todayKey = store.dayKeyOf(now.getTime());
  const yesterday = new Date(
    now.getFullYear(),
    now.getMonth(),
    now.getDate() - 1
  );
  const key = store.dayKeyOf(ms);
  if (key === todayKey) return "今天";
  if (key === store.dayKeyOf(yesterday.getTime())) return "昨天";
  const d = new Date(ms);
  if (d.getFullYear() === now.getFullYear()) {
    return d.getMonth() + 1 + "月" + d.getDate() + "日";
  }
  return d.getFullYear() + "年" + (d.getMonth() + 1) + "月" + d.getDate() + "日";
}

Page({
  data: {
    ready: false,
    monthKey: "",
    monthLabel: "",
    isCurrentMonth: true,
    canNext: false,

    expenseLabel: "本月支出",
    overviewExpenseText: "¥0",
    overviewIncomeText: "¥0",
    overviewBalanceText: "¥0",
    overviewBalanceClass: "ov-stat-value income",

    hasBudget: false,
    budgetLabel: "本月预算",
    budgetText: "",
    budgetPercentText: "",
    budgetInviteText: "还没有设置本月预算，先定个小目标",
    budgetPanelTitle: "设置本月预算",
    budgetBarWidth: "0%",
    budgetBarClass: "progress-bar",
    budgetHint: "",

    chartBars: [],
    chartEmpty: true,
    chartMaxText: "",

    groups: [],
    monthEmpty: false,
    emptyTitle: "",
    monthCountText: "",

    // 记一笔 / 编辑弹层
    sheetOpen: false,
    sheetEditing: false,
    sheetTitle: "记一笔",
    sheetSaveText: "保存",
    sheetKind: "expense",
    amountText: "",
    sheetCategories: [],
    sheetCategoryId: "",
    sheetDate: "",
    sheetDateText: "",
    sheetNote: "",
    customOpen: false,
    customName: "",
    customColor: PRESET_COLORS[0].argb,
    presetColors: [],

    // 预算弹层
    budgetOpen: false,
    budgetInput: "",
    incomeInput: "",
    budgetError: "",
  },

  onLoad() {
    this.destroyed = false;
    this.saving = false;
    this.seq = 0;
    this.editingId = "";
    this.monthKey = store.currentMonthKey();
    this.snap = null;
    this.presetColors = this.presetColorData(0);

    // 共同约束：未登录不进入记账页。
    if (!session.token()) {
      this.leaving = true;
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }

    this.snap = store.load();
    this.refreshView();
  },

  onShow() {
    if (this.leaving) return;
    if (!this.snap) return;
    if (!session.token()) {
      this.leaving = true;
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    // 每次回到页面都重新读本地，兼容其它页面/账号同步后的修改。
    this.snap = store.load();
    this.refreshView();
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
    store
      .sync(session.token())
      .then(function (snap) {
        if (self.destroyed) return;
        self.snap = snap;
        self.refreshView();
        wx.stopPullDownRefresh();
        wx.showToast({ title: "已刷新", icon: "none" });
      })
      .catch(function () {
        wx.stopPullDownRefresh();
      });
  },

  /* ---------------- 视图刷新 ---------------- */

  refreshView() {
    if (!this.snap) this.snap = store.load();
    const snap = this.snap;
    const key = this.monthKey;
    const sum = store.summary(snap, key);
    const currentKey = store.currentMonthKey();
    const isCurrent = key === currentKey;

    // 概览
    const hasBudget = sum.budget > 0;
    let budgetPercentText = "";
    let budgetBarWidth = "0%";
    let budgetHint = "";
    if (hasBudget) {
      budgetPercentText = "已用 " + sum.percent + "%";
      budgetBarWidth = Math.max(0, Math.min(100, sum.percent)) + "%";
      const remain = sum.budget - sum.expense;
      budgetHint =
        remain >= 0
          ? "剩余 " + store.fmtMoney(remain)
          : "超出 " + store.fmtMoney(-remain);
    }
    const over = hasBudget && sum.expense > sum.budget;

    // 近 7 日柱状图：最大值为柱高基准，纯 CSS 高度渲染。
    let maxDay = 0;
    sum.days.forEach(function (day) {
      if (day.value > maxDay) maxDay = day.value;
    });
    const bars = sum.days.map(function (day, index) {
      let height = 6;
      if (maxDay > 0 && day.value > 0) {
        height = Math.max(12, Math.round((day.value / maxDay) * 150));
      }
      const active = index === sum.days.length - 1;
      return {
        key: "bar-" + index,
        label: day.label,
        barStyle: "height:" + height + "rpx",
        barClass:
          "chart-bar" + (active ? " on" : "") + (day.value <= 0 ? " zero" : ""),
        labelClass: "chart-label" + (active ? " on" : ""),
      };
    });

    // 当月流水按日期分组
    const entries = Array.isArray(snap.entries) ? snap.entries : [];
    const categories = Array.isArray(snap.categories) ? snap.categories : [];
    const catMap = {};
    categories.forEach(function (category) {
      catMap[category.id] = category;
    });
    const fallbackExpense =
      catMap.other_expense || { name: "其他", color: 0xff8a7f6a };
    const fallbackIncome =
      catMap.other_income || { name: "其他", color: 0xff8a7f6a };

    const monthEntries = entries.filter(function (entry) {
      return store.monthKeyOf(entry.occurredAt) === key;
    });
    const groups = [];
    const byDay = {};
    monthEntries.forEach(function (entry) {
      const dayKey = store.dayKeyOf(entry.occurredAt);
      let group = byDay[dayKey];
      if (!group) {
        group = {
          key: dayKey,
          title: groupTitleOf(entry.occurredAt),
          expense: 0,
          income: 0,
          expenseText: "",
          incomeText: "",
          items: [],
        };
        byDay[dayKey] = group;
        groups.push(group);
      }
      const income = entry.kind === "income";
      if (income) group.income += entry.amount;
      else group.expense += entry.amount;
      const category =
        catMap[entry.category] || (income ? fallbackIncome : fallbackExpense);
      group.items.push({
        key: entry.id,
        id: entry.id,
        name: category.name || "其他",
        note: entry.note || "",
        dotStyle: "background:" + colorHex(category.color),
        amountText:
          (income ? "+" : "-") + store.fmtMoney(entry.amount),
        amountClass: "entry-amount " + (income ? "income" : "expense"),
      });
    });
    groups.forEach(function (group) {
      group.expenseText =
        group.expense > 0 ? "支出 " + store.fmtMoney(group.expense) : "";
      group.incomeText =
        group.income > 0 ? "收入 " + store.fmtMoney(group.income) : "";
    });

    const monthEmpty = monthEntries.length === 0;

    this.setData({
      ready: true,
      monthKey: key,
      monthLabel: sum.label,
      isCurrentMonth: isCurrent,
      canNext: key < currentKey,

      expenseLabel: isCurrent ? "本月支出" : "当月支出",
      overviewExpenseText: store.fmtMoney(sum.expense),
      overviewIncomeText: store.fmtMoney(sum.income),
      overviewBalanceText: store.fmtMoney(sum.balance),
      overviewBalanceClass:
        "ov-stat-value " + (sum.balance < 0 ? "danger" : "income"),

      hasBudget: hasBudget,
      budgetLabel: isCurrent ? "本月预算" : "当月预算",
      budgetText: hasBudget ? store.fmtMoney(sum.budget) : "",
      budgetPercentText: budgetPercentText,
      budgetInviteText: isCurrent
        ? "还没有设置本月预算，先定个小目标"
        : "这个月还没有设置预算，先定个小目标",
      budgetPanelTitle: isCurrent ? "设置本月预算" : "设置当月预算",
      budgetBarWidth: budgetBarWidth,
      budgetBarClass: "progress-bar" + (over ? " over" : ""),
      budgetHint: budgetHint,

      chartBars: bars,
      chartEmpty: maxDay <= 0,
      chartMaxText: maxDay > 0 ? "最高 " + store.fmtMoney(maxDay) : "",

      groups: groups,
      monthEmpty: monthEmpty,
      emptyTitle: isCurrent ? "本月还没有账单" : "这个月还没有账单",
      monthCountText: "共 " + monthEntries.length + " 笔",
    });
  },

  /* ---------------- 月份切换 ---------------- */

  onPrevMonth() {
    this.monthKey = store.shiftMonth(this.monthKey, -1);
    this.refreshView();
  },

  onNextMonth() {
    if (!this.data.canNext) return;
    this.monthKey = store.shiftMonth(this.monthKey, 1);
    this.refreshView();
  },

  onBackToCurrent() {
    if (this.data.isCurrentMonth) return;
    this.monthKey = store.currentMonthKey();
    this.refreshView();
  },

  /* ---------------- 记一笔弹层 ---------------- */

  presetColorData(selectedIndex) {
    return PRESET_COLORS.map(function (item, index) {
      return {
        key: "swatch-" + index,
        argb: item.argb,
        style: "background:" + item.hex,
        swatchClass: "swatch" + (index === selectedIndex ? " on" : ""),
      };
    });
  },

  sheetCategoriesFor(kind, selectedId) {
    const categories = this.snap && Array.isArray(this.snap.categories)
      ? this.snap.categories
      : [];
    return categories
      .filter(function (category) {
        return (
          category &&
          category.kind === kind &&
          (category.active || category.id === selectedId)
        );
      })
      .map(function (category) {
        return {
          key: category.id,
          id: category.id,
          name: category.name,
          initial: initialOf(category.name),
          dotStyle: "background:" + colorHex(category.color),
          itemClass: "cat-item" + (category.id === selectedId ? " on" : ""),
        };
      });
  },

  onOpenSheet() {
    const kind = "expense";
    const categories = this.sheetCategoriesFor(kind, "");
    const firstId = categories.length ? categories[0].id : "";
    const now = Date.now();
    this.editingId = "";
    this.setData({
      sheetOpen: true,
      sheetEditing: false,
      sheetTitle: "记一笔",
      sheetSaveText: "保存",
      sheetKind: kind,
      amountText: "",
      sheetCategories: categories,
      sheetCategoryId: firstId,
      sheetDate: dateValueOf(now),
      sheetDateText: dateTextOf(now),
      sheetNote: "",
      customOpen: false,
      customName: "",
      customColor: PRESET_COLORS[0].argb,
      presetColors: this.presetColors,
    });
  },

  onEditEntry(e) {
    const id = e.currentTarget.dataset.id;
    if (!id) return;
    const entries = this.snap && Array.isArray(this.snap.entries)
      ? this.snap.entries
      : [];
    let entry = null;
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].id === id) {
        entry = entries[i];
        break;
      }
    }
    if (!entry) return;

    const kind = entry.kind === "income" ? "income" : "expense";
    const categories = this.sheetCategoriesFor(kind, entry.category);
    let categoryId = entry.category;
    if (!this.hasCategory(categories, categoryId)) {
      categoryId = categories.length ? categories[0].id : "";
    }
    this.editingId = id;
    this.setData({
      sheetOpen: true,
      sheetEditing: true,
      sheetTitle: "编辑账单",
      sheetSaveText: "保存修改",
      sheetKind: kind,
      amountText: store.yuanText(entry.amount),
      sheetCategories: this.sheetCategoriesFor(kind, categoryId),
      sheetCategoryId: categoryId,
      sheetDate: dateValueOf(entry.occurredAt),
      sheetDateText: dateTextOf(entry.occurredAt),
      sheetNote: entry.note || "",
      customOpen: false,
      customName: "",
      customColor: PRESET_COLORS[0].argb,
      presetColors: this.presetColors,
    });
  },

  hasCategory(list, id) {
    if (!id) return false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) return true;
    }
    return false;
  },

  onCloseSheet() {
    this.editingId = "";
    this.setData({
      sheetOpen: false,
      customOpen: false,
      customName: "",
    });
  },

  onKindTap(e) {
    const raw = e.currentTarget.dataset.kind;
    const kind = raw === "income" ? "income" : "expense";
    if (kind === this.data.sheetKind) return;
    const categories = this.sheetCategoriesFor(kind, "");
    const firstId = categories.length ? categories[0].id : "";
    this.setData({
      sheetKind: kind,
      sheetCategoryId: firstId,
      sheetCategories: categories,
    });
  },

  onAmountInput(e) {
    this.setData({
      amountText: (e.detail && e.detail.value) || "",
    });
  },

  onCategoryTap(e) {
    const id = e.currentTarget.dataset.id;
    if (!id) return;
    this.setData({
      sheetCategoryId: id,
      sheetCategories: this.sheetCategoriesFor(this.data.sheetKind, id),
    });
  },

  onDateChange(e) {
    const value = (e.detail && e.detail.value) || this.data.sheetDate;
    const ms = dateValueToMs(value);
    if (!ms) return;
    this.setData({
      sheetDate: value,
      sheetDateText: dateTextOf(ms),
    });
  },

  onNoteInput(e) {
    this.setData({
      sheetNote: (e.detail && e.detail.value) || "",
    });
  },

  onToggleCustom() {
    const open = !this.data.customOpen;
    this.setData({
      customOpen: open,
      customName: open ? this.data.customName : "",
    });
  },

  onCustomNameInput(e) {
    this.setData({
      customName: (e.detail && e.detail.value) || "",
    });
  },

  onColorTap(e) {
    const index = Number(e.currentTarget.dataset.index);
    if (!(index >= 0 && index < PRESET_COLORS.length)) return;
    this.setData({
      customColor: PRESET_COLORS[index].argb,
      presetColors: this.presetColorData(index),
    });
  },

  onAddCustom() {
    const name = String(this.data.customName || "").trim();
    if (!name) {
      wx.showToast({ title: "请先填写分类名称", icon: "none" });
      return;
    }
    if (name.length > 8) {
      wx.showToast({ title: "分类名称最多 8 个字", icon: "none" });
      return;
    }
    const kind = this.data.sheetKind === "income" ? "income" : "expense";
    const categories = this.snap && Array.isArray(this.snap.categories)
      ? this.snap.categories
      : [];
    const duplicated = categories.some(function (category) {
      return category.kind === kind && category.name === name;
    });
    if (duplicated) {
      wx.showToast({ title: "已有同名分类", icon: "none" });
      return;
    }
    const id = "cat-" + Date.now() + "-" + this.seq++;
    categories.push({
      id: id,
      name: name,
      kind: kind,
      color: this.data.customColor,
      icon: "flag",
      builtIn: false,
      active: true,
    });
    this.snap.categories = categories;
    store.save(this.snap);
    this.setData({
      sheetCategoryId: id,
      sheetCategories: this.sheetCategoriesFor(kind, id),
      customOpen: false,
      customName: "",
      customColor: PRESET_COLORS[0].argb,
      presetColors: this.presetColors,
    });
    wx.showToast({ title: "已添加分类", icon: "none" });
  },

  onSaveEntry() {
    if (this.saving) return;
    const cents = store.parseAmount(this.data.amountText);
    if (cents === null || cents <= 0) {
      wx.showToast({ title: "请输入正确的金额", icon: "none" });
      return;
    }
    const categoryId = this.data.sheetCategoryId;
    if (!categoryId) {
      wx.showToast({ title: "请选择分类", icon: "none" });
      return;
    }
    const pickedMs = dateValueToMs(this.data.sheetDate);
    if (!pickedMs) {
      wx.showToast({ title: "请选择日期", icon: "none" });
      return;
    }

    const kind = this.data.sheetKind === "income" ? "income" : "expense";
    const note = String(this.data.sheetNote || "").trim().slice(0, 40);
    const wasEditing = !!this.editingId;
    const now = Date.now();
    const entries = this.snap && Array.isArray(this.snap.entries)
      ? this.snap.entries
      : [];

    this.saving = true;
    let occurredAt = pickedMs;
    if (wasEditing) {
      let target = null;
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].id === this.editingId) {
          target = entries[i];
          break;
        }
      }
      if (!target) {
        this.saving = false;
        this.onCloseSheet();
        this.refreshView();
        return;
      }
      // 只改日期时保留原来的时间点；换了日期则用当天中午。
      if (store.dayKeyOf(target.occurredAt) === store.dayKeyOf(pickedMs)) {
        occurredAt = target.occurredAt;
      }
      const updated = Object.assign({}, target, {
        kind: kind,
        amount: cents,
        category: categoryId,
        note: note,
        occurredAt: occurredAt,
      });
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].id === this.editingId) {
          entries[i] = updated;
          break;
        }
      }
    } else {
      if (store.dayKeyOf(pickedMs) === store.dayKeyOf(now)) occurredAt = now;
      entries.push({
        id: (kind === "income" ? "inc-" : "exp-") + now + "-" + this.seq++,
        kind: kind,
        amount: cents,
        category: categoryId,
        note: note,
        occurredAt: occurredAt,
        createdAt: now,
        source: "manual",
      });
    }

    entries.sort(function (a, b) {
      return b.occurredAt - a.occurredAt;
    });
    this.snap.entries = entries;
    store.save(this.snap);
    this.saving = false;
    this.onCloseSheet();
    // 账单落在别的月份时跟过去，避免「保存了却看不见」。
    const entryMonth = store.monthKeyOf(occurredAt);
    if (
      entryMonth &&
      entryMonth !== this.monthKey &&
      entryMonth <= store.currentMonthKey()
    ) {
      this.monthKey = entryMonth;
    }
    this.refreshView();
    wx.showToast({
      title: wasEditing ? "账单已更新" : "已记下",
      icon: "none",
    });
  },

  /* ---------------- 删除 ---------------- */

  onDeleteEntry(e) {
    const id = e.currentTarget.dataset.id;
    this.confirmDelete(id);
  },

  onSheetDelete() {
    if (!this.editingId) return;
    this.confirmDelete(this.editingId);
  },

  confirmDelete(id) {
    if (!id) return;
    const self = this;
    wx.showModal({
      title: "删除账单",
      content: "删除这笔账单？",
      confirmText: "删除",
      confirmColor: "#B05A4A",
      success(res) {
        if (!res.confirm) return;
        self.removeEntry(id);
      },
    });
  },

  removeEntry(id) {
    const entries = this.snap && Array.isArray(this.snap.entries)
      ? this.snap.entries
      : [];
    const next = entries.filter(function (entry) {
      return entry.id !== id;
    });
    if (next.length === entries.length) return;
    this.snap.entries = next;
    store.save(this.snap);
    if (this.editingId === id) this.onCloseSheet();
    this.refreshView();
    wx.showToast({ title: "已删除", icon: "none" });
  },

  /* ---------------- 预算弹层 ---------------- */

  onSetBudget() {
    const plans =
      this.snap && this.snap.plans && typeof this.snap.plans === "object"
        ? this.snap.plans
        : {};
    const plan =
      plans[this.monthKey] && typeof plans[this.monthKey] === "object"
        ? plans[this.monthKey]
        : {};
    this.setData({
      budgetOpen: true,
      budgetInput: plan.budget > 0 ? store.yuanText(plan.budget) : "",
      incomeInput: plan.income > 0 ? store.yuanText(plan.income) : "",
      budgetError: "",
    });
  },

  onCloseBudget() {
    this.setData({ budgetOpen: false, budgetError: "" });
  },

  onBudgetInput(e) {
    const field =
      e.currentTarget.dataset.field === "income"
        ? "incomeInput"
        : "budgetInput";
    const patch = { budgetError: "" };
    patch[field] = (e.detail && e.detail.value) || "";
    this.setData(patch);
  },

  onSaveBudget() {
    const budgetRaw = String(this.data.budgetInput || "").trim();
    const incomeRaw = String(this.data.incomeInput || "").trim();
    let budget = 0;
    let income = 0;
    if (budgetRaw) {
      budget = store.parseAmount(budgetRaw);
      if (budget === null) {
        this.setData({ budgetError: "预算金额格式不对，最多两位小数" });
        return;
      }
    }
    if (incomeRaw) {
      income = store.parseAmount(incomeRaw);
      if (income === null) {
        this.setData({ budgetError: "收入目标格式不对，最多两位小数" });
        return;
      }
    }

    const plans =
      this.snap.plans && typeof this.snap.plans === "object"
        ? this.snap.plans
        : {};
    const previous =
      plans[this.monthKey] && typeof plans[this.monthKey] === "object"
        ? plans[this.monthKey]
        : {};
    const plan = Object.assign({}, previous, {
      budget: budget,
      income: income,
    });
    // 分类预算暂时不提供入口，但字段必须原样保留。
    if (
      !plan.categoryBudgets ||
      typeof plan.categoryBudgets !== "object" ||
      Array.isArray(plan.categoryBudgets)
    ) {
      plan.categoryBudgets = {};
    }
    plans[this.monthKey] = plan;
    this.snap.plans = plans;
    store.save(this.snap);
    this.setData({ budgetOpen: false, budgetError: "" });
    this.refreshView();
    wx.showToast({ title: "预算已保存", icon: "none" });
  },

  noop() {},
});