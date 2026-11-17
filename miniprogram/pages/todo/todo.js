// 待办 · 小程序端
// 对应 flutter/lib/todo/todo_page.dart 的「待办」视图：
// 概览 + 今日 / 全部 / 逾期 / 清单筛选 + 任务卡 + 新建入口。
// 数据全部走 utils/todo-store.js，页面不直接读写 storage。
const store = require("../../utils/todo-store");
const session = require("../../utils/session");

const KIND_LABEL = {
  reminder: "提醒",
  task: "待办",
  habit: "习惯",
  quick: "随手做",
};
const WEEKDAYS = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
const HABIT_WEEK = ["一", "二", "三", "四", "五", "六", "日"];
const DAY_MS = 24 * 60 * 60 * 1000;

function pad2(n) {
  return String(n).padStart(2, "0");
}

function toNumber(value, fallback) {
  const n = Number(value);
  return isFinite(n) ? n : fallback;
}

function dayStart(value) {
  const d = value instanceof Date ? value : new Date(toNumber(value, 0));
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function createdDay(task) {
  return dayStart(task.createdAt || Date.now());
}

function occursOn(task, day) {
  const target = dayStart(day).getTime();
  if (task.kind === "habit") {
    const weekday = new Date(target).getDay() === 0 ? 7 : new Date(target).getDay();
    const days = Array.isArray(task.habitDays) ? task.habitDays : [];
    return days.indexOf(weekday) >= 0 && target >= createdDay(task).getTime();
  }
  if (task.kind === "quick") {
    return target === createdDay(task).getTime();
  }
  const at = task.kind === "reminder" ? task.remindAt : task.dueAt;
  if (at == null) {
    const created = createdDay(task).getTime();
    return target === created || (target > created && target < created + 7 * DAY_MS);
  }
  return dayStart(at).getTime() === target;
}

function isOverdue(task, now) {
  if (task.done) return false;
  const at =
    task.kind === "task"
      ? task.dueAt
      : task.kind === "reminder"
      ? task.remindAt
      : null;
  return at != null && at < now.getTime();
}

function scheduledAt(task, day) {
  if (task.kind === "habit") {
    const parts = String(task.habitTime || "20:00").split(":");
    const h = toNumber(parts[0], 20);
    const m = parts.length > 1 ? toNumber(parts[1], 0) : 0;
    const d = dayStart(day);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, m, 0, 0).getTime();
  }
  if (task.kind === "reminder") return task.remindAt;
  if (task.kind === "task") return task.dueAt;
  return null;
}

function timeTextOf(task, now) {
  if (task.kind === "habit") {
    const days = (Array.isArray(task.habitDays) ? task.habitDays : [])
      .slice()
      .sort(function (a, b) {
        return a - b;
      });
    const label = days.length
      ? "周" + days.map(function (d) {
          return HABIT_WEEK[d - 1] || "";
        }).join("、")
      : "每天";
    return label + " " + (task.habitTime || "20:00");
  }
  if (task.kind === "quick") return "想到就做";
  const at = task.kind === "reminder" ? task.remindAt : task.dueAt;
  if (at == null) return "";
  const d = new Date(toNumber(at, 0));
  if (isNaN(d.getTime())) return "";
  const hm = pad2(d.getHours()) + ":" + pad2(d.getMinutes());
  const sameDay =
    d.getFullYear() === now.getFullYear() &&
    d.getMonth() === now.getMonth() &&
    d.getDate() === now.getDate();
  if (sameDay) return hm;
  return d.getMonth() + 1 + "/" + d.getDate() + " " + hm;
}

function argbToHex(value) {
  const n = toNumber(value, 0xffc08a4a) >>> 0;
  const hex = (n & 0xffffff).toString(16).toUpperCase();
  return "#" + ("000000" + hex).slice(-6);
}

function dateTextOf(now) {
  return (
    now.getMonth() +
    1 +
    " 月 " +
    now.getDate() +
    " 日 · " +
    WEEKDAYS[now.getDay()]
  );
}

/* ---------------- 派生视图 ---------------- */

function buildChips(snap, filter) {
  function chipClass(key) {
    return filter === key ? "filter-chip is-on" : "filter-chip";
  }
  const chips = [
    { key: "today", text: "今天", cls: chipClass("today") },
    { key: "all", text: "全部", cls: chipClass("all") },
    { key: "overdue", text: "逾期", cls: chipClass("overdue") },
    { key: "__label", text: "清单", cls: "filter-label" },
  ];
  (Array.isArray(snap.lists) ? snap.lists : []).forEach(function (list) {
    if (!list || !list.id) return;
    const key = String(list.id);
    chips.push({
      key,
      text: String(list.name || "未命名"),
      cls: filter === key ? "filter-chip is-on" : "filter-chip",
    });
  });
  return chips;
}

