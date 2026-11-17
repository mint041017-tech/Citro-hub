// 心情 · 小程序端
// 对应 flutter/lib/todo/todo_models.dart 的 MoodKind / MoodEntry 与
// flutter/lib/todo/todo_mood.dart 的记录流程。
// 数据写在本地 citro_todo_v1 的 moods 数组里，统一走 utils/todo-store 同步。
const session = require("../../utils/session");
const todoStore = require("../../utils/todo-store");

// 六档心情的浅色与 Flutter todo_models.dart 的 _lightColors 完全一致。
const MOODS = [
  { key: "happy", label: "开心", color: "#E0A03E" },
  { key: "calm", label: "平静", color: "#8FA6BE" },
  { key: "neutral", label: "一般", color: "#A79E8C" },
  { key: "tired", label: "疲惫", color: "#9A8FA6" },
  { key: "low", label: "低落", color: "#7C8AA0" },
  { key: "anxious", label: "焦虑", color: "#C4855D" },
];

const MOOD_MAP = {};
MOODS.forEach((m) => {
  MOOD_MAP[m.key] = m;
});

const NOTE_MAX = 120;
const HISTORY_DAYS = 30;

function pad2(n) {
  return String(n).padStart(2, "0");
}

function dayKey(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function isDayKey(v) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(v || ""));
}

function dayFromKey(key) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ""));
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return isNaN(d.getTime()) ? null : d;
}

function weekdayText(d) {
  return "周" + "日一二三四五六".charAt(d.getDay());
}

function shortDate(d) {
  return d.getMonth() + 1 + "月" + d.getDate() + "日";
}

function rgba(hex, alpha) {
  const s = String(hex || "").replace("#", "");
  if (s.length !== 6) return "rgba(156, 134, 127, " + alpha + ")";
  const r = parseInt(s.slice(0, 2), 16);
  const g = parseInt(s.slice(2, 4), 16);
  const b = parseInt(s.slice(4, 6), 16);
  return "rgba(" + r + ", " + g + ", " + b + ", " + alpha + ")";
}

function clip(text, max) {
  const chars = Array.from(String(text || "").replace(/\s+/g, " ").trim());
  if (chars.length <= max) return chars.join("");
  return chars.slice(0, max).join("") + "…";
}

function charCount(text) {
  return Array.from(String(text || "")).length;
}

function makeId() {
  return (
    "m" +
    Date.now().toString(36) +
    Math.random().toString(36).slice(2, 7)
  );
}

function validKind(kind) {
  return MOOD_MAP[kind] ? kind : "neutral";
}

// load() 的契约是同步返回整包快照，这里仍兼容返回 Promise 的实现。
function loadStore() {
  return Promise.resolve().then(() => todoStore.load());
}

function normalizeSnapshot(raw) {
  const base =
    raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const next = Object.assign({}, base);
  next.moods = Array.isArray(base.moods)
    ? base.moods.filter((m) => m && typeof m === "object")
    : [];
  return next;
}

function latestOn(snap, date) {
  if (!snap || !Array.isArray(snap.moods)) return null;
  let latest = null;
  let best = -Infinity;
  snap.moods.forEach((m) => {
    if (!m || m.date !== date) return;
    const ts = Number(m.ts);
    const score = isFinite(ts) ? ts : 0;
    if (!latest || score >= best) {
      latest = m;
      best = score;
    }
  });
  return latest;
}

function buildOptions(selectedKind) {
  return MOODS.map((m) => {
    const on = m.key === selectedKind;
    return {
      key: m.key,
      label: m.label,
      on,
      faceClass: "mood-face face-" + m.key,
      circleBg: on ? m.color : rgba(m.color, 0.24),
      faceInk: on ? "#FFF8EC" : "rgba(97, 74, 68, 0.7)",
    };
  });
}

function buildStats(snap) {
  const counts = {};
  MOODS.forEach((m) => {
    counts[m.key] = 0;
  });
  let total = 0;
  const list = snap && Array.isArray(snap.moods) ? snap.moods : [];
  list.forEach((m) => {
    if (!m || !MOOD_MAP[m.kind]) return;
    if (!isDayKey(m.date)) return;
    counts[m.kind] += 1;
    total += 1;
  });
  let max = 1;
  MOODS.forEach((m) => {
    if (counts[m.key] > max) max = counts[m.key];
  });
  const stats = MOODS.map((m) => {
    const count = counts[m.key];
    const width = Math.round((count / max) * 100);
    return {
      key: m.key,
      label: m.label,
      color: m.color,
      count,
      countText: count + " 次",
      barStyle:
        "background:" + m.color + ";width:" + (count > 0 ? width : 0) + "%;",
    };
  });
  return { stats, total };
}

