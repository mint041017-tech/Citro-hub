// 任务编辑页 · 小程序端
// 新建与编辑共用；字段与 flutter/lib/todo/todo_models.dart 的 TodoTask 对齐。
// 数据读写全部走 utils/todo-store.js，页面不直接碰 storage。
const session = require("../../../utils/session");
const store = require("../../../utils/todo-store");

const KINDS = ["reminder", "task", "habit", "quick"];
const KIND_OPTIONS = [
  { value: "reminder", label: "提醒", desc: "到点提醒我" },
  { value: "task", label: "待办", desc: "有截止时间" },
  { value: "habit", label: "习惯", desc: "每周固定几天" },
  { value: "quick", label: "随手做", desc: "想到就记下" },
];
const PRIORITY_OPTIONS = [
  { value: 0, label: "低" },
  { value: 1, label: "中" },
  { value: 2, label: "高" },
];
const LEAD_VALUES = [0, 5, 15, 30, 60];
const LEAD_OPTIONS = [
  { value: 0, label: "准时" },
  { value: 5, label: "5 分钟前" },
  { value: 15, label: "15 分钟前" },
  { value: 30, label: "30 分钟前" },
  { value: 60, label: "1 小时前" },
];
const DAY_OPTIONS = [
  { value: 1, label: "一" },
  { value: 2, label: "二" },
  { value: 3, label: "三" },
  { value: 4, label: "四" },
  { value: 5, label: "五" },
  { value: 6, label: "六" },
  { value: 7, label: "日" },
];
const WEEKDAYS = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];

function pad2(n) {
  return String(n).padStart(2, "0");
}

function dateStrOf(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function timeStrOf(d) {
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

function dateTextOf(str) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(str || ""));
  if (!m) return String(str || "");
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return (
    Number(m[1]) +
    "年" +
    Number(m[2]) +
    "月" +
    Number(m[3]) +
    "日 " +
    WEEKDAYS[d.getDay()]
  );
}

// 日期 + 时间合成毫秒时间戳；非法日期（如 2 月 31 日）返回 null。
function parseSchedule(dateStr, timeStr) {
  const dm = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateStr || ""));
  const tm = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(String(timeStr || ""));
  if (!dm || !tm) return null;
  const y = Number(dm[1]);
  const mo = Number(dm[2]);
  const day = Number(dm[3]);
  const h = Number(tm[1]);
  const mi = Number(tm[2]);
  const d = new Date(y, mo - 1, day, h, mi, 0, 0);
  if (
    d.getFullYear() !== y ||
    d.getMonth() !== mo - 1 ||
    d.getDate() !== day
  ) {
    return null;
  }
  return d.getTime();
}

function isTimeString(value) {
  return /^([01]\d|2[0-3]):([0-5]\d)$/.test(String(value || ""));
}

function makeId(prefix) {
  return prefix + Date.now() + Math.random().toString(36).slice(2, 7);
}

function kindFlags(kind) {
  const scheduled = kind === "reminder" || kind === "task";
  return {
    showSchedule: scheduled,
    showHabit: kind === "habit",
    showLead: scheduled,
    scheduleLabel: kind === "reminder" ? "提醒时间" : "截止时间",
  };
}

// 清单 / 分类兼容对象（id+name/title/label）与纯字符串两种快照形态。
function normalizeChoices(raw) {
  const out = [];
  (Array.isArray(raw) ? raw : []).forEach((item) => {
    if (item && typeof item === "object") {
      const id = item.id != null ? item.id : item._id;
      const name = item.name || item.title || item.label || "未命名";
      if (id == null || String(id) === "") return;
      out.push({ id: String(id), name: String(name) });
      return;
    }
    if (item == null || String(item) === "") return;
    out.push({ id: String(item), name: String(item) });
  });
  return out;
}

function normalizeSubtasks(raw) {
  const out = [];
  (Array.isArray(raw) ? raw : []).forEach((item, i) => {
    const title = String((item && item.title) || "").trim();
    if (!title) return;
    out.push({
      id: String((item && item.id) || "s_" + i),
      title,
      done: !!(item && item.done),
    });
  });
  return out;
}

function clampPriority(value) {
  const n = Number(value);
  return n === 2 || n === 1 ? n : 0;
}

function sanitizeLeadMinutes(values) {
  const out = [];
  (Array.isArray(values) ? values : []).forEach((value) => {
    const n = Number(value);
    if (LEAD_VALUES.indexOf(n) >= 0 && out.indexOf(n) < 0) out.push(n);
  });
  out.sort((a, b) => a - b);
  return out;
}

