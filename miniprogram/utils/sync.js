// 三个本地优先 store 共用的云端同步样板：登录态解析、响应解包、静默推送。
// 同步时机、last writer wins 判定与离线兜底仍由各 store 自己决定。
const session = require("./session");

// 显式传入的 token 优先；否则取本地登录态。
function resolveToken(token) {
  return token || session.token();
}

// 解包 GET 响应：body[field] 为远程快照（兼容字符串 JSON），body.at 为更新时间戳。
// 返回 { remote, at, hasRemote }；coerce 为各 store 自己的数值兜底函数。
function unwrapRemote(body, field, coerce) {
  let remote = body && body[field];
  if (typeof remote === "string") {
    try {
      remote = JSON.parse(remote);
    } catch (e) {
      remote = null;
    }
  }
  const at = body ? coerce(body.at, 0) : 0;
  const hasRemote =
    !!remote && typeof remote === "object" && !Array.isArray(remote);
  return { remote: remote, at: at, hasRemote: hasRemote };
}

// 静默推送：网络失败 / 同步异常都吞掉，下次保存会整包重试。
function pushSilent(pending) {
  try {
    if (pending && typeof pending.catch === "function") {
      pending.catch(function () {});
    }
  } catch (e) {
    // 同步异常同样静默。
  }
}

module.exports = {
  resolveToken: resolveToken,
  unwrapRemote: unwrapRemote,
  pushSilent: pushSilent,
};