Page({
  data: {
    todayKey: "",
    editingDate: "",
    editingLabel: "今天",
    editingIsToday: true,
    editorTitle: "今日记录",
    editorHint: "记下此刻，之后可以回看。",
    selectedKind: "calm",
    note: "",
    noteLen: 0,
    options: [],
    history: [],
    stats: [],
    hasAnyMood: false,
    statsEmpty: true,
    loading: true,
    loadError: "",
    saveBusy: false,
    saveText: "记下心情",
  },

  onLoad() {
    this.alive = true;
    this.snap = null;
    this.formTouched = false;
    this.saving = false;

    const token = session.token();
    if (!token) {
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    this.token = token;

    const now = new Date();
    const today = dayKey(now);
    this.setData(
      Object.assign(
        {
          todayKey: today,
          editingDate: today,
          loading: true,
        },
        this.derive(null, today, "calm", "")
      )
    );
    this.load();
  },

  onUnload() {
    this.alive = false;
  },

  /* ---------------- 数据读取 ---------------- */

  load() {
    this.setData({ loading: true, loadError: "" });
    return loadStore()
      .then((raw) => {
        if (!this.alive) return;
        this.snap = normalizeSnapshot(raw);
        const today = this.data.todayKey;
        const todayLatest = latestOn(this.snap, today);
        let kind = this.data.selectedKind;
        let note = this.data.note;
        let editingDate = this.data.editingDate || today;
        if (!this.formTouched) {
          editingDate = today;
          kind = todayLatest ? validKind(todayLatest.kind) : "calm";
          note = todayLatest ? String(todayLatest.note || "") : "";
        }
        this.setData(
          Object.assign(
            { loading: false, loadError: "", saveText: "记下心情" },
            this.derive(this.snap, editingDate, kind, note)
          )
        );
      })
      .catch(() => {
        if (!this.alive) return;
        this.setData({
          loading: false,
          loadError: "本地记录暂时读取不到，保存时会再试一次。",
        });
        wx.showToast({ title: "心情记录暂时读取失败", icon: "none" });
      });
  },

  onRetryLoad() {
    this.load();
  },

  /* ---------------- 视图派生 ---------------- */

  // 所有展示字段都在 JS 里算好，WXML 只做插值。
  derive(snap, editingDate, selectedKind, note) {
    const todayKey = this.data.todayKey || dayKey(new Date());
    const date = isDayKey(editingDate) ? editingDate : todayKey;
    const kind = MOOD_MAP[selectedKind] ? selectedKind : "calm";
    const noteText = String(note || "").slice(0, NOTE_MAX);
    const todayDate = dayFromKey(todayKey) || new Date();
    const yesterdayKey = dayKey(
      new Date(
        todayDate.getFullYear(),
        todayDate.getMonth(),
        todayDate.getDate() - 1
      )
    );

    const latestByDate = {};
    const moodList = snap && Array.isArray(snap.moods) ? snap.moods : [];
    moodList.forEach((m) => {
      if (!m || !isDayKey(m.date)) return;
      const ts = Number(m.ts);
      const score = isFinite(ts) ? ts : 0;
      const prev = latestByDate[m.date];
      if (!prev || score >= prev.score) latestByDate[m.date] = { m, score };
    });

    const history = [];
    for (let i = 0; i < HISTORY_DAYS; i += 1) {
      const d = new Date(
        todayDate.getFullYear(),
        todayDate.getMonth(),
        todayDate.getDate() - i
      );
      const key = dayKey(d);
      const picked = latestByDate[key];
      const entry = picked ? picked.m : null;
      const meta = entry ? MOOD_MAP[entry.kind] || MOOD_MAP.neutral : null;
      const noteValue = entry ? String(entry.note || "").trim() : "";
      const dayText =
        key === todayKey
          ? "今天"
          : key === yesterdayKey
          ? "昨天"
          : shortDate(d);
      let rowClass = "history-row";
      if (!entry) rowClass += " empty";
      if (key === date) rowClass += " on";
      history.push({
        key,
        dayText,
        weekText: weekdayText(d),
        has: !!entry,
        dotStyle: meta ? "background:" + meta.color + ";" : "",
        kindLabel: meta ? meta.label : "未记录",
        noteText: entry
          ? noteValue
            ? clip(noteValue, 16)
            : "只记了心情"
          : "点一下补记",
        actionText: key === date ? "已选" : entry ? "编辑" : "补记",
        rowClass,
      });
    }

    const statView = buildStats(snap);
    const editingIsToday = date === todayKey;
    const editDate = dayFromKey(date);
    const editingLabel = editingIsToday
      ? "今天"
      : editDate
      ? shortDate(editDate)
      : "这一天";

    return {
      editingDate: date,
      editingLabel,
      editingIsToday,
      editorTitle: editingIsToday ? "今日记录" : editingLabel + " · 补记",
      editorHint: editingIsToday
        ? "记下此刻，之后可以回看。"
        : "补记或修改这一天的记录。",
      selectedKind: kind,
      note: noteText,
      noteLen: charCount(noteText),
      options: buildOptions(kind),
      history,
      stats: statView.stats,
      hasAnyMood: statView.total > 0,
      statsEmpty: statView.total === 0,
    };
  },

  applyEditing(date, kind, note, scrollTop) {
    this.setData(this.derive(this.snap, date, kind, note));
    if (scrollTop && wx.pageScrollTo) {
      wx.pageScrollTo({ scrollTop: 0, duration: 220 });
    }
  },

  /* ---------------- 交互 ---------------- */

  onSelectKind(e) {
    const kind = e && e.currentTarget && e.currentTarget.dataset.kind;
    if (!MOOD_MAP[kind]) return;
    this.formTouched = true;
    const patch = { selectedKind: kind, options: buildOptions(kind) };
    this.setData(patch);
  },

  onNoteInput(e) {
    const value = String((e && e.detail && e.detail.value) || "").slice(
      0,
      NOTE_MAX
    );
    this.formTouched = true;
    this.setData({ note: value, noteLen: charCount(value) });
  },

  onPickDay(e) {
    const key = e && e.currentTarget && e.currentTarget.dataset.date;
    if (!isDayKey(key)) return;
    const latest = latestOn(this.snap, key);
    this.formTouched = true;
    this.applyEditing(
      key,
      latest ? validKind(latest.kind) : "calm",
      latest ? String(latest.note || "") : "",
      true
    );
  },

  onBackToday() {
    const today = this.data.todayKey;
    const latest = latestOn(this.snap, today);
    this.formTouched = true;
    this.applyEditing(
      today,
      latest ? validKind(latest.kind) : "calm",
      latest ? String(latest.note || "") : "",
      true
    );
  },

  /* ---------------- 保存 ---------------- */

  onSave() {
    if (this.saving) return;
    const kind = this.data.selectedKind;
    if (!MOOD_MAP[kind]) {
      wx.showToast({ title: "先选一个心情", icon: "none" });
      return;
    }
    const date = isDayKey(this.data.editingDate)
      ? this.data.editingDate
      : this.data.todayKey;
    this.saving = true;
    this.setData({ saveBusy: true, saveText: "保存中…" });

    const self = this;
    const startLoad = this.snap
      ? Promise.resolve(this.snap)
      : loadStore().then(normalizeSnapshot);

    startLoad
      .then((snap) => {
        const base = snap && snap.moods ? snap : normalizeSnapshot(snap);
        const moods = base.moods.slice();
        const now = new Date();
        let idx = -1;
        let best = -Infinity;
        for (let i = 0; i < moods.length; i += 1) {
          const m = moods[i];
          if (!m || m.date !== date) continue;
          const ts = Number(m.ts);
          const score = isFinite(ts) ? ts : 0;
          if (idx < 0 || score >= best) {
            idx = i;
            best = score;
          }
        }
        let ts = Date.now();
        if (date !== this.data.todayKey) {
          const d = dayFromKey(date);
          if (d && !isNaN(d.getTime())) {
            d.setHours(
              now.getHours(),
              now.getMinutes(),
              now.getSeconds(),
              now.getMilliseconds()
            );
            ts = d.getTime();
          }
        }
        // 条目严格保持 {id,date,kind,note,ts}，更新已有的那一天而不是重复添加。
        const entry = {
          id: idx >= 0 ? String(moods[idx].id || makeId()) : makeId(),
          date,
          kind,
          note: String(self.data.note || "").slice(0, NOTE_MAX),
          ts,
        };
        if (idx >= 0) moods[idx] = entry;
        else moods.push(entry);
        const next = Object.assign({}, base, { moods });
        const saved = todoStore.save(next);
        if (!saved) throw new Error("本地写入失败");
        return saved;
      })
      .then((next) => {
        if (!self.alive) return;
        self.snap = normalizeSnapshot(next);
        self.formTouched = false;
        self.setData(
          Object.assign(
            { saveBusy: false, saveText: "记下心情", loadError: "" },
            self.derive(
              self.snap,
              self.data.editingDate,
              self.data.selectedKind,
              self.data.note
            )
          )
        );
        wx.showToast({ title: "已记下", icon: "success" });
      })
      .catch(() => {
        if (!self.alive) return;
        // 失败的草稿留在页面上，不清空输入。
        self.setData({
          saveBusy: false,
          saveText: "重新保存",
        });
        wx.showToast({ title: "保存失败，心情还留在页面上", icon: "none" });
      })
      .then(() => {
        self.saving = false;
      });
  },
});