// 本地优先 store 共用的存储与类型兜底工具。
// 只封装 wx.getStorageSync / wx.setStorageSync 的容错与归一化；
// 各 store 的快照字段结构、本地缓存 key 名与值形状保持不变。

// 两位补零：月份 / 日期 / 分秒展示共用。
function pad2(n) {
  return n < 10 ? "0" + n : String(n);
}

// 数字兜底：有限数字取整；非空字符串按 parseInt 解析；否则返回 fallback。
function asInt(value, fallback) {
  if (typeof value === "number" && isFinite(value)) return Math.floor(value);
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = parseInt(value, 10);
    if (!isNaN(parsed)) return parsed;
  }
  return fallback;
}

// 容错读取本地快照：字符串尝试 JSON.parse，对象原样返回；其余 / 异常返回 null。
function readJson(key) {
  let stored = null;
  try {
    stored = wx.getStorageSync(key);
  } catch (e) {
    stored = null;
  }
  if (typeof stored === "string" && stored) {
    try {
      return JSON.parse(stored);
    } catch (e) {
      return null;
    }
  }
  if (stored && typeof stored === "object") return stored;
  return null;
}

// 容错读取时间戳；coerce 为各 store 自己的数值兜底函数，异常时返回 0。
function readAt(atKey, coerce) {
  try {
    return coerce(wx.getStorageSync(atKey), 0);
  } catch (e) {
    return 0;
  }
}

// 容错写单个 key；本地写失败不阻断后续云端推送。
function write(key, value) {
  try {
    wx.setStorageSync(key, value);
  } catch (e) {
    // 忽略：与原 store 的本地写失败兜底一致。
  }
}

// 批量写：快照 + 时间戳；返回主快照是否写入成功（todo 编辑页据此提示保存失败）。
function writePair(storageKey, atKey, snap, at) {
  let ok = true;
  try {
    wx.setStorageSync(storageKey, snap);
  } catch (e) {
    ok = false;
  }
  try {
    wx.setStorageSync(atKey, at);
  } catch (e) {
    // 时间戳写失败不影响主数据，下次保存会再次更新。
  }
  return ok;
}

module.exports = {
  pad2: pad2,
  asInt: asInt,
  readJson: readJson,
  readAt: readAt,
  write: write,
  writePair: writePair,
};
