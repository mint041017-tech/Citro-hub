// 玩法 · 小程序端
// 对应 flutter/lib/pages/play_page.dart 与 trash/trash.js 的 /api/play。
// 四个 tab 共用全页登录门禁：未同意先同意，未登录先登录，ready 后再拉取与抽取。
// 关键顺序和 Flutter 端一致：点击瞬间先 POST 落库，动画只负责揭晓服务端发回的结果。
const api = require("../../utils/api");
const { PUNS } = require("../../utils/puns");
const session = require("../../utils/session");

const STAGE_IDLE = "点击「随机抽取」，给这局挑个玩法";
const POLL_MS = 10000;

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

// 玩法文案长度差得多（最短 5 字，最长近 60 字），分四档字号保证卡片放得下。
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

    ready: false,
    user: null,
  },

  onLoad() {
    this.destroyed = false;
    this.busy = false;
    this.cancelRoll = false;
    this.remoteVersion = 0;
    this._rollTimer = null;
    // 有本地会话时先展示昵称，门禁组件会立即放行并在后台校验。
    this.setData({ user: session.user() });
  },

  onShow() {
    this.syncGate();
    if (!this.data.ready) return;
    this.startPolling();
    this.refresh({ silent: this.data.viewState === "list" });
  },

  // 在「我的」退出登录后回到本页，需要收回门禁与旧记录。
  syncGate() {
    const gate = this.selectComponent("#gate");
    if (!gate) return;
    if (!session.token() && this.data.ready) {
      this.onGateExpired();
      if (typeof gate.boot === "function") gate.boot();
      return;
    }
    if (
      session.token() &&
      gate.data &&
      gate.data.stage === "auth" &&
      typeof gate.boot === "function"
    ) {
      gate.boot();
    }
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
    if (!this.data.ready) {
      wx.stopPullDownRefresh();
      return;
    }
    this.refresh({ silent: false }).finally(() => {
      wx.stopPullDownRefresh();
    });
  },

  /* ---------------- 全页登录门禁 ---------------- */

  onGateReady(e) {
    const user = (e && e.detail && e.detail.user) || null;
    this.setData({ ready: true, user });
    this.startPolling();
    this.refresh({ silent: false });
  },

  onGateUser(e) {
    const user = (e && e.detail && e.detail.user) || null;
    if (user) this.setData({ user });
  },

  onGateExpired() {
    this.stopPolling();
    this.setData({
      ready: false,
      user: null,
      records: [],
      loading: false,
      viewState: "syncing",
    });
  },

  onOpenDoc(e) {
    const type = e && e.currentTarget && e.currentTarget.dataset.type;
    wx.navigateTo({
      url:
        "/pages/agreement/agreement?type=" +
        (type === "privacy" ? "privacy" : "terms"),
    });
  },

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
    if (this.busy || !session.token()) return;
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
    if (!this.data.ready || !session.token()) {
      wx.showToast({ title: "请先登录", icon: "none" });
      return;
    }
    if (this.data.rolling) {
      // 再点一次只是提前结束揭晓动画；POST 已经在路上，抽取不会丢。
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
      // 别把最后一帧的随机文案当成抽到的结果。
      this.setData({ stageText: "正在记录这次抽取…" });
    }

    const out = await pending;
    if (this.destroyed) return;

    if (out.sessionExpired) {
      this.setData({ rolling: false, stageText: "登录已过期，请重新登录" });
      session.clear();
      this.setData({ ready: false, user: null });
      return;
    }

    const body = out.body || null;
    const text = String((body && body.t) || "").trim();

    if (!text) {
      if (body && Array.isArray(body.records)) this.applyRemote(body);
      const msg =
        out.error || (body && body.err) || "云端抽取失败，请稍后重试";
      this.setData({
        rolling: false,
        stageText: out.rateLimited
          ? "操作太频繁，稍后再试"
          : "抽取失败，请联网后重试",
        error: msg,
        viewState: this.data.records.length ? "list" : "offline",
      });
      wx.showToast({ title: msg, icon: "none" });
      this.refresh({ silent: true });
      return;
    }

    // POST 已返回最新全站快照，用它刷新「大家的抽取」。
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
    if (!this.data.ready) return;
    wx.showToast({ title: "正在刷新云端记录", icon: "none" });
    this.refresh({ silent: false });
  },

  onShareAppMessage() {
    const pun = this.data.lastPun;
    return {
      title: pun ? "这局这样玩：" + pun : "随机玩法 · 给这局找点乐子",
      path: "/pages/draw/draw",
    };
  },

  onShareTimeline() {
    return {
      title: this.data.lastPun || "随机玩法 · 给这局找点乐子",
    };
  },
});