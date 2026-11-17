// 首页 · 小程序端
// 对应 flutter/lib/pages/home_page.dart 的移动端：时段顶部大图 + 固定顺序卡片。
// 登录门禁放行前不发请求；单张卡失败只降级自己，不阻塞其它卡片。
const api = require("../../utils/api");
const session = require("../../utils/session");
const catalog = require("../../data/cards_index.json");

const HERO_KEY = "citro_home_hero_v1";
const TODO_KEY = "citro_todo_v1";
const WEATHER_CITY_KEY = "citro_weather_city";

const HERO_ORDER = ["dawn", "day", "dusk", "night"];
const HERO_SUB = {
  dawn: "清晨的风很轻，今天也慢慢来。",
  day: "把今天，过成自己喜欢的样子。",
  dusk: "天色慢下来，心也跟着慢一点。",
  night: "夜里把心事放轻，早点休息。",
};

// 心情档位与 Flutter todo_models.dart 的六种柔和色一致。
const MOODS = {
  happy: { label: "开心", color: "#E0A03E" },
  calm: { label: "平静", color: "#8FA6BE" },
  neutral: { label: "一般", color: "#A79E8C" },
  tired: { label: "疲惫", color: "#9A8FA6" },
  low: { label: "低落", color: "#7C8AA0" },
  anxious: { label: "焦虑", color: "#C4855D" },
};

const TINGYU_SOUNDS = [
  { no: "01", name: "雨幕远雷", tag: "雨声 · 远雷" },
  { no: "02", name: "街角咖啡馆", tag: "人声 · 杯碟" },
  { no: "03", name: "壁炉薪火", tag: "木柴 · 轻响" },
];

// 内置 30 条短句，按一年中的第几天 % 30 选取，当天稳定不随机。
const QUOTES = [
  { t: "人间有味是清欢。", f: "苏轼《浣溪沙》" },
  { t: "行到水穷处，坐看云起时。", f: "王维《终南别业》" },
  { t: "采菊东篱下，悠然见南山。", f: "陶渊明《饮酒》" },
  { t: "既见君子，云胡不喜。", f: "《诗经·风雨》" },
  { t: "人生天地间，忽如远行客。", f: "《古诗十九首》" },
  { t: "逝者如斯夫，不舍昼夜。", f: "《论语·子罕》" },
  { t: "宠辱不惊，闲看庭前花开花落。", f: "《菜根谭》" },
  { t: "致虚极，守静笃。", f: "《道德经》" },
  { t: "天与云与山与水，上下一白。", f: "张岱《湖心亭看雪》" },
  { t: "枕上诗书闲处好，门前风景雨来佳。", f: "李清照" },
  { t: "从明天起，做一个幸福的人。", f: "海子" },
  { t: "黑夜给了我黑色的眼睛，我却用它寻找光明。", f: "顾城" },
  { t: "真正重要的东西，用眼睛是看不见的。", f: "《小王子》" },
  { t: "如果你因错过太阳而流泪，那么你也将错过群星。", f: "泰戈尔《飞鸟集》" },
  { t: "在冬天的深处，我身上有一个不可战胜的夏天。", f: "加缪" },
  { t: "好好地忍耐，不要沮丧；春天要来，大地会让它一点点完成。", f: "里尔克" },
  { t: "心美一切皆美，情深万象皆深。", f: "林清玄" },
  { t: "生活是一种律动，须有光有影。", f: "老舍" },
  { t: "岁月极美，在于它必然的流逝。", f: "三毛" },
  { t: "人间烟火气，最抚凡人心。", f: "汪曾祺" },
  { t: "花看半开，酒饮微醺。", f: "《菜根谭》" },
  { t: "从前的日色变得慢，车、马、邮件都慢。", f: "木心《从前慢》" },
  { t: "一定要爱着点什么，恰似草木对光阴的钟情。", f: "汪曾祺《人间草木》" },
  { t: "世界先爱了我，我不能不爱它。", f: "汪曾祺" },
  { t: "把日子过轻一点，像翻一页书。", f: "Citro" },
  { t: "允许自己慢下来，风景不会跑。", f: "Citro" },
  { t: "今天不必圆满，有一点喜欢就够。", f: "Citro" },
  { t: "给心情留白，风会替你写几行。", f: "Citro" },
  { t: "好天气要出门，坏天气要读书。", f: "Citro" },
  { t: "夜里把心事放轻，明天再想。", f: "Citro" },
];

