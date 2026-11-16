// 登录会话
// 与 App 端共用同一套账号：登录 / 注册返回的 token 存在本地，
// 之后所有请求带上 X-Trash-Token，服务端据此把记录归到账号（u:昵称）。
const TOKEN_KEY = "citro_token";
const USER_KEY = "citro_user";

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
  wx.removeStorageSync(TOKEN_KEY);
  wx.removeStorageSync(USER_KEY);
}

module.exports = { token, user, save, clear };