function sortValue(task, filter, now) {
  if (filter === "today") return scheduledAt(task, now);
  if (task.kind === "reminder") return task.remindAt;
  if (task.kind === "task") return task.dueAt;
  if (task.kind === "habit") return scheduledAt(task, now);
  return null;
}

function buildTaskViews(snap, filter, now) {
  const categoryMap = {};
  (Array.isArray(snap.categories) ? snap.categories : []).forEach(function (c) {
    if (c && c.id) categoryMap[String(c.id)] = c;
  });
  const listMap = {};
  (Array.isArray(snap.lists) ? snap.lists : []).forEach(function (l) {
    if (l && l.id) listMap[String(l.id)] = l;
  });

  let items = (Array.isArray(snap.tasks) ? snap.tasks : []).filter(function (t) {
    return !!(t && t.id);
  });

  if (filter === "today") {
    items = items.filter(function (t) {
      return occursOn(t, now);
    });
  } else if (filter === "overdue") {
    items = items.filter(function (t) {
      return isOverdue(t, now);
    });
  } else if (filter !== "all") {
    items = items.filter(function (t) {
      return String(t.listId) === filter;
    });
  }

  items.sort(function (a, b) {
    if (a.done !== b.done) return a.done ? 1 : -1;
    const av = sortValue(a, filter, now);
    const bv = sortValue(b, filter, now);
    if (av != null && bv != null && av !== bv) return av - bv;
    if (av != null && bv == null) return -1;
    if (av == null && bv != null) return 1;
    return (toNumber(a.createdAt, 0) || 0) - (toNumber(b.createdAt, 0) || 0);
  });

  return items.map(function (task) {
    const category = categoryMap[String(task.categoryId)];
    const list = listMap[String(task.listId)];
    const subtasks = Array.isArray(task.subtasks) ? task.subtasks : [];
    let subDone = 0;
    subtasks.forEach(function (sub) {
      if (sub && sub.done) subDone += 1;
    });
    const timeText = timeTextOf(task, now);
    const done = task.done === true;
    const kind = task.kind || "task";
    const priority = toNumber(task.priority, 0);
    return {
      id: String(task.id),
      title: String(task.title || ""),
      done,
      kind,
      kindLabel: KIND_LABEL[kind] || KIND_LABEL.task,
      kindClass: "kind-tag kind-" + (KIND_LABEL[kind] ? kind : "task"),
      timeText,
      listName: list ? String(list.name || "未命名") : "未归类",
      categoryColor: argbToHex(category ? category.color : 0xffc08a4a),
      hasPriority: priority > 0,
      priorityClass: priority >= 2 ? "prio-dot is-urgent" : "prio-dot is-important",
      subtaskText: subtasks.length ? "子任务 " + subDone + "/" + subtasks.length : "",
      overdue: isOverdue(task, now),
      cardClass: done ? "task-card is-done" : "task-card",
      checkClass: done ? "task-check is-on" : "task-check",
      titleClass: done ? "task-title is-done" : "task-title",
    };
  });
}

function emptyTextFor(filter, lists) {
  if (filter === "overdue") return "没有逾期任务，节奏刚刚好";
  if (filter === "all") return "还没有任务，从新建一件小事开始";
  if (filter !== "today") {
    let name = "";
    (Array.isArray(lists) ? lists : []).forEach(function (list) {
      if (list && String(list.id) === filter) name = String(list.name || "");
    });
    return name ? "「" + name + "」还是空的，新建一件吧" : "这个清单还是空的，新建一件吧";
  }
  return "今天还没有任务，先写一件小事";
}

/* ---------------- 页面 ---------------- */