// 卡面目录：内置 catalog 的 base + file 拼出 OBS 地址，id 用于服务端记账。
const CARD_MAP = {};
const CARD_IDS = [];
(catalog.categories || []).forEach((cat) => {
  ((cat && cat.cards) || []).forEach((card) => {
    if (!card || !card.id) return;
    const id = String(card.id);
    if (CARD_MAP[id]) return;
    CARD_MAP[id] = card;
    CARD_IDS.push(id);
  });
});
const CARD_TOTAL = CARD_IDS.length;
const CARD_BASE = String(catalog.base || "").replace(/\/+$/, "");

function cardUrl(file) {
  return encodeURI(CARD_BASE + "/" + String(file || ""));
}

function pad2(n) {
  return String(n).padStart(2, "0");
}

function dateKey(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function dayOfYear(d) {
  const start = new Date(d.getFullYear(), 0, 1);
  return Math.floor((d.getTime() - start.getTime()) / 86400000) + 1;
}

function weekdayText(d) {
  return "星期" + "日一二三四五六".charAt(d.getDay());
}

function hmText(v) {
  const s = String(v || "");
  return /^\d{1,2}:\d{2}$/.test(s) ? s : "";
}

function hmToMinutes(v) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(v || ""));
  if (!m) return -1;
  const h = Number(m[1]);
  const mm = Number(m[2]);
  if (h > 23 || mm > 59) return -1;
  return h * 60 + mm;
}

function durationText(minutes) {
  const total = Math.max(0, Math.round(minutes));
  if (total <= 0) return "马上";
  if (total < 60) return total + " 分钟";
  const h = Math.floor(total / 60);
  const m = total % 60;
  return m ? h + " 小时 " + m + " 分" : h + " 小时";
}

function timePeriod(hour) {
  if (hour >= 5 && hour < 10) return "dawn";
  if (hour >= 10 && hour < 16) return "day";
  if (hour >= 16 && hour < 19) return "dusk";
  return "night";
}

function greetingFor(hour) {
  if (hour >= 5 && hour < 11) return "早上好";
  if (hour >= 11 && hour < 18) return "下午好";
  return "晚上好";
}

// WMO weather code -> 中文描述，只覆盖 Open-Meteo 常见码值。
function weatherText(code) {
  const n = Number(code);
  if (n === 0) return "晴";
  if (n === 1 || n === 2) return "多云";
  if (n === 3) return "阴";
  if (n === 45 || n === 48) return "雾";
  if ((n >= 51 && n <= 57) || n === 61 || n === 66 || n === 67) return "小雨";
  if (n === 63) return "中雨";
  if (n === 65) return "大雨";
  if (n === 71 || n === 77 || n === 85) return "小雪";
  if (n === 73 || n === 86) return "中雪";
  if (n === 75) return "大雪";
  if (n === 80 || n === 81 || n === 82) return "阵雨";
  if (n === 95 || n === 96 || n === 99) return "雷雨";
  return "多云";
}

function readStoredJson(key) {
  const raw = wx.getStorageSync(key);
  if (!raw) return null;
  if (typeof raw === "object") return raw;
  if (typeof raw !== "string") return null;
  try {
    return JSON.parse(raw);
  } catch (e) {
    return null;
  }
}

