// 用户服务协议 / 隐私政策
// 从登录门禁或页面底部进入，可按顶部分页切换两份文档。
const { TERMS, PRIVACY, UPDATED, VERSION } = require("./content");

const DOCS = {
  terms: { title: "用户服务协议", sections: TERMS },
  privacy: { title: "隐私政策", sections: PRIVACY },
};

const NOTE = {
  terms:
    "登录或使用 Citro 小程序即表示你同意本协议。若不同意，请不要注册或使用本小程序。",
  privacy:
    "我们不出售你的个人信息，未接入广告或第三方统计 SDK。抽取记录会在「大家的抽取」中公开显示昵称与玩法文案。",
};

Page({
  data: {
    type: "terms",
    title: "",
    sections: [],
    note: "",
    updated: UPDATED,
    version: VERSION,
  },

  onLoad(options) {
    this.apply((options && options.type) === "privacy" ? "privacy" : "terms");
  },

  apply(type) {
    const doc = DOCS[type] || DOCS.terms;
    this.setData({
      type,
      title: doc.title,
      sections: doc.sections,
      note: NOTE[type],
    });
    wx.setNavigationBarTitle({ title: doc.title });
  },

  onSwitch(e) {
    const type = e && e.currentTarget && e.currentTarget.dataset.type;
    if (type !== "terms" && type !== "privacy") return;
    if (type === this.data.type) return;
    this.apply(type);
    wx.pageScrollTo({ scrollTop: 0, duration: 0 });
  },
});