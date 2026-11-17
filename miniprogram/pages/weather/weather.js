// 天气页：手动选城市，数据来自 Open-Meteo（经 chimu-claw.xyz 服务端代理）。
// 不调用 wx.getLocation，定位隐私接口与类目限制都绕开，城市由用户搜索选择。
const api = require("../../utils/api");
const session = require("../../utils/session");

const CITY_KEY = "citro_weather_city";
const WEEKDAYS = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];

function pad2(n) {
  return n < 10 ? "0" + n : "" + n;
}

function numText(v, suffix) {
  const n = Number(v);
  return isFinite(n) ? String(Math.round(n)) + (suffix || "") : "--";
}

// WMO 天气码 → 中文描述 + 图标（范围与 App 端映射一致）。
function weatherInfo(code) {
  const c = Number(code);
  if (c === 0) return { desc: "晴", emoji: "☀️" };
  if (c >= 1 && c <= 3) return { desc: "多云", emoji: "⛅" };
  if (c === 45 || c === 48) return { desc: "雾", emoji: "🌫️" };
  if (c >= 51 && c <= 57) return { desc: "毛毛雨", emoji: "🌦️" };
  if (c >= 61 && c <= 67) return { desc: "雨", emoji: "🌧️" };
  if (c >= 71 && c <= 77) return { desc: "雪", emoji: "🌨️" };
  if (c >= 80 && c <= 82) return { desc: "阵雨", emoji: "🌦️" };
  if (c >= 85 && c <= 86) return { desc: "阵雪", emoji: "🌨️" };
  if (c >= 95 && c <= 99) return { desc: "雷雨", emoji: "⛈️" };
  return { desc: "多云", emoji: "⛅" };
}

function dateStr(now) {
  return now.getFullYear() + "-" + pad2(now.getMonth() + 1) + "-" + pad2(now.getDate());
}

function labelCity(city) {
  if (!city) return "";
  const extra =
    city.admin1 && city.admin1 !== city.name ? " · " + city.admin1 : "";
  return city.name + extra;
}

function sunText(v) {
  const s = typeof v === "string" ? v : "";
  return s.length >= 16 ? s.slice(11, 16) : "";
}

function buildCurrent(data, now) {
  const c = data && data.current;
  if (!c || c.temperature_2m === undefined || c.temperature_2m === null) {
    return null;
  }
  const info = weatherInfo(c.weather_code);
  return {
    tempText: numText(c.temperature_2m, "°"),
    desc: info.desc,
    emoji: info.emoji,
    feelsText: numText(c.apparent_temperature, "°"),
    humidityText: numText(c.relative_humidity_2m, "%"),
    windText: numText(c.wind_speed_10m, " km/h"),
    updatedText: "更新于 " + pad2(now.getHours()) + ":" + pad2(now.getMinutes()),
  };
}

// 从当前整点开始，每 2 小时取一项，共覆盖未来 24 小时。
function buildHourly(data, now) {
  const h = data && data.hourly;
  if (!h || !Array.isArray(h.time) || !h.time.length) return [];
  const target = dateStr(now) + "T" + pad2(now.getHours()) + ":00";
  let start = -1;
  for (let i = 0; i < h.time.length; i++) {
    if (String(h.time[i]) >= target) {
      start = i;
      break;
    }
  }
  if (start < 0) start = 0;
  const temps = h.temperature_2m || [];
  const codes = h.weather_code || [];
  const pops = h.precipitation_probability || [];
  const out = [];
  const end = Math.min(h.time.length, start + 24);
  for (let i = start; i < end; i += 2) {
    const t = String(h.time[i]);
    const info = weatherInfo(codes[i]);
    const pop = pops[i];
    out.push({
      key: t,
      time: t.length >= 16 ? t.slice(11, 16) : t,
      emoji: info.emoji,
      tempText: numText(temps[i], "°"),
      popText:
        pop === null || pop === undefined
          ? ""
          : Math.round(Number(pop)) + "%",
    });
  }
  return out;
}