function readCity() {
  let v = wx.getStorageSync(WEATHER_CITY_KEY);
  if (typeof v === "string") {
    try {
      v = JSON.parse(v);
    } catch (e) {
      v = null;
    }
  }
  if (!v || typeof v !== "object") return null;
  const lat = Number(v.lat);
  const lon = Number(v.lon);
  if (!isFinite(lat) || !isFinite(lon)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
  return {
    name: String(v.name || "").trim() || "这里的天气",
    lat,
    lon,
  };
}

function readManualHero() {
  const v = wx.getStorageSync(HERO_KEY);
  let period = "";
  if (typeof v === "string") period = v;
  else if (v && typeof v === "object") period = String(v.manual || "");
  return HERO_ORDER.indexOf(period) >= 0 ? period : "";
}

Page({
  data: {
    tingyuSounds: TINGYU_SOUNDS,

    // 自定义顶栏与 hero
    topbarStyle: "",
    topbarRowStyle: "",
    heroStyle: "",
    userInitial: "C",
    greeting: "你好",
    todayText: "",
    heroClass: "hero hero-day",
    heroPeriod: "day",
    heroSrc: "/assets/home/day.webp",
    heroImageFailed: false,
    heroSub: HERO_SUB.day,

    // 今日卡面（同时供卡面收藏卡复用）
    cardsFailed: false,
    cardsHint: "…",
    cardsFlipped: false,
    flipClass: "flip-inner",
    todayCardId: "",
    todayCardImage: "",
    ownedCount: 0,
    cardTotal: CARD_TOTAL,
    ownedPercent: "0%",
    cardsLine: "收藏进度同步中…",
    collectionLine: "收藏进度同步中…",

    // 打卡
    checkinDone: false,
    checkinStatusText: "同步中",
    checkinChipClass: "status-chip chip-off",
    checkinStreakText: "…",
    checkinStreakUnit: "",
    checkinSub: "正在同步打卡记录",
    checkinButtonText: "打卡",
    checkinButtonDisabled: true,
    checkinBusy: false,

    // 摸鱼日历
    fishMain: "…",
    fishSub: "正在同步摸鱼配置",
    fishRestText: "",
    fishShowChip: false,
    fishHasConfig: false,

    // 天气（城市只读，由天气页写入）
    weatherCity: "",
    weatherHasCity: false,
    weatherShowTemp: false,
    weatherTempText: "",
    weatherDesc: "…",
    weatherDetail: "",

    // 心情（本地 todo 数据的 moods）
    moodHas: false,
    moodLabel: "",
    moodDotStyle: "",
    moodTime: "",
    moodNote: "",

    // 食谱日记
    cookTitleText: "…",
    cookSub: "正在看看你的食谱",

    // 每日一言
    quoteText: "",
    quoteFrom: "",
  },

  onLoad() {
    this.alive = true;
    this.ready = false;
    this.userName = "";
    this.lastRefreshAt = 0;
    this._lastTap = null;
    this.fishConfig = null;

    this.setupNav();

    const cached = session.user();
    if (cached && cached.name) this.userName = cached.name;
    this.applyUserInitial();
    this.updateLocal();
  },

  onShow() {
    if (!this.alive) this.alive = true;
    this.syncGate();
    this.updateLocal();
    if (this.fishConfig) this.renderFish(this.fishConfig);
    if (this.ready && Date.now() - this.lastRefreshAt > 1200) {
      this.refreshAll();
    }
  },

  // 在别的 tab 退出/登录后，本页的门禁实例可能还停在旧状态。
  // 没有 token 就收回数据并重新走门禁；有 token 但门禁停在 auth 就让它重查会话。
  syncGate() {
    const gate = this.selectComponent("#gate");
    if (!gate) return;
    if (!session.token() && this.ready) {
      this.onGateExpired();
      if (typeof gate.boot === "function") gate.boot();
      return;
    }
    if (
      session.token() &&
      gate.data &&
      gate.data.stage === "auth" &&
      typeof gate.boot === "function"
    ) {
      gate.boot();
    }
  },

  onUnload() {
    this.alive = false;
  },

  onPullDownRefresh() {
    this.updateLocal();
    if (!this.ready) {
      wx.stopPullDownRefresh();
      return;
    }
    const done = () => wx.stopPullDownRefresh();
    this.refreshAll().then(done, done);
  },

  /* ---------------- 登录门禁 ---------------- */

  onGateReady(e) {
    this.ready = true;
    const user = e && e.detail && e.detail.user;
    this.applyUser(user);
    this.updateLocal();
    this.lastRefreshAt = Date.now();
    this.refreshAll();
  },

  onGateUser(e) {
    const user = e && e.detail && e.detail.user;
    if (user && user.name) {
      this.applyUser(user);
      this.updateLocal();
    }
  },

  onGateExpired() {
    this.ready = false;
    this.userName = "";
    this.lastRefreshAt = 0;
    this.fishConfig = null;
    this.applyUserInitial();
    this.updateLocal();
    this.resetRemote();
  },

  applyUser(user) {
    if (user && user.name) this.userName = String(user.name);
    this.applyUserInitial();
  },

  applyUserInitial() {
    const chars = Array.from(this.userName || "");
    this.setData({ userInitial: chars.length ? chars[0] : "C" });
  },

  resetRemote() {
    this.setData({
      cardsFailed: false,
      cardsHint: "…",
      cardsFlipped: false,
      flipClass: "flip-inner",
      todayCardId: "",
      todayCardImage: "",
      ownedCount: 0,
      ownedPercent: "0%",
      cardsLine: "收藏进度同步中…",
      collectionLine: "收藏进度同步中…",
      checkinDone: false,
      checkinStatusText: "同步中",
      checkinChipClass: "status-chip chip-off",
      checkinStreakText: "…",
      checkinStreakUnit: "",
      checkinSub: "正在同步打卡记录",
      checkinButtonText: "打卡",
      checkinButtonDisabled: true,
      checkinBusy: false,
      fishMain: "…",
      fishSub: "正在同步摸鱼配置",
      fishRestText: "",
      fishShowChip: false,
      fishHasConfig: false,
      weatherCity: "",
      weatherHasCity: false,
      weatherShowTemp: false,
      weatherTempText: "",
      weatherDesc: "…",
      weatherDetail: "",
      cookTitleText: "…",
      cookSub: "正在看看你的食谱",
    });
  },

  /* ---------------- 本地信息 ---------------- */

  setupNav() {
    let sys = {};
    try {
      sys = wx.getSystemInfoSync() || {};
    } catch (e) {
      sys = {};
    }
    const winW = Number(sys.windowWidth) || 375;
    const statusBar = Number(sys.statusBarHeight) || 20;
    let navBar = 44;
    let right = 96;
    try {
      const cap = wx.getMenuButtonBoundingClientRect();
      if (cap && Number(cap.width) > 0 && Number(cap.height) > 0) {
        const top = Number(cap.top) || statusBar;
        const h = (top - statusBar) * 2 + Number(cap.height);
        if (h >= 28 && h <= 80) navBar = h;
        right = Math.max(72, winW - Number(cap.left) + 10);
      }
    } catch (e) {
      // 取不到胶囊时用保守值，至少不会压住右上角。
    }
    const topBar = statusBar + navBar;
    this.setData({
      topbarStyle:
        "height:" +
        topBar +
        "px;padding-top:" +
        statusBar +
        "px;padding-right:" +
        right +
        "px;",
      topbarRowStyle: "height:" + navBar + "px;",
      heroStyle: "padding-top:" + topBar + "px;",
    });
  },

  updateLocal() {
    const now = new Date();
    const period = readManualHero() || timePeriod(now.getHours());
    const greeting = greetingFor(now.getHours()) + (this.userName ? "，" + this.userName : "");
    const quote = QUOTES[dayOfYear(now) % QUOTES.length];
    const patch = {
      greeting,
      todayText: now.getMonth() + 1 + "月" + now.getDate() + "日 · " + weekdayText(now),
      quoteText: "「" + quote.t + "」",
      quoteFrom: "— " + quote.f,
      heroSub: HERO_SUB[period],
    };
    if (period !== this.data.heroPeriod) {
      patch.heroPeriod = period;
      patch.heroClass = "hero hero-" + period;
      patch.heroSrc = "/assets/home/" + period + ".webp";
      patch.heroImageFailed = false;
    }
    this.setData(patch);
    this.refreshMood(now);
  },

  refreshMood(now) {
    const d = now || new Date();
    const today = dateKey(d);
    const todo = readStoredJson(TODO_KEY);
    const moods = todo && Array.isArray(todo.moods) ? todo.moods : [];
    let last = null;
    for (let i = 0; i < moods.length; i += 1) {
      const m = moods[i];
      if (m && m.date === today) last = m;
    }
    if (!last) {
      this.setData({
        moodHas: false,
        moodLabel: "",
        moodDotStyle: "",
        moodTime: "",
        moodNote: "",
      });
      return;
    }
    const meta = MOODS[last.kind] || MOODS.neutral;
    const ts = Number(last.ts);
    let time = "今天";
    if (isFinite(ts) && ts > 0) {
      const t = new Date(ts);
      time = "今天 " + pad2(t.getHours()) + ":" + pad2(t.getMinutes());
    }
    const note = String(last.note || "").trim();
    this.setData({
      moodHas: true,
      moodLabel: meta.label,
      moodDotStyle: "background:" + meta.color + ";",
      moodTime: time,
      moodNote: note.slice(0, 40),
    });
  },

  /* ---------------- 数据刷新 ---------------- */

  refreshAll() {
    if (!this.ready) return Promise.resolve();
    const token = session.token();
    if (!token) return Promise.resolve();
    return Promise.all([
      this.loadCards(token),
      this.loadCheckin(token),
      this.loadFish(token),
      this.loadWeather(),
      this.loadCook(token),
    ]).catch(() => {});
  },

  loadCards(token) {
    return api
      .cardsToday(token, CARD_IDS, false)
      .then((res) => {
        if (!this.alive) return;
        const state = (res && res.state) || {};
        const cardId = String((res && res.card) || "");
        const meta = CARD_MAP[cardId];
        const seen = {};
        let owned = 0;
        const list = Array.isArray(state.owned) ? state.owned : [];
        for (let i = 0; i < list.length; i += 1) {
          const id = String(list[i]);
          if (!seen[id] && CARD_MAP[id]) {
            seen[id] = true;
            owned += 1;
          }
        }
        const rawCredits = Number(state.credits);
        const credits =
          isFinite(rawCredits) && rawCredits > 0 ? Math.floor(rawCredits) : 0;
        const percent = CARD_TOTAL
          ? Math.min(100, Math.round((owned / CARD_TOTAL) * 100))
          : 0;
        const patch = {
          cardsFailed: false,
          ownedCount: owned,
          cardTotal: CARD_TOTAL,
          ownedPercent: percent + "%",
          cardsLine:
            "已收集 " +
            owned +
            " / " +
            CARD_TOTAL +
            " · 剩余抽取 " +
            credits +
            " 次",
          collectionLine: "已收集 " + owned + " / " + CARD_TOTAL,
        };
        if (meta && meta.file) {
          patch.todayCardId = cardId;
          patch.todayCardImage = cardUrl(meta.file);
          patch.cardsHint = "轻点翻面";
          if (cardId !== this.data.todayCardId) {
            patch.cardsFlipped = false;
            patch.flipClass = "flip-inner";
          }
        } else {
          patch.todayCardId = "";
          patch.todayCardImage = "";
          patch.cardsHint = "今日卡面稍后见";
          patch.cardsFlipped = false;
          patch.flipClass = "flip-inner";
        }
        this.setData(patch);
      })
      .catch(() => {
        if (!this.alive) return;
        this.setData({
          cardsFailed: true,
          cardsHint: "今日卡面稍后见",
          todayCardId: "",
          todayCardImage: "",
          cardsFlipped: false,
          flipClass: "flip-inner",
          cardsLine: "收藏进度稍后同步",
          collectionLine: "已收集 — / " + CARD_TOTAL,
          ownedPercent: "0%",
        });
      });
  },

  loadCheckin(token) {
    return api
      .checkinStats(token)
      .then((res) => {
        if (!this.alive) return;
        const done = !!(res && res.checkedInToday);
        const raw = Number(res && res.streak);
        const streak = isFinite(raw) && raw > 0 ? Math.floor(raw) : 0;
        this.applyCheckin(done, streak);
      })
      .catch(() => {
        if (!this.alive) return;
        const done = this.data.checkinDone;
        this.setData({
          checkinStatusText: done ? "已打卡" : "稍后同步",
          checkinChipClass: done ? "status-chip" : "status-chip chip-off",
          checkinStreakText: done ? this.data.checkinStreakText : "—",
          checkinStreakUnit: done ? "天" : "",
          checkinSub: done ? this.data.checkinSub : "打卡数据稍后再试",
          checkinButtonText: done ? "今天已打卡" : "打卡",
          checkinButtonDisabled: done,
          checkinBusy: false,
        });
      });
  },

  applyCheckin(done, streak) {
    const sub = done
      ? streak > 0
        ? "连续第 " + streak + " 天，今天也来过啦"
        : "今天来过啦"
      : "来过就算数，轻轻按一下";
    this.setData({
      checkinDone: done,
      checkinStreakText: String(streak),
      checkinStreakUnit: "天",
      checkinStatusText: done ? "已打卡" : "未打卡",
      checkinChipClass: done ? "status-chip" : "status-chip chip-off",
      checkinSub: sub,
      checkinButtonText: done ? "今天已打卡" : "打卡",
      checkinButtonDisabled: done,
      checkinBusy: false,
    });
  },

  onCheckin() {
    if (!this.ready) return;
    if (this.data.checkinBusy || this.data.checkinDone) return;
    const token = session.token();
    if (!token) {
      wx.showToast({ title: "请先登录", icon: "none" });
      return;
    }
    this.setData({
      checkinBusy: true,
      checkinButtonDisabled: true,
      checkinButtonText: "打卡中…",
    });
    api
      .checkinSave(token)
      .then((res) => {
        if (!this.alive) return;
        const done =
          res && typeof res.checkedInToday === "boolean"
            ? res.checkedInToday
            : true;
        let streak = Number(this.data.checkinStreakText);
        if (!isFinite(streak) || streak < 0) streak = 0;
        const raw = Number(res && res.streak);
        if (isFinite(raw) && raw >= 0) streak = Math.floor(raw);
        this.applyCheckin(done, streak);
        wx.showToast({ title: "今天也来过啦", icon: "none" });
        // 打卡后刷新打卡数据与卡面收藏进度。
        Promise.all([this.loadCheckin(token), this.loadCards(token)]).catch(
          () => {}
        );
      })
      .catch(() => {
        if (!this.alive) return;
        const done = this.data.checkinDone;
        this.setData({
          checkinBusy: false,
          checkinButtonDisabled: done,
          checkinButtonText: done ? "今天已打卡" : "打卡",
        });
        wx.showToast({ title: "打卡失败，请稍后再试", icon: "none" });
      });
  },

  loadFish(token) {
    return api
      .moyuGet(token)
      .then((res) => {
        if (!this.alive) return;
        const config = res && res.config;
        if (!config || typeof config !== "object") {
          this.fishConfig = null;
          this.setData({
            fishMain: "设置上下班时间",
            fishSub: "告诉我你的作息，帮你数着下班",
            fishRestText: "",
            fishShowChip: false,
            fishHasConfig: false,
          });
          return;
        }
        this.fishConfig = config;
        this.renderFish(config);
      })
      .catch(() => {
        if (!this.alive) return;
        this.fishConfig = null;
        this.setData({
          fishMain: "摸鱼日历稍后再看",
          fishSub: "暂时没连上，稍后刷新试试",
          fishRestText: "",
          fishShowChip: false,
          fishHasConfig: false,
        });
      });
  },

  renderFish(config) {
    if (!config || typeof config !== "object") return;
    const rest = [];
    const rawRest = Array.isArray(config.rest) ? config.rest : [];
    for (let i = 0; i < rawRest.length; i += 1) {
      const n = Number(rawRest[i]);
      if (isFinite(n) && n >= 0 && n <= 6 && rest.indexOf(n) < 0) rest.push(n);
    }
    const start = hmText(config.start) || "09:00";
    const end = hmText(config.end) || "18:00";
    const breakStart = hmText(config.breakStart);
    const breakEnd = hmText(config.breakEnd);
    const now = new Date();
    const isRest = rest.indexOf(now.getDay()) >= 0;
    const startMin = hmToMinutes(start);
    const endMin = hmToMinutes(end);
    const nowMin = now.getHours() * 60 + now.getMinutes();
    let main = "上班 " + start + " · 下班 " + end;
    if (isRest) {
      main = "今天是休息日，慢慢过";
    } else if (endMin >= 0 && nowMin >= endMin) {
      main = "已经下班啦，去吹吹风";
    } else if (startMin >= 0 && nowMin < startMin) {
      main = "距上班 " + durationText(startMin - nowMin);
    } else if (endMin >= 0) {
      main = "距下班 " + durationText(endMin - nowMin);
    }
    let sub = "上班 " + start + " · 下班 " + end;
    if (breakStart && breakEnd) sub += " · 午休 " + breakStart + "-" + breakEnd;
    this.setData({
      fishHasConfig: true,
      fishMain: main,
      fishSub: sub,
      fishRestText: "本周休息 " + rest.length + " 天",
      fishShowChip: true,
    });
  },

  loadWeather() {
    const city = readCity();
    if (!city) {
      this.setData({
        weatherCity: "",
        weatherHasCity: false,
        weatherShowTemp: false,
        weatherTempText: "",
        weatherDesc: "选择城市看天气",
        weatherDetail: "在天气页手动选一个城市",
      });
      return Promise.resolve();
    }
    const patch = { weatherCity: city.name, weatherHasCity: true };
    if (!this.data.weatherShowTemp) {
      patch.weatherDesc = "…";
      patch.weatherDetail = "正在看看外面的天气";
    }
    this.setData(patch);
    return api
      .weather(city.lat, city.lon)
      .then((body) => {
        if (!this.alive) return;
        const current = body && body.current;
        if (!current || typeof current !== "object") {
          throw new Error("weather shape");
        }
        const temp = Math.round(Number(current.temperature_2m));
        const feels = Math.round(Number(current.apparent_temperature));
        const daily = body && body.daily;
        const maxArr = daily && daily.temperature_2m_max;
        const minArr = daily && daily.temperature_2m_min;
        const max = Array.isArray(maxArr) ? Math.round(Number(maxArr[0])) : NaN;
        const min = Array.isArray(minArr) ? Math.round(Number(minArr[0])) : NaN;
        const parts = [];
        if (isFinite(feels)) parts.push("体感 " + feels + "°");
        if (isFinite(max) && isFinite(min)) {
          parts.push("最高 " + max + "° / 最低 " + min + "°");
        }
        this.setData({
          weatherShowTemp: true,
          weatherTempText: isFinite(temp) ? temp + "°" : "—",
          weatherDesc: weatherText(current.weather_code),
          weatherDetail: parts.join(" · ") || "出门前看看窗外",
        });
      })
      .catch(() => {
        if (!this.alive) return;
        this.setData({
          weatherShowTemp: false,
          weatherTempText: "",
          weatherDesc: "天气稍后见",
          weatherDetail: "稍后刷新试试",
        });
      });
  },

  loadCook(token) {
    return api
      .cookData(token)
      .then((body) => {
        if (!this.alive) return;
        let data = body;
        if (body && body.data && typeof body.data === "object") {
          data = body.data;
        }
        const recipes =
          data && Array.isArray(data.recipes) ? data.recipes : [];
        let latest = null;
        let latestAt = -Infinity;
        for (let i = 0; i < recipes.length; i += 1) {
          const r = recipes[i];
          if (!r) continue;
          let at = Number(r.updatedAt);
          if (!isFinite(at)) at = Number(r.createdAt);
          if (!isFinite(at)) at = 0;
          if (!latest || at > latestAt) {
            latest = r;
            latestAt = at;
          }
        }
        let title = "";
        if (latest) title = String(latest.title || latest.name || "").trim();
        this.setData({
          cookTitleText: recipes.length
            ? title || "未命名食谱"
            : "还没有食谱",
          cookSub: recipes.length
            ? "共 " + recipes.length + " 篇 · 最近的一篇"
            : "去记下今天吃了什么",
        });
      })
      .catch(() => {
        if (!this.alive) return;
        this.setData({
          cookTitleText: "食谱稍后见",
          cookSub: "稍后再试",
        });
      });
  },

  /* ---------------- 交互 ---------------- */

  onHeroTap(e) {
    const now = Date.now();
    const touch = e && e.changedTouches && e.changedTouches[0];
    const x = touch
      ? Number(touch.clientX) || 0
      : Number(e && e.detail && e.detail.x) || 0;
    const y = touch
      ? Number(touch.clientY) || 0
      : Number(e && e.detail && e.detail.y) || 0;
    const last = this._lastTap;
    this._lastTap = { at: now, x, y };
    if (
      last &&
      now - last.at <= 320 &&
      Math.abs(x - last.x) <= 40 &&
      Math.abs(y - last.y) <= 40
    ) {
      this._lastTap = null;
      this.cycleHero();
    }
  },

  cycleHero() {
    const idx = HERO_ORDER.indexOf(this.data.heroPeriod);
    const next = HERO_ORDER[(idx + 1 + HERO_ORDER.length) % HERO_ORDER.length];
    try {
      wx.setStorageSync(HERO_KEY, { manual: next });
    } catch (e) {
      // 存储失败也不影响本次切换。
    }
    this.setData({
      heroPeriod: next,
      heroClass: "hero hero-" + next,
      heroSrc: "/assets/home/" + next + ".webp",
      heroSub: HERO_SUB[next],
      heroImageFailed: false,
    });
  },

  onHeroImageError() {
    this.setData({ heroImageFailed: true });
  },

  onFlipCard() {
    if (!this.data.todayCardImage) return;
    const flipped = !this.data.cardsFlipped;
    this.setData({
      cardsFlipped: flipped,
      flipClass: flipped ? "flip-inner flipped" : "flip-inner",
    });
  },

  onCardImageError() {
    this.setData({
      todayCardImage: "",
      cardsHint: "今日卡面稍后见",
      cardsFlipped: false,
      flipClass: "flip-inner",
    });
  },

  onUserTap() {
    wx.switchTab({ url: "/pages/me/me" });
  },

  onOpenCards() {
    wx.navigateTo({ url: "/pages/cards/cards" });
  },

  onOpenFish() {
    wx.navigateTo({ url: "/pages/fish/fish" });
  },

  onOpenWeather() {
    wx.navigateTo({ url: "/pages/weather/weather" });
  },

  onOpenMood() {
    wx.navigateTo({ url: "/pages/mood/mood" });
  },

  onOpenTingyu() {
    wx.navigateTo({ url: "/pages/tingyu/tingyu" });
  },

  onOpenCook() {
    wx.navigateTo({ url: "/pages/cook/cook" });
  },

  onOpenDoc(e) {
    const type = e && e.currentTarget && e.currentTarget.dataset.type;
    wx.navigateTo({
      url:
        "/pages/agreement/agreement?type=" +
        (type === "privacy" ? "privacy" : "terms"),
    });
  },
});