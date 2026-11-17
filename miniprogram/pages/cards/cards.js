// 卡面馆 · 小程序端
// 对应 flutter/lib/overlays/card_collection.dart / card_draw.dart 与
// flutter/lib/data/cards.dart。目录用内置 cards_index.json，
// 收藏状态以服务端 /api/cards/* 返回的 state 为准。
const api = require("../../utils/api");
const session = require("../../utils/session");
const catalog = require("../../data/cards_index.json");

const LOCAL_KEY = "citro_cards_v1";
const BASE = String(catalog.base || "https://obs.chimu-claw.xyz/card").replace(
  /\/+$/,
  ""
);
const NO_CREDIT_TIP = "通过记录食谱等方式可以获得卡面抽取机会";

const CATEGORIES = [];
const CARD_MAP = {};
const CARD_IDS = [];

function cardUrl(file) {
  return encodeURI(BASE + "/" + String(file || ""));
}

function cardNumber(id) {
  const raw = String(id || "").split("/").pop();
  return /^\d+$/.test(raw) ? raw : "特别";
}

(function buildCatalog() {
  const rawCategories = Array.isArray(catalog.categories)
    ? catalog.categories
    : [];
  rawCategories.forEach((cat) => {
    if (!cat || !cat.id) return;
    const catId = String(cat.id);
    const catName = String(cat.name || cat.id);
    const cards = [];
    const rawCards = Array.isArray(cat.cards) ? cat.cards : [];
    rawCards.forEach((item) => {
      if (!item || !item.id || !item.file) return;
      const id = String(item.id);
      if (CARD_MAP[id]) return;
      const card = {
        id,
        categoryId: catId,
        categoryName: catName,
        file: String(item.file),
        url: cardUrl(item.file),
        number: cardNumber(id),
      };
      CARD_MAP[id] = card;
      CARD_IDS.push(id);
      cards.push(card);
    });
    if (cards.length) {
      CATEGORIES.push({ id: catId, name: catName, cards });
    }
  });
})();

const TOTAL = CARD_IDS.length;

function toast(title, duration) {
  wx.showToast({
    title: String(title || ""),
    icon: "none",
    duration: duration || 2200,
  });
}

function messageOf(e) {
  return (e && e.message) || "网络连接失败，请检查网络后重试";
}

function normalizeState(raw) {
  const src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const ownedRaw = Array.isArray(src.owned) ? src.owned : [];
  const seen = {};
  const owned = [];
  ownedRaw.forEach((value) => {
    const id = String(value || "").trim();
    if (!CARD_MAP[id] || seen[id]) return;
    seen[id] = true;
    owned.push(id);
  });
  const rawCredits = Number(src.credits);
  const credits = isFinite(rawCredits)
    ? Math.max(0, Math.min(999, Math.floor(rawCredits)))
    : 0;
  const today =
    typeof src.today === "string" && CARD_MAP[src.today] ? src.today : "";
  return { owned, credits, today };
}

function readLocalOwned() {
  let raw = null;
  try {
    raw = wx.getStorageSync(LOCAL_KEY);
  } catch (e) {
    return [];
  }
  if (typeof raw === "string") {
    try {
      raw = JSON.parse(raw);
    } catch (e) {
      raw = null;
    }
  }
  const list = Array.isArray(raw)
    ? raw
    : raw && Array.isArray(raw.owned)
    ? raw.owned
    : [];
  const seen = {};
  const out = [];
  list.forEach((value) => {
    const id = String(value || "").trim();
    if (!CARD_MAP[id] || seen[id]) return;
    seen[id] = true;
    out.push(id);
  });
  return out;
}

function saveLocal(state) {
  if (!state || !Array.isArray(state.owned)) return;
  try {
    wx.setStorageSync(LOCAL_KEY, { owned: state.owned.slice(0, 500) });
  } catch (e) {}
}

function countOwned(state) {
  if (!state || !Array.isArray(state.owned)) return 0;
  let n = 0;
  CATEGORIES.forEach((cat) => {
    cat.cards.forEach((card) => {
      if (state.owned.indexOf(card.id) >= 0) n += 1;
    });
  });
  return n;
}

function buildChips(selected) {
  const chips = [{ id: "all", name: "全部", on: selected === "all" }];
  CATEGORIES.forEach((cat) => {
    chips.push({ id: cat.id, name: cat.name, on: selected === cat.id });
  });
  return chips;
}

