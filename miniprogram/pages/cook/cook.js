// 食谱日记 · 小程序端
// 对应 flutter/lib/pages/cook_page.dart、overlays/cook_editor.dart 与 trash/trash.js 的 /api/cook*。
// 单页结构：我的食谱 / 食谱广场 / 购物清单（含冰箱）三个页内 tab，
// 详情与四步新建向导都用页内固定 overlay 呈现。
const api = require("../../utils/api");
const session = require("../../utils/session");
const cook = require("./cook-utils");

const GRANT_KEY = "citro_cook_grant_date";
const WIZARD_LABELS = ["基本信息", "食材", "步骤", "封面"];
const FRIDGE_UNITS = ["个", "包", "瓶", "罐", "把", "克", "斤", "毫升", "升", "杯", "少许", "适量"];

function noop() {}

function trimOf(v) {
  return String(v === undefined || v === null ? "" : v).trim();
}

Page({
  data: {
    ready: false,

    tab: "mine",
    showSearch: true,
    showCreate: true,
    search: "",

    mineCount: 0,
    squareCount: 0,
    mineCards: [],
    squareCards: [],
    mineLoading: true,
    squareLoading: true,
    mineError: "",
    squareError: "",
    mineEmpty: false,
    mineNoMatch: false,
    squareEmpty: false,
    squareNoMatch: false,

    detail: null,
    detailBusy: false,
    collectBusy: false,

    wizardOpen: false,
    wizardEditing: false,
    wizardTitle: "新建食谱",
    wizardStep: 1,
    wizardTabs: [],
    wizardScrollTarget: "wizard-anchor-1",
    canBack: false,
    nextLabel: "下一步",
    form: {
      name: "",
      note: "",
      tags: "",
      servings: "2",
      minutes: "",
      visibility: "private",
      cover: "",
      coverPreview: "",
    },
    formIngList: [],
    formStepList: [],
    coverBusy: false,
    saving: false,
    wizardError: "",

    shopView: "shopping",
    shopping: [],
    shoppingTotal: 0,
    shoppingDone: 0,
    shoppingEmpty: true,
    shoppingLoading: true,
    shopInput: "",
    shopError: "",

    fridge: [],
    fridgeCount: 0,
    fridgeEmpty: true,
    fridgeError: "",
    fridgeInputName: "",
    fridgeInputQty: "",
    fridgeUnits: FRIDGE_UNITS,
    fridgeUnitIndex: 0,
    fridgeUnit: "个",
  },

  onLoad() {
    this.destroyed = false;
    this.mineRaw = [];
    this.squareRaw = [];
    this.shoppingRaw = [];
    this.fridgeRaw = [];
    this.editBase = null;
    this.detailRaw = null;
    this.detailSource = "";
    this.formDirty = false;
    this.userName = (session.user() && session.user().name) || "";
    this._authOut = false;
    this._shopBusy = false;
    this._shopQueued = false;
    this._shopRev = 0;
    this._addShopBusy = false;
    this._fridgeBusy = false;
    this._fridgeQueued = false;
    this._fridgeRev = 0;
    this._coverSeq = 0;

    if (!session.token()) {
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    this.setData({ ready: true });
    this.loadAll();
  },

  onUnload() {
    this.destroyed = true;
  },

  onPullDownRefresh() {
    if (!session.token()) {
      wx.stopPullDownRefresh();
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    if (this.data.wizardOpen || this.data.detail) {
      wx.stopPullDownRefresh();
      return;
    }
    this.loadAll().then(
      () => wx.stopPullDownRefresh(),
      () => wx.stopPullDownRefresh()
    );
  },

  noop,

  /* ---------------- 顶部 tab 与搜索 ---------------- */

  onTab(e) {
    const tab = e && e.currentTarget && e.currentTarget.dataset.tab;
    if (["mine", "square", "shopping"].indexOf(tab) === -1) return;
    if (tab === this.data.tab) return;
    this.setData({
      tab: tab,
      search: "",
      showSearch: tab !== "shopping",
      showCreate: tab === "mine",
    });
    this.renderMine("");
    this.renderSquare("");
  },

  onSearch(e) {
    const value = (e && e.detail && e.detail.value) || "";
    this.setData({ search: value });
    this.renderMine(value);
    this.renderSquare(value);
  },

  onClearSearch() {
    this.setData({ search: "" });
    this.renderMine("");
    this.renderSquare("");
  },

  /* ---------------- 加载 ---------------- */

  loadAll() {
    const token = session.token();
    if (!token) {
      this.handleAuth({ code: 401 });
      return Promise.resolve();
    }
    this.setData({ mineLoading: true, squareLoading: true });

    const mineTask = api.cookData(token).then(
      (body) => {
        if (this.destroyed) return;
        const recipes = body && Array.isArray(body.recipes) ? body.recipes : [];
        this.mineRaw = recipes.map(cook.normalizeRecipe).filter((r) => r.id);
        this.shoppingRaw = cook.normalizeShopping(body && body.shopping);
        this.fridgeRaw = cook.normalizeFridge(body && body.fridge);
        const cached = session.user();
        if (cached && cached.name) this.userName = cached.name;
        this.renderMine();
        this.renderShopping();
        this.renderFridge();
        this.setData({
          mineLoading: false,
          mineError: "",
          shoppingLoading: false,
          shopError: "",
          fridgeError: "",
        });
      },
      (e) => {
        if (this.destroyed) return;
        if (this.handleAuth(e)) {
          this.setData({ mineLoading: false, shoppingLoading: false });
          return;
        }
        const msg = (e && e.message) || "暂时连不上服务器";
        this.setData({
          mineLoading: false,
          shoppingLoading: false,
          mineError: msg,
          shopError: msg,
          fridgeError: msg,
        });
        wx.showToast({ title: msg, icon: "none" });
      }
    );

    const squareTask = api.cookSquare(token).then(
      (body) => {
        if (this.destroyed) return;
        const recipes = body && Array.isArray(body.recipes) ? body.recipes : [];
        this.squareRaw = recipes.map(cook.normalizeRecipe).filter((r) => r.id);
        this.renderSquare();
        this.setData({ squareLoading: false, squareError: "" });
      },
      (e) => {
        if (this.destroyed) return;
        if (this.handleAuth(e)) {
          this.setData({ squareLoading: false });
          return;
        }
        const msg = (e && e.message) || "广场暂时打不开";
        this.setData({ squareLoading: false, squareError: msg });
        wx.showToast({ title: msg, icon: "none" });
      }
    );

    return Promise.all([mineTask, squareTask]);
  },

  handleAuth(e) {
    if (!(e && e.code === 401)) return false;
    if (this._authOut) return true;
    this._authOut = true;
    session.clear();
    wx.showToast({ title: "登录已过期，请重新登录", icon: "none" });
    setTimeout(() => {
      wx.switchTab({ url: "/pages/home/home" });
    }, 800);
    return true;
  },

  /* ---------------- 列表渲染 ---------------- */

  renderMine(query) {
    const q = query === undefined ? this.data.search : query;
    const cards = this.mineRaw
      .filter((r) => cook.matchRecipe(r, q))
      .map((r) => cook.cardModel(r, { source: "mine" }));
    this.setData({
      mineCards: cards,
      mineCount: this.mineRaw.length,
      mineEmpty: this.mineRaw.length === 0,
      mineNoMatch: this.mineRaw.length > 0 && cards.length === 0,
    });
  },

  renderSquare(query) {
    const q = query === undefined ? this.data.search : query;
    const cards = this.squareRaw
      .filter((r) => cook.matchRecipe(r, q))
      .map((r) => cook.cardModel(r, { source: "square" }));
    this.setData({
      squareCards: cards,
      squareCount: this.squareRaw.length,
      squareEmpty: this.squareRaw.length === 0,
      squareNoMatch: this.squareRaw.length > 0 && cards.length === 0,
    });
  },

  /* ---------------- 详情 ---------------- */

  onOpenMine(e) {
    this.openDetail(e && e.currentTarget && e.currentTarget.dataset.id, "mine");
  },

  onOpenSquare(e) {
    this.openDetail(e && e.currentTarget && e.currentTarget.dataset.id, "square");
  },

  openDetail(id, source) {
    if (!id) return;
    const list = source === "square" ? this.squareRaw : this.mineRaw;
    let raw = null;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        raw = list[i];
        break;
      }
    }
    if (!raw) {
      wx.showToast({ title: "食谱已经不在了", icon: "none" });
      return;
    }
    this.detailRaw = raw;
    this.detailSource = source;
    this.setData({
      detail: cook.detailModel(raw, { source: source, meName: this.userName }),
    });
  },

  // UGC 举报：公开食谱由用户发布，发现不当内容可提交给运营者人工审核。
  onReportDetail() {
    const raw = this.detailRaw;
    if (!raw || this.detailSource !== "square") return;
    const token = session.token();
    if (!token) return;
    const reasons = ["垃圾广告", "辱骂攻击", "色情低俗", "违法违规", "侵犯隐私", "其他"];
    const self = this;
    wx.showActionSheet({
      itemList: reasons,
      success(res) {
        const reason = reasons[res.tapIndex];
        if (!reason) return;
        api
          .report(token, {
            type: "recipe",
            recipeId: raw.id,
            reason: reason,
          })
          .then(
            () => {
              if (self.destroyed) return;
              wx.showToast({
                title: "已提交，运营者会尽快处理",
                icon: "none",
              });
            },
            (e) => {
              if (self.destroyed) return;
              if (self.handleAuth(e)) return;
              wx.showToast({
                title: (e && e.message) || "举报提交失败，请稍后再试",
                icon: "none",
              });
            }
          );
      },
    });
  },

  onCloseDetail() {
    this.detailRaw = null;
    this.detailSource = "";
    this.setData({ detail: null, collectBusy: false, detailBusy: false });
  },

  onDetailCoverError() {
    if (this.data.detail) this.setData({ "detail.hasCover": false });
  },

  onEditDetail() {
    if (!this.detailRaw) return;
    const raw = this.detailRaw;
    this.setData({ detail: null });
    this.openEdit(raw);
  },

  onDeleteDetail() {
    if (!this.detailRaw || this.data.detailBusy) return;
    const raw = this.detailRaw;
    const self = this;
    wx.showModal({
      title: "删除食谱",
      content: "删除《" + (raw.name || "这份食谱") + "》后无法恢复。",
      confirmText: "删除",
      confirmColor: "#B05A4A",
      success(res) {
        if (res.confirm) self.deleteRecipe(raw);
      },
    });
  },

  deleteRecipe(raw) {
    const token = session.token();
    if (!token) return;
    const self = this;
    this.setData({ detailBusy: true });
    api.cookDeleteRecipe(token, raw.id).then(
      () => {
        if (self.destroyed) return;
        self.mineRaw = self.mineRaw.filter((r) => r.id !== raw.id);
        self.squareRaw = self.squareRaw.filter((r) => r.id !== raw.id);
        self.detailRaw = null;
        self.detailSource = "";
        self.renderMine();
        self.renderSquare();
        self.setData({ detail: null, detailBusy: false });
        wx.showToast({ title: "已删除", icon: "none" });
      },
      (e) => {
        if (self.destroyed) return;
        self.setData({ detailBusy: false });
        if (self.handleAuth(e)) return;
        wx.showToast({
          title: (e && e.message) || "删除失败",
          icon: "none",
        });
      }
    );
  },

  onAddToShopping() {
    const raw = this.detailRaw;
    if (!raw) return;
    const token = session.token();
    if (!token) return;
    if (!raw.ingredients.length) {
      wx.showToast({ title: "这道食谱还没有食材", icon: "none" });
      return;
    }
    if (this._addShopBusy) return;
    if (this._shopBusy) {
      wx.showToast({ title: "清单正在保存，稍后再试", icon: "none" });
      return;
    }
    this._addShopBusy = true;
    const seen = {};
    this.shoppingRaw.forEach((it) => {
      seen[trimOf(it.text)] = true;
    });
    const additions = [];
    raw.ingredients.forEach((it) => {
      const name = trimOf(it.name);
      if (!name) return;
      const amount = trimOf(it.amount);
      const content = amount ? name + " " + amount : name;
      if (seen[content]) return;
      seen[content] = true;
      additions.push({ id: cook.newId("s"), text: content, done: false });
    });
    if (!additions.length) {
      wx.showToast({ title: "食材已经在购物清单里了", icon: "none" });
      return;
    }
    const next = this.shoppingRaw.concat(additions);
    const self = this;
    api.cookSaveShopping(token, next).then(
      (res) => {
        if (self.destroyed) return;
        self._addShopBusy = false;
        self.shoppingRaw = cook.normalizeShopping(res && res.shopping);
        self._shopRev += 1;
        self.renderShopping();
        wx.showToast({
          title: "已加入 " + additions.length + " 项到购物清单",
          icon: "none",
        });
      },
      (e) => {
        if (self.destroyed) return;
        self._addShopBusy = false;
        if (self.handleAuth(e)) return;
        wx.showToast({ title: "清单保存失败", icon: "none" });
      }
    );
  },

  onCollectDetail() {
    if (!this.detailRaw || this.detailSource !== "square") return;
    if (this.data.collectBusy) return;
    const token = session.token();
    if (!token) return;
    const raw = this.detailRaw;
    const copy = cook.copyForSave(raw);
    const self = this;
    this.setData({ collectBusy: true });
    api.cookSaveRecipe(token, copy).then(
      (res) => {
        if (self.destroyed) return;
        const saved = cook.normalizeRecipe(
          res && res.recipe ? res.recipe : copy
        );
        if (!saved.id) saved.id = copy.id;
        self.mineRaw = [saved].concat(
          self.mineRaw.filter((r) => r.id !== saved.id)
        );
        self.detailRaw = null;
        self.detailSource = "";
        self.renderMine("");
        self.setData({
          detail: null,
          collectBusy: false,
          tab: "mine",
          showSearch: true,
          showCreate: true,
          search: "",
        });
        wx.showToast({ title: "已复制到我的食谱", icon: "none" });
      },
      (e) => {
        if (self.destroyed) return;
        self.setData({ collectBusy: false });
        if (self.handleAuth(e)) return;
        wx.showToast({
          title: (e && e.message) || "复制失败，请稍后再试",
          icon: "none",
        });
      }
    );
  },

  /* ---------------- 新建 / 编辑向导 ---------------- */

  newIngRow(group) {
    return {
      key: cook.newId("i"),
      group: group || "main",
      name: "",
      qty: "",
      unit: "",
    };
  },

  newStepRow(index) {
    return {
      key: cook.newId("s"),
      text: "",
      img: "",
      timer: 0,
      no: String((index || 0) + 1),
    };
  },

  buildWizardTabs(step) {
    return WIZARD_LABELS.map((label, i) => {
      const n = i + 1;
      return {
        n: String(n),
        no: String(n),
        label: label,
        cls: n < step ? "done" : n === step ? "on" : "",
      };
    });
  },

  openNew() {
    if (!session.token()) {
      this.handleAuth({ code: 401 });
      return;
    }
    this.editBase = null;
    this.detailRaw = null;
    this.detailSource = "";
    this.formDirty = false;
    this._coverSeq += 1;
    this.setData({
      detail: null,
      wizardOpen: true,
      wizardEditing: false,
      wizardTitle: "新建食谱",
      wizardStep: 1,
      wizardTabs: this.buildWizardTabs(1),
      wizardScrollTarget: "wizard-anchor-1",
      canBack: false,
      nextLabel: "下一步",
      wizardError: "",
      saving: false,
      coverBusy: false,
      form: {
        name: "",
        note: "",
        tags: "",
        servings: "2",
        minutes: "",
        visibility: "private",
        cover: "",
        coverPreview: "",
      },
      formIngList: [this.newIngRow()],
      formStepList: [this.newStepRow(0)],
    });
  },

  openEdit(raw) {
    const r = cook.normalizeRecipe(raw);
    if (!r.id) return;
    this.editBase = r;
    this.detailRaw = null;
    this.detailSource = "";
    this.formDirty = false;
    this._coverSeq += 1;
    const ingRows = r.ingredients.length
      ? r.ingredients.map((it) => {
          const split = cook.parseAmount(it.amount);
          return {
            key: cook.newId("i"),
            group: it.group || "main",
            name: it.name,
            qty: split.qty,
            unit: split.unit,
          };
        })
      : [this.newIngRow()];
    const stepRows = r.steps.length
      ? r.steps.map((s, i) => {
          return {
            key: cook.newId("s"),
            text: s.text,
            img: s.img,
            timer: s.timer,
            no: String(i + 1),
          };
        })
      : [this.newStepRow(0)];
    const total = r.prepMin + r.cookMin;
    this.setData({
      detail: null,
      wizardOpen: true,
      wizardEditing: true,
      wizardTitle: "编辑食谱",
      wizardStep: 1,
      wizardTabs: this.buildWizardTabs(1),
      wizardScrollTarget: "wizard-anchor-1",
      canBack: false,
      nextLabel: "下一步",
      wizardError: "",
      saving: false,
      coverBusy: false,
      form: {
        name: r.name,
        note: r.note,
        tags: r.tags.join("，"),
        servings: String(r.servings > 0 ? r.servings : 2),
        minutes: total > 0 ? String(total) : "",
        visibility: r.visibility,
        cover: r.cover,
        coverPreview: r.cover ? cook.imageUrl(r.cover) : "",
      },
      formIngList: ingRows,
      formStepList: stepRows,
    });
  },

  onCloseWizard() {
    if (this.data.saving) return;
    if (!this.formDirty) {
      this._coverSeq += 1;
      this.setData({ wizardOpen: false, wizardError: "", coverBusy: false });
      return;
    }
    const self = this;
    wx.showModal({
      title: "放弃编辑",
      content: "还没保存的内容会丢失。",
      confirmText: "放弃",
      confirmColor: "#B05A4A",
      success(res) {
        if (!res.confirm) return;
        self._coverSeq += 1;
        self.formDirty = false;
        self.setData({
          wizardOpen: false,
          wizardError: "",
          coverBusy: false,
        });
      },
    });
  },

  onFormInput(e) {
    const field = e && e.currentTarget && e.currentTarget.dataset.field;
    if (!field) return;
    const value = (e && e.detail && e.detail.value) || "";
    const patch = { wizardError: "" };
    patch["form." + field] = value;
    this.formDirty = true;
    this.setData(patch);
  },

  onVisibility(e) {
    const value = e && e.currentTarget && e.currentTarget.dataset.value;
    if (value !== "public" && value !== "private") return;
    this.formDirty = true;
    this.setData({ "form.visibility": value });
  },

  onIngInput(e) {
    const index = Number(e && e.currentTarget && e.currentTarget.dataset.index);
    const field = e && e.currentTarget && e.currentTarget.dataset.field;
    if (!isFinite(index) || !field) return;
    const value = (e && e.detail && e.detail.value) || "";
    const patch = { wizardError: "" };
    patch["formIngList[" + index + "]." + field] = value;
    this.formDirty = true;
    this.setData(patch);
  },

  onIngAdd() {
    this.formDirty = true;
    this.setData({
      formIngList: this.data.formIngList.concat([this.newIngRow()]),
    });
  },

  onIngDelete(e) {
    const index = Number(e && e.currentTarget && e.currentTarget.dataset.index);
    if (!isFinite(index)) return;
    const rows = this.data.formIngList.slice();
    rows.splice(index, 1);
    if (!rows.length) rows.push(this.newIngRow());
    this.formDirty = true;
    this.setData({ formIngList: rows });
  },

  onStepInput(e) {
    const index = Number(e && e.currentTarget && e.currentTarget.dataset.index);
    const field = e && e.currentTarget && e.currentTarget.dataset.field;
    if (!isFinite(index) || !field) return;
    const value = (e && e.detail && e.detail.value) || "";
    const patch = { wizardError: "" };
    patch["formStepList[" + index + "]." + field] = value;
    this.formDirty = true;
    this.setData(patch);
  },

  onStepAdd() {
    const rows = this.data.formStepList.concat([
      this.newStepRow(this.data.formStepList.length),
    ]);
    this.formDirty = true;
    this.setData({ formStepList: rows });
  },

  onStepDelete(e) {
    const index = Number(e && e.currentTarget && e.currentTarget.dataset.index);
    if (!isFinite(index)) return;
    const rows = this.data.formStepList.slice();
    rows.splice(index, 1);
    if (!rows.length) rows.push(this.newStepRow(0));
    rows.forEach((row, i) => {
      row.no = String(i + 1);
    });
    this.formDirty = true;
    this.setData({ formStepList: rows });
  },

  onWizardBack() {
    if (this.data.saving) return;
    const step = this.data.wizardStep;
    if (step <= 1) return;
    this.goStep(step - 1);
  },

  onWizardNext() {
    if (this.data.saving) return;
    const step = this.data.wizardStep;
    if (!this.validateStep(step)) return;
    if (step >= 4) {
      this.submitRecipe();
      return;
    }
    this.goStep(step + 1);
  },

  goStep(step) {
    this.setData({
      wizardStep: step,
      wizardTabs: this.buildWizardTabs(step),
      wizardScrollTarget: "wizard-anchor-" + step,
      canBack: step > 1,
      nextLabel: step === 4 ? "保存食谱" : "下一步",
      wizardError: "",
    });
  },

  wizardFail(message) {
    this.setData({ wizardError: message });
    wx.showToast({ title: message, icon: "none" });
    return false;
  },

  validateStep(step) {
    if (step === 4 && this.data.coverBusy) {
      return this.wizardFail("封面还在处理，稍等一下");
    }
    if (step !== 1) return true;
    const form = this.data.form;
    if (!trimOf(form.name)) return this.wizardFail("先给这道菜起个名字");
    const tags = cook.splitTags(form.tags);
    if (tags.length > 8) return this.wizardFail("标签最多 8 个");
    for (let i = 0; i < tags.length; i++) {
      if (Array.from(tags[i]).length > 12) {
        return this.wizardFail("单个标签最多 12 个字");
      }
    }
    const servings = parseInt(form.servings, 10);
    if (!isFinite(servings) || servings < 0 || servings > 99) {
      return this.wizardFail("份数填 0-99 的数字");
    }
    if (trimOf(form.minutes) !== "") {
      const minutes = parseInt(form.minutes, 10);
      if (!isFinite(minutes) || minutes < 0 || minutes > 1440) {
        return this.wizardFail("用时填 0-1440 分钟");
      }
    }
    return true;
  },

  submitRecipe() {
    if (this.data.saving) return;
    if (!this.validateStep(1)) {
      this.goStep(1);
      return;
    }
    const token = session.token();
    if (!token) {
      this.handleAuth({ code: 401 });
      return;
    }
    const form = this.data.form;
    const base = this.editBase || {};
    const servings = parseInt(form.servings, 10) || 0;
    const minutes = trimOf(form.minutes) ? parseInt(form.minutes, 10) || 0 : 0;
    const tags = cook.splitTags(form.tags).slice(0, 8);

    const ingredients = [];
    this.data.formIngList.forEach((row) => {
      const name = trimOf(row.name);
      if (!name) return;
      ingredients.push({
        name: name.slice(0, 200),
        amount: cook.joinAmount(row.qty, row.unit).slice(0, 60),
        group: row.group === "aux" || row.group === "season" ? row.group : "main",
      });
    });

    const steps = [];
    this.data.formStepList.forEach((row) => {
      const text = trimOf(row.text);
      if (!text && !row.img) return;
      steps.push({
        text: text.slice(0, 1000),
        img: row.img || "",
        timer: Number(row.timer) || 0,
      });
    });

    const recipe = {
      id: base.id || "",
      name: trimOf(form.name).slice(0, 40),
      emoji: base.emoji || "",
      tags: tags,
      cuisine: base.cuisine || "",
      dishType: base.dishType || "",
      cover: form.cover || "",
      prepMin: 0,
      cookMin: minutes,
      calories: base.calories || 0,
      source: base.source || "",
      servings: servings,
      ingredients: ingredients,
      steps: steps,
      note: trimOf(form.note).slice(0, 2000),
      diary: base.diary || [],
      fromOwner: base.fromOwner || "",
      visibility: form.visibility === "public" ? "public" : "private",
      createdAt: base.createdAt || Date.now(),
    };

    const self = this;
    this.setData({ saving: true, wizardError: "" });
    api.cookSaveRecipe(token, recipe).then(
      (res) => {
        if (self.destroyed) return;
        const saved = cook.normalizeRecipe(
          res && res.recipe ? res.recipe : recipe
        );
        if (!saved.id) saved.id = recipe.id;
        self.mineRaw = [saved].concat(
          self.mineRaw.filter((r) => r.id !== saved.id)
        );
        self.squareRaw = self.squareRaw.filter((r) => r.id !== saved.id);
        if (saved.visibility === "public") {
          // 广场接口的 owner 是发布者本人；本地区块也保持同一口径。
          const squareCopy = Object.assign({}, saved, {
            owner: self.userName || saved.owner,
            mine: true,
          });
          self.squareRaw = [squareCopy].concat(self.squareRaw);
        }
        self.formDirty = false;
        self.editBase = null;
        self._coverSeq += 1;
        self.setData({
          wizardOpen: false,
          saving: false,
          wizardError: "",
          coverBusy: false,
          detail: null,
          search: "",
        });
        self.renderMine("");
        self.renderSquare("");
        wx.showToast({ title: "食谱已保存", icon: "none" });
        self.maybeGrantCard();
      },
      (e) => {
        if (self.destroyed) return;
        self.setData({ saving: false });
        if (self.handleAuth(e)) return;
        const msg = (e && e.message) || "保存失败，请稍后重试";
        self.setData({ wizardError: msg });
        wx.showToast({ title: msg, icon: "none" });
      }
    );
  },

  /* ---------------- 封面选择与上传 ---------------- */

  chooseCover() {
    if (this.data.coverBusy) return;
    if (!session.token()) {
      this.handleAuth({ code: 401 });
      return;
    }
    const self = this;
    wx.chooseMedia({
      count: 1,
      mediaType: ["image"],
      sourceType: ["album", "camera"],
      sizeType: ["compressed"],
      success(res) {
        const files = res && res.tempFiles;
        const file = files && files[0];
        const path = file && (file.tempFilePath || file.path);
        if (!path) {
          wx.showToast({ title: "没能读到图片", icon: "none" });
          return;
        }
        self.uploadCover(path);
      },
      fail(err) {
        const msg = String((err && err.errMsg) || "");
        if (msg.toLowerCase().indexOf("cancel") >= 0) return;
        wx.showToast({ title: "没能选到图片，可稍后再试", icon: "none" });
      },
    });
  },

  uploadCover(src) {
    const token = session.token();
    if (!token) return;
    const self = this;
    const seq = (this._coverSeq += 1);
    this.setData({ coverBusy: true });

    const finish = (path) => {
      if (self.destroyed) return;
      wx.getFileSystemManager().readFile({
        filePath: path,
        encoding: "base64",
        success(readRes) {
          if (self.destroyed || seq !== self._coverSeq) return;
          const mime = /\.png$/i.test(path)
            ? "image/png"
            : /\.webp$/i.test(path)
            ? "image/webp"
            : "image/jpeg";
          const dataUrl =
            "data:" + mime + ";base64," + ((readRes && readRes.data) || "");
          api.cookImage(token, dataUrl).then(
            (body) => {
              if (self.destroyed || seq !== self._coverSeq) return;
              const url = body && body.url;
              if (!url) {
                self.setData({ coverBusy: false });
                wx.showToast({
                  title: "封面上传失败，可以稍后再试",
                  icon: "none",
                });
                return;
              }
              self.formDirty = true;
              self.setData({
                "form.cover": url,
                "form.coverPreview": path,
                coverBusy: false,
              });
              wx.showToast({ title: "封面已就绪", icon: "none" });
            },
            (e) => {
              if (self.destroyed || seq !== self._coverSeq) return;
              self.setData({ coverBusy: false });
              if (self.handleAuth(e)) return;
              wx.showToast({
                title: "封面上传失败，可以稍后再试",
                icon: "none",
              });
            }
          );
        },
        fail() {
          if (self.destroyed || seq !== self._coverSeq) return;
          self.setData({ coverBusy: false });
          wx.showToast({ title: "图片读取失败，可以稍后再试", icon: "none" });
        },
      });
    };

    wx.compressImage({
      src: src,
      quality: 70,
      success(res) {
        finish((res && res.tempFilePath) || src);
      },
      fail() {
        finish(src);
      },
    });
  },

  onRemoveCover() {
    this._coverSeq += 1;
    this.formDirty = true;
    this.setData({
      "form.cover": "",
      "form.coverPreview": "",
      coverBusy: false,
    });
  },

  onCoverPreviewError() {
    this.setData({ "form.coverPreview": "" });
  },

  /* ---------------- 购物清单 ---------------- */

  renderShopping() {
    const items = this.shoppingRaw.map((it) => {
      return { id: it.id, text: it.text, done: it.done === true };
    });
    let done = 0;
    items.forEach((it) => {
      if (it.done) done += 1;
    });
    this.setData({
      shopping: items,
      shoppingTotal: items.length,
      shoppingDone: done,
      shoppingEmpty: items.length === 0,
      shoppingLoading: false,
    });
  },

  onShopView(e) {
    const view = e && e.currentTarget && e.currentTarget.dataset.view;
    if (view !== "shopping" && view !== "fridge") return;
    this.setData({ shopView: view });
  },

  onShopInput(e) {
    this.setData({
      shopInput: (e && e.detail && e.detail.value) || "",
    });
  },

  onAddShop() {
    const value = trimOf(this.data.shopInput);
    if (!value) {
      wx.showToast({ title: "先写点要买的东西", icon: "none" });
      return;
    }
    this.shoppingRaw = this.shoppingRaw.concat([
      { id: cook.newId("s"), text: value.slice(0, 80), done: false },
    ]);
    this.setData({ shopInput: "" });
    this.bumpShopping();
  },

  onToggleShop(e) {
    const id = e && e.currentTarget && e.currentTarget.dataset.id;
    if (!id) return;
    for (let i = 0; i < this.shoppingRaw.length; i++) {
      if (this.shoppingRaw[i].id === id) {
        this.shoppingRaw[i].done = !this.shoppingRaw[i].done;
        break;
      }
    }
    this.bumpShopping();
  },

  onDeleteShop(e) {
    const id = e && e.currentTarget && e.currentTarget.dataset.id;
    if (!id) return;
    this.shoppingRaw = this.shoppingRaw.filter((it) => it.id !== id);
    this.bumpShopping();
  },

  onClearDone() {
    if (this.data.shoppingDone <= 0) return;
    const self = this;
    wx.showModal({
      title: "清空已完成",
      content: "只会移除勾选过的条目。",
      confirmText: "清空",
      success(res) {
        if (!res.confirm) return;
        self.shoppingRaw = self.shoppingRaw.filter((it) => !it.done);
        self.bumpShopping();
      },
    });
  },

  bumpShopping() {
    this._shopRev += 1;
    this.renderShopping();
    this.pushShopping();
  },

  pushShopping() {
    const token = session.token();
    if (!token) {
      this.handleAuth({ code: 401 });
      return;
    }
    if (this._shopBusy) {
      this._shopQueued = true;
      return;
    }
    this._shopBusy = true;
    const rev = this._shopRev;
    const self = this;
    api
      .cookSaveShopping(token, this.shoppingRaw)
      .then(
        (res) => {
          if (self.destroyed) return;
          if (rev === self._shopRev && res && Array.isArray(res.shopping)) {
            self.shoppingRaw = cook.normalizeShopping(res.shopping);
            self.renderShopping();
          }
        },
        (e) => {
          if (self.destroyed) return;
          if (self.handleAuth(e)) return;
          wx.showToast({ title: "清单保存失败，稍后重试", icon: "none" });
        }
      )
      .then(() => {
        if (self.destroyed) return;
        self._shopBusy = false;
        if (self._shopQueued) {
          self._shopQueued = false;
          self.pushShopping();
        }
      });
  },

  /* ---------------- 冰箱 ---------------- */

  renderFridge() {
    const today = cook.todayKey();
    const items = this.fridgeRaw.map((it) => {
      const parts = [];
      if (it.qty) parts.push(it.qty);
      if (it.unit) parts.push(it.unit);
      let expText = "";
      let expClass = "";
      if (it.expDate) {
        expText = "到期 " + it.expDate;
        expClass = it.expDate < today ? "exp-danger" : "exp-ok";
      }
      return {
        id: it.id,
        name: it.name,
        amountText: parts.join(" "),
        expText: expText,
        expClass: expClass,
      };
    });
    this.setData({
      fridge: items,
      fridgeCount: items.length,
      fridgeEmpty: items.length === 0,
    });
  },

  onFridgeName(e) {
    this.setData({
      fridgeInputName: (e && e.detail && e.detail.value) || "",
    });
  },

  onFridgeQty(e) {
    this.setData({
      fridgeInputQty: (e && e.detail && e.detail.value) || "",
    });
  },

  onFridgeUnit(e) {
    const index = Number(e && e.detail && e.detail.value);
    if (!isFinite(index) || index < 0 || index >= FRIDGE_UNITS.length) return;
    this.setData({
      fridgeUnitIndex: index,
      fridgeUnit: FRIDGE_UNITS[index],
    });
  },

  onAddFridge() {
    const name = trimOf(this.data.fridgeInputName);
    if (!name) {
      wx.showToast({ title: "先写食材名", icon: "none" });
      return;
    }
    const qty = trimOf(this.data.fridgeInputQty) || "1";
    this.fridgeRaw = this.fridgeRaw.concat([
      {
        id: cook.newId("f"),
        name: name.slice(0, 40),
        qty: qty.slice(0, 20),
        unit: this.data.fridgeUnit || "个",
        buyDate: "",
        expDate: "",
      },
    ]);
    this.setData({ fridgeInputName: "", fridgeInputQty: "" });
    this.bumpFridge();
  },

  onDeleteFridge(e) {
    const id = e && e.currentTarget && e.currentTarget.dataset.id;
    if (!id) return;
    this.fridgeRaw = this.fridgeRaw.filter((it) => it.id !== id);
    this.bumpFridge();
  },

  bumpFridge() {
    this._fridgeRev = (this._fridgeRev || 0) + 1;
    this.renderFridge();
    this.pushFridge();
  },

  pushFridge() {
    const token = session.token();
    if (!token) {
      this.handleAuth({ code: 401 });
      return;
    }
    if (this._fridgeBusy) {
      this._fridgeQueued = true;
      return;
    }
    this._fridgeBusy = true;
    const rev = this._fridgeRev;
    const self = this;
    api
      .cookSaveFridge(token, this.fridgeRaw)
      .then(
        (res) => {
          if (self.destroyed) return;
          if (rev === self._fridgeRev && res && Array.isArray(res.fridge)) {
            self.fridgeRaw = cook.normalizeFridge(res.fridge);
            self.renderFridge();
          }
        },
        (e) => {
          if (self.destroyed) return;
          if (self.handleAuth(e)) return;
          wx.showToast({ title: "冰箱保存失败，稍后重试", icon: "none" });
        }
      )
      .then(() => {
        if (self.destroyed) return;
        self._fridgeBusy = false;
        if (self._fridgeQueued) {
          self._fridgeQueued = false;
          self.pushFridge();
        }
      });
  },

  /* ---------------- 每日第一次保存的卡面机会 ---------------- */

  maybeGrantCard() {
    const token = session.token();
    if (!token) return;
    const today = cook.todayKey();
    let stored = "";
    try {
      stored = wx.getStorageSync(GRANT_KEY) || "";
    } catch (e) {
      stored = "";
    }
    if (stored === today) return;
    const self = this;
    api.cardsGrant(token, "recipe").then(
      (res) => {
        try {
          wx.setStorageSync(GRANT_KEY, today);
        } catch (e) {}
        if (self.destroyed) return;
        if (res && res.granted) {
          setTimeout(() => {
            if (!self.destroyed) {
              wx.showToast({ title: "获得 1 次卡面抽取机会", icon: "none" });
            }
          }, 700);
        }
      },
      () => {
        // 奖励失败不影响食谱保存，静默处理。
      }
    );
  },
});