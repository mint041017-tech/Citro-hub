// 全局门禁：协议同意 + 登录。
// 四个 tab 页共用：未同意先同意，未登录先登录，都满足后触发 ready。
// 已登录用户先用本地缓存放行，再在后台用 /api/auth/me 校验；失效则触发 expired。
const api = require("../../utils/api");
const session = require("../../utils/session");

// 与 trash.js 的注册校验保持一致
const NAME_RE = /^[一-龥A-Za-z0-9_]{2,16}$/;
const PHONE_RE = /^1[3-9]\d{9}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const FIELDS = {
  account: "account",
  name: "name",
  password: "password",
  confirm: "confirm",
};

function accountBody(account) {
  const a = String(account || "").trim();
  return EMAIL_RE.test(a)
    ? { email: a.toLowerCase() }
    : { phone: a.replace(/\D/g, "") };
}

Component({
  data: {
    stage: "loading", // loading | consent | auth | ready
    agreeChecked: false,
    mode: "login", // login | register
    account: "",
    name: "",
    password: "",
    confirm: "",
    busy: false,
    error: "",
  },

  lifetimes: {
    attached() {
      this.boot();
    },
  },

  methods: {
    boot() {
      if (!session.hasAgreed()) {
        this.setData({ stage: "consent", error: "" });
        return;
      }
      const cached = session.token() ? session.user() : null;
      if (cached) {
        this.finish(cached);
        this.verify();
        return;
      }
      this.setData({ stage: "auth", error: "" });
    },

    verify() {
      const token = session.token();
      if (!token) return;
      api
        .authMe(token)
        .then((res) => {
          const u = res && res.user;
          if (!u || !u.name) {
            session.clear();
            this.setData({
              stage: "auth",
              mode: "login",
              error: "登录已过期，请重新登录",
            });
            this.triggerEvent("expired");
            return;
          }
          const user = { name: u.name, av: u.av || "" };
          session.save(token, user);
          this.triggerEvent("user", { user });
        })
        .catch(() => {
          // 网络异常时保留本地会话，离线数据仍可用。
        });
    },

    finish(user) {
      this.setData({ stage: "ready", error: "" });
      this.triggerEvent("ready", { user });
    },

    onToggleAgree() {
      this.setData({ agreeChecked: !this.data.agreeChecked });
    },

    onOpenDoc(e) {
      const type = e && e.currentTarget && e.currentTarget.dataset.type;
      wx.navigateTo({
        url:
          "/pages/agreement/agreement?type=" +
          (type === "privacy" ? "privacy" : "terms"),
      });
    },

    onAcceptAgree() {
      if (!this.data.agreeChecked) {
        wx.showToast({ title: "请先勾选同意", icon: "none" });
        return;
      }
      session.saveAgreement();
      const cached = session.token() ? session.user() : null;
      if (cached) {
        this.finish(cached);
        this.verify();
        return;
      }
      this.setData({
        stage: "auth",
        agreeChecked: false,
        mode: "login",
        error: "",
      });
    },

    onMode(e) {
      const mode = e && e.currentTarget && e.currentTarget.dataset.mode;
      if (mode !== "login" && mode !== "register") return;
      this.setData({
        mode,
        error: "",
        password: "",
        confirm: "",
      });
    },

    onInput(e) {
      const field = e && e.currentTarget && e.currentTarget.dataset.field;
      const key = FIELDS[field];
      if (!key) return;
      const payload = { error: "" };
      payload[key] = (e.detail && e.detail.value) || "";
      this.setData(payload);
    },

    validate() {
      const mode = this.data.mode;
      const account = String(this.data.account || "").trim();
      const password = String(this.data.password || "");
      if (!account) return "请填写手机号或邮箱";
      if (!EMAIL_RE.test(account)) {
        const phone = account.replace(/\D/g, "");
        if (!PHONE_RE.test(phone)) return "请填写正确的邮箱或 11 位手机号";
      }
      if (mode === "register") {
        const name = String(this.data.name || "").trim();
        if (!NAME_RE.test(name)) return "昵称需 2-16 位中英文/数字/下划线";
        if (name.indexOf("游客") === 0) return "昵称不能以「游客」开头";
        if (name === "CiCi") return "该昵称不可用";
        if (password.length < 6 || password.length > 32) return "密码需 6-32 位";
        if (String(this.data.confirm || "") !== password)
          return "两次输入的密码不一致";
      } else if (!password) {
        return "请填写密码";
      }
      return "";
    },

    async onSubmit() {
      if (this.data.busy) return;
      if (!session.hasAgreed()) {
        this.setData({ stage: "consent", agreeChecked: false });
        return;
      }
      const err = this.validate();
      if (err) {
        this.setData({ error: err });
        return;
      }
      this.setData({ busy: true, error: "" });
      try {
        let res;
        if (this.data.mode === "register") {
          res = await api.register(
            Object.assign(accountBody(this.data.account), {
              name: String(this.data.name || "").trim(),
              password: this.data.password,
            })
          );
        } else {
          res = await api.login(
            String(this.data.account || "").trim(),
            this.data.password
          );
        }
        const token = res && res.token;
        const u = res && res.user;
        if (!token || !u || !u.name) {
          throw new api.ApiError("登录失败，请重试", 0, null);
        }
        const user = { name: u.name, av: u.av || "" };
        session.save(token, user);
        this.setData({
          busy: false,
          password: "",
          confirm: "",
        });
        wx.showToast({ title: "登录成功", icon: "none" });
        this.finish(user);
      } catch (e) {
        this.setData({
          busy: false,
          error: (e && e.message) || "登录失败，请重试",
        });
      }
    },
  },
});