Page({
  data: {
    loading: true,
    error: "",
    drawing: false,
    selectedCat: "all",
    categories: [],
    wallGroups: [],
    wallEmpty: false,
    ownedCount: 0,
    total: TOTAL,
    credits: 0,
    collectedText: "已收集 0 / " + TOTAL,
    todayView: null,
    catalogEmpty: TOTAL === 0,
    drawLabel: "抽一张",
    drawHint: "通过记录食谱等方式可以获得卡面抽取机会。",
    noCredit: true,
    detail: null,
    drawOverlay: null,
  },

  onLoad() {
    this.alive = true;
    this.state = null;
    this.broken = {};
    this.drawing = false;
    this.loadingAll = false;
    this.ensuring = false;
    this.mergedLocal = false;

    const token = session.token();
    if (!token) {
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    this.token = token;

    this.setData(
      Object.assign({ categories: buildChips("all") }, this.buildViews("all"))
    );
    this.loadAll();
  },

  onUnload() {
    this.alive = false;
  },

  noop() {},

  /* ---------------- 视图 ---------------- */

  buildViews(cat) {
    const selected = cat || this.data.selectedCat || "all";
    const state = this.state || { owned: [], credits: 0, today: "" };
    const owned = state.owned || [];
    const credits = state.credits || 0;
    const ownedCount = countOwned(state);
    const broken = this.broken || {};

    const chips = buildChips(selected);
    const groups = [];
    CATEGORIES.forEach((category) => {
      if (selected !== "all" && selected !== category.id) return;
      let catOwned = 0;
      const tiles = category.cards.map((card) => {
        const has = owned.indexOf(card.id) >= 0;
        if (has) catOwned += 1;
        return {
          id: card.id,
          url: card.url,
          categoryName: card.categoryName,
          number: card.number,
          owned: has,
          isToday: state.today === card.id,
          broken: !!broken[card.id],
          showImage: has && !broken[card.id],
          frameClass: "wall-frame " + (has ? "owned" : "locked"),
          backLabel: has ? "加载失败" : "未收集",
        };
      });
      groups.push({
        id: category.id,
        name: category.name,
        countText: catOwned + " / " + category.cards.length,
        tiles,
      });
    });

    let todayView = null;
    if (state.today && CARD_MAP[state.today]) {
      const card = CARD_MAP[state.today];
      todayView = {
        id: card.id,
        url: card.url,
        categoryName: card.categoryName,
        number: card.number,
        broken: !!broken[card.id],
        showImage: !broken[card.id],
        backLabel: "图片暂时加载失败",
      };
    }

    return {
      categories: chips,
      wallGroups: groups,
      wallEmpty: groups.length === 0,
      ownedCount,
      total: TOTAL,
      credits,
      collectedText: "已收集 " + ownedCount + " / " + TOTAL,
      todayView,
      catalogEmpty: TOTAL === 0,
      drawLabel: credits > 0 ? "抽一张（剩 " + credits + " 次）" : "抽一张",
      drawHint:
        credits > 0
          ? "每次抽取消耗 1 次机会，卡面免费收藏。"
          : "通过记录食谱等方式可以获得卡面抽取机会。",
      noCredit: credits <= 0,
    };
  },

  applyState(raw) {
    this.state = normalizeState(raw);
    saveLocal(this.state);
    this.setData(Object.assign({ error: "" }, this.buildViews(this.data.selectedCat)));
  },

  handleAuthError(e) {
    if (!e || e.code !== 401) return false;
    toast("登录已过期，请重新登录", 2400);
    const self = this;
    setTimeout(() => {
      if (self.alive) wx.switchTab({ url: "/pages/home/home" });
    }, 900);
    return true;
  },

  /* ---------------- 加载 ---------------- */

  loadAll() {
    if (this.loadingAll) return;
    this.loadingAll = true;
    if (!TOTAL) {
      this.setData({
        loading: false,
        error: "卡面目录为空，稍后再试",
        categories: buildChips("all"),
        wallEmpty: true,
      });
      this.loadingAll = false;
      return;
    }
    this.setData({ loading: true, error: "" });
    const token = this.token;
    const self = this;
    let state = null;

    const mergeLocal = () => {
      if (this.mergedLocal) return Promise.resolve(null);
      this.mergedLocal = true;
      const local = readLocalOwned();
      if (!local.length) return Promise.resolve(null);
      return api
        .cardsSync(token, { owned: local, migrate: false })
        .then((res) => (res && res.state) || null)
        .catch(() => null);
    };

    mergeLocal()
      .then((synced) => {
        state = synced;
        return api.cardsToday(token, CARD_IDS, false);
      })
      .then((res) => {
        if (!self.alive) return;
        if (res && res.state) state = res.state;
        if (!state) {
          self.setData({
            loading: false,
            error: "卡面暂时没有加载出来，请稍后重试",
          });
          return;
        }
        self.applyState(state);
        self.setData({ loading: false, error: "" });
      })
      .catch((e) => {
        if (!self.alive) return;
        if (state) {
          self.applyState(state);
          self.setData({
            loading: false,
            error: "今日卡面暂时没取到，收藏进度已同步",
          });
        } else {
          self.setData({ loading: false, error: messageOf(e) });
          self.handleAuthError(e);
        }
      })
      .then(() => {
        self.loadingAll = false;
      });
  },

  onRetry() {
    if (this.loadingAll) return;
    this.loadAll();
  },

  onEnsureToday() {
    if (this.ensuring || !TOTAL) return;
    this.ensuring = true;
    this.setData({ loading: true, error: "" });
    const self = this;
    api
      .cardsToday(this.token, CARD_IDS, false)
      .then((res) => {
        if (!self.alive) return;
        if (res && res.state) {
          self.applyState(res.state);
          self.setData({ loading: false, error: "" });
        } else {
          self.setData({
            loading: false,
            error: "今天还没有取到卡面，稍后再试",
          });
        }
      })
      .catch((e) => {
        if (!self.alive) return;
        self.setData({ loading: false, error: messageOf(e) });
        self.handleAuthError(e);
      })
      .then(() => {
        self.ensuring = false;
      });
  },

  /* ---------------- 抽卡 ---------------- */

  onDraw() {
    if (this.drawing) return;
    if (!TOTAL) {
      toast("卡面目录暂时为空");
      return;
    }
    if (!this.state) {
      toast("卡面还在加载，请稍候");
      return;
    }
    if (!this.state.credits) {
      toast(NO_CREDIT_TIP, 3000);
      return;
    }
    const before = this.state.owned.slice();
    this.drawing = true;
    this.setData({ drawing: true });
    const self = this;
    api
      .cardsDraw(this.token, CARD_IDS)
      .then((res) => {
        if (!self.alive) return;
        if (!res || !res.state) {
          throw new Error("抽取没有完成，请稍后再试");
        }
        const cardId = String(res.card || "");
        const wasOwned = before.indexOf(cardId) >= 0;
        self.applyState(res.state);
        const card = CARD_MAP[cardId];
        if (card) {
          self.setData({ drawOverlay: self.drawOverlayFor(card, wasOwned) });
        } else {
          toast("获得了一张新卡面");
        }
      })
      .catch((e) => {
        if (!self.alive) return;
        const msg = String((e && e.message) || "");
        if (e && e.code === 400 && msg.indexOf("抽卡机会") >= 0) {
          toast(NO_CREDIT_TIP, 3000);
        } else if (!self.handleAuthError(e)) {
          toast(msg || "抽取没有成功，稍后再试");
        }
      })
      .then(() => {
        self.drawing = false;
        if (self.alive) self.setData({ drawing: false });
      });
  },

  drawOverlayFor(card, wasOwned) {
    const ownedCount = countOwned(this.state);
    const credits = (this.state && this.state.credits) || 0;
    return {
      id: card.id,
      url: card.url,
      categoryName: card.categoryName,
      number: card.number,
      broken: !!this.broken[card.id],
      showImage: !this.broken[card.id],
      badge: wasOwned ? "又见面了" : "新卡面",
      caption: wasOwned ? "这张之前已经收集过" : "已收入卡面收藏",
      collectedText: "已收集 " + ownedCount + " / " + TOTAL,
      canAgain: credits > 0,
      againLabel: "再抽一次（剩 " + credits + " 次）",
    };
  },

  onDrawAgain() {
    if (this.drawing) return;
    this.setData({ drawOverlay: null });
    const self = this;
    setTimeout(() => {
      if (self.alive) self.onDraw();
    }, 100);
  },

  onCloseDraw() {
    this.setData({ drawOverlay: null });
  },

  /* ---------------- 收藏墙与详情 ---------------- */

  onSelectCat(e) {
    const id = String(
      (e && e.currentTarget && e.currentTarget.dataset.id) || "all"
    );
    if (!id || id === this.data.selectedCat) return;
    this.setData(Object.assign({ selectedCat: id }, this.buildViews(id)));
  },

  onTapTile(e) {
    const id = String(
      (e && e.currentTarget && e.currentTarget.dataset.id) || ""
    );
    const card = CARD_MAP[id];
    if (!card) return;
    if (!this.state) {
      toast("收藏进度还在同步，请稍候");
      return;
    }
    if (this.state.owned.indexOf(id) < 0) {
      toast("抽到这张后才会点亮");
      return;
    }
    this.openDetail(id);
  },

  onOpenToday() {
    const view = this.data.todayView;
    if (view && view.id) this.openDetail(view.id);
  },

  openDetail(id) {
    const card = CARD_MAP[id];
    if (!card) return;
    const isToday = !!(this.state && this.state.today === id);
    this.setData({
      detail: {
        id: card.id,
        url: card.url,
        categoryName: card.categoryName,
        number: card.number,
        broken: !!this.broken[card.id],
        showImage: !this.broken[card.id],
        isToday,
        subText: isToday ? "今日卡面 · 已收入收藏" : "已收入卡面收藏",
      },
    });
  },

  onCloseDetail() {
    this.setData({ detail: null });
  },

  onImageError(e) {
    const id = String(
      (e && e.currentTarget && e.currentTarget.dataset.id) || ""
    );
    if (!id || this.broken[id]) return;
    this.broken[id] = true;
    const patch = this.buildViews(this.data.selectedCat);
    if (this.data.detail && this.data.detail.id === id) {
      patch.detail = Object.assign({}, this.data.detail, {
        broken: true,
        showImage: false,
      });
    }
    if (this.data.drawOverlay && this.data.drawOverlay.id === id) {
      patch.drawOverlay = Object.assign({}, this.data.drawOverlay, {
        broken: true,
        showImage: false,
      });
    }
    this.setData(patch);
  },
});