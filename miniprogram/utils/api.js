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

function request(method, path, options) {
  const opts = options || {};
  return new Promise((resolve, reject) => {
    const header = { Accept: "application/json" };
    if (opts.data) header["Content-Type"] = "application/json";
    if (opts.token) header["X-Trash-Token"] = opts.token;
    wx.request({
      url: BASE + path,
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

/* ---------------- 玩法抽签 ---------------- */

// 登录后不传 deviceId：服务端优先按账号记账（u:昵称）。
// 调用的 token 失效时会返回 400「缺少身份标识」，前端据此要求重新登录。
function playRecords(token) {
  return request("GET", "/api/play", { token });
}

function playDraw(token) {
  return request("POST", "/api/play", { data: {}, token });
}

module.exports = {
  BASE,
  ApiError,
  authMe,
  login,
  register,
  logout,
  playRecords,
  playDraw,
};