function buildDaily(data) {
  const d = data && data.daily;
  if (!d || !Array.isArray(d.time) || !d.time.length) return [];
  const codes = d.weather_code || [];
  const maxs = d.temperature_2m_max || [];
  const mins = d.temperature_2m_min || [];
  const pops = d.precipitation_probability_max || [];
  const out = [];
  const n = Math.min(7, d.time.length);
  for (let i = 0; i < n; i++) {
    const date = String(d.time[i]);
    const parts = date.split("-");
    let day = date;
    if (parts.length === 3) {
      const dt = new Date(
        Number(parts[0]),
        Number(parts[1]) - 1,
        Number(parts[2])
      );
      if (!isNaN(dt.getTime())) day = WEEKDAYS[dt.getDay()];
    }
    if (i === 0) day = "今天";
    else if (i === 1) day = "明天";
    const info = weatherInfo(codes[i]);
    const pop = pops[i];
    out.push({
      key: date,
      day: day,
      emoji: info.emoji,
      desc: info.desc,
      popText:
        pop === null || pop === undefined
          ? ""
          : Math.round(Number(pop)) + "%",
      highText: numText(maxs[i], "°"),
      lowText: numText(mins[i], "°"),
    });
  }
  return out;
}

Page({
  data: {
    searchQ: "",
    searchBtnText: "搜索",
    searching: false,
    showResults: false,
    results: [],
    resultsEmpty: false,
    searchHint: "",

    city: null,
    hasCity: false,
    cityLabel: "",
    dateLine: "",

    loading: false,
    showLoading: false,
    error: false,
    refreshText: "刷新",
    showGuide: true,

    current: null,
    hourly: [],
    daily: [],
    hasHourly: false,
    hasDaily: false,
    sunrise: "",
    sunset: "",
    showSun: false,
  },

  onLoad() {
    if (!session.token()) {
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    this._loadSeq = 0;
    this._searchSeq = 0;
    const now = new Date();
    const raw = wx.getStorageSync(CITY_KEY);
    let city = null;
    if (
      raw &&
      typeof raw === "object" &&
      typeof raw.name === "string" &&
      raw.name
    ) {
      const lat = Number(raw.lat);
      const lon = Number(raw.lon);
      if (
        isFinite(lat) &&
        isFinite(lon) &&
        Math.abs(lat) <= 90 &&
        Math.abs(lon) <= 180
      ) {
        city = {
          name: raw.name,
          lat: lat,
          lon: lon,
          admin1: typeof raw.admin1 === "string" ? raw.admin1 : "",
          country: typeof raw.country === "string" ? raw.country : "",
        };
      }
    }
    this.setData({
      dateLine:
        now.getMonth() +
        1 +
        "月" +
        now.getDate() +
        "日 · " +
        WEEKDAYS[now.getDay()],
      city: city,
      hasCity: !!city,
      cityLabel: labelCity(city),
      showGuide: !city,
    });
    // 有缓存城市直接加载；没有则只展示搜索引导，不发任何请求。
    if (city) this.loadWeather();
  },

  onSearchInput(e) {
    const q = (e && e.detail && e.detail.value) || "";
    this.setData({ searchQ: q });
    if (!String(q).trim()) {
      this.setData({
        showResults: false,
        results: [],
        resultsEmpty: false,
        searchHint: "",
      });
    }
  },

  onSearch(e) {
    const raw =
      e && e.detail && typeof e.detail.value === "string"
        ? e.detail.value
        : this.data.searchQ;
    const q = String(raw || "").trim();
    if (!q) {
      wx.showToast({ title: "请输入城市名", icon: "none" });
      return;
    }
    if (this.data.searching) return;
    const seq = ++this._searchSeq;
    this.setData({
      searching: true,
      searchBtnText: "搜索中",
      searchQ: q,
      showResults: true,
      results: [],
      resultsEmpty: false,
      searchHint: "正在搜索…",
    });
    api
      .weatherGeocode(q)
      .then((res) => {
        if (seq !== this._searchSeq) return;
        const list = res && Array.isArray(res.results) ? res.results : [];
        const results = list
          .slice(0, 8)
          .map((r, i) => {
            const lat = Number(r.latitude);
            const lon = Number(r.longitude);
            const admin1 = typeof r.admin1 === "string" ? r.admin1 : "";
            const country = typeof r.country === "string" ? r.country : "";
            const sub = admin1 && country ? admin1 + " · " + country : admin1 || country;
            return {
              id: String(i) + "|" + (r.name || "") + "|" + lat + "|" + lon,
              name: typeof r.name === "string" && r.name ? r.name : "未知城市",
              lat: lat,
              lon: lon,
              admin1: admin1,
              country: country,
              sub: sub,
            };
          })
          .filter((r) => isFinite(r.lat) && isFinite(r.lon));
        this.setData({
          searching: false,
          searchBtnText: "搜索",
          results: results,
          resultsEmpty: results.length === 0,
          searchHint:
            results.length === 0
              ? "没有找到这个城市，换个关键词试试"
              : "点选一个城市即可加载天气",
        });
      })
      .catch(() => {
        if (seq !== this._searchSeq) return;
        this.setData({
          searching: false,
          searchBtnText: "搜索",
          results: [],
          resultsEmpty: true,
          searchHint: "搜索失败，请稍后再试",
        });
      });
  },

  onPickCity(e) {
    const idx = Number(e.currentTarget.dataset.index);
    const r = this.data.results[idx];
    if (!r) return;
    const city = {
      name: r.name,
      lat: r.lat,
      lon: r.lon,
      admin1: r.admin1,
      country: r.country,
    };
    wx.setStorageSync(CITY_KEY, city);
    this.setData({
      city: city,
      hasCity: true,
      cityLabel: labelCity(city),
      searchQ: r.name,
      showResults: false,
      results: [],
      resultsEmpty: false,
      searchHint: "",
      showGuide: false,
    });
    this.loadWeather();
  },

  onRefresh() {
    if (this.data.loading) return;
    this.loadWeather();
  },

  onRetry() {
    if (this.data.loading) return;
    this.loadWeather();
  },

  onPullDownRefresh() {
    if (!this.data.hasCity || this.data.loading) {
      wx.stopPullDownRefresh();
      return;
    }
    this.loadWeather();
  },

  loadWeather() {
    const city = this.data.city;
    if (!city) return;
    const seq = ++this._loadSeq;
    this.setData({
      loading: true,
      showLoading: !this.data.current,
      error: false,
      showGuide: false,
      refreshText: "刷新中",
    });
    api
      .weather(city.lat, city.lon)
      .then((data) => {
        if (seq !== this._loadSeq) return;
        const now = new Date();
        const current = buildCurrent(data, now);
        if (!current) throw new Error("bad weather payload");
        const hourly = buildHourly(data, now);
        const daily = buildDaily(data);
        const sunrise = sunText(
          data.daily && data.daily.sunrise && data.daily.sunrise[0]
        );
        const sunset = sunText(
          data.daily && data.daily.sunset && data.daily.sunset[0]
        );
        this.setData({
          loading: false,
          showLoading: false,
          error: false,
          refreshText: "刷新",
          current: current,
          hourly: hourly,
          daily: daily,
          hasHourly: hourly.length > 0,
          hasDaily: daily.length > 0,
          sunrise: sunrise,
          sunset: sunset,
          showSun: !!(sunrise && sunset),
          showGuide: false,
        });
        wx.stopPullDownRefresh();
      })
      .catch(() => {
        if (seq !== this._loadSeq) return;
        this.setData({
          loading: false,
          showLoading: false,
          error: true,
          refreshText: "刷新",
          current: null,
          hourly: [],
          daily: [],
          hasHourly: false,
          hasDaily: false,
          sunrise: "",
          sunset: "",
          showSun: false,
        });
        wx.stopPullDownRefresh();
      });
  },
});