function buildLeadOptions(values) {
  const picked = sanitizeLeadMinutes(values);
  return LEAD_OPTIONS.map((item) => ({
    value: item.value,
    label: item.label,
    on: picked.indexOf(item.value) >= 0,
  }));
}

function sanitizeHabitDays(values) {
  const out = [];
  (Array.isArray(values) ? values : []).forEach((value) => {
    const n = Number(value);
    if (n >= 1 && n <= 7 && out.indexOf(n) < 0) out.push(n);
  });
  out.sort((a, b) => a - b);
  return out;
}

function buildDayOptions(values) {
  const picked = sanitizeHabitDays(values);
  return DAY_OPTIONS.map((item) => ({
    value: item.value,
    label: item.label,
    on: picked.indexOf(item.value) >= 0,
  }));
}

function choiceIndex(list, id) {
  if (id == null) return 0;
  const target = String(id);
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === target) return i;
  }
  return 0;
}

function choiceText(list, index) {
  return list[index] ? list[index].name : "未分类";
}

Page({
  data: {
    ready: false,
    saving: false,
    isEdit: false,
    taskId: "",
    pageTitle: "新建任务",
    pageSub: "把要做的事，放进今天。",

    title: "",
    note: "",

    kind: "task",
    kindOptions: KIND_OPTIONS,
    showSchedule: true,
    showHabit: false,
    showLead: true,
    scheduleLabel: "截止时间",

    priority: 0,
    priorityOptions: PRIORITY_OPTIONS,

    lists: [],
    listNames: [],
    listIndex: 0,
    listText: "未分类",
    categories: [],
    categoryNames: [],
    categoryIndex: 0,
    categoryText: "未分类",

    dateStr: "",
    dateText: "",
    timeStr: "20:00",

    leadMinutes: [15],
    leadOptions: buildLeadOptions([15]),

    habitDays: [1, 2, 3, 4, 5],
    habitDayOptions: buildDayOptions([1, 2, 3, 4, 5]),
    habitTime: "20:00",

    subtasks: [],
    subtaskDraft: "",
  },

  onLoad(options) {
    if (!session.token()) {
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }

    const picked = new Date();
    picked.setHours(picked.getHours() + 1, 0, 0, 0);
    const defaultDateStr = dateStrOf(picked);
    const defaultTimeStr = timeStrOf(picked);

    let snapshot = {};
    try {
      snapshot = store.load() || {};
    } catch (e) {
      snapshot = {};
    }

    const lists = normalizeChoices(snapshot.lists);
    const categories = normalizeChoices(snapshot.categories);
    const tasks = Array.isArray(snapshot.tasks) ? snapshot.tasks : [];
    const id = options && options.id != null ? String(options.id) : "";
    let task = null;
    if (id) {
      for (let i = 0; i < tasks.length; i++) {
        if (tasks[i] && String(tasks[i].id) === id) {
          task = tasks[i];
          break;
        }
      }
    }

    if (task) {
      const kind = KINDS.indexOf(String(task.kind)) >= 0 ? String(task.kind) : "task";
      const flags = kindFlags(kind);
      const listIndex = choiceIndex(lists, task.listId);
      const categoryIndex = choiceIndex(categories, task.categoryId);

      let at = null;
      if (kind === "reminder") at = Number(task.remindAt);
      if (kind === "task") at = Number(task.dueAt);
      if (!isFinite(at) || at <= 0) at = null;

      const dateStr = at ? dateStrOf(new Date(at)) : defaultDateStr;
      const timeStr = at ? timeStrOf(new Date(at)) : defaultTimeStr;
      const habitDays = sanitizeHabitDays(task.habitDays);
      const habitTime = isTimeString(task.habitTime) ? String(task.habitTime) : "20:00";
      const leadMinutes = sanitizeLeadMinutes(
        Array.isArray(task.leadMinutes) ? task.leadMinutes : [15]
      );

      this.setData({
        ready: true,
        isEdit: true,
        taskId: String(task.id || ""),
        pageTitle: "编辑任务",
        pageSub: "改一改，接着做。",
        title: String(task.title || ""),
        note: String(task.note || ""),
        kind,
        showSchedule: flags.showSchedule,
        showHabit: flags.showHabit,
        showLead: flags.showLead,
        scheduleLabel: flags.scheduleLabel,
        priority: clampPriority(task.priority),
        lists,
        listNames: lists.map((item) => item.name),
        listIndex,
        listText: choiceText(lists, listIndex),
        categories,
        categoryNames: categories.map((item) => item.name),
        categoryIndex,
        categoryText: choiceText(categories, categoryIndex),
        dateStr,
        dateText: dateTextOf(dateStr),
        timeStr,
        leadMinutes,
        leadOptions: buildLeadOptions(leadMinutes),
        habitDays,
        habitDayOptions: buildDayOptions(habitDays),
        habitTime,
        subtasks: normalizeSubtasks(task.subtasks),
      });
      return;
    }

    this.setData({
      ready: true,
      isEdit: false,
      taskId: "",
      pageTitle: "新建任务",
      pageSub: "把要做的事，放进今天。",
      lists,
      listNames: lists.map((item) => item.name),
      listIndex: 0,
      listText: choiceText(lists, 0),
      categories,
      categoryNames: categories.map((item) => item.name),
      categoryIndex: 0,
      categoryText: choiceText(categories, 0),
      dateStr: defaultDateStr,
      dateText: dateTextOf(defaultDateStr),
      timeStr: defaultTimeStr,
    });
  },

  /* ---------------- 表单输入 ---------------- */

  onTitleInput(e) {
    this.setData({ title: e.detail.value });
  },

  onNoteInput(e) {
    this.setData({ note: e.detail.value });
  },

  onKindTap(e) {
    const kind = String(e.currentTarget.dataset.value || "");
    if (KINDS.indexOf(kind) < 0 || kind === this.data.kind) return;
    const flags = kindFlags(kind);
    this.setData({
      kind,
      showSchedule: flags.showSchedule,
      showHabit: flags.showHabit,
      showLead: flags.showLead,
      scheduleLabel: flags.scheduleLabel,
    });
  },

  onPriorityTap(e) {
    this.setData({ priority: clampPriority(e.currentTarget.dataset.value) });
  },

  onToggleLead(e) {
    const value = Number(e.currentTarget.dataset.value);
    if (LEAD_VALUES.indexOf(value) < 0) return;
    const next = sanitizeLeadMinutes(this.data.leadMinutes);
    const at = next.indexOf(value);
    if (at >= 0) next.splice(at, 1);
    else next.push(value);
    next.sort((a, b) => a - b);
    this.setData({
      leadMinutes: next,
      leadOptions: buildLeadOptions(next),
    });
  },

  onToggleDay(e) {
    const value = Number(e.currentTarget.dataset.value);
    if (!(value >= 1 && value <= 7)) return;
    const next = sanitizeHabitDays(this.data.habitDays);
    const at = next.indexOf(value);
    if (at >= 0) next.splice(at, 1);
    else next.push(value);
    next.sort((a, b) => a - b);
    this.setData({
      habitDays: next,
      habitDayOptions: buildDayOptions(next),
    });
  },

  onDateChange(e) {
    const value = String((e.detail && e.detail.value) || "");
    this.setData({ dateStr: value, dateText: dateTextOf(value) });
  },

  onTimeChange(e) {
    this.setData({ timeStr: String((e.detail && e.detail.value) || "") });
  },

  onHabitTimeChange(e) {
    const value = String((e.detail && e.detail.value) || "");
    if (isTimeString(value)) this.setData({ habitTime: value });
  },

  onListChange(e) {
    const index = Number(e.detail && e.detail.value);
    const safe = index >= 0 && index < this.data.lists.length ? index : 0;
    this.setData({
      listIndex: safe,
      listText: choiceText(this.data.lists, safe),
    });
  },

  onCategoryChange(e) {
    const index = Number(e.detail && e.detail.value);
    const safe =
      index >= 0 && index < this.data.categories.length ? index : 0;
    this.setData({
      categoryIndex: safe,
      categoryText: choiceText(this.data.categories, safe),
    });
  },

  /* ---------------- 子任务 ---------------- */

  onSubtaskInput(e) {
    this.setData({ subtaskDraft: e.detail.value });
  },

  onAddSubtask() {
    const title = String(this.data.subtaskDraft || "").trim();
    if (!title) {
      wx.showToast({ title: "先写点子任务内容", icon: "none" });
      return;
    }
    const subtasks = this.data.subtasks.concat([
      { id: makeId("s_"), title, done: false },
    ]);
    this.setData({ subtasks, subtaskDraft: "" });
  },

  onToggleSubtask(e) {
    const index = Number(e.currentTarget.dataset.index);
    if (!(index >= 0 && index < this.data.subtasks.length)) return;
    const subtasks = this.data.subtasks.map((item, i) =>
      i === index ? { id: item.id, title: item.title, done: !item.done } : item
    );
    this.setData({ subtasks });
  },

  onDeleteSubtask(e) {
    const index = Number(e.currentTarget.dataset.index);
    if (!(index >= 0 && index < this.data.subtasks.length)) return;
    const subtasks = this.data.subtasks.slice();
    subtasks.splice(index, 1);
    this.setData({ subtasks });
  },

  /* ---------------- 保存 / 删除 ---------------- */

  onSave() {
    if (!this.data.ready || this.data.saving) return;

    const title = String(this.data.title || "").trim();
    if (!title) {
      wx.showToast({ title: "请填写任务标题", icon: "none" });
      return;
    }

    const kind = KINDS.indexOf(this.data.kind) >= 0 ? this.data.kind : "task";
    let remindAt = null;
    let dueAt = null;
    let habitDays = [];
    const habitTime = isTimeString(this.data.habitTime)
      ? String(this.data.habitTime)
      : "20:00";

    if (kind === "reminder" || kind === "task") {
      const at = parseSchedule(this.data.dateStr, this.data.timeStr);
      if (at == null) {
        wx.showToast({ title: "请选择有效的日期和时间", icon: "none" });
        return;
      }
      if (kind === "reminder") remindAt = at;
      else dueAt = at;
    }

    if (kind === "habit" && !isTimeString(this.data.habitTime)) {
      wx.showToast({ title: "请选择有效的执行时间", icon: "none" });
      return;
    }
    if (kind === "habit") habitDays = sanitizeHabitDays(this.data.habitDays);

    const list = this.data.lists[this.data.listIndex] || null;
    const category = this.data.categories[this.data.categoryIndex] || null;
    const subtasks = (Array.isArray(this.data.subtasks) ? this.data.subtasks : [])
      .map((item) => ({
        id: String(item.id || makeId("s_")),
        title: String(item.title || "").trim(),
        done: !!item.done,
      }))
      .filter((item) => item.title);

    const fields = {
      title,
      note: String(this.data.note || "").trim(),
      kind,
      categoryId: category ? category.id : "",
      listId: list ? list.id : "",
      remindAt,
      dueAt,
      leadMinutes:
        kind === "reminder" || kind === "task"
          ? sanitizeLeadMinutes(this.data.leadMinutes)
          : [],
      habitDays,
      habitTime,
      priority: clampPriority(this.data.priority),
      subtasks,
    };

    this.setData({ saving: true });

    try {
      const snapshot = store.load() || {};
      const tasks = Array.isArray(snapshot.tasks) ? snapshot.tasks : [];
      if (this.data.isEdit && this.data.taskId) {
        const taskId = String(this.data.taskId);
        let found = false;
        snapshot.tasks = tasks.map((task) => {
          if (!task || String(task.id) !== taskId) return task;
          found = true;
          const state = task.done
            ? "done"
            : task.state === "doing"
            ? "doing"
            : "todo";
          return Object.assign({}, task, fields, { state });
        });
        if (!found) {
          snapshot.tasks.unshift(
            Object.assign(
              {
                id: taskId,
                done: false,
                completedAt: null,
                createdAt: Date.now(),
                state: "todo",
              },
              fields
            )
          );
        }
      } else {
        snapshot.tasks = tasks.concat([
          Object.assign(
            {
              id: makeId("t_"),
              done: false,
              completedAt: null,
              createdAt: Date.now(),
              state: "todo",
            },
            fields
          ),
        ]);
      }

      if (store.save(snapshot) === false) throw new Error("保存失败");
    } catch (e) {
      this.setData({ saving: false });
      wx.showToast({
        title: (e && e.message) || "保存失败，请稍后重试",
        icon: "none",
      });
      return;
    }

    this.setData({ saving: false });
    wx.showToast({ title: "已保存", icon: "success", duration: 900 });
    this.goBack();
  },

  onDelete() {
    if (!this.data.isEdit || this.data.saving) return;
    const raw = String(this.data.title || "").trim();
    const label = Array.from(raw).slice(0, 20).join("") || "这条任务";
    wx.showModal({
      title: "删除任务",
      content: "「" + label + "」删除后无法恢复，确定删除吗？",
      confirmText: "删除",
      confirmColor: "#B05A4A",
      success: (res) => {
        if (!res.confirm) return;
        this.setData({ saving: true });
        try {
          const snapshot = store.load() || {};
          const tasks = Array.isArray(snapshot.tasks) ? snapshot.tasks : [];
          const taskId = String(this.data.taskId);
          snapshot.tasks = tasks.filter(
            (task) => !task || String(task.id) !== taskId
          );
          if (store.save(snapshot) === false) throw new Error("删除失败");
        } catch (e) {
          this.setData({ saving: false });
          wx.showToast({
            title: (e && e.message) || "删除失败，请稍后重试",
            icon: "none",
          });
          return;
        }
        this.setData({ saving: false });
        wx.showToast({ title: "已删除", icon: "success", duration: 900 });
        this.goBack();
      },
    });
  },

  goBack() {
    if (getCurrentPages().length > 1) {
      wx.navigateBack({ delta: 1 });
      return;
    }
    wx.switchTab({ url: "/pages/home/home" });
  },
});