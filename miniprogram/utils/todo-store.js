// 待办 · 本地优先的数据层
// 与 flutter/lib/todo/todo_store.dart 共用同一套云端契约：
// 整包快照 {tasks, lists, categories, reviews, moods, ...} + updatedAt，
// 本地时间戳存在 citro_todo_v1_at，GET /api/todo 返回 {todo, at}，
// at 更新则覆盖本地，否则把本地整包推上去（last writer wins）。
const api = require("./api");
const session = require("./session");
const kit = require("./storage");
const synckit = require("./sync");

const STORAGE_KEY = "citro_todo_v1";
const AT_KEY = "citro_todo_v1_at";
const KINDS = ["reminder", "task", "habit", "quick"];
const DAY_MS = 24 * 60 * 60 * 1000;

function isObj(v) {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function str(v) {
  return v == null ? "" : String(v);
}

function toInt(v, fallback) {
  if (typeof v === "number" && isFinite(v)) return Math.floor(v);
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v);
    if (isFinite(n)) return Math.floor(n);
  }
  return fallback;
}

// Flutter 端接受毫秒数、数字字符串与 ISO 字符串，这里保持同样的宽松度。
function parseDate(v) {
  if (typeof v === "number" && isFinite(v)) return v;
  if (typeof v === "string" && v !== "") {
    const n = Number(v);
    if (isFinite(n)) return n;
    const at = Date.parse(v);
    if (!isNaN(at)) return at;
  }
  return null;
}

