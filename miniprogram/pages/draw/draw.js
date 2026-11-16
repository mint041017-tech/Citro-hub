// 玩法抽签 · 小程序端
// 对应 flutter/lib/pages/play_page.dart 与 trash/trash.js 的 /api/play。
// 首次进入必须先登录（与 App 共用同一套账号）；登录后抽签记录归到账号（u:昵称）。
// 关键顺序和 Flutter 端一致：点击瞬间先 POST 落库，动画只负责揭晓服务端发回的签。
const api = require("../../utils/api");
const { PUNS } = require("../../utils/puns");
const session = require("../../utils/session");

const STAGE_IDLE = "点击「开始抽取」，命运交给橘子";
const POLL_MS = 10000;

// 与 trash.js 的注册校验保持一致
const NAME_RE = /^[一-龥A-Za-z0-9_]{2,16}$/;
const PHONE_RE = /^1[3-9]\d{9}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const AUTH_FIELDS = {
  account: "authAccount",
  name: "authName",
  password: "authPassword",
  confirm: "authConfirm",
};

function accountBody(account) {
  const a = String(account || "").trim();
  return EMAIL_RE.test(a)
    ? { email: a.toLowerCase() }
    : { phone: a.replace(/\D/g, "") };
}

function timeText(ts) {
  const d = new Date(ts || 0);
  const pad = (n) => String(n).padStart(2, "0");
  return (
    d.getMonth() +
    1 +
    "/" +
    d.getDate() +
    " " +
    pad(d.getHours()) +
    ":" +
    pad(d.getMinutes())
  );
}

// 签面长度差得多（最短 5 字，最长近 60 字），分四档字号保证卡片放得下。
function stageClassFor(text) {
  const len = Array.from(text || "").length;
  if (len <= 14) return "stage-short";
  if (len <= 24) return "stage-medium";
  if (len <= 36) return "stage-long";
  return "stage-xlong";
}

