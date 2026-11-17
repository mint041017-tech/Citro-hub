// 食谱模块的纯函数工具：字段归一化、展示模型、用量拆分、日期文案。
// 字段与 flutter/lib/services/models.dart 的 Recipe / ShoppingItem / FridgeItem
// 以及 trash/trash.js 的 cookPubMine / cookPubSquare 保持一致。
const api = require("../../utils/api");
const BASE = api.BASE;

// 用量单位：与 Flutter 编辑器的单位表思路一致，拆分时按最长后缀匹配。
const AMOUNT_UNITS = [
  "千克",
  "一小把",
  "毫升",
  "汤匙",
  "茶匙",
  "少许",
  "少量",
  "适量",
  "克",
  "斤",
  "两",
  "升",
  "个",
  "只",
  "颗",
  "片",
  "块",
  "根",
  "瓣",
  "张",
  "包",
  "瓶",
  "罐",
  "把",
  "杯",
  "勺",
  "条",
  "袋",
  "盒",
  "束",
];
const FREE_UNITS = ["少许", "适量", "少量", "一小把"];

function text(v, fallback) {
  if (v === undefined || v === null) return fallback || "";
  return String(v).trim();
}

function int(v, min, max, fallback) {
  const n = parseInt(v, 10);
  if (!isFinite(n)) return fallback || 0;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

function list(v) {
  return Array.isArray(v) ? v : [];
}

function pad(n) {
  return n < 10 ? "0" + n : String(n);
}

function imageUrl(path) {
  const p = text(path);
  if (!p) return "";
  if (p.indexOf("http") === 0) return p;
  if (p.charAt(0) === "/") return BASE + p;
  return p;
}

function newId(prefix) {
  return (
    (prefix || "c") +
    Date.now().toString(36) +
    Math.random().toString(36).slice(2, 8)
  );
}

function dateText(ts, full) {
  const n = Number(ts) || 0;
  if (!n) return "";
  const d = new Date(n);
  if (isNaN(d.getTime())) return "";
  const day = pad(d.getMonth() + 1) + "/" + pad(d.getDate());
  return full ? d.getFullYear() + "." + day : day;
}

function todayKey() {
  const d = new Date();
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
}

/* ---------------- 标签 ---------------- */

function splitTags(value) {
  const out = [];
  String(value || "")
    .split(/[,，]+/)
    .forEach(function (raw) {
      const t = text(raw);
      if (t && out.indexOf(t) === -1) out.push(t);
    });
  return out;
}

function cleanTags(raw) {
  const source = typeof raw === "string" ? raw.split(/[,，]+/) : list(raw);
  const out = [];
  source.forEach(function (rawTag) {
    const t = text(rawTag).slice(0, 12);
    if (t && out.indexOf(t) === -1 && out.length < 8) out.push(t);
  });
  return out;
}

/* ---------------- 食材用量 ---------------- */

function parseAmount(raw) {
  const s = text(raw);
  if (!s) return { qty: "", unit: "" };
  if (FREE_UNITS.indexOf(s) >= 0) return { qty: "", unit: s };
  const units = AMOUNT_UNITS.slice().sort(function (a, b) {
    return b.length - a.length;
  });
  for (let i = 0; i < units.length; i++) {
    const u = units[i];
    if (s.length > u.length && s.slice(-u.length) === u) {
      const head = s.slice(0, s.length - u.length).trim();
      if (head) return { qty: head, unit: u };
    }
  }
  // 没有可识别的单位（如「200cc」「半碗」）：整段放在用量里，单位留空。
  return { qty: s, unit: "" };
}

function joinAmount(qty, unit) {
  const q = text(qty);
  const u = text(unit);
  if (u && FREE_UNITS.indexOf(u) >= 0) return u;
  if (q && u) return q + u;
  return q || u;
}

/* ---------------- 归一化 ---------------- */

function normIngredients(raw) {
  const out = [];
  list(raw).forEach(function (it) {
    if (typeof it === "string") {
      const name = text(it);
      if (name) out.push({ name: name, amount: "", group: "main" });
      return;
    }
    const j = it && typeof it === "object" ? it : {};
    const name = text(j.name);
    if (!name) return;
    const group = text(j.group);
    out.push({
      name: name,
      // 以 amount 为准；兼容只有 qty/unit 的旧形状。
      amount: text(j.amount) || joinAmount(j.qty, j.unit),
      group: group === "aux" || group === "season" ? group : "main",
    });
  });
  return out.slice(0, 40);
}

function normSteps(raw) {
  const out = [];
  list(raw).forEach(function (it) {
    let textValue = "";
    let img = "";
    let timer = 0;
    if (it && typeof it === "object") {
      textValue = text(it.text);
      img = text(it.img);
      timer = int(it.timer, 0, 600, 0);
    } else {
      textValue = text(it);
    }
    if (!textValue && !img) return;
    out.push({ text: textValue, img: img, timer: timer });
  });
  return out.slice(0, 40);
}

function normDiary(raw) {
  const out = [];
  list(raw).forEach(function (it) {
    const j = it && typeof it === "object" ? it : {};
    const tweaks = text(j.tweaks);
    const result = text(j.result);
    if (!tweaks && !result) return;
    out.push({
      id: text(j.id),
      date: text(j.date),
      tweaks: tweaks,
      rating: int(j.rating, 0, 5, 0),
      result: result,
      ts: int(j.ts, 0, 4102444800000, 0),
    });
  });
  return out;
}

function normalizeRecipe(raw) {
  const j = raw && typeof raw === "object" ? raw : {};
  return {
    id: text(j.id),
    name: text(j.name) || text(j.title),
    emoji: text(j.emoji),
    tags: cleanTags(j.tags),
    cuisine: text(j.cuisine),
    dishType: text(j.dishType),
    cover: text(j.cover),
    prepMin: int(j.prepMin, 0, 1440, 0),
    cookMin: int(j.cookMin, 0, 1440, 0),
    calories: int(j.calories, 0, 20000, 0),
    source: text(j.source),
    servings: int(j.servings, 0, 99, 0),
    ingredients: normIngredients(j.ingredients),
    steps: normSteps(j.steps),
    note: text(j.note) || text(j.desc),
    diary: normDiary(j.diary),
    visibility: j.visibility === "public" ? "public" : "private",
    createdAt: int(j.createdAt, 0, 4102444800000, 0),
    updatedAt: int(j.updatedAt, 0, 4102444800000, 0),
    owner: text(j.owner) || text(j.author),
    ownerAv: text(j.ownerAv),
    fromOwner: text(j.fromOwner),
    mine: j.mine === true,
    cookCount: int(j.cookCount, 0, 1000000, 0),
  };
}

function normalizeShopping(raw) {
  const out = [];
  list(raw).forEach(function (it) {
    if (typeof it === "string") {
      const s = text(it);
      if (s) out.push({ id: newId("s"), text: s, done: false });
      return;
    }
    const j = it && typeof it === "object" ? it : {};
    const content = text(j.text) || text(j.name);
    if (!content) return;
    out.push({
      id: text(j.id) || newId("s"),
      text: content,
      done: j.done === true,
    });
  });
  return out.slice(0, 100);
}

function normalizeFridge(raw) {
  const out = [];
  list(raw).forEach(function (it) {
    if (typeof it === "string") {
      const s = text(it);
      if (s) {
        out.push({
          id: newId("f"),
          name: s,
          qty: "1",
          unit: "个",
          buyDate: "",
          expDate: "",
        });
      }
      return;
    }
    const j = it && typeof it === "object" ? it : {};
    const name = text(j.name);
    if (!name) return;
    out.push({
      id: text(j.id) || newId("f"),
      name: name,
      qty: text(j.qty) || "1",
      unit: text(j.unit) || "个",
      buyDate: text(j.buyDate),
      expDate: text(j.expDate),
    });
  });
  return out.slice(0, 200);
}

/* ---------------- 展示模型 ---------------- */

function matchRecipe(raw, query) {
  const s = text(query).toLowerCase();
  if (!s) return true;
  const name = text(raw && raw.name).toLowerCase();
  if (name.indexOf(s) >= 0) return true;
  return list(raw && raw.tags).join(" ").toLowerCase().indexOf(s) >= 0;
}

function cardModel(raw, opts) {
  const r = normalizeRecipe(raw);
  const o = opts || {};
  const total = r.prepMin + r.cookMin;
  const note = Array.from(r.note);
  const noteText = note.length > 54 ? note.slice(0, 54).join("") + "…" : r.note;
  const ownerName = r.owner || r.fromOwner;
  let ownerText = "";
  if (o.source === "square") {
    ownerText = "作者 " + (ownerName || "匿名");
  } else if (r.fromOwner) {
    ownerText = "来自 " + r.fromOwner;
  }
  return {
    id: r.id,
    name: r.name || "未命名食谱",
    hasCover: !!r.cover,
    coverUrl: imageUrl(r.cover),
    hasNote: !!noteText,
    note: noteText,
    timeText: total > 0 ? "用时 " + total + " 分钟" : "",
    servingsText: r.servings > 0 ? r.servings + " 人份" : "",
    hasTags: r.tags.length > 0,
    tags: r.tags.slice(0, 3),
    updatedText: r.updatedAt ? dateText(r.updatedAt) + " 更新" : "",
    visibilityText: r.visibility === "public" ? "公开" : "私密",
    visibilityClass: r.visibility === "public" ? "vis-public" : "vis-private",
    showVisibility: o.source !== "square",
    ownerText: ownerText,
    hasOwner: !!ownerText,
    isMine: r.mine,
    isPublic: r.visibility === "public",
  };
}

function detailModel(raw, opts) {
  const r = normalizeRecipe(raw);
  const o = opts || {};
  const me = text(o.meName);
  const total = r.prepMin + r.cookMin;
  const pills = [];
  if (total > 0) pills.push({ key: "time", text: total + " 分钟" });
  if (r.servings > 0) pills.push({ key: "servings", text: r.servings + " 人份" });
  if (r.calories > 0) pills.push({ key: "cal", text: r.calories + " 千卡/100g" });
  if (r.cuisine) pills.push({ key: "cuisine", text: r.cuisine });
  if (r.dishType) pills.push({ key: "dish", text: r.dishType });
  pills.push({
    key: "vis",
    text: r.visibility === "public" ? "公开" : "私密",
  });

  const ingredients = r.ingredients.map(function (it, i) {
    return {
      key: "i" + i,
      name: it.name,
      amount: it.amount,
      hasAmount: !!it.amount,
    };
  });

  const steps = r.steps.map(function (s, i) {
    return {
      key: "s" + i,
      indexText: String(i + 1),
      text: s.text,
      hasText: !!s.text,
      hasImg: !!s.img,
      imgUrl: imageUrl(s.img),
      hasTimer: s.timer > 0,
      timerText: s.timer > 0 ? "约 " + s.timer + " 分钟" : "",
    };
  });

  let authorText = "";
  if (o.source === "square") {
    authorText = "作者 " + (r.owner || "匿名");
  } else if (r.fromOwner) {
    authorText = "来自 " + r.fromOwner;
  } else if (r.owner) {
    authorText = "作者 " + r.owner;
  }

  const own = o.source === "mine";
  return {
    id: r.id,
    name: r.name || "未命名食谱",
    kicker: own ? "我的食谱" : "食谱广场",
    coverUrl: imageUrl(r.cover),
    hasCover: !!r.cover,
    hasTags: r.tags.length > 0,
    tags: r.tags,
    pills: pills,
    authorText: authorText,
    hasAuthor: !!authorText,
    hasNote: !!r.note,
    note: r.note,
    hasSource: !!r.source,
    sourceText: r.source ? "来源：" + r.source : "",
    ingredients: ingredients,
    hasIngredients: ingredients.length > 0,
    ingredientCount: ingredients.length + " 项",
    steps: steps,
    hasSteps: steps.length > 0,
    noSteps: steps.length === 0,
    updatedText: r.updatedAt ? dateText(r.updatedAt, true) + " 更新" : "",
    canEdit: own,
    canDelete: own,
    canJoinShopping: own,
    canCollect:
      o.source === "square" && !r.mine && !(me && r.owner && r.owner === me),
    canReport:
      o.source === "square" && !r.mine && !(me && r.owner && r.owner === me),
  };
}

// 从广场复制到自己的食谱：生成新 id，来源作者单独记录，默认私密。
function copyForSave(raw) {
  const r = normalizeRecipe(raw);
  return {
    id: newId("r"),
    name: r.name,
    emoji: r.emoji,
    tags: r.tags.slice(),
    cuisine: r.cuisine,
    dishType: r.dishType,
    cover: r.cover,
    prepMin: r.prepMin,
    cookMin: r.cookMin,
    calories: r.calories,
    source: r.source,
    servings: r.servings,
    ingredients: r.ingredients.map(function (it) {
      return { name: it.name, amount: it.amount, group: it.group };
    }),
    steps: r.steps.map(function (s) {
      return { text: s.text, img: s.img, timer: s.timer };
    }),
    note: r.note,
    diary: [],
    fromOwner: r.owner || "",
    visibility: "private",
    createdAt: 0,
  };
}

module.exports = {
  BASE,
  imageUrl,
  newId,
  dateText,
  todayKey,
  splitTags,
  parseAmount,
  joinAmount,
  normalizeRecipe,
  normalizeShopping,
  normalizeFridge,
  matchRecipe,
  cardModel,
  detailModel,
  copyForSave,
};