Page({
  data: {
    filter: "today",
    dateText: "",
    overview: {
      done: 0,
      total: 0,
      left: 0,
      percent: 0,
      progressStyle: "width: 0%",
      overdue: 0,
      overdueText: "没有逾期",
      overdueClass: "overdue-pill",
    },
    chips: [],
    tasks: [],
    emptyText: "今天还没有任务，先写一件小事",
  },

  onLoad() {
    if (!session.token()) {
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    this.reload();
  },

  onShow() {
    if (!session.token()) {
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    this.reload();
  },

  onPullDownRefresh() {
    const token = session.token();
    if (!token) {
      wx.stopPullDownRefresh();
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    const done = () => {
      wx.stopPullDownRefresh();
    };
    store
      .sync(token)
      .then(() => {
        this.reload();
        done();
      })
      .catch(done);
  },

  reload() {
    let snap;
    try {
      snap = store.load() || {};
    } catch (e) {
      snap = {};
    }
    const now = new Date();
    const lists = Array.isArray(snap.lists) ? snap.lists : [];

    let filter = String(this.data.filter || "today");
    if (filter !== "today" && filter !== "all" && filter !== "overdue") {
      let exists = false;
      lists.forEach(function (list) {
        if (list && String(list.id) === filter) exists = true;
      });
      if (!exists) filter = "today";
    }

    let sum;
    try {
      sum = store.summary(snap);
    } catch (e) {
      sum = { today: 0, done: 0, overdue: 0, percent: 0, items: [] };
    }

    const total = Math.max(0, toNumber(sum.today, 0));
    const doneCount = Math.max(0, toNumber(sum.done, 0));
    const overdue = Math.max(0, toNumber(sum.overdue, 0));
    const percent = Math.max(0, Math.min(100, toNumber(sum.percent, 0)));

    this.setData({
      filter,
      dateText: dateTextOf(now),
      overview: {
        done: doneCount,
        total,
        left: Math.max(0, total - doneCount),
        percent,
        progressStyle: "width: " + percent + "%",
        overdue,
        overdueText: overdue > 0 ? "逾期 " + overdue + " 件" : "没有逾期",
        overdueClass: overdue > 0 ? "overdue-pill is-hot" : "overdue-pill",
      },
      chips: buildChips(snap, filter),
      tasks: buildTaskViews(snap, filter, now),
      emptyText: emptyTextFor(filter, lists),
    });
  },

  onFilterTap(e) {
    const key = String((e.currentTarget.dataset && e.currentTarget.dataset.key) || "");
    if (!key || key === "__label" || key === this.data.filter) return;
    this.setData({ filter: key }, () => {
      this.reload();
    });
  },

  onTaskTap(e) {
    const id = String((e.currentTarget.dataset && e.currentTarget.dataset.id) || "");
    if (!id) return;
    wx.navigateTo({
      url: "/pages/todo/edit/edit?id=" + encodeURIComponent(id),
      fail() {
        wx.showToast({ title: "编辑页暂不可用", icon: "none" });
      },
    });
  },

  onToggle(e) {
    const id = String((e.currentTarget.dataset && e.currentTarget.dataset.id) || "");
    if (!id) return;

    let snap;
    try {
      snap = store.load();
    } catch (err) {
      return;
    }
    const tasks = Array.isArray(snap.tasks) ? snap.tasks : [];
    let task = null;
    for (let i = 0; i < tasks.length; i += 1) {
      if (tasks[i] && String(tasks[i].id) === id) {
        task = tasks[i];
        break;
      }
    }
    if (!task) return;

    const done = task.done !== true;
    task.done = done;
    task.doing = false;
    task.doneAt = done ? Date.now() : null;
    task.completedAt = task.doneAt;
    task.state = done ? "done" : "todo";

    const saved = store.save(snap);
    if (saved === false) {
      wx.showToast({ title: "保存失败，请稍后重试", icon: "none" });
      return;
    }
    this.reload();
  },

  onDelete(e) {
    const id = String((e.currentTarget.dataset && e.currentTarget.dataset.id) || "");
    if (!id) return;

    let label = "";
    (Array.isArray(this.data.tasks) ? this.data.tasks : []).forEach(function (item) {
      if (item.id === id) {
        label = Array.from(String(item.title || "")).slice(0, 18).join("");
      }
    });
    const content = label
      ? "「" + label + "」删除后不能恢复，确定删除吗？"
      : "删除后不能恢复，确定删除吗？";

    wx.showModal({
      title: "删除任务",
      content,
      confirmText: "删除",
      confirmColor: "#B05A4A",
      success: (res) => {
        if (!res.confirm) return;
        store.deleteTask(id);
        this.reload();
        wx.showToast({ title: "已删除", icon: "success", duration: 800 });
      },
    });
  },

  onNew() {
    wx.navigateTo({
      url: "/pages/todo/edit/edit",
      fail() {
        wx.showToast({ title: "编辑页暂不可用", icon: "none" });
      },
    });
  },
});