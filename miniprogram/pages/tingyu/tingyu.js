// 听隅 · 小程序端
// 声音名称与分类以 flutter/lib/tingyu/tingyu_models.dart 的 sounds 为准，
// 这里精选 27 条，一次只播一条，离开页面就停止并销毁音频。
const session = require("../../utils/session");

const AUDIO_BASE = "https://obs.chimu-claw.xyz/ambient%20noise/";

const CATEGORY_META = {
  雨声: { glyph: "雨", color: "#8FA6BE" },
  森林: { glyph: "林", color: "#8FB8A0" },
  水流: { glyph: "溪", color: "#7C8AA0" },
  风铃: { glyph: "铃", color: "#E0A03E" },
  水下: { glyph: "潜", color: "#9A8FA6" },
  城市: { glyph: "城", color: "#A79E8C" },
  篝火: { glyph: "火", color: "#C4855D" },
  噪声: { glyph: "噪", color: "#9C867F" },
};

const CATEGORY_ORDER = [
  "雨声",
  "森林",
  "水流",
  "风铃",
  "水下",
  "城市",
  "篝火",
  "噪声",
];

const SOUNDS = [
  { id: "rain", name: "雨幕远雷", category: "雨声", desc: "真实雨声，伴有雷声起伏" },
  { id: "rain_soft", name: "伞下雨声", category: "雨声", desc: "雨滴落在伞面的持续声响" },
  { id: "rain_roof", name: "车顶落雨", category: "雨声", desc: "坐在车里，听雨滴打在车顶" },
  { id: "forest", name: "林间鸟鸣", category: "森林", desc: "鸟鸣与虫声，偶有远处车声" },
  { id: "crickets", name: "田野蟋蟀", category: "森林", desc: "田野里，一只蟋蟀的鸣唱" },
  { id: "cicadas", name: "林野蝉鸣", category: "森林", desc: "多只蝉鸣交织的自然底色" },
  { id: "frogs", name: "池畔蛙鸣", category: "森林", desc: "池畔群蛙，伴着背景水声" },
  { id: "leaves", name: "风吹灌木", category: "森林", desc: "乡间灌木丛里，风在穿行" },
  { id: "wind", name: "草野之风", category: "森林", desc: "有风经过高草的午后" },
  { id: "stream", name: "潺潺溪流", category: "水流", desc: "让思绪，跟着水流走" },
  { id: "river", name: "河道流水", category: "水流", desc: "河道里持续流动的水声" },
  { id: "waterfall", name: "山间瀑布", category: "水流", desc: "山间小瀑布，绵密而厚实" },
  { id: "ocean", name: "海浪与海鸟", category: "水流", desc: "浪拍岸边，鸟鸣掠过" },
  { id: "chimes", name: "风铃清音", category: "风铃", desc: "棚内实录，清亮的铃音" },
  { id: "underwater", name: "水下静域", category: "水下", desc: "低沉而柔和的合成氛围" },
  { id: "bubbles", name: "近水气泡", category: "水下", desc: "吸管吹出的真实水泡，近水细节" },
  { id: "cafe", name: "街角咖啡馆", category: "城市", desc: "含交谈声的咖啡馆氛围" },
  { id: "train", name: "列车车厢", category: "城市", desc: "列车行进中的稳定环境声" },
  { id: "traffic", name: "桥上车流", category: "城市", desc: "桥上俯瞰的巴黎环城车流" },
  { id: "fan", name: "电扇低鸣", category: "城市", desc: "电扇稳定转动的持续低鸣" },
  { id: "clock", name: "机械钟滴答", category: "城市", desc: "不紧不慢地走过每一秒" },
  { id: "keyboard", name: "键盘慢敲", category: "城市", desc: "慢速打字，陪你把事做完" },
  { id: "laundry", name: "洗衣机滚筒", category: "城市", desc: "烘干模式中段的平稳转动" },
  { id: "fire", name: "枝火轻响", category: "篝火", desc: "户外枝火，间有清脆爆裂声" },
  { id: "fireplace", name: "壁炉薪火", category: "篝火", desc: "木柴燃烧，比枝火更柔一些" },
  { id: "white", name: "白噪声", category: "噪声", desc: "均匀、明亮的声音底色" },
  { id: "pink", name: "粉红噪声", category: "噪声", desc: "更柔和的宽频声音" },
  { id: "brown", name: "棕色噪声", category: "噪声", desc: "温厚、低沉，少一点锐利" },
];

const SOUND_MAP = {};
SOUNDS.forEach((s) => {
  SOUND_MAP[s.id] = s;
});