Page({
  data: {
    stageText: STAGE_IDLE,
    stageClass: "stage-short",
    rolling: false,
    lastPun: "",
    records: [],
    loading: true,
    error: "",
    // syncing | offline | empty | list
    viewState: "syncing",

    // 登录门禁
    user: null,
    authGate: false,
    authMode: "login", // login | register
    authAccount: "",
    authName: "",
    authPassword: "",
    authConfirm: "",
    authBusy: false,
    authError: "",
  },

  onLoad() {
    this.destroyed = false;
    this.busy = false;
    this.cancelRoll = false;
    this.remoteVersion = 0;
    this._rollTimer = null;

    // 有本地缓存就先放行，再用 /api/auth/me 校验 token 是否仍然有效。
    const cached = session.token() ? session.user() : null;
    this.user = cached;
    this.setData({
      user: cached,
      authGate: !cached,
      authMode: "login",
    });
    this.restoreSession();
  },

  onShow() {
    this.startPolling();
    // 全站记录本身是公开的，未登录也先拉一份，登录后立即有数据。
    this.refresh({ silent: this.data.viewState === "list" });
  },

  onHide() {
    this.stopPolling();
  },

  onUnload() {
    this.destroyed = true;
    this.stopPolling();
    if (this._rollTimer) {
      clearTimeout(this._rollTimer);
      this._rollTimer = null;
    }
  },

  onPullDownRefresh() {
    this.refresh({ silent: false }).finally(() => {
      wx.stopPullDownRefresh();
    });
  },

  /* ---------------- 登录状态 ---------------- */

  async restoreSession() {
    const token = session.token();
    if (!token) {
      this.user = null;
      this.setData({ user: null, authGate: true, authMode: "login" });
      return;
    }
    try {
      const res = await api.authMe(token);
      const u = res && res.user;
      if (!u || !u.name) {
        this.expireSession("登录已过期，请重新登录");
        return;
      }
      const user = { name: u.name, av: u.av || "" };
      session.save(token, user);
      this.user = user;
      this.setData({ user, authGate: false, authError: "" });
      this.refresh({ silent: true });
    } catch (e) {
      // 网络不通时：本地有缓存会话就继续用；没有就停在登录门禁。
      this.setData({
        authGate: !this.user,
        authError: this.user ? "" : "暂时连不上服务器，请检查网络后重试",
      });
    }
  },

  expireSession(message) {
    session.clear();
    this.user = null;
    this.setData({
      user: null,
      authGate: true,
      authMode: "login",
      authError: message || "登录已过期，请重新登录",
      authPassword: "",
      authConfirm: "",
    });
  },

  /* ---------------- 登录表单 ---------------- */

  onAuthMode(e) {
    const mode = e && e.currentTarget && e.currentTarget.dataset.mode;
    if (mode !== "login" && mode !== "register") return;
    this.setData({
      authMode: mode,
      authError: "",
      authPassword: "",
      authConfirm: "",
    });
  },

  onAuthInput(e) {
    const field = e && e.currentTarget && e.currentTarget.dataset.field;
    const key = AUTH_FIELDS[field];
    if (!key) return;
    const value = (e && e.detail && e.detail.value) || "";
    const patch = { authError: "" };
    patch[key] = value;
    this.setData(patch);
  },

  validateAuth() {
    const mode = this.data.authMode;
    const account = String(this.data.authAccount || "").trim();
    const password = String(this.data.authPassword || "");
    if (!account) return "请填写手机号或邮箱";
    if (!EMAIL_RE.test(account)) {
      const phone = account.replace(/\D/g, "");
      if (!PHONE_RE.test(phone)) return "请填写正确的邮箱地址或 11 位手机号";
    }
    if (mode === "register") {
      const name = String(this.data.authName || "").trim();
      if (!NAME_RE.test(name)) return "昵称需 2-16 位，中英文/数字/下划线";
      if (name.indexOf("游客") === 0) return "昵称不能以「游客」开头";
      if (name === "CiCi") return "该昵称不可用";
      if (password.length < 6 || password.length > 32) return "密码需 6-32 位";
      if (String(this.data.authConfirm || "") !== password)
        return "两次输入的密码不一致";
    } else if (!password) {
      return "请填写密码";
    }
    return "";
  },

  async onAuthSubmit() {
    if (this.data.authBusy) return;
    const err = this.validateAuth();
    if (err) {
      this.setData({ authError: err });
      return;
    }
    this.setData({ authBusy: true, authError: "" });
    const mode = this.data.authMode;
    try {
      let res;
      if (mode === "register") {
        res = await api.register(
          Object.assign(accountBody(this.data.authAccount), {
            name: String(this.data.authName || "").trim(),
            password: this.data.authPassword,
          })
        );
      } else {
        res = await api.login(
          String(this.data.authAccount || "").trim(),
          this.data.authPassword
        );
      }
      const token = res && res.token;
      const u = res && res.user;
      if (!token || !u || !u.name) {
        throw new api.ApiError("登录失败，请重试", 0, null);
      }
      const user = { name: u.name, av: u.av || "" };
      session.save(token, user);
      this.user = user;
      this.setData({
        user,
        authGate: false,
        authBusy: false,
        authError: "",
        authPassword: "",
        authConfirm: "",
      });
      wx.showToast({ title: "登录成功", icon: "none" });
      this.refresh({ silent: true });
    } catch (e) {
      this.setData({
        authBusy: false,
        authError: (e && e.message) || "登录失败，请重试",
      });
    }
  },

  onLogout() {
    const token = session.token();
    const self = this;
    wx.showModal({
      title: "退出登录",
      content: "退出后需要重新登录才能抽签。",
      confirmText: "退出",
      confirmColor: "#B05A4A",
      success(res) {
        if (!res.confirm) return;
        if (token) api.logout(token).catch(() => {});
        session.clear();
        self.user = null;
        self.setData({
          user: null,
          authGate: true,
          authMode: "login",
          authAccount: "",
          authPassword: "",
          authConfirm: "",
          authError: "",
        });
        self.refresh({ silent: true }); // 刷掉列表里的「你」标记
      },
    });
  },

  noop() {},

  /* ---------------- 全站记录 ---------------- */

  startPolling() {
    this.stopPolling();
    this.pollTimer = setInterval(() => {
      if (this.data.rolling || this.busy) return;
      this.refresh({ silent: true });
    }, POLL_MS);
  },

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  },

  mapRecords(list) {
    return (Array.isArray(list) ? list : [])
      .slice(0, 20)
      .map((r, i) => {
        const name = String((r && r.name) || "游客").trim() || "游客";
        const chars = Array.from(name);
        return {
          key: String((r && r.ts) || 0) + "-" + i,
          text: String((r && r.t) || "").trim(),
          name,
          you: !!(r && r.you),
          initial: chars.length ? chars[chars.length - 1] : "?",
          timeText: timeText(Number((r && r.ts) || 0)),
        };
      })
      .filter((r) => r.text);
  },

  applyRemote(body) {
    if (this.destroyed) return;
    const records = this.mapRecords(body && body.records);
    this.setData({
      records,
      loading: false,
      error: "",
      viewState: records.length ? "list" : "empty",
    });
  },

  async refresh(options) {
    const silent = !!(options && options.silent);
    if (this.busy) return;
    this.busy = true;
    const version = this.remoteVersion;
    if (!silent) this.setData({ loading: true, error: "" });

    try {
      const body = await api.playRecords(session.token());
      if (this.destroyed) return;
      // POST 已经带回了更新的全站快照：这份旧 GET 直接丢弃。
      if (version !== this.remoteVersion) {
        if (!silent) this.setData({ loading: false });
        return;
      }
      this.applyRemote(body);
    } catch (e) {
      if (this.destroyed) return;
      this.setData({
        loading: false,
        error: (e && e.message) || "网络连接失败",
        viewState: this.data.records.length ? "list" : "offline",
      });
    } finally {
      this.busy = false;
    }
  },

  /* ---------------- 抽取 ---------------- */

  // 所有异常都在这里吃掉；429 只可能是防刷限流，按普通错误提示。
  // 登录 token 失效时服务端返回 400「缺少身份标识」，据此要求重新登录。
  async postDraw() {
    try {
      const body = await api.playDraw(session.token());
      return { body };
    } catch (e) {
      const limited = !!(e && e.code === 429);
      const body = limited && e.body ? e.body : null;
      const expired = !!(
        e &&
        e.code === 400 &&
        String(e.message || "").indexOf("身份标识") >= 0
      );
      return {
        error: (e && e.message) || "网络连接失败，请检查网络",
        rateLimited: limited,
        sessionExpired: expired,
        body,
      };
    }
  },

  rollAnimation() {
    const seq = [];
    for (let i = 0; i < 16; i++) {
      seq.push(PUNS[Math.floor(Math.random() * PUNS.length)]);
    }
    return new Promise((resolve) => {
      let i = 0;
      const step = () => {
        if (!this.destroyed && !this.cancelRoll && i < seq.length) {
          const text = seq[i];
          this.setData({ stageText: text, stageClass: stageClassFor(text) });
          const delay = 55 + i * 6;
          i += 1;
          this._rollTimer = setTimeout(step, delay);
          return;
        }
        resolve();
      };
      step();
    });
  },

  async onDraw() {
    if (!this.user) {
      this.setData({ authGate: true });
      return;
    }
    if (this.data.rolling) {
      // 再点一次只是提前结束揭晓动画；POST 已经在路上，抽签不会丢。
      this.cancelRoll = true;
      return;
    }

    this.cancelRoll = false;
    this.setData({
      rolling: true,
      stageText: "正在抽取…",
      stageClass: "stage-short",
    });

    // 先发请求、再播动画。
    const pending = this.postDraw();
    let settled = false;
    pending.then(
      () => {
        settled = true;
      },
      () => {
        settled = true;
      }
    );

    await this.rollAnimation();
    if (this.destroyed) return;
    if (!settled) {
      // 别把最后一帧的随机签当成抽到的签。
      this.setData({ stageText: "正在记录这次抽签…" });
    }

    const out = await pending;
    if (this.destroyed) return;

    if (out.sessionExpired) {
      this.setData({ rolling: false, stageText: "登录已过期，请重新登录" });
      this.expireSession("登录已过期，请重新登录");
      return;
    }

    const body = out.body || null;
    const text = String((body && body.t) || "").trim();

    if (!text) {
      // 429 可能仍带一份全站快照：先刷新列表，再报错。
      if (body && Array.isArray(body.records)) this.applyRemote(body);
      const msg =
        out.error || (body && body.err) || "云端抽签失败，请稍后重试";
      this.setData({
        rolling: false,
        stageText: out.rateLimited
          ? "操作太频繁，稍后再试"
          : "抽签失败，请联网后重试",
        error: msg,
        viewState: this.data.records.length ? "list" : "offline",
      });
      wx.showToast({ title: msg, icon: "none" });
      this.refresh({ silent: true });
      return;
    }

    // POST 已返回最新全站快照，用它刷新「大家的抽签」。
    this.remoteVersion += 1;
    this.setData({
      rolling: false,
      stageText: text,
      stageClass: stageClassFor(text),
      lastPun: text,
    });
    this.applyRemote(body);
  },

  /* ---------------- 交互 ---------------- */

  onRefresh() {
    wx.showToast({ title: "正在刷新云端抽签记录", icon: "none" });
    this.refresh({ silent: false });
  },

  onShareAppMessage() {
    const pun = this.data.lastPun;
    return {
      title: pun ? "我抽到了：" + pun : "无畏契约 · 玩法抽签",
      path: "/pages/draw/draw",
    };
  },

  onShareTimeline() {
    return {
      title: this.data.lastPun || "无畏契约 · 玩法抽签",
    };
  },
});