function dayStart(value) {
  const d = value instanceof Date ? value : new Date(Number(value) || 0);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

/* ------------------------------------------------------------------ *
 * 默认种子：首次没有存储数据时使用。
 * 清单「工作 / 生活 / 学习」，分类「工作 / 生活 / 健康 / 学习」。
 * ------------------------------------------------------------------ */

function seedLists() {
  return [
    { id: "work", name: "工作", color: 0xff6f8ca8, icon: "note" },
    { id: "life", name: "生活", color: 0xffe8935a, icon: "list" },
    { id: "study", name: "学习", color: 0xffc08a4a, icon: "book" },
  ];
}

function seedCategories() {
  return [
    {
      id: "work",
      name: "工作",
      color: 0xff6f8ca8,
      icon: "note",
      builtIn: true,
    },
    {
      id: "life",
      name: "生活",
      color: 0xffe8935a,
      icon: "flag",
      builtIn: true,
    },
    {
      id: "health",
      name: "健康",
      color: 0xffb5717a,
      icon: "heart",
      builtIn: true,
    },
    {
      id: "study",
      name: "学习",
      color: 0xffc08a4a,
      icon: "book",
      builtIn: true,
    },
  ];
}

function seedSnapshot() {
  return {
    tasks: [],
    lists: seedLists(),
    categories: seedCategories(),
    reviews: {},
    moods: [],
  };
}

/* ------------------------------------------------------------------ *
 * 归一化：缺省容错，未知字段原样保留（source / autoReview* / 未来字段）。
 * ------------------------------------------------------------------ */

function normalizeList(raw) {
  const out = Object.assign({}, raw);
  out.id = str(raw.id);
  out.name = str(raw.name);
  out.color = toInt(raw.color, 0xffe8935a);
  out.icon = str(raw.icon) || "list";
  return out;
}

function normalizeCategory(raw) {
  const out = Object.assign({}, raw);
  out.id = str(raw.id);
  out.name = str(raw.name);
  out.color = toInt(raw.color, 0xff8a7f6a);
  out.icon = str(raw.icon) || "flag";
  out.builtIn = raw.builtIn === true;
  return out;
}

function normalizeLeadMinutes(raw) {
  if (!Array.isArray(raw)) return [15];
  const out = [];
  raw.forEach(function (item) {
    const n = toInt(item, -1);
    if (n >= 0 && n <= 10080 && out.indexOf(n) < 0) out.push(n);
  });
  return out;
}

function normalizeHabitDays(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  raw.forEach(function (item) {
    const n = toInt(item, 0);
    if (n >= 1 && n <= 7 && out.indexOf(n) < 0) out.push(n);
  });
  out.sort(function (a, b) {
    return a - b;
  });
  return out;
}

function normalizeSubtasks(raw) {
  const out = [];
  (Array.isArray(raw) ? raw : []).forEach(function (item) {
    if (!isObj(item)) return;
    const sub = Object.assign({}, item);
    sub.id = str(item.id);
    sub.title = str(item.title);
    sub.done = item.done === true;
    out.push(sub);
  });
  return out;
}

function normalizeTask(raw) {
  const source = isObj(raw) ? raw : {};
  const out = Object.assign({}, source);

  out.id = str(source.id);
  out.title = str(source.title);
  out.note = str(source.note);
  out.kind = KINDS.indexOf(source.kind) >= 0 ? source.kind : "task";
  out.categoryId = str(source.categoryId) || "study";
  out.listId = str(source.listId) || "default";
  out.remindAt = parseDate(source.remindAt);
  out.dueAt = parseDate(source.dueAt);
  out.leadMinutes = normalizeLeadMinutes(source.leadMinutes);
  out.habitDays = normalizeHabitDays(source.habitDays);
  out.habitTime = str(source.habitTime) || "20:00";
  out.priority = toInt(source.priority, 0);

  let done = source.done === true;
  let doing = source.doing === true;
  // 小程序编辑页会写 state；把它当作 done/doing 缺失时的补充来源。
  if (!done && source.state === "done") done = true;
  if (!done && !doing && source.state === "doing") doing = true;
  if (done) doing = false;

  let doneAt = parseDate(source.doneAt);
  if (doneAt == null) doneAt = parseDate(source.completedAt);

  out.done = done;
  out.doing = doing;
  out.doneAt = done ? doneAt : null;
  out.completedAt = done ? doneAt : null;
  out.createdAt = parseDate(source.createdAt);
  if (out.createdAt == null) out.createdAt = Date.now();
  out.subtasks = normalizeSubtasks(source.subtasks);
  out.source = str(source.source) || "manual";
  out.state = done ? "done" : doing ? "doing" : "todo";
  return out;
}

function normalizeSnapshot(raw) {
  const source = isObj(raw) ? raw : {};
  const out = Object.assign({}, source);

  const lists = [];
  (Array.isArray(source.lists) ? source.lists : []).forEach(function (item) {
    if (!isObj(item)) return;
    const list = normalizeList(item);
    if (list.id) lists.push(list);
  });

  const categories = [];
  (Array.isArray(source.categories) ? source.categories : []).forEach(
    function (item) {
      if (!isObj(item)) return;
      const category = normalizeCategory(item);
      if (category.id) categories.push(category);
    }
  );

  const tasks = [];
  (Array.isArray(source.tasks) ? source.tasks : []).forEach(function (item) {
    if (!isObj(item)) return;
    const task = normalizeTask(item);
    if (task.id && task.title) tasks.push(task);
  });

  out.lists = lists.length ? lists : seedLists();
  out.categories = categories.length ? categories : seedCategories();
  out.tasks = tasks;
  out.reviews = isObj(source.reviews) ? source.reviews : {};
  out.moods = Array.isArray(source.moods) ? source.moods : [];
  return out;
}

/* ------------------------------------------------------------------ *
 * 本地存储
 * ------------------------------------------------------------------ */

function persist(snap, at) {
  return kit.writePair(STORAGE_KEY, AT_KEY, snap, at);
}

function readAt(snap) {
  let at = 0;
  try {
    at = toInt(wx.getStorageSync(AT_KEY), 0);
  } catch (e) {
    at = 0;
  }
  if (at > 0) return at;
  let source = snap;
  if (!isObj(source)) {
    try {
      source = wx.getStorageSync(STORAGE_KEY);
    } catch (e) {
      source = null;
    }
  }
  if (isObj(source)) return Math.max(0, toInt(source.updatedAt, 0));
  return 0;
}

function load() {
  let raw = null;
  try {
    raw = wx.getStorageSync(STORAGE_KEY);
  } catch (e) {
    raw = null;
  }
  if (!isObj(raw)) {
    // 首次进入：落一份种子，at 保持 0，云端有数据时让远端先覆盖。
    const seed = seedSnapshot();
    persist(seed, 0);
    return seed;
  }
  return normalizeSnapshot(raw);
}

function pushRemote(snap) {
  const token = session.token();
  if (!token) return;
  // 离线 / 同步异常时静默失败，下次保存会整包重试。
  synckit.pushSilent(api.todoSave(token, snap));
}

// 返回 false 表示本地写失败（编辑页据此提示保存失败）；其余情况返回快照。
function save(snap) {
  let normalized;
  try {
    normalized = normalizeSnapshot(snap);
  } catch (e) {
    return false;
  }
  const at = Date.now();
  normalized.updatedAt = at;
  if (!persist(normalized, at)) return false;
  pushRemote(normalized);
  return normalized;
}

/* ------------------------------------------------------------------ *
 * 云端同步
 * ------------------------------------------------------------------ */

function sync(token) {
  const tok = synckit.resolveToken(token);
  if (!tok) return Promise.resolve(load());

  return api
    .todoGet(tok)
    .then(function (body) {
      const u = synckit.unwrapRemote(body, "todo", toInt);
      const local = load();
      const localAt = readAt(local);

      if (isObj(u.remote) && u.at > localAt) {
        const next = normalizeSnapshot(u.remote);
        next.updatedAt = u.at;
        persist(next, u.at);
        return load();
      }

      // 本地不旧于云端：把本地整包推上去。
      save(local);
      return load();
    })
    .catch(function () {
      return load();
    });
}

/* ------------------------------------------------------------------ *
 * 今日摘要（供首页 / 计划卡使用）
 * ------------------------------------------------------------------ */

function createdDay(task) {
  return dayStart(task.createdAt || Date.now());
}

function occursOn(task, day) {
  const target = dayStart(day);
  const targetTime = target.getTime();
  if (task.kind === "habit") {
    const weekday = target.getDay() === 0 ? 7 : target.getDay();
    const days = Array.isArray(task.habitDays) ? task.habitDays : [];
    return (
      days.indexOf(weekday) >= 0 && targetTime >= createdDay(task).getTime()
    );
  }
  if (task.kind === "quick") {
    return targetTime === createdDay(task).getTime();
  }
  const at = task.kind === "reminder" ? task.remindAt : task.dueAt;
  if (at == null) {
    const created = createdDay(task).getTime();
    return (
      targetTime === created ||
      (targetTime > created && targetTime < created + 7 * DAY_MS)
    );
  }
  return dayStart(at).getTime() === targetTime;
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
    const parts = str(task.habitTime || "20:00").split(":");
    const h = toInt(parts[0], 20);
    const m = parts.length > 1 ? toInt(parts[1], 0) : 0;
    const d = dayStart(day);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, m, 0, 0).getTime();
  }
  if (task.kind === "reminder") return task.remindAt;
  if (task.kind === "task") return task.dueAt;
  return null;
}

