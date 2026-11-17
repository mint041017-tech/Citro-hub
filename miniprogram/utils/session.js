// 登录会话
// 与 App 端共用同一套账号：登录 / 注册返回的 token 存在本地，
// 之后所有请求带上 X-Trash-Token，服务端据此把记录归到账号（u:昵称）。
const TOKEN_KEY = "citro_token";
const USER_KEY = "citro_user";
// 协议同意记录：记录同意的版本与时间。条款有实质修改时提升版本号，
// 老用户下次进入会重新看到同意浮层。
const AGREEMENT_KEY = "citro_agreement";
const AGREEMENT_VERSION = "2026-11-17-tabs";

function token() {
  const v = wx.getStorageSync(TOKEN_KEY);
  return typeof v === "string" ? v : "";
}

function user() {
  const v = wx.getStorageSync(USER_KEY);
  if (v && typeof v === "object" && typeof v.name === "string" && v.name) {
    return { name: v.name, av: typeof v.av === "string" ? v.av : "" };
  }
  return null;
}

function save(tok, usr) {
  if (!tok) return false;
  wx.setStorageSync(TOKEN_KEY, tok);
  wx.setStorageSync(USER_KEY, {
    name: (usr && usr.name) || "",
    av: (usr && usr.av) || "",
  });
  return true;
}

function clear() {
  // 只清登录态；协议同意记录独立保留，退出登录不需要重新同意。
  wx.removeStorageSync(TOKEN_KEY);
  wx.removeStorageSync(USER_KEY);
}

function agreement() {
  const v = wx.getStorageSync(AGREEMENT_KEY);
  if (v && typeof v === "object") {
    return {
      version: typeof v.version === "string" ? v.version : "",
      at: Number(v.at) || 0,
    };
  }
  return { version: "", at: 0 };
}

function hasAgreed() {
  return agreement().version === AGREEMENT_VERSION;
}

function saveAgreement() {
  wx.setStorageSync(AGREEMENT_KEY, {
    version: AGREEMENT_VERSION,
    at: Date.now(),
  });
}

module.exports = {
  token,
  user,
  save,
  clear,
  agreement,
  hasAgreed,
  saveAgreement,
  AGREEMENT_VERSION,
};