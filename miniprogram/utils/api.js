// 后端接口封装
// 与 Flutter 端 flutter/lib/services/api.dart 使用同一个 base，接口契约完全一致。
// 登录态走 X-Trash-Token 头（服务端 currentUser 支持 Cookie 与这个头两种来源）。
const BASE = "https://chimu-claw.xyz/trashapi";

class ApiError extends Error {
  constructor(message, code, body) {
    super(message);
    this.name = "ApiError";
    this.code = code || 0;
    this.body = body || null;
  }
}

function queryString(params) {
  if (!params) return "";
  const parts = [];
  Object.keys(params).forEach((key) => {
    const v = params[key];
    if (v === undefined || v === null || v === "") return;
    parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(v));
  });
  return parts.length ? "?" + parts.join("&") : "";
}

function request(method, path, options) {
  const opts = options || {};
  return new Promise((resolve, reject) => {
    const header = { Accept: "application/json" };
    if (opts.data) header["Content-Type"] = "application/json";
    if (opts.token) header["X-Trash-Token"] = opts.token;
    wx.request({
      url: BASE + path + queryString(opts.query),
      method,
      data: opts.data,
      timeout: opts.timeout || 20000,
      header,
      success(res) {
        let body = res.data;
        if (typeof body === "string") {
          try {
            body = JSON.parse(body);
          } catch (e) {
            body = null;
          }
        }
        const ok =
          res.statusCode >= 200 &&
          res.statusCode < 300 &&
          body &&
          typeof body === "object";
        if (ok) {
          resolve(body);
          return;
        }
        const message =
          (body && (body.err || body.error)) ||
          "请求失败（" + res.statusCode + "）";
        reject(
          new ApiError(
            message,
            res.statusCode,
            body && typeof body === "object" ? body : null
          )
        );
      },
      fail() {
        reject(new ApiError("网络连接失败，请检查网络", 0, null));
      },
    });
  });
}

/* ---------------- 账号 ---------------- */

function authMe(token) {
  return request("GET", "/api/auth/me", { token });
}

function login(account, password) {
  return request("POST", "/api/auth/login", {
    data: { account, password },
  });
}

function register(payload) {
  return request("POST", "/api/auth/register", { data: payload });
}

function logout(token) {
  return request("POST", "/api/auth/logout", {
    data: { token },
    token,
  });
}

function profile(token, payload) {
  return request("POST", "/api/auth/profile", { data: payload, token });
}

function updateAvatar(token, dataUrl) {
  return request("POST", "/api/auth/avatar", {
    data: { img: dataUrl },
    token,
    timeout: 30000,
  });
}

function deleteAccount(token, password) {
  return request("POST", "/api/auth/delete", {
    data: { password },
    token,
  });
}

/* ---------------- 玩法抽签 ---------------- */

// 登录后不传 deviceId：服务端优先按账号记账（u:昵称）。
// 调用的 token 失效时会返回 400「缺少身份标识」，前端据此要求重新登录。
function playRecords(token) {
  return request("GET", "/api/play", { token });
}

function playDraw(token) {
  return request("POST", "/api/play", { data: {}, token });
}

/* ---------------- 首页：摸鱼配置 ---------------- */

function moyuGet(token) {
  return request("GET", "/api/moyu/config", { token });
}

function moyuSave(token, config) {
  return request("PUT", "/api/moyu/config", {
    data: { config },
    token,
  });
}

/* ---------------- 计划：待办 / 日历 / 记账 ---------------- */

function todoGet(token) {
  return request("GET", "/api/todo", { token });
}

function todoSave(token, todo) {
  return request("POST", "/api/todo", { data: { todo }, token });
}

function calendarGet(token) {
  return request("GET", "/api/calendar", { token });
}

function calendarSave(token, calendar) {
  return request("POST", "/api/calendar", {
    data: { calendar },
    token,
  });
}

function ledgerGet(token) {
  return request("GET", "/api/ledger", { token });
}

function ledgerSave(token, ledger) {
  return request("POST", "/api/ledger", {
    data: { ledger },
    token,
  });
}

/* ---------------- 举报（UGC） ---------------- */

// type: post | comment | recipe | user；食谱使用 {type:"recipe", recipeId, reason, detail}
function report(token, payload) {
  return request("POST", "/api/report", {
    data: payload || {},
    token,
  });
}

/* ---------------- 首页：食谱日记 ---------------- */

function cookData(token) {
  return request("GET", "/api/cook", { token });
}

function cookSquare(token) {
  return request("GET", "/api/cook/square", { token });
}

function cookSaveRecipe(token, recipe) {
  return request("POST", "/api/cook/recipe", {
    data: { recipe },
    token,
  });
}

function cookDeleteRecipe(token, id) {
  return request("POST", "/api/cook/recipe/delete", {
    data: { id },
    token,
  });
}

function cookImage(token, dataUrl) {
  return request("POST", "/api/cook/img", {
    data: { img: dataUrl },
    token,
    timeout: 30000,
  });
}

function cookSaveShopping(token, shopping) {
  return request("POST", "/api/cook/shopping", {
    data: { shopping },
    token,
  });
}

function cookSaveFridge(token, fridge) {
  return request("POST", "/api/cook/fridge", {
    data: { fridge },
    token,
  });
}

module.exports = {
  BASE,
  ApiError,
  authMe,
  login,
  register,
  logout,
  profile,
  updateAvatar,
  deleteAccount,
  playRecords,
  playDraw,
  moyuGet,
  moyuSave,
  todoGet,
  todoSave,
  calendarGet,
  calendarSave,
  ledgerGet,
  ledgerSave,
  report,
  cookData,
  cookSquare,
  cookSaveRecipe,
  cookDeleteRecipe,
  cookImage,
  cookSaveShopping,
  cookSaveFridge,
};