const TIMER_MINUTES = [15, 30, 60];

function pad2(n) {
  return String(n).padStart(2, "0");
}

function clockText(seconds) {
  const n = Math.max(0, Math.floor(Number(seconds) || 0));
  const h = Math.floor(n / 3600);
  const m = Math.floor((n % 3600) / 60);
  const s = n % 60;
  return h > 0
    ? h + ":" + pad2(m) + ":" + pad2(s)
    : pad2(m) + ":" + pad2(s);
}

function rgba(hex, alpha) {
  const s = String(hex || "").replace("#", "");
  if (s.length !== 6) return "rgba(156, 134, 127, " + alpha + ")";
  return (
    "rgba(" +
    parseInt(s.slice(0, 2), 16) +
    ", " +
    parseInt(s.slice(2, 4), 16) +
    ", " +
    parseInt(s.slice(4, 6), 16) +
    ", " +
    alpha +
    ")"
  );
}

function audioUrl(id) {
  return AUDIO_BASE + encodeURIComponent(String(id || "")) + ".wav";
}

function buildCategoryChips(selected) {
  const chips = [
    { id: "全部", name: "全部", on: selected === "全部" },
  ];
  CATEGORY_ORDER.forEach((name) => {
    chips.push({ id: name, name, on: selected === name });
  });
  return chips;
}

function buildTimerChips(activeMin) {
  return TIMER_MINUTES.map((min) => ({
    min,
    label: min + " 分钟",
    on: min === activeMin,
  }));
}

function buildGroups(selected, currentId, playing, loading) {
  const names = selected === "全部" ? CATEGORY_ORDER : [selected];
  const groups = [];
  names.forEach((name) => {
    const meta = CATEGORY_META[name] || { glyph: "声", color: "#9C867F" };
    const items = SOUNDS.filter((s) => s.category === name).map((s) => {
      const on = s.id === currentId;
      let stateLabel = "▶";
      if (on) stateLabel = loading ? "…" : playing ? "Ⅱ" : "▶";
      return {
        id: s.id,
        name: s.name,
        desc: s.desc,
        letter: meta.glyph,
        iconStyle:
          "background:" +
          rgba(meta.color, 0.16) +
          ";color:" +
          meta.color +
          ";",
        on,
        rowClass: "sound" + (on ? " on" : "") + (on && playing ? " playing" : ""),
        stateClass: "sound-state" + (on ? " on" : ""),
        stateLabel,
      };
    });
    if (items.length) {
      groups.push({
        id: name,
        name,
        color: meta.color,
        countText: items.length + " 条",
        items,
      });
    }
  });
  return groups;
}