function pad2(n) {
  return String(n).padStart(2, "0");
}

function timeText(task) {
  if (task.kind === "habit") {
    const names = ["一", "二", "三", "四", "五", "六", "日"];
    const days = (Array.isArray(task.habitDays) ? task.habitDays : [])
      .slice()
      .sort(function (a, b) {
        return a - b;
      });
    const label = days.length
      ? "周" + days.map(function (d) {
          return names[d - 1] || "";
        }).join("、")
      : "每天";
    return label + " " + (task.habitTime || "20:00");
  }
  if (task.kind === "quick") return "";
  const at = task.kind === "reminder" ? task.remindAt : task.dueAt;
  if (at == null) return "";
  const d = new Date(at);
  if (isNaN(d.getTime())) return "";
  const hm = pad2(d.getHours()) + ":" + pad2(d.getMinutes());
  const now = new Date();
  if (
    d.getFullYear() === now.getFullYear() &&
    d.getMonth() === now.getMonth() &&
    d.getDate() === now.getDate()
  ) {
    return hm;
  }
  return d.getMonth() + 1 + "/" + d.getDate() + " " + hm;
}

function kindLabel(kind) {
  if (kind === "reminder") return "提醒";
  if (kind === "habit") return "习惯";
  if (kind === "quick") return "随手做";
  return "待办";
}

function summary(snap) {
  const data = snap ? normalizeSnapshot(snap) : load();
  const now = new Date();
  const today = dayStart(now);
  const todayTime = today.getTime();
  let total = 0;
  let done = 0;

  data.tasks.forEach(function (task) {
    const occurs = occursOn(task, today);
    if (occurs) total += 1;
    if (task.done && task.doneAt != null) {
      if (dayStart(task.doneAt).getTime() === todayTime) {
        done += 1;
        // Flutter 的 totalOn：今天完成但本不属于今天的任务也算进分母。
        if (!occurs) total += 1;
      }
    }
  });

  const overdue = data.tasks.filter(function (task) {
    return isOverdue(task, now);
  }).length;

  const percent = total > 0 ? Math.round((done * 100) / total) : 0;

  const open = data.tasks.filter(function (task) {
    return !task.done;
  });

  function bucketOf(task) {
    if (isOverdue(task, now)) return 0;
    if (occursOn(task, today)) return 1;
    if (task.doing) return 2;
    return 3;
  }

  open.sort(function (a, b) {
    const ba = bucketOf(a);
    const bb = bucketOf(b);
    if (ba !== bb) return ba - bb;
    const av = scheduledAt(a, today);
    const bv = scheduledAt(b, today);
    if (av != null && bv != null && av !== bv) return av - bv;
    if (av != null && bv == null) return -1;
    if (av == null && bv != null) return 1;
    return (a.createdAt || 0) - (b.createdAt || 0);
  });

  const items = open.slice(0, 5).map(function (task) {
    return {
      id: task.id,
      title: task.title,
      kindLabel: kindLabel(task.kind),
      dueText: timeText(task),
      done: task.done === true,
    };
  });

  return {
    today: total,
    done: done,
    overdue: overdue,
    percent: percent,
    items: items,
  };
}

/* ------------------------------------------------------------------ *
 * 任务级便捷写入（编辑页 / 勾选）
 * ------------------------------------------------------------------ */

function deleteTask(id) {
  const data = load();
  const target = str(id);
  const next = data.tasks.filter(function (task) {
    return task.id !== target;
  });
  if (next.length === data.tasks.length) return data;
  data.tasks = next;
  return save(data) || load();
}

module.exports = {
  load: load,
  save: save,
  sync: sync,
  summary: summary,
  deleteTask: deleteTask,
};