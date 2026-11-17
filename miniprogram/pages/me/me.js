// 我的 · 小程序端
// 对应 flutter/lib/pages/me_page.dart 的账号与关于部分。
// 协议/登录由全局 login-gate 负责：ready 之前不请求任何账号数据。
const api = require("../../utils/api");
const session = require("../../utils/session");

// 与 trash.js 的注册/改名校验保持一致
const NAME_RE = /^[一-龥A-Za-z0-9_]{2,16}$/;
const VERSION = "0.2.0";
const OVERVIEW_GAP = 1500;

function pad2(n) {
  return n < 10 ? "0" + n : String(n);
}

function monthKeyOf(ts) {
  const d = new Date(Number(ts));
  if (isNaN(d.getTime())) return "";
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1);
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

// 与 utils/ledger-store.js 相同的展示规则：整数元不补小数，金额一律按分计算。
function fmtMoney(cents) {
  const n = Math.max(0, Math.floor(Number(cents) || 0));
  const yuan = Math.floor(n / 100);
  const fen = n % 100;
  const body =
    fen === 0 ? groupDigits(yuan) : groupDigits(yuan) + "." + pad2(fen);
  return "¥" + body;
}

// 服务端返回的 av 是 /api/img/avatars/... 相对路径，与 App 的 Api.imageUrl 一致。
function avatarUrl(av) {
  const path = String(av || "").trim();
  if (!path) return "";
  if (/^https?:\/\//i.test(path)) return path;
  if (path.charAt(0) === "/") return api.BASE + path;
  return api.BASE + "/" + path;
}

function initialOf(name) {
  const chars = Array.from(String(name || ""));
  return chars.length ? chars[0] : "C";
}

Page({
  data: {
    version: VERSION,
    ready: false,

    userName: "",
    userInitial: "C",
    userAv: "",
    avatarUrl: "",
    hasAvatar: false,

    // 数据概览：加载中显示 …，失败显示 —
    statTodo: "…",
    statExpense: "…",
    statCheckin: "…",

    // 昵称编辑
    editing: false,
    editName: "",
    editError: "",
    editBusy: false,

    aboutOpen: false,

    // 注销账号
    deleteOpen: false,
    deletePassword: "",
    deleteError: "",
    deleteBusy: false,
  },

  onLoad() {
    this.alive = true;
    this.lastOverviewAt = 0;
  },

  onShow() {
    if (!this.alive) this.alive = true;

    if (this.data.ready) {
      if (!session.token()) {
        // 在别的页面退出或登录过期：回到本页时收回内容，重新走门禁。
        this.resetPage(true);
        return;
      }
      if (Date.now() - this.lastOverviewAt >= OVERVIEW_GAP) {
        this.refreshOverview();
      }
      return;
    }

    const gate = this.selectComponent("#gate");
    if (
      gate &&
      gate.data &&
      gate.data.stage === "auth" &&
      session.token()
    ) {
      // 可能在其它 tab 刚登录，门禁还停在 auth，让它重新检查本地会话。
      gate.boot();
    }
  },

  onUnload() {
    this.alive = false;
  },

  /* ---------------- 登录门禁 ---------------- */

  onGateReady(e) {
    if (!this.alive) this.alive = true;
    this.setData({ ready: true });
    this.applyUser(e && e.detail && e.detail.user);
    this.refreshOverview();
  },

  onGateUser(e) {
    const user = e && e.detail && e.detail.user;
    if (user && user.name) this.applyUser(user);
  },

  onGateExpired() {
    this.resetPage(false);
  },

  applyUser(user) {
    const name = String((user && user.name) || "").trim();
    const av = user && typeof user.av === "string" ? user.av : "";
    this.setData({
      userName: name || "Citro",
      userInitial: initialOf(name),
      userAv: av,
      avatarUrl: avatarUrl(av),
      hasAvatar: !!av,
    });
  },

  onAvatarError() {
    // 头像加载失败时退回昵称首字，不重试、不打断页面。
    this.setData({ hasAvatar: false });
  },

  /* ---------------- 数据概览 ---------------- */

  refreshOverview() {
    if (!this.data.ready) return Promise.resolve();
    const token = session.token();
    if (!token) return Promise.resolve();
    this.lastOverviewAt = Date.now();
    return Promise.all([
      this.loadTodo(token),
      this.loadLedger(token),
      this.loadCheckin(token),
    ]).catch(() => {});
  },

  loadTodo(token) {
    return api
      .todoGet(token)
      .then((res) => {
        if (!this.alive || !this.data.ready) return;
        const todo = res && res.todo;
        const tasks = todo && Array.isArray(todo.tasks) ? todo.tasks : [];
        let open = 0;
        tasks.forEach((task) => {
          if (task && task.done !== true) open += 1;
        });
        this.setData({ statTodo: String(open) });
      })
      .catch(() => {
        if (!this.alive || !this.data.ready) return;
        this.setData({ statTodo: "—" });
      });
  },

  loadLedger(token) {
    return api
      .ledgerGet(token)
      .then((body) => {
        if (!this.alive || !this.data.ready) return;
        const ledger = body && body.ledger;
        const entries =
          ledger && Array.isArray(ledger.entries) ? ledger.entries : [];
        const now = new Date();
        const key = now.getFullYear() + "-" + pad2(now.getMonth() + 1);
        let expense = 0;
        entries.forEach((entry) => {
          if (!entry || entry.kind === "income") return;
          if (monthKeyOf(entry.occurredAt) !== key) return;
          const amount = Number(entry.amount);
          if (isFinite(amount) && amount > 0) expense += Math.floor(amount);
        });
        this.setData({ statExpense: fmtMoney(expense) });
      })
      .catch(() => {
        if (!this.alive || !this.data.ready) return;
        this.setData({ statExpense: "—" });
      });
  },

  loadCheckin(token) {
    return api
      .checkinStats(token)
      .then((res) => {
        if (!this.alive || !this.data.ready) return;
        const streak = Number(res && res.streak);
        const text =
          isFinite(streak) && streak >= 0
            ? Math.floor(streak) + " 天"
            : "—";
        this.setData({ statCheckin: text });
      })
      .catch(() => {
        if (!this.alive || !this.data.ready) return;
        this.setData({ statCheckin: "—" });
      });
  },

  /* ---------------- 昵称编辑 ---------------- */

  onEditOpen() {
    this.setData({
      editing: true,
      editName: this.data.userName,
      editError: "",
      editBusy: false,
      aboutOpen: false,
      deleteOpen: false,
      deletePassword: "",
      deleteError: "",
    });
  },

  onEditInput(e) {
    this.setData({
      editName: (e && e.detail && e.detail.value) || "",
      editError: "",
    });
  },

  onEditCancel() {
    if (this.data.editBusy) return;
    this.setData({
      editing: false,
      editName: "",
      editError: "",
      editBusy: false,
    });
  },

  onEditSave() {
    if (this.data.editBusy) return;
    const token = session.token();
    if (!token) {
      this.setData({ editError: "登录已过期，请重新登录" });
      return;
    }
    const name = String(this.data.editName || "").trim();
    if (!NAME_RE.test(name)) {
      this.setData({ editError: "昵称需 2-16 位，中英文/数字/下划线" });
      return;
    }
    if (name === this.data.userName) {
      this.onEditCancel();
      return;
    }
    this.setData({ editBusy: true, editError: "" });
    api
      .profile(token, { name })
      .then((res) => {
        if (!this.alive) return;
        const user = res && res.user;
        const next = {
          name: (user && user.name) || name,
          av:
            user && typeof user.av === "string"
              ? user.av
              : this.data.userAv,
        };
        session.save(token, next);
        this.applyUser(next);
        this.setData({
          editing: false,
          editName: "",
          editError: "",
          editBusy: false,
        });
        wx.showToast({ title: "昵称已更新", icon: "none" });
      })
      .catch((e) => {
        if (!this.alive) return;
        this.setData({
          editBusy: false,
          editError: (e && e.message) || "保存失败，请稍后重试",
        });
      });
  },

  /* ---------------- 协议与关于 ---------------- */

  onOpenDoc(e) {
    const type = e && e.currentTarget && e.currentTarget.dataset.type;
    wx.navigateTo({
      url:
        "/pages/agreement/agreement?type=" +
        (type === "privacy" ? "privacy" : "terms"),
    });
  },

  onAboutOpen() {
    this.setData({
      aboutOpen: true,
      editing: false,
      editError: "",
      deleteOpen: false,
      deletePassword: "",
      deleteError: "",
    });
  },

  onAboutClose() {
    this.setData({ aboutOpen: false });
  },

  noop() {},

  /* ---------------- 账号操作 ---------------- */

  onLogout() {
    const token = session.token();
    wx.showModal({
      title: "退出登录",
      content: "退出后需要重新登录才能查看账号数据。",
      confirmText: "退出",
      confirmColor: "#B05A4A",
      success: (res) => {
        if (!res.confirm) return;
        if (token) api.logout(token).catch(() => {});
        session.clear();
        this.resetPage(true);
        wx.switchTab({ url: "/pages/home/home" });
      },
    });
  },

  onDeleteTap() {
    wx.showModal({
      title: "注销账号",
      content: "账号与云端数据将被永久删除，且无法恢复。确定继续吗？",
      confirmText: "继续",
      confirmColor: "#B05A4A",
      success: (res) => {
        if (!res.confirm) return;
        this.setData({
          deleteOpen: true,
          deletePassword: "",
          deleteError: "",
          deleteBusy: false,
          editing: false,
          editError: "",
          aboutOpen: false,
        });
      },
    });
  },

  onDeleteInput(e) {
    this.setData({
      deletePassword: (e && e.detail && e.detail.value) || "",
      deleteError: "",
    });
  },

  onDeleteCancel() {
    if (this.data.deleteBusy) return;
    this.setData({
      deleteOpen: false,
      deletePassword: "",
      deleteError: "",
    });
  },

  onDeleteConfirm() {
    if (this.data.deleteBusy) return;
    const password = String(this.data.deletePassword || "");
    if (!password) {
      this.setData({ deleteError: "请输入登录密码" });
      return;
    }
    const token = session.token();
    if (!token) {
      this.setData({ deleteError: "登录已过期，请重新登录" });
      return;
    }
    this.setData({ deleteBusy: true, deleteError: "" });
    api
      .deleteAccount(token, password)
      .then(() => {
        if (!this.alive) return;
        session.clear();
        this.setData({ deleteBusy: false, deletePassword: "" });
        this.resetPage(true);
        wx.switchTab({ url: "/pages/home/home" });
        wx.showToast({ title: "账号已注销", icon: "none" });
      })
      .catch((e) => {
        if (!this.alive) return;
        this.setData({
          deleteBusy: false,
          deletePassword: "",
          deleteError: (e && e.message) || "注销失败，请稍后重试",
        });
      });
  },

  /* ---------------- 状态清空 ---------------- */

  resetPage(rebootGate) {
    this.lastOverviewAt = 0;
    this.setData({
      ready: false,
      userName: "",
      userInitial: "C",
      userAv: "",
      avatarUrl: "",
      hasAvatar: false,
      statTodo: "—",
      statExpense: "—",
      statCheckin: "—",
      editing: false,
      editName: "",
      editError: "",
      editBusy: false,
      aboutOpen: false,
      deleteOpen: false,
      deletePassword: "",
      deleteError: "",
      deleteBusy: false,
    });
    if (rebootGate) {
      const gate = this.selectComponent("#gate");
      if (gate && typeof gate.boot === "function") gate.boot();
    }
  },
});