Page({
  data: {
    ready: false,
    selectedCat: "全部",
    categories: buildCategoryChips("全部"),
    groups: buildGroups("全部", "", false, false),
    hasActive: false,
    playing: false,
    loading: false,
    playerName: "还没有播放",
    playerSub: "从下面选一条声音开始",
    playerGlyph: "▶",
    progress: 0,
    timeNow: "00:00",
    timeTotal: "--:--",
    volume: 70,
    timerActive: false,
    timerStateText: "未设定",
    timerChips: buildTimerChips(0),
  },

  onLoad() {
    this.alive = true;
    this.audio = null;
    this.currentId = "";
    this.currentName = "";
    this.currentCat = "";
    this.playing = false;
    this.loading = false;
    this.volume = 70;
    this.erroredId = "";
    this.timerActive = false;
    this.timerMin = 0;
    this.timerDeadline = 0;
    this.expireTimer = null;
    this.tickTimer = null;
    this.lastClock = "";
    this.lastDuration = -1;

    const token = session.token();
    if (!token) {
      wx.switchTab({ url: "/pages/home/home" });
      return;
    }
    this.token = token;
    this.setData({ ready: true });
  },

  onHide() {
    this.teardown(true);
  },

  onUnload() {
    this.alive = false;
    this.teardown(false);
  },

  /* ---------------- 分类与列表 ---------------- */

  onSelectCategory(e) {
    const id = e && e.currentTarget && e.currentTarget.dataset.id;
    if (!id || id === this.data.selectedCat) return;
    this.setData({
      selectedCat: id,
      categories: buildCategoryChips(id),
      groups: buildGroups(
        id,
        this.currentId,
        this.playing,
        this.loading
      ),
    });
  },

  refreshList() {
    if (!this.alive) return;
    this.setData({
      groups: buildGroups(
        this.data.selectedCat,
        this.currentId,
        this.playing,
        this.loading
      ),
    });
  },

  /* ---------------- 音频 ---------------- */

  ensureAudio() {
    if (this.audio) return this.audio;
    const ctx = wx.createInnerAudioContext();
    ctx.loop = true;
    ctx.autoplay = false;
    ctx.obeyMuteSwitch = true;
    ctx.volume = this.volume / 100;

    const self = this;
    ctx.onPlay(() => {
      if (!self.alive) return;
      self.playing = true;
      self.loading = false;
      self.erroredId = "";
      self.publishPlayer();
      self.refreshList();
    });
    ctx.onPause(() => {
      if (!self.alive) return;
      self.playing = false;
      self.publishPlayer();
      self.refreshList();
    });
    ctx.onStop(() => {
      if (!self.alive) return;
      // 切歌时 stop 可能在新音源 play 之后才回调；这里保留 loading 状态。
      self.playing = false;
      self.publishPlayer();
      self.refreshList();
    });
    if (ctx.onWaiting) {
      ctx.onWaiting(() => {
        if (!self.alive) return;
        self.loading = true;
        self.publishPlayer();
        self.refreshList();
      });
    }
    if (ctx.onCanplay) {
      ctx.onCanplay(() => {
        if (!self.alive) return;
        self.loading = false;
        self.publishPlayer();
        self.refreshList();
      });
    }
    if (ctx.onTimeUpdate) {
      ctx.onTimeUpdate(() => self.handleTimeUpdate());
    }
    ctx.onError(() => self.handleAudioError());

    this.audio = ctx;
    return ctx;
  },

  handleAudioError() {
    this.playing = false;
    this.loading = false;
    if (!this.alive) return;
    this.setData({
      progress: 0,
      timeNow: "00:00",
      timeTotal: "--:--",
    });
    this.publishPlayer();
    this.refreshList();
    const id = this.currentId;
    if (id && this.erroredId !== id) {
      this.erroredId = id;
      wx.showToast({ title: "这条声音暂时听不到", icon: "none" });
    }
  },

  handleTimeUpdate() {
    if (!this.alive || !this.audio || !this.currentId) return;
    const rawDur = Number(this.audio.duration);
    const rawCur = Number(this.audio.currentTime);
    const dur = isFinite(rawDur) && rawDur > 0 ? rawDur : 0;
    const cur = isFinite(rawCur) && rawCur > 0 ? rawCur : 0;
    const second = Math.floor(cur);
    if (second === this.lastClock && dur === this.lastDuration) return;
    this.lastClock = second;
    this.lastDuration = dur;
    this.setData({
      progress: dur > 0 ? Math.min(100, Math.round((cur / dur) * 100)) : 0,
      timeNow: clockText(cur),
      timeTotal: dur > 0 ? clockText(dur) : "--:--",
    });
  },

  onTapSound(e) {
    const id = e && e.currentTarget && e.currentTarget.dataset.id;
    const spec = SOUND_MAP[id];
    if (!spec) return;

    if (this.currentId === id) {
      if (!this.audio) {
        this.startTrack(id, spec);
        return;
      }
      if (this.playing) {
        this.audio.pause();
      } else {
        this.loading = true;
        this.publishPlayer();
        this.refreshList();
        this.audio.play();
      }
      return;
    }
    this.startTrack(id, spec);
  },

  startTrack(id, spec) {
    const previousId = this.currentId;
    this.currentId = id;
    this.currentName = spec.name;
    this.currentCat = spec.category;
    this.playing = false;
    this.loading = true;
    this.erroredId = "";
    this.lastClock = "";
    this.lastDuration = -1;

    try {
      const ctx = this.ensureAudio();
      if (previousId && previousId !== id) ctx.stop();
      ctx.src = audioUrl(id);
      ctx.volume = this.volume / 100;
      ctx.play();
    } catch (err) {
      this.handleAudioError();
      return;
    }

    this.setData({ progress: 0, timeNow: "00:00", timeTotal: "--:--" });
    this.publishPlayer();
    this.refreshList();
  },

  onTogglePlay() {
    if (!this.currentId) {
      wx.showToast({ title: "先从列表里选一条声音", icon: "none" });
      return;
    }
    if (!this.audio) {
      const spec = SOUND_MAP[this.currentId];
      if (spec) this.startTrack(this.currentId, spec);
      return;
    }
    if (this.playing) {
      this.audio.pause();
      return;
    }
    try {
      this.loading = true;
      this.publishPlayer();
      this.refreshList();
      this.audio.play();
    } catch (err) {
      this.handleAudioError();
    }
  },

  onVolume(e) {
    const raw = Number(e && e.detail && e.detail.value);
    const v = isFinite(raw) ? Math.max(0, Math.min(100, Math.round(raw))) : 0;
    this.volume = v;
    if (this.audio) this.audio.volume = v / 100;
    if (v !== this.data.volume) this.setData({ volume: v });
  },

  publishPlayer() {
    if (!this.alive) return;
    this.setData({
      hasActive: !!this.currentId,
      playerName: this.currentName || "还没有播放",
      playerSub: this.playerSubText(),
      playerGlyph: this.loading ? "…" : this.playing ? "Ⅱ" : "▶",
      playing: this.playing,
      loading: this.loading,
    });
  },

  playerSubText() {
    if (!this.currentId) return "从下面选一条声音开始";
    const cat = this.currentCat || "声音";
    if (this.timerActive) {
      const remain = Math.max(
        0,
        Math.ceil((this.timerDeadline - Date.now()) / 1000)
      );
      return cat + " · 定时剩余 " + clockText(remain);
    }
    return cat + " · 循环播放";
  },

  /* ---------------- 睡眠定时 ---------------- */

  onTimer(e) {
    const raw = Number(e && e.currentTarget && e.currentTarget.dataset.min);
    if (TIMER_MINUTES.indexOf(raw) < 0) return;
    this.clearTimerTimers();
    this.timerActive = true;
    this.timerMin = raw;
    this.timerDeadline = Date.now() + raw * 60000;
    const self = this;
    this.expireTimer = setTimeout(() => {
      self.expireTimerEnd();
    }, raw * 60000);
    this.tickTimer = setInterval(() => {
      self.publishTimer();
    }, 1000);
    this.setData({
      timerActive: true,
      timerChips: buildTimerChips(raw),
    });
    this.publishTimer();
    this.publishPlayer();
  },

  publishTimer() {
    if (!this.alive) return;
    if (!this.timerActive) {
      this.setData({
        timerStateText: "未设定",
        timerChips: buildTimerChips(0),
        playerSub: this.playerSubText(),
      });
      return;
    }
    const remain = Math.max(
      0,
      Math.ceil((this.timerDeadline - Date.now()) / 1000)
    );
    this.setData({
      timerStateText: "剩余 " + clockText(remain),
      playerSub: this.playerSubText(),
    });
  },

  expireTimerEnd() {
    this.clearTimerTimers();
    const wasActive = this.timerActive;
    this.timerActive = false;
    this.timerMin = 0;
    this.timerDeadline = 0;
    let hadTrack = false;
    if (this.audio && this.currentId) {
      hadTrack = true;
      try {
        this.audio.stop();
      } catch (err) {}
    }
    this.playing = false;
    this.loading = false;
    if (!this.alive) return;
    this.setData({
      timerActive: false,
      timerChips: buildTimerChips(0),
      timerStateText: "未设定",
      progress: 0,
      timeNow: "00:00",
      timeTotal: "--:--",
    });
    this.publishPlayer();
    this.refreshList();
    if (wasActive) {
      wx.showToast({
        title: hadTrack ? "定时结束，已停止播放" : "定时结束",
        icon: "none",
      });
    }
  },

  onCancelTimer() {
    this.clearTimerTimers();
    this.timerActive = false;
    this.timerMin = 0;
    this.timerDeadline = 0;
    if (!this.alive) return;
    this.setData({
      timerActive: false,
      timerChips: buildTimerChips(0),
      timerStateText: "未设定",
    });
    this.publishPlayer();
  },

  clearTimerTimers() {
    if (this.expireTimer) {
      clearTimeout(this.expireTimer);
      this.expireTimer = null;
    }
    if (this.tickTimer) {
      clearInterval(this.tickTimer);
      this.tickTimer = null;
    }
  },

  teardown(update) {
    this.clearTimerTimers();
    this.timerActive = false;
    this.timerMin = 0;
    this.timerDeadline = 0;
    if (this.audio) {
      try {
        this.audio.stop();
      } catch (err) {}
      try {
        this.audio.destroy();
      } catch (err) {}
      this.audio = null;
    }
    this.currentId = "";
    this.currentName = "";
    this.currentCat = "";
    this.playing = false;
    this.loading = false;
    if (!update || !this.alive) return;
    this.setData({
      hasActive: false,
      playing: false,
      loading: false,
      playerName: "还没有播放",
      playerSub: "从下面选一条声音开始",
      playerGlyph: "▶",
      progress: 0,
      timeNow: "00:00",
      timeTotal: "--:--",
      timerActive: false,
      timerStateText: "未设定",
      timerChips: buildTimerChips(0),
    });
    this.refreshList();
  },
});