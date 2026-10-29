(function () {
  "use strict";

  const { SoftBlob, SoftWorld } = window.GuluPhysics;
  const Audio = window.GuluAudio;

  const TAU = Math.PI * 2;
  const STORE_BEST = "gulu-jelly-best-v2";
  const STORE_SCORES = "gulu-jelly-scores-v2";
  const STORE_MUTED = "gulu-jelly-muted-v1";

  const BASE_LEVELS = [
    null,
    { name: "薄荷", value: 1, fill: "#a9eccb", edge: "#2f7c62", r: 18 },
    { name: "海盐", value: 2, fill: "#a9d8ff", edge: "#346a9c", r: 22 },
    { name: "紫苏", value: 4, fill: "#cbb8ff", edge: "#6b50a8", r: 26.5 },
    { name: "蜜桃", value: 8, fill: "#ffc3d6", edge: "#ab4f72", r: 31.5 },
    { name: "橘子", value: 16, fill: "#ffb08c", edge: "#a95835", r: 37 },
    { name: "焦糖", value: 32, fill: "#ffdd7f", edge: "#98701a", r: 43 },
    { name: "青柠", value: 64, fill: "#c9ea7c", edge: "#66821f", r: 49.5 },
    { name: "苏打", value: 128, fill: "#86e6dc", edge: "#2f7f78", r: 56.5 },
    { name: "莓果", value: 256, fill: "#ff9fc3", edge: "#a73963", r: 64 },
    { name: "葡萄", value: 512, fill: "#b7a3ff", edge: "#5e4a99", r: 72 },
    { name: "抹茶", value: 1024, fill: "#a9d98b", edge: "#5b7a2c", r: 80 },
    {
      name: "金箔",
      value: 2048,
      fill: "#ffd36e",
      edge: "#a66a00",
      r: 88,
      rainbow: true,
    },
  ];

  const BASE_MAX_LEVEL = BASE_LEVELS.length - 1;
  const EXTRA_NAMES = [
    "星云",
    "极光",
    "熔岩",
    "冰川",
    "蜜露",
    "幻海",
    "月岩",
    "云霞",
    "萤火",
    "星尘",
    "潮汐",
    "虹光",
  ];
  const RADIUS_LIMIT = 100;
  const EXTRA_RADIUS_START = BASE_LEVELS[BASE_MAX_LEVEL].r + 6;
  const levelCache = BASE_LEVELS.slice();

  function hslToHex(h, s, l) {
    const hue = ((h % 360) + 360) % 360;
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const hp = hue / 60;
    const x = c * (1 - Math.abs((hp % 2) - 1));
    let r = 0;
    let g = 0;
    let b = 0;
    if (hp < 1) [r, g, b] = [c, x, 0];
    else if (hp < 2) [r, g, b] = [x, c, 0];
    else if (hp < 3) [r, g, b] = [0, c, x];
    else if (hp < 4) [r, g, b] = [0, x, c];
    else if (hp < 5) [r, g, b] = [x, 0, c];
    else [r, g, b] = [c, 0, x];
    const m = l - c / 2;
    const to = (v) =>
      Math.round((v + m) * 255)
        .toString(16)
        .padStart(2, "0");
    return `#${to(r)}${to(g)}${to(b)}`;
  }

  function levelDef(level) {
    if (level < levelCache.length) return levelCache[level];
    for (let i = levelCache.length; i <= level; i++) {
      const hue = ((i - 13) * 47 + 266) % 360;
      levelCache[i] = {
        name: EXTRA_NAMES[(i - 13) % EXTRA_NAMES.length],
        value: Math.pow(2, i - 1),
        fill: hslToHex(hue, 0.58, 0.76),
        edge: hslToHex(hue, 0.62, 0.38),
        r:
          RADIUS_LIMIT -
          (RADIUS_LIMIT - EXTRA_RADIUS_START) *
            Math.exp(-(i - 13) / 8),
        rainbow: i >= 12 && (i - 12) % 6 === 0,
      };
    }
    return levelCache[level];
  }

  const SPAWN_LADDER = [2, 3, 4, 5, 6, 7];
  const SPAWN_WEIGHTS = [8, 5, 3, 2, 1, 1];

  const INK = "#26313f";
  const CREAM = "#fffaf0";
  const NUM_FONT =
    '"Arial Rounded MT Bold", "Trebuchet MS", "Microsoft YaHei", sans-serif';
  const UI_FONT =
    '"YouYuan", "Yuanti SC", "PingFang SC", "Microsoft YaHei", sans-serif';

  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const rand = (a, b) => a + Math.random() * (b - a);

  function formatScore(value) {
    try {
      return Math.round(value).toLocaleString("en-US");
    } catch (err) {
      return String(Math.round(value));
    }
  }

  const VALUE_UNITS = [
    "K",
    "M",
    "B",
    "T",
    "Qa",
    "Qi",
    "Sx",
    "Sp",
    "Oc",
    "No",
    "Dc",
  ];

  function compactValue(value) {
    if (!Number.isFinite(value)) return "∞";
    let scaled = value;
    let unit = -1;
    while (scaled >= 1000 && unit < VALUE_UNITS.length - 1) {
      scaled /= 1000;
      unit++;
    }
    let digits = scaled >= 100 ? 0 : 1;
    while (
      Number(scaled.toFixed(digits)) >= 1000 &&
      unit < VALUE_UNITS.length - 1
    ) {
      scaled /= 1000;
      unit++;
      digits = scaled >= 100 ? 0 : 1;
    }
    return `${scaled.toFixed(digits)}${VALUE_UNITS[unit]}`;
  }

  function formatBlobValue(value) {
    if (!Number.isFinite(value)) return "∞";
    if (value < 10000000) return String(Math.round(value));
    return compactValue(value);
  }

  function formatScoreValue(value) {
    if (!Number.isFinite(value)) return "∞";
    if (value < 1000000) return formatScore(value);
    return compactValue(value);
  }

  function shortDate(ts) {
    const d = new Date(ts);
    return `${String(d.getMonth() + 1).padStart(2, "0")}/${String(
      d.getDate()
    ).padStart(2, "0")}`;
  }

  function shade(hex, amount) {
    const value = parseInt(hex.slice(1), 16);
    let r = (value >> 16) & 255;
    let g = (value >> 8) & 255;
    let b = value & 255;
    if (amount >= 0) {
      r += (255 - r) * amount;
      g += (255 - g) * amount;
      b += (255 - b) * amount;
    } else {
      r *= 1 + amount;
      g *= 1 + amount;
      b *= 1 + amount;
    }
    return `rgb(${Math.round(r)}, ${Math.round(g)}, ${Math.round(b)})`;
  }

  function rgba(hex, alpha) {
    const value = parseInt(hex.slice(1), 16);
    const r = (value >> 16) & 255;
    const g = (value >> 8) & 255;
    const b = value & 255;
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }

  function roundRectPath(ctx, x, y, w, h, r) {
    const radius = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.arcTo(x + w, y, x + w, y + h, radius);
    ctx.arcTo(x + w, y + h, x, y + h, radius);
    ctx.arcTo(x, y + h, x, y, radius);
    ctx.arcTo(x, y, x + w, y, radius);
    ctx.closePath();
  }

  function traceSmooth(ctx, points, tension) {
    const n = points.length;
    if (n < 3) return;
    const factor = tension === undefined ? 0.9 : tension;
    ctx.beginPath();
    ctx.moveTo(points[0].x, points[0].y);
    for (let i = 0; i < n; i++) {
      const p0 = points[(i - 1 + n) % n];
      const p1 = points[i];
      const p2 = points[(i + 1) % n];
      const p3 = points[(i + 2) % n];
      const cp1x = p1.x + ((p2.x - p0.x) / 6) * factor;
      const cp1y = p1.y + ((p2.y - p0.y) / 6) * factor;
      const cp2x = p2.x - ((p3.x - p1.x) / 6) * factor;
      const cp2y = p2.y - ((p3.y - p1.y) / 6) * factor;
      ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y);
    }
    ctx.closePath();
  }

  function starPath(ctx, x, y, radius) {
    const inner = radius * 0.4;
    ctx.beginPath();
    ctx.moveTo(x, y - radius);
    ctx.lineTo(x + inner * 0.62, y - inner * 0.62);
    ctx.lineTo(x + radius, y);
    ctx.lineTo(x + inner * 0.62, y + inner * 0.62);
    ctx.lineTo(x, y + radius);
    ctx.lineTo(x - inner * 0.62, y + inner * 0.62);
    ctx.lineTo(x - radius, y);
    ctx.lineTo(x - inner * 0.62, y - inner * 0.62);
    ctx.closePath();
  }

  class Game {
    constructor() {
      this.stage = document.getElementById("stage");
      this.ctx = this.stage.getContext("2d");
      this.scoreEl = document.getElementById("score");
      this.bestEl = document.getElementById("best");
      this.nextQueueEl = document.getElementById("nextQueue");
      this.startOverlay = document.getElementById("startOverlay");
      this.endOverlay = document.getElementById("endOverlay");
      this.startBtn = document.getElementById("startBtn");
      this.restartBtn = document.getElementById("restartBtn");
      this.soundBtn = document.getElementById("soundBtn");
      this.againBtn = document.getElementById("againBtn");
      this.homeBtn = document.getElementById("homeBtn");
      this.playHint = document.getElementById("playHint");
      this.toastEl = document.getElementById("toast");
      this.finalScoreEl = document.getElementById("finalScore");
      this.finalLevelEl = document.getElementById("finalLevel");
      this.finalShotsEl = document.getElementById("finalShots");
      this.finalCopyEl = document.getElementById("endCopy");
      this.newBestEl = document.getElementById("newBest");
      this.scoreBoardEl = document.getElementById("scoreBoard");

      this.state = "start";
      this.dark = document.documentElement.classList.contains("citro-dark");
      this.time = 0;
      this.lastFrame = 0;
      this.best = this.loadBest();
      this.muted = this.loadMuted();
      this.bestShown = -1;

      this.world = null;
      this.layout = null;
      this.bgCanvas = null;
      this.W = 0;
      this.H = 0;
      this.dpr = 1;

      this.score = 0;
      this.maxLevel = 1;
      this.shots = 0;
      this.queue = [2, 2, 2, 2];
      this.queueSignature = "";
      this.combo = 0;
      this.comboTimer = 0;
      this.overflowTime = 0;
      this.overflowWarned = false;
      this.overflowClear = 0;
      this.shake = 0;
      this.hintTimer = 0;
      this.hintVisible = false;
      this.toastTimer = 0;
      this.endTimer = 0;
      this.burst = null;
      this.lastHudScore = -1;

      this.aim = 0;
      this.charging = false;
      this.chargeTime = 0;
      this.power = 0;
      this.cooldown = 0;
      this.previewPop = 0;
      this.recoil = 0;

      this.effects = [];
      this.floats = [];
      this.announced = new Set();

      this.resize();
      this.prepareRound("start");
      this.bindEvents();
      this.syncSoundButton();
      this.setOverlay(this.endOverlay, false);
      this.loop = this.loop.bind(this);
      this.stage.tabIndex = 0;

      if (window.matchMedia && window.matchMedia("(pointer: coarse)").matches) {
        this.playHint.innerHTML =
          "<span><kbd>按住</kbd> 蓄力</span><i></i><span><kbd>拖动</kbd> 瞄准</span><i></i><span><kbd>松开</kbd> 投喂</span>";
      }

      requestAnimationFrame(this.loop);
    }

    /* ---------- storage ---------- */

    loadMuted() {
      try {
        return localStorage.getItem(STORE_MUTED) === "1";
      } catch (err) {
        return false;
      }
    }

    loadBest() {
      let best = 0;
      try {
        best = parseInt(localStorage.getItem(STORE_BEST) || "0", 10) || 0;
      } catch (err) {
        best = 0;
      }
      const scores = this.loadScores();
      if (scores.length && scores[0].score > best) best = scores[0].score;
      return best;
    }

    loadScores() {
      try {
        const raw = localStorage.getItem(STORE_SCORES);
        if (!raw) return [];
        const parsed = JSON.parse(raw);
        if (!Array.isArray(parsed)) return [];
        return parsed
          .filter((s) => s && Number.isFinite(s.score))
          .sort((a, b) => b.score - a.score)
          .slice(0, 5);
      } catch (err) {
        return [];
      }
    }

    saveRun() {
      let newBest = this.score > this.best;
      if (this.score > 0) {
        const list = this.loadScores();
        list.push({
          score: Math.round(this.score),
          level: this.maxLevel,
          value: levelDef(this.maxLevel).value,
          at: Date.now(),
        });
        list.sort((a, b) => b.score - a.score);
        try {
          localStorage.setItem(STORE_SCORES, JSON.stringify(list.slice(0, 5)));
          if (this.score > this.best) {
            localStorage.setItem(STORE_BEST, String(Math.round(this.score)));
          }
        } catch (err) {
          /* storage unavailable */
        }
        this.best = Math.max(this.best, Math.round(this.score));
      }
      if (this.bestShown !== this.best) {
        this.bestShown = this.best;
        this.bestEl.textContent = formatScoreValue(this.best);
      }
      return newBest;
    }

    /* ---------- layout ---------- */

    resize() {
      const W = window.innerWidth;
      const H = window.innerHeight;
      const oldLayout = this.layout;
      this.W = W;
      this.H = H;
      this.dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.stage.width = Math.round(W * this.dpr);
      this.stage.height = Math.round(H * this.dpr);
      this.ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      this.computeLayout();
      this.buildBackground();
      if (this.world) {
        this.world.bounds = this.burst
          ? this.burstBounds()
          : this.layout.bounds;
        this.world.gravity = this.gravityValue();
        this.world.maxSpeed = this.speedLimit();
        this.world.mouthY = this.burst ? null : this.layout.jarTop;
        if (oldLayout) this.world.rescale(oldLayout, this.layout);
        this.world.containAll();
      }
    }

    burstBounds() {
      return {
        left: -this.W,
        right: this.W * 2,
        top: -this.H * 2,
        floor: this.layout.floorY - 2,
      };
    }

    // 裂口的位置固定，只随罐子尺寸变化，不会每帧乱跳
    buildCracks() {
      const l = this.layout;
      const rand = (seed) => {
        const v = Math.sin(seed * 127.1 + 311.7) * 43758.5453;
        return v - Math.floor(v);
      };
      const make = (x, y, dir, steps, spread, seed) => {
        let px = x;
        let py = y;
        let angle = dir;
        const points = [{ x: px, y: py }];
        for (let i = 0; i < steps; i++) {
          angle += (rand(seed + i) - 0.5) * spread;
          const len = 11 + rand(seed + i + 0.5) * 15;
          px += Math.cos(angle) * len;
          py += Math.sin(angle) * len;
          points.push({ x: px, y: py });
        }
        return points;
      };
      this.cracks = [
        make(l.jarX0 + 1, l.jarTop + 2, 0.55, 5, 1.15, 3),
        make(l.jarX1 - 1, l.jarTop + 2, Math.PI - 0.55, 5, 1.15, 9),
        make(l.jarX0 + 1, l.floorY - 56, 0.35, 4, 1.05, 21),
        make(l.jarX1 - 1, l.floorY - 78, Math.PI - 0.35, 4, 1.05, 31),
      ];
    }

    computeLayout() {
      const W = this.W;
      const H = this.H;
      const compact = W < 760;
      const bottomPad = Math.max(24, H * 0.05);
      const floorY = H - bottomPad;
      const minTop = H < 540 ? 150 : H < 700 ? 176 : 192;
      const heightRoom = Math.max(160, floorY - minTop);
      let jarW;
      let jarH;

      if (compact) {
        // Phones keep using the width; larger compact windows (small tablets)
        // can grow the jar a little more if the height allows it.
        const compactMaxW = Math.max(420, Math.min(560, heightRoom * 0.8));
        jarW = Math.min(W - 26, compactMaxW);
        jarH = Math.min(H * 0.72, 800, jarW * 1.6);
      } else {
        // On wide screens the jar is limited by the available height instead
        // of a fixed 420px width, so it keeps growing with the window.
        const widthFromHeight = clamp(heightRoom * 0.8, 300, 700);
        jarW = Math.min(W - 76, widthFromHeight);
        jarH = Math.min(heightRoom, 1100, jarW * 1.6);
      }

      jarH = Math.max(160, jarH);
      let jarTop = floorY - jarH;
      if (jarTop < minTop) {
        jarTop = minTop;
        jarH = floorY - jarTop;
      }

      const cx = W / 2;
      const scale = clamp(Math.min(jarW / 430, jarH / 290), 0.8, 1.7);
      const jarX0 = cx - jarW / 2;
      const jarX1 = cx + jarW / 2;
      const pivotY = Math.max(
        jarTop - 76,
        H < 540 ? 84 : H < 700 ? 96 : 108
      );

      this.layout = {
        W,
        H,
        cx,
        jarW,
        jarH,
        jarX0,
        jarX1,
        jarTop,
        floorY,
        scale,
        launcher: {
          x: cx,
          y: pivotY,
          muzzle: 43 + scale * 8,
        },
        bounds: {
          left: jarX0 + 2,
          right: jarX1 - 2,
          top: Math.max(24, jarTop - 180),
          floor: floorY - 2,
        },
        dangerY: jarTop + 2,
        gravityFactor: clamp(scale, 0.68, 1.7),
      };
      this.buildCracks();
    }

    speedLimit() {
      return 2600 * Math.max(1, this.layout.scale);
    }

    gravityValue() {
      return 2230 * this.layout.gravityFactor;
    }

    levelRadius(level) {
      return levelDef(level).r * this.layout.scale * 1.15;
    }

    launchSpeed(power) {
      const factor = Math.sqrt(this.layout.gravityFactor);
      return (1000 + 2000 * clamp(power, 0, 1)) * factor;
    }

    themeInk() {
      return this.dark ? "#f1eee5" : INK;
    }

    themeCard() {
      return this.dark ? "#1e1f27" : "#fffaf0";
    }

    setDarkMode(dark) {
      const next = !!dark;
      if (this.dark === next) return;
      this.dark = next;
      if (this.layout) this.buildBackground();
    }

    buildBackground() {
      const { W, H, cx } = this.layout;
      const dark = this.dark;
      const dpr = this.dpr;
      const canvas = document.createElement("canvas");
      canvas.width = Math.round(W * dpr);
      canvas.height = Math.round(H * dpr);
      const g = canvas.getContext("2d");
      g.setTransform(dpr, 0, 0, dpr, 0, 0);

      g.fillStyle = dark ? "#14141b" : "#f5ecdb";
      g.fillRect(0, 0, W, H);

      let wash = g.createRadialGradient(
        W * 0.12,
        H * 0.08,
        0,
        W * 0.12,
        H * 0.08,
        Math.max(W, H) * 0.58
      );
      wash.addColorStop(0, dark ? "rgba(120, 184, 154, 0.16)" : "rgba(169, 229, 200, 0.4)");
      wash.addColorStop(0.6, dark ? "rgba(120, 184, 154, 0.03)" : "rgba(169, 229, 200, 0.08)");
      wash.addColorStop(1, "rgba(169, 229, 200, 0)");
      g.fillStyle = wash;
      g.fillRect(0, 0, W, H);

      wash = g.createRadialGradient(
        W * 0.92,
        H * 0.92,
        0,
        W * 0.92,
        H * 0.92,
        Math.max(W, H) * 0.48
      );
      wash.addColorStop(0, dark ? "rgba(255, 123, 103, 0.08)" : "rgba(255, 123, 103, 0.16)");
      wash.addColorStop(0.65, dark ? "rgba(255, 123, 103, 0.02)" : "rgba(255, 123, 103, 0.04)");
      wash.addColorStop(1, "rgba(255, 123, 103, 0)");
      g.fillStyle = wash;
      g.fillRect(0, 0, W, H);

      let seed = 24681357;
      const random = () => {
        seed = (seed * 16807) % 2147483647;
        return seed / 2147483647;
      };

      g.fillStyle = dark ? "rgba(241, 238, 229, 0.06)" : "rgba(38, 49, 63, 0.052)";
      for (let y = 18; y < H; y += 24) {
        for (let x = 16; x < W; x += 24) {
          if (random() < 0.52) continue;
          g.beginPath();
          g.arc(x + random() * 3, y + random() * 3, 1.05, 0, TAU);
          g.fill();
        }
      }

      g.strokeStyle = dark ? "rgba(241, 238, 229, 0.12)" : "rgba(38, 49, 63, 0.12)";
      g.lineWidth = 1.2;
      g.setLineDash([2, 7]);
      g.beginPath();
      g.arc(cx, H * 0.28, Math.min(W * 0.43, 420), Math.PI * 0.08, Math.PI * 0.9);
      g.stroke();
      g.setLineDash([]);

      g.fillStyle = dark ? "rgba(241, 238, 229, 0.18)" : "rgba(38, 49, 63, 0.18)";
      for (let i = 0; i < 9; i++) {
        const x = W * (0.06 + random() * 0.88);
        const y = H * (0.08 + random() * 0.55);
        if (Math.abs(x - cx) < Math.min(W * 0.42, 380) && y > H * 0.2) {
          continue;
        }
        starPath(g, x, y, 2 + random() * 4);
        g.fill();
      }

      g.strokeStyle = dark ? "rgba(241, 238, 229, 0.1)" : "rgba(38, 49, 63, 0.1)";
      g.lineWidth = 1.4;
      for (let i = 0; i < 3; i++) {
        const x = W * (0.05 + random() * 0.2);
        const y = H * (0.2 + random() * 0.4);
        g.beginPath();
        g.moveTo(x, y);
        g.quadraticCurveTo(x + 18, y - 8, x + 34, y + 4);
        g.stroke();
      }

      this.bgCanvas = canvas;
    }

    /* ---------- round lifecycle ---------- */

    prepareRound(state) {
      this.state = state;
      this.score = 0;
      this.shots = 0;
      this.spawnUnlocked = new Set([SPAWN_LADDER[0]]);
      this.combo = 0;
      this.comboTimer = 0;
      this.overflowTime = 0;
      this.overflowWarned = false;
      this.overflowClear = 0;
      this.shake = 0;
      this.endTimer = 0;
      this.burst = null;
      this.aim = 0;
      this.charging = false;
      this.chargeTime = 0;
      this.power = 0;
      this.cooldown = 0;
      this.previewPop = 0;
      this.recoil = 0;
      this.effects.length = 0;
      this.floats.length = 0;
      this.announced.clear();
      this.lastHudScore = -1;
      this.queueSignature = "";
      this.hintVisible = false;
      this.playHint.classList.remove("is-visible");
      this.playHint.setAttribute("aria-hidden", "true");

      this.world = new SoftWorld(this.layout.bounds);
      this.world.gravity = this.gravityValue();
      this.world.maxSpeed = this.speedLimit();
      this.world.mouthY = this.layout.jarTop;

      this.queue = [2, 2, 2, 2];
      while (this.queue.length < 4) this.queue.push(this.rollLevel(true));

      this.maxLevel = 1;
      this.seedJar();
      for (let i = 0; i < 42; i++) this.world.step(1 / 60);
      this.activeFace = this.makeFace();

      this.syncQueueUI(true);
      this.updateHud(true);

      if (state === "playing") {
        this.setOverlay(this.startOverlay, false);
        this.setOverlay(this.endOverlay, false);
        this.showHint();
        this.stage.focus({ preventScroll: true });
      } else {
        this.setOverlay(this.startOverlay, true);
        this.setOverlay(this.endOverlay, false);
      }
    }

    seedJar() {
      const levels = [2, 2, 2, 2];
      // 四颗同级果冻要留出比合并判定更大的缝，避免开局自动连合。
      const offsets = [-0.27, -0.09, 0.09, 0.27];
      const faceStyles = [0, 2, 5, 8];
      const { cx, jarW, bounds } = this.layout;

      levels.forEach((level, index) => {
        const radius = this.levelRadius(level);
        const x = cx + offsets[index] * jarW + rand(-3, 3);
        // 都放在各自的落地高度，开局不会互相砸出横向力把整排顶散
        const y = bounds.floor - radius - 8;
        const blob = new SoftBlob(level, x, y, radius, 0, 0);
        this.decorateBlob(blob, faceStyles[index % faceStyles.length]);
        this.world.add(blob);
      });
    }

    makeFace(style) {
      const roll = Math.random();
      let chosen = style;
      if (chosen === undefined) {
        const used = new Set();
        if (this.world) {
          for (let i = 0; i < this.world.blobs.length; i++) {
            const blob = this.world.blobs[i];
            if (blob.face) used.add(blob.face.style);
          }
        }
        const options = [];
        for (let i = 0; i < 11; i++) {
          if (!used.has(i)) options.push(i);
        }
        chosen = options.length
          ? options[Math.floor(Math.random() * options.length)]
          : Math.floor(Math.random() * 11);
      }
      return {
        style: ((chosen % 11) + 11) % 11,
        seed: Math.random() * 1000,
        blush: Math.random() < 0.62,
        accessory:
          roll < 0.14
            ? "star"
            : roll < 0.26
            ? "bandage"
            : roll < 0.36
            ? "sprout"
            : roll < 0.44
            ? "sweat"
            : null,
      };
    }

    decorateBlob(blob, faceStyle) {
      const def = levelDef(blob.level);
      blob.fill = def.fill;
      blob.edge = def.edge;
      blob.visualPop = 0;
      blob.face = this.makeFace(faceStyle);
      this.maxLevel = Math.max(this.maxLevel || 1, blob.level);
    }

    startGame() {
      if (this.state !== "start") return;
      Audio.init();
      Audio.start();
      this.state = "playing";
      this.setOverlay(this.startOverlay, false);
      this.showHint();
      this.lastFrame = 0;
      this.stage.focus({ preventScroll: true });
    }

    startNewRound(source) {
      if (this.state === "ending") {
        this.saveRun();
      }
      if (source !== "end") {
        Audio.init();
        Audio.ui();
      }
      this.prepareRound("playing");
      if (source === "end") {
        Audio.start();
      }
      this.showToast(source === "end" ? "新的一罐，慢慢来" : "重新开张");
    }

    finishRound() {
      if (this.state !== "playing") return;
      this.state = "ending";
      this.charging = false;
      this.power = 0;
      this.endTimer = 1.35;
      this.shake = Math.max(this.shake, 24);
      this.startBurst();
      Audio.burst();
    }

    startBurst() {
      const l = this.layout;
      const rand = (a, b) => a + Math.random() * (b - a);
      const shards = [];
      const shardShape = () => {
        const s = rand(6, 16);
        return [
          { x: -s * rand(0.5, 1), y: -s * rand(0.2, 0.8) },
          { x: s * rand(0.5, 1.1), y: -s * rand(0.5, 0.9) },
          { x: s * rand(0.1, 0.8), y: s * rand(0.4, 1) },
          { x: -s * rand(0.3, 0.9), y: s * rand(0.2, 0.8) },
        ];
      };
      for (let i = 0; i < 9; i++) {
        const x = l.jarX0 + (l.jarW * (i + 0.5)) / 9;
        shards.push({
          x,
          y: l.jarTop + rand(-2, 6),
          vx: (x - l.cx) * rand(1.2, 2.4) + rand(-60, 60),
          vy: rand(-560, -160),
          rot: rand(0, TAU),
          spin: rand(-9, 9),
          pts: shardShape(),
          life: rand(1.5, 2.4),
          maxLife: 2.4,
        });
      }
      for (let side = 0; side < 2; side++) {
        const x = side === 0 ? l.jarX0 : l.jarX1;
        for (let i = 0; i < 4; i++) {
          shards.push({
            x: x + (side === 0 ? -2 : 2),
            y: l.jarTop + (l.jarH * (i + 0.5)) / 4,
            vx: (side === 0 ? -1 : 1) * rand(120, 440),
            vy: rand(-260, 40),
            rot: rand(0, TAU),
            spin: rand(-8, 8),
            pts: shardShape(),
            life: rand(1.4, 2.2),
            maxLife: 2.4,
          });
        }
      }

      const drops = [];
      for (let i = 0; i < 26; i++) {
        const def = levelDef(1 + Math.floor(Math.random() * Math.min(9, this.maxLevel + 2)));
        drops.push({
          type: "dot",
          x: l.jarX0 + Math.random() * l.jarW,
          y: l.jarTop + Math.random() * l.jarH * 0.3,
          vx: rand(-320, 320),
          vy: rand(-620, -120),
          size: rand(2.5, 7),
          life: rand(0.6, 1.2),
          maxLife: 1.2,
          color: Math.random() < 0.5 ? def.fill : def.edge,
          gravity: 1500,
        });
      }
      this.effects.push(...drops);

      // 罐子破开后不再兜住果冻，让它们跟着碎玻璃一起冲出来
      for (let i = 0; i < this.world.blobs.length; i++) {
        const blob = this.world.blobs[i];
        const side = blob.cx < l.cx ? -1 : 1;
        blob.addVelocity(side * rand(60, 260), rand(-460, -140));
        blob.floatT = 0;
      }
      this.world.bounds = this.burstBounds();
      this.world.mouthY = null;

      this.burst = { t: 0, shards };
    }

    updateBurst(dt) {
      if (!this.burst) return;
      this.burst.t += dt;
      const shards = this.burst.shards;
      let write = 0;
      for (let i = 0; i < shards.length; i++) {
        const s = shards[i];
        s.vy += 1600 * dt;
        s.x += s.vx * dt;
        s.y += s.vy * dt;
        s.rot += s.spin * dt;
        s.life -= dt;
        if (s.life > 0 && s.y < this.H + 90) shards[write++] = s;
      }
      shards.length = write;
    }

    showEnd() {
      this.state = "over";
      const previousBest = this.best;
      this.saveRun();
      const newBest = this.score > 0 && this.score > previousBest;
      this.finalScoreEl.textContent = formatScoreValue(this.score);
      this.finalLevelEl.textContent = formatBlobValue(
        levelDef(this.maxLevel).value
      );
      this.finalShotsEl.textContent = String(this.shots);
      this.newBestEl.classList.toggle("hidden", !newBest);
      if (newBest) {
        this.finalCopyEl.textContent = "刷新了本机纪录，这罐果冻很争气。";
      } else {
        this.finalCopyEl.textContent = "果冻们冲出罐子，这罐就打烊。";
      }
      this.renderScoreBoard();
      this.setOverlay(this.endOverlay, true);
    }

    renderScoreBoard() {
      const scores = this.loadScores();
      this.scoreBoardEl.innerHTML = "";
      if (!scores.length) {
        const li = document.createElement("li");
        li.className = "is-empty";
        li.textContent = "还没有记录，来投第一罐吧";
        this.scoreBoardEl.appendChild(li);
        return;
      }
      scores.forEach((entry, index) => {
        const li = document.createElement("li");
        const rank = document.createElement("span");
        rank.className = "rank";
        rank.textContent = String(index + 1);
        const label = document.createElement("span");
        const entryValue =
          entry.value ||
          (entry.level ? levelDef(entry.level).value : 1);
        label.textContent = `最大 ${formatBlobValue(entryValue)} 果冻`;
        const date = document.createElement("span");
        date.className = "date";
        date.textContent = shortDate(entry.at || Date.now());
        const pts = document.createElement("span");
        pts.className = "pts";
        pts.textContent = formatScoreValue(entry.score);
        li.appendChild(rank);
        li.appendChild(label);
        li.appendChild(date);
        li.appendChild(pts);
        this.scoreBoardEl.appendChild(li);
      });
    }

    setOverlay(el, open) {
      if (!el) return;
      el.classList.toggle("is-open", open);
      el.setAttribute("aria-hidden", open ? "false" : "true");
      if (open) {
        window.setTimeout(() => {
          const target = el.querySelector(".primary-btn");
          if (target) target.focus({ preventScroll: true });
        }, 120);
      }
    }

    /* ---------- input ---------- */

    bindEvents() {
      window.addEventListener("resize", () => this.resize());

      this.startBtn.addEventListener("click", () => {
        Audio.init();
        this.startGame();
      });

      this.restartBtn.addEventListener("click", () => {
        if (this.state === "start") return;
        this.startNewRound("restart");
      });

      this.againBtn.addEventListener("click", () => {
        this.startNewRound("end");
      });

      this.homeBtn.addEventListener("click", () => {
        Audio.ui();
        this.prepareRound("start");
      });

      this.soundBtn.addEventListener("click", () => {
        Audio.init();
        this.muted = !this.muted;
        Audio.setEnabled(!this.muted);
        this.syncSoundButton();
        Audio.ui();
      });

      this.stage.addEventListener("pointerdown", (event) => {
        if (this.state !== "playing") return;
        if (event.button !== undefined && event.button !== 0) return;
        event.preventDefault();
        Audio.init();
        this.updateAim(event.clientX, event.clientY);
        this.beginCharge();
        try {
          this.stage.setPointerCapture(event.pointerId);
        } catch (err) {
          /* pointer capture unavailable */
        }
      });

      this.stage.addEventListener("pointermove", (event) => {
        if (this.state !== "playing") return;
        this.updateAim(event.clientX, event.clientY);
      });

      this.stage.addEventListener("pointerup", (event) => {
        if (this.state !== "playing") return;
        if (!this.charging) return;
        event.preventDefault();
        this.releaseShot();
      });

      this.stage.addEventListener("pointercancel", () => {
        this.charging = false;
        this.power = 0;
      });

      window.addEventListener("keydown", (event) => {
        if (this.state !== "playing") return;
        const key = event.key;
        if (key === " " || key === "Spacebar") {
          event.preventDefault();
          if (!event.repeat && !this.charging) {
            Audio.init();
            this.beginCharge();
          }
        } else if (key === "ArrowLeft" || key === "a" || key === "A") {
          event.preventDefault();
          this.aim = clamp(this.aim - 0.06, -1.0, 1.0);
        } else if (key === "ArrowRight" || key === "d" || key === "D") {
          event.preventDefault();
          this.aim = clamp(this.aim + 0.06, -1.0, 1.0);
        } else if (key === "r" || key === "R") {
          this.startNewRound("restart");
        } else if (key === "m" || key === "M") {
          this.muted = !this.muted;
          Audio.setEnabled(!this.muted);
          this.syncSoundButton();
        }
      });

      window.addEventListener("keyup", (event) => {
        if (event.key === " " || event.key === "Spacebar") {
          if (this.state === "playing" && this.charging) {
            event.preventDefault();
            this.releaseShot();
          }
        }
      });
    }

    updateAim(x, y) {
      const launcher = this.layout.launcher;
      const dx = x - launcher.x;
      const dy = Math.max(10, y - launcher.y);
      this.aim = clamp(Math.atan2(dx, dy), -1.0, 1.0);
    }

    beginCharge() {
      if (this.state !== "playing" || this.cooldown > 0 || this.charging) {
        return;
      }
      this.charging = true;
      this.chargeTime = 0;
      this.power = 0.12;
    }

    releaseShot() {
      if (!this.charging || this.state !== "playing") return;
      this.charging = false;
      const power = this.power;
      this.cooldown = 0.24;
      this.launch(power);
    }

    launch(power) {
      if (this.state !== "playing") return;
      const level = this.queue[0];
      const radius = this.levelRadius(level);
      const dirX = Math.sin(this.aim);
      const dirY = Math.cos(this.aim);
      const muzzleDist = this.layout.launcher.muzzle + radius * 0.12;
      const x = this.layout.launcher.x + dirX * muzzleDist;
      const y = this.layout.launcher.y + dirY * muzzleDist;
      const speed = this.launchSpeed(power);
      const face = this.activeFace;

      const blob = new SoftBlob(
        level,
        x,
        y,
        radius,
        dirX * speed,
        dirY * speed
      );
      this.decorateBlob(blob);
      blob.face = face;
      this.world.add(blob);

      this.effects.push({
        type: "ring",
        x,
        y,
        radius: radius * 0.35,
        growth: 70 + power * 80,
        life: 0.36,
        maxLife: 0.36,
        color: levelDef(level).edge,
        width: 2,
      });
      for (let i = 0; i < 5; i++) {
        const a = Math.atan2(dirY, dirX) + rand(-0.7, 0.7);
        const s = rand(35, 120);
        this.effects.push({
          type: "dot",
          x,
          y,
          vx: Math.cos(a) * s,
          vy: Math.sin(a) * s,
          size: rand(1.5, 3.4),
          life: rand(0.22, 0.4),
          maxLife: 0.4,
          color: levelDef(level).fill,
          gravity: 350,
        });
      }

      Audio.shoot(power);
      this.shake = Math.min(8, this.shake + 1.2 + power * 1.8);
      this.recoil = 1;
      this.previewPop = 0.24;
      this.shots += 1;

      this.queue.shift();
      this.queue.push(this.rollLevel(false));
      this.activeFace = this.makeFace();
      this.syncQueueUI(false);

      if (this.shots >= 4 && this.hintVisible) {
        this.hintVisible = false;
        this.playHint.classList.remove("is-visible");
        this.playHint.setAttribute("aria-hidden", "true");
      }
    }

    rollLevel(intro) {
      if (intro) return SPAWN_LADDER[0];

      let totalWeight = 0;
      for (const level of this.spawnUnlocked) {
        totalWeight += SPAWN_WEIGHTS[SPAWN_LADDER.indexOf(level)];
      }
      let roll = Math.random() * totalWeight;
      for (const level of this.spawnUnlocked) {
        roll -= SPAWN_WEIGHTS[SPAWN_LADDER.indexOf(level)];
        if (roll < 0) return level;
      }
      return SPAWN_LADDER[0];
    }

    unlockSpawnLevel(level) {
      const index = SPAWN_LADDER.indexOf(level);
      if (index <= 0 || this.spawnUnlocked.has(level)) return;
      this.spawnUnlocked.add(level);
      const labels = [...this.spawnUnlocked]
        .map((lv) => formatBlobValue(levelDef(lv).value))
        .join(" / ");
      this.showToast(`出货升级：现在可以投出 ${labels}`);
      Audio.pop();
    }

    /* ---------- update ---------- */

    loop(now) {
      requestAnimationFrame(this.loop);
      if (!this.lastFrame) this.lastFrame = now;
      let dt = (now - this.lastFrame) / 1000;
      this.lastFrame = now;
      if (!Number.isFinite(dt) || dt < 0) dt = 0;
      if (dt > 0.05) dt = 0.05;

      this.time += dt;
      this.updateToast(dt);

      if (this.state === "playing") {
        this.update(dt);
      } else if (this.state === "ending") {
        this.updateEnding(dt);
      } else {
        this.updateIdle(dt);
      }

      this.render();
    }

    update(dt) {
      this.world.step(dt);

      for (let i = 0; i < this.world.blobs.length; i++) {
        const blob = this.world.blobs[i];
        if (blob.visualPop > 0) {
          blob.visualPop = Math.max(0, blob.visualPop - dt);
        }
      }

      this.checkMerges();

      if (this.state !== "playing") return;

      this.updateOverflow(dt);
      if (this.state !== "playing") return;

      this.updateFX(dt);

      this.cooldown = Math.max(0, this.cooldown - dt);
      if (this.comboTimer > 0) {
        this.comboTimer = Math.max(0, this.comboTimer - dt);
        if (this.comboTimer === 0) this.combo = 0;
      }

      if (this.charging) {
        this.chargeTime += dt;
        this.power = Math.min(1, 0.12 + (this.chargeTime / 1.05) * 0.88);
      }

      if (this.previewPop > 0) {
        this.previewPop = Math.max(0, this.previewPop - dt * 1.8);
      }
      if (this.recoil > 0) {
        this.recoil = Math.max(0, this.recoil - dt * 7);
      }

      this.shake = Math.max(0, this.shake - dt * 26);

      if (this.hintVisible) {
        this.hintTimer -= dt;
        if (this.hintTimer <= 0 || this.shots >= 4) {
          this.hintVisible = false;
          this.playHint.classList.remove("is-visible");
          this.playHint.setAttribute("aria-hidden", "true");
        }
      }

      this.updateHud(false);
    }

    updateIdle(dt) {
      if (this.burst) {
        this.world.step(dt);
        this.updateBurst(dt);
      }
      this.shake = Math.max(0, this.shake - dt * 20);
      if (this.recoil > 0) this.recoil = Math.max(0, this.recoil - dt * 7);
      this.updateFX(dt);
    }

    updateEnding(dt) {
      this.world.step(dt);
      this.updateBurst(dt);
      this.updateFX(dt);
      this.shake = Math.max(0, this.shake - dt * 26);
      this.endTimer -= dt;
      if (this.endTimer <= 0) {
        this.showEnd();
      }
    }

    updateFX(dt) {
      const effects = this.effects;
      let write = 0;
      for (let i = 0; i < effects.length; i++) {
        const fx = effects[i];
        fx.life -= dt;
        if (fx.life > 0) {
          if (fx.type === "ring") {
            fx.radius += fx.growth * dt;
          } else if (fx.type === "dot") {
            fx.vy += (fx.gravity || 0) * dt;
            fx.x += fx.vx * dt;
            fx.y += fx.vy * dt;
          }
          effects[write++] = fx;
        }
      }
      effects.length = write;

      const floats = this.floats;
      let fw = 0;
      for (let i = 0; i < floats.length; i++) {
        const item = floats[i];
        item.life -= dt;
        if (item.life > 0) {
          item.y -= item.rise * dt;
          floats[fw++] = item;
        }
      }
      floats.length = fw;
    }

    checkMerges() {
      const blobs = this.world.blobs;
      if (blobs.length < 2) return;

      const used = new Set();
      const pairs = [];

      for (let i = 0; i < blobs.length; i++) {
        const a = blobs[i];
        if (used.has(a) || a.age < 0.12) continue;
        for (let j = i + 1; j < blobs.length; j++) {
          const b = blobs[j];
          if (used.has(b) || b.age < 0.12) continue;
          if (a.level !== b.level) continue;
          const dx = a.cx - b.cx;
          const dy = a.cy - b.cy;
          // 贴住就合：物理分离会留 0.4~1px 的皮面间隙，判定要略大于它，
          // 否则两颗球明明挨在一起却永远差一点，合成会时灵时不灵。
          const reach = a.R + b.R + 1.8;
          if (dx * dx + dy * dy <= reach * reach) {
            used.add(a);
            used.add(b);
            pairs.push([a, b]);
            break;
          }
        }
      }

      if (!pairs.length) return;

      this.world.blobs = blobs.filter((blob) => !used.has(blob));

      for (let i = 0; i < pairs.length; i++) {
        const a = pairs[i][0];
        const b = pairs[i][1];
        this.resolveMerge(a, b);
      }
    }

    resolveMerge(a, b) {
      if (this.comboTimer > 0) this.combo += 1;
      else this.combo = 1;
      this.comboTimer = 1.35;

      const massA = 1 / a.invMass;
      const massB = 1 / b.invMass;
      const totalMass = massA + massB;
      let vxA = 0;
      let vyA = 0;
      let vxB = 0;
      let vyB = 0;
      for (let i = 0; i < a.n; i++) {
        vxA += a.p[i].vx;
        vyA += a.p[i].vy;
      }
      for (let i = 0; i < b.n; i++) {
        vxB += b.p[i].vx;
        vyB += b.p[i].vy;
      }
      vxA /= a.n;
      vyA /= a.n;
      vxB /= b.n;
      vyB /= b.n;

      const x = (a.cx * massA + b.cx * massB) / totalMass;
      const y = (a.cy * massA + b.cy * massB) / totalMass;
      const vx = (vxA * massA + vxB * massB) / totalMass;
      const vy = (vyA * massA + vyB * massB) / totalMass;

      const resultLevel = a.level + 1;
      const def = levelDef(resultLevel);
      const resultValue = def.value;
      const gained = resultValue + (this.combo > 1 ? this.combo * 4 : 0);

      this.score += gained;
      this.shake = Math.min(12, this.shake + 3 + resultLevel * 0.7);

      const baseRadius = this.levelRadius(resultLevel);

      this.spawnMergeFX(x, y, baseRadius, def.fill, def.edge, resultLevel);

      this.world.makeRoom(x, y, baseRadius, [a, b]);
      this.world.applyRadialImpulse(
        x,
        y,
        baseRadius * 2.4,
        30 + resultLevel * 6
      );
      const blob = new SoftBlob(
        resultLevel,
        x,
        y,
        baseRadius,
        vx * 0.45,
        vy * 0.45
      );
      this.decorateBlob(blob);
      blob.visualPop = 0.34;
      blob.jiggle = 1;
      this.world.add(blob);
      this.world.containAll();
      this.world.separateAll(4);

      Audio.merge(resultLevel, this.combo);

      this.floats.push({
        x,
        y: y - Math.max(14, baseRadius * 0.5),
        text: `+${formatScoreValue(gained)}`,
        life: 0.95,
        maxLife: 0.95,
        rise: 38,
        size: 20 + Math.min(8, resultLevel * 0.8),
        color: this.combo > 1 ? "#d9584a" : this.themeInk(),
      });

      if (this.combo > 1) {
        this.floats.push({
          x,
          y: y - Math.max(32, baseRadius * 0.9),
          text: `连锁 ×${this.combo}`,
          life: 1.05,
          maxLife: 1.05,
          rise: 30,
          size: 13,
          color: "#d9584a",
        });
      }

      if (resultLevel >= 5 && !this.announced.has(resultLevel)) {
        this.announced.add(resultLevel);
        const valueLabel = formatBlobValue(resultValue);
        if (resultLevel === 12) {
          this.showToast("2048 成精了！还能继续往上合");
        } else if (resultLevel === 13) {
          this.showToast("4096 · 果冻没有上限");
        } else if (resultLevel > 13) {
          this.showToast(`${def.name} ${valueLabel} · 无上限`);
        } else {
          this.showToast(`新果冻解锁：${def.name} ${valueLabel}`);
        }
      }

      this.maxLevel = Math.max(this.maxLevel, resultLevel);
      this.unlockSpawnLevel(resultLevel);
    }

    spawnMergeFX(x, y, radius, fill, edge, level) {
      this.effects.push({
        type: "ring",
        x,
        y,
        radius: radius * 0.45,
        growth: 130 + level * 18,
        life: 0.5,
        maxLife: 0.5,
        color: edge,
        width: 2.4,
      });
      this.effects.push({
        type: "ring",
        x,
        y,
        radius: radius * 0.2,
        growth: 90 + level * 10,
        life: 0.3,
        maxLife: 0.3,
        color: CREAM,
        width: 3,
      });

      const count = 10 + Math.min(14, level * 2);
      for (let i = 0; i < count; i++) {
        const angle = rand(0, TAU);
        const speed = rand(80, 260 + level * 12);
        this.effects.push({
          type: "dot",
          x,
          y,
          vx: Math.cos(angle) * speed,
          vy: Math.sin(angle) * speed - 40,
          size: rand(1.6, 4.4),
          life: rand(0.3, 0.7),
          maxLife: 0.7,
          color: i % 3 === 0 ? CREAM : i % 2 === 0 ? edge : fill,
          gravity: 900,
        });
      }
    }

    updateOverflow(dt) {
      const dangerY = this.layout.dangerY;
      // A jelly that fills the mouth can sit a few pixels below the painted
      // line; without this margin a full jar could never start the countdown.
      const fullY = dangerY + 24;
      let crowded = false;

      for (let i = 0; i < this.world.blobs.length; i++) {
        const blob = this.world.blobs[i];
        // Give a fresh shot just enough time to clear the muzzle, then count
        // it: a jelly that stays at the mouth must start the overflow clock.
        if (blob.age < 0.35) continue;
        if (blob.top() < fullY) {
          crowded = true;
          break;
        }
      }

      if (crowded) {
        this.overflowClear = 0;
        this.overflowTime += dt;
        const pressure = clamp(this.overflowTime / 3.2, 0, 1);
        this.shake = Math.max(this.shake, pressure * 2.1);
        if (!this.overflowWarned && this.overflowTime > 0.35) {
          this.overflowWarned = true;
          Audio.warn();
        }
        if (this.overflowTime >= 3.2) {
          this.finishRound();
        }
      } else {
        this.overflowClear = (this.overflowClear || 0) + dt;
        if (this.overflowClear > 0.5) {
          this.overflowTime = Math.max(0, this.overflowTime - dt * 1.7);
          if (this.overflowTime === 0) this.overflowWarned = false;
        }
      }
    }

    showHint() {
      this.hintTimer = 9;
      this.hintVisible = true;
      this.playHint.classList.add("is-visible");
      this.playHint.setAttribute("aria-hidden", "false");
    }

    showToast(text) {
      this.toastEl.textContent = text;
      this.toastEl.classList.add("is-visible");
      this.toastTimer = 2.6;
    }

    updateToast(dt) {
      if (this.toastTimer > 0) {
        this.toastTimer -= dt;
        if (this.toastTimer <= 0) this.toastEl.classList.remove("is-visible");
      }
    }

    syncSoundButton() {
      this.soundBtn.classList.toggle("is-muted", this.muted);
      const label = this.muted ? "打开声音" : "关闭声音";
      this.soundBtn.setAttribute("aria-label", label);
      this.soundBtn.title = label;
      Audio.setEnabled(!this.muted);
    }

    updateHud(force) {
      if (force || this.score !== this.lastHudScore) {
        const previous = this.lastHudScore;
        this.lastHudScore = this.score;
        this.scoreEl.textContent = formatScoreValue(this.score);
        if (!force && previous >= 0 && this.scoreEl.animate) {
          this.scoreEl.animate(
            [
              { transform: "scale(1.22)", offset: 0.2 },
              { transform: "scale(1)" },
            ],
            { duration: 240, easing: "ease-out" }
          );
        }
      }

      const bestNow = Math.max(this.best, this.score);
      if (force || bestNow !== this.bestShown) {
        this.bestShown = bestNow;
        this.bestEl.textContent = formatScoreValue(bestNow);
      }
    }

    syncQueueUI(force) {
      const signature = this.queue.slice(1, 4).join("-");
      if (!force && signature === this.queueSignature) return;
      this.queueSignature = signature;
      this.nextQueueEl.innerHTML = "";
      for (let i = 1; i < Math.min(4, this.queue.length); i++) {
        const level = this.queue[i];
        const def = levelDef(level);
        const chip = document.createElement("span");
        chip.className = "next-chip";
        chip.textContent = formatBlobValue(def.value);
        chip.style.background = def.fill;
        chip.style.borderColor = def.edge;
        chip.title = `${def.name} ${formatBlobValue(def.value)}`;
        this.nextQueueEl.appendChild(chip);
      }
    }

    /* ---------- rendering ---------- */

    render() {
      const ctx = this.ctx;
      const { W, H } = this.layout;

      ctx.clearRect(0, 0, W, H);
      if (this.bgCanvas) ctx.drawImage(this.bgCanvas, 0, 0, W, H);

      ctx.save();
      if (this.shake > 0.2) {
        ctx.translate(rand(-this.shake, this.shake), rand(-this.shake, this.shake));
      }

      this.drawShelf();
      if (this.burst) {
        this.drawJarRuin();
        this.drawBlobs();
        this.drawEffects();
        this.drawBurstShards();
        this.drawFloats();
      } else {
        this.drawJarBack();
        this.drawBlobs();
        this.drawEffects();
        this.drawJarFront();
        this.drawOverflowWarning();
        this.drawLauncher();
        this.drawFloats();
      }

      ctx.restore();
    }

    drawShelf() {
      const ctx = this.ctx;
      const { jarX0, jarX1, floorY, cx, jarW } = this.layout;

      ctx.save();
      const shadow = ctx.createRadialGradient(
        cx,
        floorY + 12,
        0,
        cx,
        floorY + 12,
        jarW * 0.55
      );
      const shelfInk = this.dark ? "241, 238, 229" : "38, 49, 63";
      shadow.addColorStop(0, `rgba(${shelfInk}, ${this.dark ? 0.22 : 0.15})`);
      shadow.addColorStop(0.7, `rgba(${shelfInk}, ${this.dark ? 0.08 : 0.05})`);
      shadow.addColorStop(1, `rgba(${shelfInk}, 0)`);
      ctx.fillStyle = shadow;
      ctx.beginPath();
      ctx.ellipse(cx, floorY + 12, jarW * 0.54, 18, 0, 0, TAU);
      ctx.fill();

      const shelfY = floorY + 3;
      const shelfH = 10;
      const shelfPad = Math.min(54, jarW * 0.09);
      ctx.fillStyle = this.dark ? "rgba(92, 72, 50, 0.85)" : "rgba(222, 203, 176, 0.7)";
      roundRectPath(
        ctx,
        jarX0 - shelfPad,
        shelfY,
        jarX1 - jarX0 + shelfPad * 2,
        shelfH,
        4
      );
      ctx.fill();
      ctx.strokeStyle = `rgba(${shelfInk}, ${this.dark ? 0.3 : 0.24})`;
      ctx.lineWidth = 1.2;
      ctx.stroke();

      ctx.fillStyle = this.dark ? "rgba(126, 100, 70, 0.9)" : "rgba(246, 237, 221, 0.9)";
      roundRectPath(
        ctx,
        jarX0 - shelfPad,
        shelfY - 2,
        jarX1 - jarX0 + shelfPad * 2,
        4,
        2
      );
      ctx.fill();
      ctx.strokeStyle = `rgba(${shelfInk}, ${this.dark ? 0.26 : 0.2})`;
      ctx.stroke();
      ctx.restore();
    }

    jarClosedPath(ctx) {
      const { jarX0, jarX1, jarTop, floorY } = this.layout;
      const r = Math.min(26, (jarX1 - jarX0) * 0.08);
      ctx.beginPath();
      ctx.moveTo(jarX0, jarTop);
      ctx.lineTo(jarX0, floorY - r);
      ctx.quadraticCurveTo(jarX0, floorY, jarX0 + r, floorY);
      ctx.lineTo(jarX1 - r, floorY);
      ctx.quadraticCurveTo(jarX1, floorY, jarX1, floorY - r);
      ctx.lineTo(jarX1, jarTop);
      ctx.closePath();
    }

    jarOpenPath(ctx) {
      const { jarX0, jarX1, jarTop, floorY } = this.layout;
      const r = Math.min(26, (jarX1 - jarX0) * 0.08);
      ctx.beginPath();
      ctx.moveTo(jarX0, jarTop);
      ctx.lineTo(jarX0, floorY - r);
      ctx.quadraticCurveTo(jarX0, floorY, jarX0 + r, floorY);
      ctx.lineTo(jarX1 - r, floorY);
      ctx.quadraticCurveTo(jarX1, floorY, jarX1, floorY - r);
      ctx.lineTo(jarX1, jarTop);
    }

    drawJarBack() {
      const ctx = this.ctx;
      const l = this.layout;

      ctx.save();
      this.jarClosedPath(ctx);
      const glass = ctx.createLinearGradient(0, l.jarTop, 0, l.floorY);
      glass.addColorStop(0, "rgba(255, 255, 255, 0.2)");
      glass.addColorStop(0.45, "rgba(255, 255, 255, 0.05)");
      glass.addColorStop(1, "rgba(190, 224, 211, 0.14)");
      ctx.fillStyle = glass;
      ctx.fill();

      const floorShade = ctx.createLinearGradient(
        0,
        l.floorY - 42,
        0,
        l.floorY
      );
      floorShade.addColorStop(0, "rgba(0, 0, 0, 0)");
      floorShade.addColorStop(1, `rgba(0, 0, 0, ${this.dark ? 0.2 : 0.075})`);
      ctx.fillStyle = floorShade;
      ctx.fillRect(l.jarX0, l.floorY - 42, l.jarW, 42);

      ctx.strokeStyle = this.dark ? "rgba(241, 238, 229, 0.16)" : "rgba(38, 49, 63, 0.1)";
      ctx.lineWidth = 1;
      for (let i = 1; i <= 3; i++) {
        const y = l.jarTop + l.jarH * (i / 4);
        ctx.beginPath();
        ctx.moveTo(l.jarX0 + 16, y);
        ctx.lineTo(l.jarX0 + 34, y);
        ctx.stroke();
        ctx.fillStyle = this.dark ? "rgba(241, 238, 229, 0.42)" : "rgba(38, 49, 63, 0.22)";
        ctx.font = `600 8px ${NUM_FONT}`;
        ctx.textAlign = "left";
        ctx.textBaseline = "middle";
        ctx.fillText(`${i * 25}`, l.jarX0 + 40, y);
      }

      const rimShade = ctx.createLinearGradient(
        0,
        l.jarTop,
        0,
        l.jarTop + 34
      );
      rimShade.addColorStop(0, this.dark ? "rgba(255, 255, 255, 0.05)" : "rgba(38, 49, 63, 0.08)");
      rimShade.addColorStop(1, "rgba(0, 0, 0, 0)");
      ctx.fillStyle = rimShade;
      ctx.fillRect(l.jarX0, l.jarTop, l.jarW, 34);
      ctx.restore();
    }

    drawJarFront() {
      const ctx = this.ctx;
      const l = this.layout;

      ctx.save();
      this.jarClosedPath(ctx);
      ctx.clip();

      const sheen = ctx.createLinearGradient(
        l.jarX0,
        l.jarTop,
        l.jarX1,
        l.floorY
      );
      sheen.addColorStop(0, "rgba(255, 255, 255, 0.08)");
      sheen.addColorStop(0.2, "rgba(255, 255, 255, 0)");
      sheen.addColorStop(0.78, "rgba(255, 255, 255, 0)");
      sheen.addColorStop(1, "rgba(255, 255, 255, 0.07)");
      ctx.fillStyle = sheen;
      ctx.fillRect(l.jarX0, l.jarTop, l.jarW, l.jarH);

      ctx.globalAlpha = this.dark ? 0.035 : 0.12;
      ctx.fillStyle = "#ffffff";
      ctx.beginPath();
      ctx.moveTo(l.jarX0 + l.jarW * 0.13, l.jarTop);
      ctx.lineTo(l.jarX0 + l.jarW * 0.23, l.jarTop);
      ctx.lineTo(l.jarX0 + l.jarW * 0.01, l.floorY);
      ctx.lineTo(l.jarX0 - l.jarW * 0.07, l.floorY);
      ctx.closePath();
      ctx.fill();
      ctx.globalAlpha = 1;

      ctx.strokeStyle = `rgba(255, 255, 255, ${this.dark ? 0.25 : 0.55})`;
      ctx.lineWidth = 1.4;
      ctx.beginPath();
      ctx.moveTo(l.jarX0 + 10, l.jarTop + 28);
      ctx.lineTo(l.jarX0 + 10, l.floorY - 24);
      ctx.stroke();
      ctx.restore();

      this.jarOpenPath(ctx);
      ctx.strokeStyle = this.themeInk();
      ctx.lineWidth = 2.5;
      ctx.lineJoin = "round";
      ctx.lineCap = "round";
      ctx.stroke();

      ctx.save();
      this.jarOpenPath(ctx);
      ctx.strokeStyle = "rgba(255, 255, 255, 0.7)";
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.restore();

      const lip = 9;
      ctx.strokeStyle = this.themeInk();
      ctx.lineWidth = 2.5;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(l.jarX0 - lip, l.jarTop);
      ctx.quadraticCurveTo(l.jarX0 + 2, l.jarTop - 5, l.jarX0 + lip + 4, l.jarTop);
      ctx.moveTo(l.jarX1 + lip, l.jarTop);
      ctx.quadraticCurveTo(l.jarX1 - 2, l.jarTop - 5, l.jarX1 - lip - 4, l.jarTop);
      ctx.stroke();

      ctx.fillStyle = "rgba(255, 255, 255, 0.65)";
      ctx.beginPath();
      ctx.ellipse(l.jarX0 + 13, l.jarTop + 18, 2.2, 5, -0.3, 0, TAU);
      ctx.fill();
      ctx.beginPath();
      ctx.ellipse(l.jarX1 - 17, l.jarTop + 46, 1.4, 3.2, 0.2, 0, TAU);
      ctx.fill();

      if (this.W - l.jarX1 > 90) {
        this.drawJarTag();
      }

      if (this.overflowTime > 0.05) {
        this.drawJarCracks(clamp(this.overflowTime / 3.2, 0, 1));
      }
    }

    // 撑爆预警：裂纹从罐口和罐壁一点点长开，越接近爆炸越深
    drawJarCracks(progress) {
      if (!this.cracks || progress <= 0) return;
      const ctx = this.ctx;
      const reach = clamp((progress - 0.1) / 0.75, 0, 1);
      if (reach <= 0) return;
      ctx.save();
      this.jarClosedPath(ctx);
      ctx.clip();
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      for (let c = 0; c < this.cracks.length; c++) {
        const crack = this.cracks[c];
        const n = Math.max(2, Math.ceil(crack.length * reach));
        ctx.beginPath();
        ctx.moveTo(crack[0].x, crack[0].y);
        for (let i = 1; i < n; i++) {
          ctx.lineTo(crack[i].x, crack[i].y);
        }
        ctx.strokeStyle = `rgba(${this.dark ? "241, 238, 229" : "38, 49, 63"}, ${0.26 + progress * 0.5})`;
        ctx.lineWidth = 1.6;
        ctx.stroke();
        ctx.strokeStyle = `rgba(255, 255, 255, ${0.3 + progress * 0.4})`;
        ctx.lineWidth = 0.8;
        ctx.stroke();
      }
      ctx.restore();
    }

    // 爆开的罐子只剩下半截，断口是锯齿状
    drawJarRuin() {
      const ctx = this.ctx;
      const l = this.layout;
      const topY = l.floorY - Math.min(150, l.jarH * 0.33);
      const steps = 12;
      const edge = [];
      for (let i = 0; i <= steps; i++) {
        const x = l.jarX0 + (l.jarW * i) / steps;
        const jag =
          Math.sin(i * 3.1 + 0.7) * 12 + Math.sin(i * 7.9 + 2.1) * 7;
        edge.push({ x, y: topY + jag });
      }
      const r = Math.min(26, l.jarW * 0.08);

      ctx.save();
      ctx.beginPath();
      ctx.moveTo(l.jarX0, l.floorY - r);
      ctx.quadraticCurveTo(l.jarX0, l.floorY, l.jarX0 + r, l.floorY);
      ctx.lineTo(l.jarX1 - r, l.floorY);
      ctx.quadraticCurveTo(l.jarX1, l.floorY, l.jarX1, l.floorY - r);
      ctx.lineTo(l.jarX1, edge[steps].y);
      for (let i = steps; i >= 0; i--) {
        ctx.lineTo(edge[i].x, edge[i].y);
      }
      ctx.closePath();

      const glass = ctx.createLinearGradient(0, topY, 0, l.floorY);
      glass.addColorStop(0, "rgba(226, 244, 236, 0.4)");
      glass.addColorStop(0.5, "rgba(214, 242, 232, 0.22)");
      glass.addColorStop(1, "rgba(190, 224, 211, 0.3)");
      ctx.fillStyle = glass;
      ctx.fill();
      ctx.strokeStyle = this.themeInk();
      ctx.lineWidth = 2.4;
      ctx.lineJoin = "round";
      ctx.stroke();

      // 断口内沿的高光
      ctx.beginPath();
      ctx.moveTo(edge[0].x, edge[0].y);
      for (let i = 1; i <= steps; i++) ctx.lineTo(edge[i].x, edge[i].y);
      ctx.strokeStyle = "rgba(255, 255, 255, 0.75)";
      ctx.lineWidth = 1;
      ctx.stroke();

      ctx.clip();
      ctx.globalAlpha = 0.14;
      ctx.fillStyle = "#ffffff";
      ctx.beginPath();
      ctx.moveTo(l.jarX0 + l.jarW * 0.13, topY);
      ctx.lineTo(l.jarX0 + l.jarW * 0.23, topY);
      ctx.lineTo(l.jarX0 + l.jarW * 0.01, l.floorY);
      ctx.lineTo(l.jarX0 - l.jarW * 0.07, l.floorY);
      ctx.closePath();
      ctx.fill();
      ctx.globalAlpha = 1;
      ctx.restore();
    }

    drawBurstShards() {
      if (!this.burst) return;
      const ctx = this.ctx;
      const shards = this.burst.shards;
      for (let i = 0; i < shards.length; i++) {
        const s = shards[i];
        const alpha = clamp(s.life / s.maxLife, 0, 1);
        ctx.save();
        ctx.translate(s.x, s.y);
        ctx.rotate(s.rot);
        ctx.globalAlpha = Math.min(1, alpha * 1.8);
        ctx.beginPath();
        ctx.moveTo(s.pts[0].x, s.pts[0].y);
        for (let k = 1; k < s.pts.length; k++) {
          ctx.lineTo(s.pts[k].x, s.pts[k].y);
        }
        ctx.closePath();
        ctx.fillStyle = "rgba(204, 235, 224, 0.55)";
        ctx.fill();
        ctx.strokeStyle = `rgba(${this.dark ? "241, 238, 229" : "38, 49, 63"}, ${0.3 + 0.45 * alpha})`;
        ctx.lineWidth = 1.2;
        ctx.lineJoin = "round";
        ctx.stroke();
        ctx.strokeStyle = "rgba(255, 255, 255, 0.8)";
        ctx.lineWidth = 0.8;
        ctx.beginPath();
        ctx.moveTo(s.pts[0].x, s.pts[0].y);
        ctx.lineTo(s.pts[1].x, s.pts[1].y);
        ctx.stroke();
        ctx.restore();
      }
      ctx.globalAlpha = 1;
    }

    drawJarTag() {
      const ctx = this.ctx;
      const l = this.layout;
      const x = l.jarX1 + 8;
      const y = l.jarTop + 54;

      ctx.save();
      ctx.strokeStyle = this.dark ? "rgba(241, 238, 229, 0.5)" : "rgba(38, 49, 63, 0.5)";
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.moveTo(l.jarX1 - 2, l.jarTop + 32);
      ctx.quadraticCurveTo(x + 2, y - 14, x + 15, y + 2);
      ctx.stroke();

      ctx.translate(x + 24, y + 6);
      ctx.rotate(0.1);
      ctx.fillStyle = this.themeCard();
      ctx.strokeStyle = this.themeInk();
      ctx.lineWidth = 1.4;
      roundRectPath(ctx, -22, -14, 48, 30, 5);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = this.themeInk();
      ctx.font = `800 8px ${NUM_FONT}`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText("NO. 6", 2, -3);
      ctx.strokeStyle = this.dark ? "rgba(241, 238, 229, 0.35)" : "rgba(38, 49, 63, 0.35)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(-13, 5);
      ctx.lineTo(15, 5);
      ctx.stroke();
      ctx.fillStyle = this.dark ? "rgba(241, 238, 229, 0.6)" : "rgba(38, 49, 63, 0.55)";
      ctx.font = `600 6px ${NUM_FONT}`;
      ctx.fillText("SOFT JELLY", 1, 11);
      ctx.restore();
    }

    blobOuterPoints(blob) {
      return blob.boundaryPoints();
    }

    // 挤压程度 → 可鼓出的最大幅度（渲染层）
    bulgeAmpFor(blob) {
      let contacts = 0;
      for (let i = 0; i < this.world.blobs.length; i++) {
        const other = this.world.blobs[i];
        if (other === blob) continue;
        const dx = other.cx - blob.cx;
        const dy = other.cy - blob.cy;
        if (Math.hypot(dx, dy) < blob.R + other.R + 3.5) contacts++;
      }
      const areaLoss = Math.max(0, 1 - blob.area / blob.targetArea);
      const squeeze = Math.min(1, contacts * 0.62 + areaLoss * 3);
      return squeeze * Math.min(blob.R * 0.3, 14);
    }

    // Q 弹果冻：整体保持圆形，只留轻微的呼吸和落地压扁回弹；
    // 被挤压时往缝隙鼓出，鼓出量由邻居/罐壁的实际余量封顶，绝不穿透
    visualBlobPoints(blob) {
      const points = this.blobOuterPoints(blob);
      const faceSeed = (blob.face && blob.face.seed) || 0;
      const ripple = Math.max(0.15, Math.min(0.4, blob.R * 0.005));
      const jiggle = Math.max(0, Math.min(1.2, blob.jiggle || 0));
      const jiggleAmp = jiggle * Math.min(blob.R * 0.13, 8);
      const jigglePhase = blob.jigglePhase || 0;
      const jiggleDir =
        blob.jiggleDir === undefined ? -Math.PI / 2 : blob.jiggleDir;
      const duang = Math.cos(jigglePhase);
      const float = Math.max(0, Math.min(1, (blob.floatT || 0) / 0.28));
      const tilt = float * 0.035 * Math.sin(this.time * 1.6 + faceSeed * 0.02);
      const cosT = Math.cos(tilt);
      const sinT = Math.sin(tilt);

      // 被挤压时往缝隙鼓出：鼓出量由到最近邻居/罐壁的余量封顶，绝不穿透
      const bulgeAmp =
        blob._bulgeAmp === undefined ? this.bulgeAmpFor(blob) : blob._bulgeAmp;
      const neighbors = [];
      for (let i = 0; i < this.world.blobs.length; i++) {
        const other = this.world.blobs[i];
        if (other === blob) continue;
        const ox = other.cx - blob.cx;
        const oy = other.cy - blob.cy;
        const d = Math.hypot(ox, oy);
        if (d < blob.R + other.R + 18) {
          neighbors.push({
            x: other.cx,
            y: other.cy,
            // 按对方实际变形后的轮廓留位；两侧各填一半缝宽，谁也不会穿过去
            r: (other.visR || other.R) - 0.4,
          });
        }
      }
      const bounds = this.world.bounds;

      for (let k = 0; k < points.length; k++) {
        const pt = points[k];
        const dx = pt.x - blob.cx;
        const dy = pt.y - blob.cy;
        const d = Math.hypot(dx, dy) || 1;
        const angle = Math.atan2(dy, dx);
        const nx = dx / d;
        const ny = dy / d;
        // 呼吸：两瓣缓慢起伏，正负抵消，平均轮廓仍贴着物理半径
        const breathe =
          Math.cos(angle * 2 + faceSeed * 0.03) *
          ripple *
          (0.7 + 0.3 * Math.sin(this.time * 1.15 + faceSeed * 0.01));
        // 回弹：沿冲击轴压扁、垂直轴鼓出，快速弹两下就收住
        const squash =
          -Math.cos((angle - jiggleDir) * 2) * jiggleAmp * duang * 0.85;
        const wave = breathe + squash;

        const baseX = pt.x;
        const baseY = pt.y;
        let px = baseX + nx * Math.min(0, wave);
        let py = baseY + ny * Math.min(0, wave);
        if (tilt !== 0) {
          const rx = px - blob.cx;
          const ry = py - blob.cy;
          px = blob.cx + rx * cosT - ry * sinT;
          py = blob.cy + rx * sinT + ry * cosT;
        }

        const baseOut = Math.max(0, wave);
        const out = baseOut + bulgeAmp;
        if (out > 0.15) {
          let free = Infinity;
          for (let i = 0; i < neighbors.length; i++) {
            const n = neighbors[i];
            const gap = Math.hypot(baseX - n.x, baseY - n.y) - n.r;
            if (gap < free) free = gap;
          }
          const wallGap =
            Math.min(
              baseX - bounds.left,
              bounds.right - baseX,
              baseY - bounds.top,
              bounds.floor - baseY
            ) - 0.5;
          const atWall = wallGap < free;
          if (atWall) free = wallGap;
          // 邻居之间各填一半，贴在一起又不越界；贴罐壁时整段都可以填
          const share = atWall ? free : free * 0.5;
          if (share > 0.12) {
            const rx = px - blob.cx;
            const ry = py - blob.cy;
            const rl = Math.hypot(rx, ry) || 1;
            const push = Math.min(share, out);
            px += (rx / rl) * push;
            py += (ry / rl) * push;
            const fill = Math.max(0, push - baseOut);
            if (fill > (blob._bulgeUsed || 0)) blob._bulgeUsed = fill;
          }
        }
        pt.x = px;
        pt.y = py;
      }
      return points;
    }

    drawBlobs() {
      const blobs = this.world.blobs.slice().sort((a, b) => b.R - a.R);
      const now = this.time;
      const dt = Math.min(
        0.05,
        Math.max(0.001, now - (this._bulgeT || now - 1 / 60))
      );
      this._bulgeT = now;
      const bulgeK = 1 - Math.exp(-5.0 * dt);
      for (let i = 0; i < blobs.length; i++) {
        blobs[i]._bulgeAmp = this.bulgeAmpFor(blobs[i]);
        blobs[i]._bulgeUsed = 0;
      }
      // 第一遍算出每个果冻实际填缝的鼓出量；第二遍按邻居实际鼓出量预留，
      // 并做时间平滑，贴住邻居但不穿透
      for (let i = 0; i < blobs.length; i++) this.visualBlobPoints(blobs[i]);
      for (let i = 0; i < blobs.length; i++) {
        const actual = blobs[i]._bulgeUsed;
        const drawn = blobs[i]._bulgeDraw || 0;
        blobs[i]._bulgeDraw = drawn + (actual - drawn) * bulgeK;
        blobs[i]._bulgeAmp = blobs[i]._bulgeDraw;
      }
      for (let i = 0; i < blobs.length; i++) {
        blobs[i]._visPoints = this.visualBlobPoints(blobs[i]);
      }
      for (let i = 0; i < blobs.length; i++) {
        const blob = blobs[i];
        if (blob.cx < -blob.R * 2 || blob.cx > this.W + blob.R * 2) continue;

        const points = blob._visPoints;
        let radiusSum = 0;
        for (let k = 0; k < points.length; k++) {
          radiusSum += Math.hypot(
            points[k].x - blob.cx,
            points[k].y - blob.cy
          );
        }
        const visualR = radiusSum / points.length;
        let minX = Infinity;
        let maxX = -Infinity;
        let minY = Infinity;
        let maxY = -Infinity;
        for (let k = 0; k < points.length; k++) {
          if (points[k].x < minX) minX = points[k].x;
          if (points[k].x > maxX) maxX = points[k].x;
          if (points[k].y < minY) minY = points[k].y;
          if (points[k].y > maxY) maxY = points[k].y;
        }
        const halfW = Math.max(blob.cx - minX, maxX - blob.cx, 1);
        const halfH = Math.max(blob.cy - minY, maxY - blob.cy, 1);
        const faceR = Math.max(
          4,
          Math.min(visualR * 0.96, halfW * 0.9, halfH * 0.84)
        );
        let scale = 1;
        if (blob.visualPop > 0) {
          const t = 1 - blob.visualPop / 0.34;
          scale = 1 + Math.sin(t * Math.PI) * 0.03;
        }
        let faceTilt = 0;
        if (blob.kinetic > 4) {
          let avgVx = 0;
          for (let k = 0; k < blob.n; k++) avgVx += blob.p[k].vx;
          faceTilt = clamp(avgVx / blob.n / 2600, -0.1, 0.1);
        }
        const floatAmt = Math.max(0, Math.min(1, (blob.floatT || 0) / 0.4));
        if (floatAmt > 0) {
          faceTilt += floatAmt * 0.05 * Math.sin(this.time * 1.3);
        }

        this.drawJelly(points, blob.cx, blob.cy, visualR, blob.level, {
          scale,
          faceR,
          face: blob.face || this.makeFace(),
          blink: blob.blinkFor > 0,
          tilt: faceTilt,
          shadow: blob.R > 11,
        });
      }
    }

    drawJelly(points, cx, cy, size, level, options) {
      const ctx = this.ctx;
      const opts = options || {};
      const def = levelDef(level);
      const scale = opts.scale === undefined ? 1 : opts.scale;
      const scaleX = opts.scaleX === undefined ? scale : opts.scaleX;
      const scaleY = opts.scaleY === undefined ? scale : opts.scaleY;
      const faceR = Math.max(4, opts.faceR || size * 0.8);
      const face = opts.face || {
        style: 0,
        seed: 0,
        blush: true,
        accessory: null,
      };
      const showFace = faceR > 16.5;

      ctx.save();
      if (scaleX !== 1 || scaleY !== 1) {
        ctx.translate(cx, cy);
        ctx.scale(scaleX, scaleY);
        ctx.translate(-cx, -cy);
      }

      if (opts.shadow !== false) {
        ctx.save();
        ctx.translate(0, Math.max(2, size * 0.09));
        traceSmooth(ctx, points, 0.9);
        ctx.fillStyle = "rgba(38, 49, 63, 0.09)";
        ctx.fill();
        ctx.restore();
      }

      traceSmooth(ctx, points, 0.9);
      const gradient = ctx.createLinearGradient(
        cx - size,
        cy - size * 0.9,
        cx + size * 0.9,
        cy + size
      );
      if (def.rainbow) {
        gradient.addColorStop(0, "#fff1b8");
        gradient.addColorStop(0.28, "#ffd36e");
        gradient.addColorStop(0.55, "#ffa9c8");
        gradient.addColorStop(0.8, "#9fe8da");
        gradient.addColorStop(1, "#b7a3ff");
      } else {
        gradient.addColorStop(0, shade(def.fill, 0.36));
        gradient.addColorStop(0.5, def.fill);
        gradient.addColorStop(1, shade(def.fill, -0.05));
      }
      ctx.globalAlpha = 0.9;
      ctx.fillStyle = gradient;
      ctx.fill();
      ctx.globalAlpha = 1;
      // 薄薄的糖果高光，保持果冻质感，不做水光
      ctx.strokeStyle = "rgba(255,255,255,0.16)";
      ctx.lineWidth = Math.max(1, size * 0.014);
      ctx.stroke();

      ctx.save();
      ctx.clip();
      const drift = Math.sin(this.time * 0.85 + face.seed) * size * 0.05;
      const glow = ctx.createRadialGradient(
        cx - size * 0.36 + drift,
        cy - size * 0.44,
        0,
        cx - size * 0.36 + drift,
        cy - size * 0.44,
        size * 1.18
      );
      glow.addColorStop(0, "rgba(255, 255, 255, 0.5)");
      glow.addColorStop(0.3, "rgba(255, 255, 255, 0.12)");
      glow.addColorStop(1, "rgba(255, 255, 255, 0)");
      ctx.fillStyle = glow;
      ctx.fillRect(cx - size * 1.4, cy - size * 1.4, size * 2.8, size * 2.8);

      ctx.globalAlpha = 0.2;
      ctx.fillStyle = "#ffffff";
      ctx.beginPath();
      ctx.ellipse(
        cx - size * 0.33,
        cy - size * 0.4,
        Math.max(2, size * 0.26),
        Math.max(1.2, size * 0.1),
        -0.36,
        0,
        TAU
      );
      ctx.fill();
      ctx.globalAlpha = 1;

      if (def.value >= 8) {
        const bubbles = def.value >= 128 ? 3 : 2;
        for (let i = 0; i < bubbles; i++) {
          const angle = face.seed * 0.02 + i * 2.1;
          const bx =
            cx +
            Math.cos(angle + this.time * 0.25) * size * 0.42;
          const by =
            cy +
            size * 0.22 +
            Math.sin(angle * 1.3 + this.time * 0.2) * size * 0.26;
          const br = Math.max(1.2, size * (0.025 + i * 0.008));
          ctx.globalAlpha = 0.2;
          ctx.fillStyle = "#fffaf0";
          ctx.beginPath();
          ctx.arc(bx, by, br, 0, TAU);
          ctx.fill();
          ctx.globalAlpha = 0.5;
          ctx.fillStyle = "#ffffff";
          ctx.beginPath();
          ctx.arc(bx - br * 0.3, by - br * 0.3, br * 0.32, 0, TAU);
          ctx.fill();
        }
        ctx.globalAlpha = 1;
      }

      const bottom = ctx.createLinearGradient(0, cy, 0, cy + size);
      bottom.addColorStop(0, "rgba(255, 255, 255, 0)");
      bottom.addColorStop(1, "rgba(255, 255, 255, 0.1)");
      ctx.fillStyle = bottom;
      ctx.fillRect(cx - size, cy, size * 2, size);
      ctx.restore();

      traceSmooth(ctx, points, 0.9);
      ctx.lineJoin = "round";
      ctx.strokeStyle = "rgba(255, 255, 255, 0.16)";
      ctx.lineWidth = Math.max(1.5, size * 0.05);
      ctx.stroke();
      traceSmooth(ctx, points, 0.9);
      ctx.strokeStyle = def.edge;
      ctx.lineWidth = Math.max(1.3, Math.min(2.7, size * 0.045));
      ctx.stroke();

      if (showFace) {
        ctx.save();
        ctx.translate(cx, cy);
        ctx.rotate(opts.tilt || 0);
        ctx.translate(-cx, -cy);
        this.drawExpression(cx, cy, faceR, face, opts.blink, def);
        ctx.restore();
      }

      if (showFace) {
        this.drawNumberBadge(cx, cy, faceR, def.value, def);
      } else {
        this.drawCenteredNumber(cx, cy, faceR, def.value);
      }

      if (level >= 7) {
        ctx.save();
        ctx.translate(cx + size * 0.55, cy - size * 0.56);
        ctx.rotate(-0.1);
        starPath(ctx, 0, 0, Math.max(2.5, size * 0.09));
        ctx.fillStyle = "rgba(255, 250, 240, 0.94)";
        ctx.fill();
        ctx.strokeStyle = def.edge;
        ctx.lineWidth = 1;
        ctx.stroke();
        if (level >= 10) {
          ctx.translate(-size * 0.92, size * 0.32);
          starPath(ctx, 0, 0, Math.max(1.8, size * 0.055));
          ctx.fillStyle = "rgba(255, 250, 240, 0.8)";
          ctx.fill();
          ctx.stroke();
        }
        ctx.restore();
      }

      ctx.restore();
    }

    drawExpression(cx, cy, r, face, blink, def) {
      const ctx = this.ctx;
      const ink = INK;
      const style = face.style % 11;
      const eyeY = cy - r * 0.3;
      const eyeX = r * 0.22;
      const eyeR = Math.max(1.8, r * 0.082);
      const mouthY = cy - r * 0.03;
      const lw = Math.max(1.4, r * 0.045);
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw;

      if (face.blush) {
        ctx.globalAlpha = 0.2;
        ctx.fillStyle = "#ff7b67";
        ctx.beginPath();
        ctx.ellipse(
          cx - r * 0.37,
          cy - r * 0.04,
          r * 0.095,
          r * 0.045,
          0,
          0,
          TAU
        );
        ctx.ellipse(
          cx + r * 0.37,
          cy - r * 0.04,
          r * 0.095,
          r * 0.045,
          0,
          0,
          TAU
        );
        ctx.fill();
        ctx.globalAlpha = 1;
      }

      const roundEye = (x, scale) => {
        const s = scale || 1;
        ctx.fillStyle = ink;
        ctx.beginPath();
        ctx.arc(x, eyeY, eyeR * s, 0, TAU);
        ctx.fill();
        ctx.fillStyle = "rgba(255,255,255,.88)";
        ctx.beginPath();
        ctx.arc(
          x + eyeR * 0.34 * s,
          eyeY - eyeR * 0.34 * s,
          eyeR * 0.3 * s,
          0,
          TAU
        );
        ctx.fill();
      };

      const closedDown = (x) => {
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw;
        ctx.beginPath();
        ctx.moveTo(x - eyeR * 1.3, eyeY);
        ctx.quadraticCurveTo(x, eyeY + eyeR * 1.15, x + eyeR * 1.3, eyeY);
        ctx.stroke();
      };

      const closedUp = (x) => {
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw;
        ctx.beginPath();
        ctx.moveTo(x - eyeR * 1.3, eyeY + eyeR * 0.25);
        ctx.quadraticCurveTo(x, eyeY - eyeR * 1.05, x + eyeR * 1.3, eyeY + eyeR * 0.25);
        ctx.stroke();
      };

      const wideEye = (x) => {
        ctx.fillStyle = "rgba(255,250,240,.97)";
        ctx.strokeStyle = ink;
        ctx.lineWidth = Math.max(1, r * 0.022);
        ctx.beginPath();
        ctx.arc(x, eyeY, eyeR * 1.5, 0, TAU);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = ink;
        ctx.beginPath();
        ctx.arc(x, eyeY + eyeR * 0.15, eyeR * 0.65, 0, TAU);
        ctx.fill();
        ctx.fillStyle = "rgba(255,255,255,.9)";
        ctx.beginPath();
        ctx.arc(x + eyeR * 0.2, eyeY - eyeR * 0.1, eyeR * 0.25, 0, TAU);
        ctx.fill();
      };

      const starEye = (x) => {
        ctx.fillStyle = ink;
        starPath(ctx, x, eyeY, eyeR * 1.6);
        ctx.fill();
        ctx.fillStyle = "rgba(255,255,255,.7)";
        ctx.beginPath();
        ctx.arc(x + eyeR * 0.4, eyeY - eyeR * 0.45, eyeR * 0.28, 0, TAU);
        ctx.fill();
      };

      const xEye = (x) => {
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw;
        ctx.beginPath();
        ctx.moveTo(x - eyeR * 0.8, eyeY - eyeR * 0.8);
        ctx.lineTo(x + eyeR * 0.8, eyeY + eyeR * 0.8);
        ctx.moveTo(x + eyeR * 0.8, eyeY - eyeR * 0.8);
        ctx.lineTo(x - eyeR * 0.8, eyeY + eyeR * 0.8);
        ctx.stroke();
      };

      const smile = (rad) => {
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw;
        ctx.beginPath();
        ctx.arc(cx, mouthY - r * 0.01, rad, Math.PI * 0.16, Math.PI * 0.84);
        ctx.stroke();
      };

      const wavyMouth = () => {
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw;
        ctx.beginPath();
        ctx.moveTo(cx - r * 0.12, mouthY + r * 0.02);
        ctx.quadraticCurveTo(cx - r * 0.05, mouthY - r * 0.04, cx, mouthY + r * 0.02);
        ctx.quadraticCurveTo(cx + r * 0.05, mouthY + r * 0.08, cx + r * 0.12, mouthY + r * 0.02);
        ctx.stroke();
      };

      const drawSweat = (x, y) => {
        ctx.save();
        ctx.fillStyle = "rgba(126, 202, 240, 0.92)";
        ctx.strokeStyle = "#3d8cb3";
        ctx.lineWidth = Math.max(1, r * 0.018);
        ctx.beginPath();
        ctx.moveTo(x, y - r * 0.14);
        ctx.bezierCurveTo(
          x + r * 0.12,
          y - r * 0.02,
          x + r * 0.08,
          y + r * 0.09,
          x,
          y + r * 0.09
        );
        ctx.bezierCurveTo(
          x - r * 0.08,
          y + r * 0.09,
          x - r * 0.12,
          y - r * 0.02,
          x,
          y - r * 0.14
        );
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = "rgba(255,255,255,.72)";
        ctx.beginPath();
        ctx.arc(x - r * 0.025, y + r * 0.02, r * 0.025, 0, TAU);
        ctx.fill();
        ctx.restore();
      };

      const drawSprout = (x, y) => {
        ctx.save();
        ctx.strokeStyle = "#2f7c62";
        ctx.lineWidth = Math.max(1, r * 0.022);
        ctx.beginPath();
        ctx.moveTo(x, y + r * 0.16);
        ctx.quadraticCurveTo(x - r * 0.04, y + r * 0.04, x, y - r * 0.06);
        ctx.stroke();
        ctx.fillStyle = "#a9e5c8";
        ctx.strokeStyle = "#2f7c62";
        ctx.beginPath();
        ctx.ellipse(x - r * 0.07, y - r * 0.02, r * 0.09, r * 0.045, -0.55, 0, TAU);
        ctx.fill();
        ctx.stroke();
        ctx.beginPath();
        ctx.ellipse(x + r * 0.07, y - r * 0.08, r * 0.09, r * 0.045, 0.55, 0, TAU);
        ctx.fill();
        ctx.stroke();
        ctx.restore();
      };

      const drawSticker = (x, y) => {
        ctx.save();
        ctx.translate(x, y);
        ctx.rotate(-0.18);
        starPath(ctx, 0, 0, Math.max(2.4, r * 0.12));
        ctx.fillStyle = "rgba(255,250,240,.95)";
        ctx.fill();
        ctx.strokeStyle = def.edge;
        ctx.lineWidth = Math.max(1, r * 0.018);
        ctx.stroke();
        ctx.restore();
      };

      const drawBandage = (x, y) => {
        ctx.save();
        ctx.translate(x, y);
        ctx.rotate(-0.35);
        roundRectPath(ctx, -r * 0.17, -r * 0.055, r * 0.34, r * 0.11, r * 0.04);
        ctx.fillStyle = "rgba(255,250,240,.92)";
        ctx.fill();
        ctx.strokeStyle = "rgba(38,49,63,.55)";
        ctx.lineWidth = Math.max(1, r * 0.014);
        ctx.stroke();
        ctx.strokeStyle = "rgba(38,49,63,.3)";
        ctx.beginPath();
        ctx.moveTo(-r * 0.04, -r * 0.045);
        ctx.lineTo(r * 0.04, r * 0.045);
        ctx.moveTo(r * 0.04, -r * 0.045);
        ctx.lineTo(-r * 0.04, r * 0.045);
        ctx.stroke();
        ctx.restore();
      };

      const blinkClose = () => {
        closedDown(cx - eyeX);
        closedDown(cx + eyeX);
      };

      switch (style) {
        case 0: {
          if (blink) blinkClose();
          else {
            roundEye(cx - eyeX);
            roundEye(cx + eyeX);
          }
          smile(r * 0.15);
          break;
        }
        case 1: {
          closedDown(cx - eyeX);
          closedDown(cx + eyeX);
          ctx.fillStyle = ink;
          ctx.beginPath();
          ctx.ellipse(cx, mouthY + r * 0.03, r * 0.055, r * 0.075, 0, 0, TAU);
          ctx.fill();
          ctx.save();
          ctx.globalAlpha = 0.45;
          ctx.fillStyle = ink;
          ctx.font = `800 ${Math.max(7, r * 0.18)}px ${NUM_FONT}`;
          ctx.textAlign = "center";
          ctx.textBaseline = "middle";
          ctx.fillText("z", cx + r * 0.52, cy - r * 0.58);
          ctx.restore();
          break;
        }
        case 2: {
          ctx.strokeStyle = ink;
          ctx.lineWidth = lw;
          ctx.beginPath();
          ctx.moveTo(cx - eyeX - eyeR * 1.3, eyeY - r * 0.16);
          ctx.quadraticCurveTo(cx - eyeX, eyeY - r * 0.25, cx - eyeX + eyeR * 1.2, eyeY - r * 0.14);
          ctx.moveTo(cx + eyeX + eyeR * 1.3, eyeY - r * 0.16);
          ctx.quadraticCurveTo(cx + eyeX, eyeY - r * 0.25, cx + eyeX - eyeR * 1.2, eyeY - r * 0.14);
          ctx.stroke();
          if (blink) blinkClose();
          else {
            wideEye(cx - eyeX);
            wideEye(cx + eyeX);
          }
          ctx.fillStyle = ink;
          ctx.beginPath();
          ctx.ellipse(cx, mouthY + r * 0.04, r * 0.06, r * 0.075, 0, 0, TAU);
          ctx.fill();
          ctx.fillStyle = "rgba(255,250,240,.55)";
          ctx.beginPath();
          ctx.arc(cx - r * 0.015, mouthY + r * 0.01, r * 0.018, 0, TAU);
          ctx.fill();
          break;
        }
        case 3: {
          const winkRight = face.seed % 2 > 1;
          if (blink) blinkClose();
          else if (winkRight) {
            roundEye(cx - eyeX);
            closedDown(cx + eyeX);
          } else {
            closedDown(cx - eyeX);
            roundEye(cx + eyeX);
          }
          ctx.strokeStyle = ink;
          ctx.lineWidth = lw;
          ctx.beginPath();
          ctx.moveTo(cx - r * 0.13, mouthY + r * 0.03);
          ctx.quadraticCurveTo(cx + r * 0.02, mouthY - r * 0.05, cx + r * 0.14, mouthY - r * 0.02);
          ctx.stroke();
          break;
        }
        case 4: {
          if (blink) blinkClose();
          else {
            roundEye(cx - eyeX);
            roundEye(cx + eyeX);
          }
          ctx.fillStyle = ink;
          ctx.beginPath();
          ctx.ellipse(cx, mouthY + r * 0.02, r * 0.07, r * 0.045, 0, 0, TAU);
          ctx.fill();
          ctx.strokeStyle = ink;
          ctx.lineWidth = lw;
          ctx.beginPath();
          ctx.moveTo(cx - r * 0.1, mouthY + r * 0.09);
          ctx.quadraticCurveTo(cx, mouthY + r * 0.02, cx + r * 0.1, mouthY + r * 0.09);
          ctx.stroke();
          break;
        }
        case 5: {
          ctx.strokeStyle = ink;
          ctx.lineWidth = lw;
          ctx.beginPath();
          ctx.moveTo(cx - eyeX - eyeR * 1.35, eyeY - r * 0.3);
          ctx.lineTo(cx - eyeX + eyeR * 1.1, eyeY - r * 0.07);
          ctx.moveTo(cx + eyeX + eyeR * 1.35, eyeY - r * 0.3);
          ctx.lineTo(cx + eyeX - eyeR * 1.1, eyeY - r * 0.07);
          ctx.stroke();
          if (blink) blinkClose();
          else {
            roundEye(cx - eyeX, 0.9);
            roundEye(cx + eyeX, 0.9);
          }
          ctx.beginPath();
          ctx.moveTo(cx - r * 0.13, mouthY + r * 0.06);
          ctx.lineTo(cx + r * 0.13, mouthY + r * 0.06);
          ctx.stroke();
          break;
        }
        case 6: {
          if (blink) blinkClose();
          else {
            const halfEye = (x) => {
              ctx.fillStyle = ink;
              ctx.beginPath();
              ctx.arc(x, eyeY + r * 0.03, eyeR, 0, Math.PI);
              ctx.fill();
              ctx.strokeStyle = ink;
              ctx.lineWidth = lw;
              ctx.beginPath();
              ctx.moveTo(x - eyeR * 1.2, eyeY);
              ctx.lineTo(x + eyeR * 1.2, eyeY);
              ctx.stroke();
            };
            halfEye(cx - eyeX);
            halfEye(cx + eyeX);
          }
          ctx.strokeStyle = ink;
          ctx.lineWidth = lw;
          ctx.beginPath();
          ctx.moveTo(cx - r * 0.12, mouthY + r * 0.03);
          ctx.quadraticCurveTo(cx + r * 0.03, mouthY + r * 0.1, cx + r * 0.14, mouthY - r * 0.02);
          ctx.stroke();
          break;
        }
        case 7: {
          if (blink) blinkClose();
          else {
            starEye(cx - eyeX);
            starEye(cx + eyeX);
          }
          ctx.fillStyle = ink;
          ctx.beginPath();
          ctx.moveTo(cx - r * 0.14, mouthY + r * 0.01);
          ctx.quadraticCurveTo(cx, mouthY + r * 0.2, cx + r * 0.14, mouthY + r * 0.01);
          ctx.closePath();
          ctx.fill();
          ctx.fillStyle = "rgba(255,250,240,.62)";
          ctx.fillRect(
            cx - r * 0.09,
            mouthY + r * 0.035,
            r * 0.18,
            Math.max(1.2, r * 0.028)
          );
          break;
        }
        case 8: {
          ctx.strokeStyle = ink;
          ctx.lineWidth = lw;
          ctx.beginPath();
          ctx.moveTo(cx - eyeX - eyeR * 1.35, eyeY - r * 0.31);
          ctx.quadraticCurveTo(cx - eyeX, eyeY - r * 0.12, cx - eyeX + eyeR * 1.25, eyeY - r * 0.25);
          ctx.moveTo(cx + eyeX + eyeR * 1.35, eyeY - r * 0.31);
          ctx.quadraticCurveTo(cx + eyeX, eyeY - r * 0.12, cx + eyeX - eyeR * 1.25, eyeY - r * 0.25);
          ctx.stroke();
          if (blink) blinkClose();
          else {
            roundEye(cx - eyeX, 0.95);
            roundEye(cx + eyeX, 0.95);
          }
          wavyMouth();
          drawSweat(cx + r * 0.55, cy - r * 0.4);
          break;
        }
        case 9: {
          if (blink) blinkClose();
          else {
            xEye(cx - eyeX);
            xEye(cx + eyeX);
          }
          wavyMouth();
          break;
        }
        case 10: {
          closedUp(cx - eyeX);
          closedUp(cx + eyeX);
          smile(r * 0.13);
          drawSprout(cx + r * 0.4, cy - r * 0.7);
          break;
        }
      }

      if (face.accessory === "star") {
        drawSticker(cx - r * 0.55, cy - r * 0.52);
      } else if (face.accessory === "bandage") {
        drawBandage(cx + r * 0.5, cy + r * 0.1);
      } else if (face.accessory === "sprout" && style !== 10) {
        drawSprout(cx + r * 0.4, cy - r * 0.7);
      } else if (face.accessory === "sweat" && style !== 8) {
        drawSweat(cx + r * 0.55, cy - r * 0.4);
      }
    }

    drawNumberBadge(cx, cy, r, value, def) {
      const ctx = this.ctx;
      const label = formatBlobValue(value);
      const maxW = r * 1.06;
      let font = r * 0.46;
      ctx.font = `800 ${font}px ${NUM_FONT}`;
      let textW = ctx.measureText(label).width;

      if (textW > maxW * 0.78) {
        font *= (maxW * 0.78) / textW;
        ctx.font = `800 ${font}px ${NUM_FONT}`;
        textW = ctx.measureText(label).width;
      }

      let h = Math.min(r * 0.72, Math.max(12, font * 1.65));
      if (font * 1.65 > h) {
        font = h / 1.65;
      }
      const w = Math.max(
        r * 0.58,
        Math.min(maxW, textW + Math.max(10, h * 0.55))
      );
      const badgeY = cy + r * 0.54;

      ctx.save();
      roundRectPath(
        ctx,
        cx - w / 2,
        badgeY - h / 2 + 1.5,
        w,
        h,
        h / 2
      );
      ctx.fillStyle = "rgba(38, 49, 63, 0.12)";
      ctx.fill();

      roundRectPath(ctx, cx - w / 2, badgeY - h / 2, w, h, h / 2);
      ctx.fillStyle = "rgba(255, 250, 240, 0.96)";
      ctx.fill();
      ctx.strokeStyle = def.edge;
      ctx.lineWidth = Math.max(1, r * 0.018);
      ctx.stroke();

      ctx.save();
      roundRectPath(ctx, cx - w / 2, badgeY - h / 2, w, h, h / 2);
      ctx.clip();
      ctx.fillStyle = "rgba(255, 255, 255, 0.55)";
      ctx.beginPath();
      ctx.ellipse(
        cx - w * 0.18,
        badgeY - h * 0.25,
        w * 0.26,
        h * 0.18,
        -0.25,
        0,
        TAU
      );
      ctx.fill();
      ctx.restore();

      ctx.font = `800 ${font}px ${NUM_FONT}`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillStyle = INK;
      ctx.fillText(label, cx, badgeY + h * 0.02);
      ctx.restore();
    }

    drawCenteredNumber(cx, cy, r, value) {
      const ctx = this.ctx;
      const label = formatBlobValue(value);
      let font = r * 0.95;
      const maxW = r * 1.65;
      ctx.font = `800 ${font}px ${NUM_FONT}`;
      let textW = ctx.measureText(label).width;
      if (textW > maxW) {
        font *= maxW / textW;
      }
      ctx.font = `800 ${font}px ${NUM_FONT}`;
      ctx.save();
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.lineWidth = Math.max(2.5, font * 0.22);
      ctx.strokeStyle = "rgba(255, 250, 240, 0.78)";
      ctx.strokeText(label, cx, cy + r * 0.04);
      ctx.fillStyle = INK;
      ctx.fillText(label, cx, cy + r * 0.04);
      ctx.restore();
    }

    previewPoints(cx, cy, radius, seed) {
      const n = 18;
      const points = [];
      const phase = seed * 0.7;
      for (let i = 0; i < n; i++) {
        const angle = (i / n) * TAU;
        const wobble =
          1 +
          Math.sin(this.time * 2.2 + i * 0.9 + phase) *
            (0.018 + (this.charging ? this.power : 0) * 0.022) +
          Math.cos(this.time * 1.7 + i * 1.4 + phase) *
            (0.012 + (this.charging ? this.power : 0) * 0.014);
        points.push({
          x: cx + Math.cos(angle) * radius * wobble,
          y: cy + Math.sin(angle) * radius * wobble,
        });
      }
      return points;
    }

    drawLauncher() {
      const ctx = this.ctx;
      const l = this.layout;
      const level = this.queue[0] || 1;
      const def = levelDef(level);
      const radius = this.levelRadius(level);
      const dirX = Math.sin(this.aim);
      const dirY = Math.cos(this.aim);
      const recoil = this.recoil * 6;
      const muzzleDist = l.launcher.muzzle + radius * 0.12 - recoil;
      const mx = l.launcher.x + dirX * muzzleDist;
      const my = l.launcher.y + dirY * muzzleDist;

      this.drawAimGuide(mx, my, dirX, dirY, radius);

      ctx.save();
      ctx.strokeStyle = this.dark ? "rgba(241, 238, 229, 0.32)" : "rgba(38, 49, 63, 0.28)";
      ctx.lineWidth = 1.3;
      ctx.setLineDash([2, 6]);
      ctx.beginPath();
      ctx.moveTo(l.launcher.x, Math.max(12, l.launcher.y - 96));
      ctx.lineTo(l.launcher.x, l.launcher.y - 10);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = this.dark ? "#7a6448" : "#e8d6b9";
      ctx.strokeStyle = this.themeInk();
      ctx.lineWidth = 1.8;
      ctx.beginPath();
      ctx.arc(l.launcher.x, l.launcher.y - 6, 6, 0, TAU);
      ctx.fill();
      ctx.stroke();
      ctx.restore();

      ctx.save();
      ctx.translate(l.launcher.x, l.launcher.y);
      ctx.rotate(this.aim);
      const wobble = Math.sin(this.time * 2.4) * 0.8;
      ctx.translate(0, -recoil * 0.4);

      ctx.beginPath();
      ctx.moveTo(-17, -2);
      ctx.quadraticCurveTo(-15, 22, -10, 34 + wobble);
      ctx.lineTo(10, 34 + wobble);
      ctx.quadraticCurveTo(15, 22, 17, -2);
      ctx.quadraticCurveTo(0, -8, -17, -2);
      ctx.closePath();
      ctx.fillStyle = this.themeCard();
      ctx.strokeStyle = this.themeInk();
      ctx.lineWidth = 2;
      ctx.lineJoin = "round";
      ctx.fill();
      ctx.stroke();

      ctx.fillStyle = def.fill;
      ctx.beginPath();
      ctx.moveTo(-12, 25 + wobble);
      ctx.lineTo(12, 25 + wobble);
      ctx.lineTo(8.5, 34 + wobble);
      ctx.lineTo(-8.5, 34 + wobble);
      ctx.closePath();
      ctx.fillStyle = rgba(def.fill, 0.6);
      ctx.fill();

      ctx.fillStyle = this.themeInk();
      roundRectPath(ctx, -5, -4, 10, 8, 3);
      ctx.fill();

      ctx.strokeStyle = "rgba(38, 49, 63, 0.3)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(-10, 9);
      ctx.quadraticCurveTo(0, 13, 10, 9);
      ctx.stroke();
      ctx.restore();

      const pop = this.previewPop > 0
        ? 1 + Math.sin((1 - this.previewPop / 0.24) * Math.PI) * 0.09
        : 1;
      const charge = this.charging ? this.power : 0;
      const previewScale = (this.charging ? 0.96 + charge * 0.05 : 1) * pop;
      const previewPoints = this.previewPoints(
        mx,
        my,
        radius,
        level * 1.7
      );
      this.drawJelly(previewPoints, mx, my, radius, level, {
        scale: previewScale,
        scaleX: previewScale * (1 + charge * 0.12),
        scaleY: previewScale * (1 - charge * 0.08),
        faceR: radius * 0.8,
        face: this.activeFace || this.makeFace(),
        blink: false,
        tilt: -this.aim * 0.05,
        shadow: false,
      });

      if (this.charging || this.power > 0.02) {
        const ringR = radius + 7;
        const start = -Math.PI / 2;
        ctx.save();
        ctx.lineCap = "round";
        ctx.strokeStyle = "rgba(38, 49, 63, 0.12)";
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.arc(mx, my, ringR, 0, TAU);
        ctx.stroke();

        ctx.strokeStyle = this.power >= 1 ? "#d9584a" : "#ff7b67";
        ctx.lineWidth = 3.4;
        ctx.beginPath();
        ctx.arc(
          mx,
          my,
          ringR,
          start,
          start + TAU * Math.max(0.04, this.power)
        );
        ctx.stroke();

        if (this.power >= 1) {
          const pulse = 1 + Math.sin(this.time * 9) * 0.06;
          ctx.globalAlpha = 0.35;
          ctx.strokeStyle = "#ff7b67";
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.arc(mx, my, ringR * pulse + 3, 0, TAU);
          ctx.stroke();
          ctx.globalAlpha = 1;
        }
        ctx.restore();
      }

      if (this.charging) {
        const dotR = radius + 7;
        const start = -Math.PI / 2;
        const angle = start + TAU * this.power;
        ctx.fillStyle = "#fffaf0";
        ctx.strokeStyle = "#d9584a";
        ctx.lineWidth = 1.4;
        ctx.beginPath();
        ctx.arc(
          mx + Math.cos(angle) * dotR,
          my + Math.sin(angle) * dotR,
          3.2,
          0,
          TAU
        );
        ctx.fill();
        ctx.stroke();
      }
    }

    drawAimGuide(fromX, fromY, dirX, dirY, radius) {
      const ctx = this.ctx;
      const power = this.charging ? this.power : 0.55;
      const speed = this.launchSpeed(power);
      let vx = dirX * speed;
      let vy = dirY * speed;
      const gravity = this.world.gravity;
      const dt = 1 / 40;
      const bounds = this.layout.bounds;
      let x = fromX;
      let y = fromY;
      const points = [];
      const maxTime = this.charging ? 1.1 : 0.65;

      for (let t = 0; t < maxTime; t += dt) {
        vy += gravity * dt;
        x += vx * dt;
        y += vy * dt;
        if (x < bounds.left + radius * 0.35 || x > bounds.right - radius * 0.35) {
          break;
        }
        if (y > bounds.floor - radius * 0.25) {
          break;
        }
        points.push({ x, y });
      }

      if (!points.length) return;
      const alpha = this.charging ? 0.45 : 0.2;
      const step = Math.max(1, Math.floor(points.length / 11));
      ctx.save();
      for (let i = 0; i < points.length; i += step) {
        const t = i / points.length;
        ctx.globalAlpha = alpha * (1 - t * 0.8);
        ctx.fillStyle = this.themeInk();
        ctx.beginPath();
        ctx.arc(
          points[i].x,
          points[i].y,
          lerp(2.4, 1.2, t),
          0,
          TAU
        );
        ctx.fill();
      }
      const last = points[points.length - 1];
      ctx.globalAlpha = alpha * 0.7;
      ctx.strokeStyle = this.themeInk();
      ctx.lineWidth = 1.2;
      ctx.setLineDash([3, 4]);
      ctx.beginPath();
      ctx.arc(last.x, last.y, Math.max(5, radius * 0.28), 0, TAU);
      ctx.stroke();
      ctx.restore();
    }

    drawEffects() {
      const ctx = this.ctx;
      for (let i = 0; i < this.effects.length; i++) {
        const fx = this.effects[i];
        const alpha = clamp(fx.life / fx.maxLife, 0, 1);
        if (fx.type === "ring") {
          ctx.globalAlpha = alpha * 0.7;
          ctx.strokeStyle = fx.color;
          ctx.lineWidth = fx.width;
          ctx.beginPath();
          ctx.arc(fx.x, fx.y, Math.max(0.1, fx.radius), 0, TAU);
          ctx.stroke();
        } else if (fx.type === "dot") {
          ctx.globalAlpha = alpha;
          ctx.fillStyle = fx.color;
          ctx.beginPath();
          ctx.arc(fx.x, fx.y, fx.size, 0, TAU);
          ctx.fill();
        }
      }
      ctx.globalAlpha = 1;
    }

    drawFloats() {
      const ctx = this.ctx;
      ctx.save();
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      for (let i = 0; i < this.floats.length; i++) {
        const item = this.floats[i];
        const t = 1 - item.life / item.maxLife;
        const alpha = clamp(item.life / item.maxLife, 0, 1);
        const scale = t < 0.16 ? 0.6 + (t / 0.16) * 0.5 : 1 + (t - 0.16) * 0.14;
        ctx.globalAlpha = alpha;
        ctx.font = `800 ${item.size}px ${NUM_FONT}`;
        ctx.lineWidth = 4;
        ctx.strokeStyle = "rgba(255, 250, 240, 0.78)";
        ctx.fillStyle = item.color;
        ctx.save();
        ctx.translate(item.x, item.y);
        ctx.scale(scale, scale);
        ctx.strokeText(item.text, 0, 0);
        ctx.fillText(item.text, 0, 0);
        ctx.restore();
      }
      ctx.globalAlpha = 1;
      ctx.restore();
    }

    drawOverflowWarning() {
      if (this.overflowTime <= 0.04) return;
      const ctx = this.ctx;
      const l = this.layout;
      const progress = clamp(this.overflowTime / 3.2, 0, 1);
      const pulse = 0.65 + Math.sin(this.time * 8) * 0.2;

      ctx.save();
      ctx.strokeStyle = `rgba(217, 88, 74, ${0.35 + progress * 0.45})`;
      ctx.lineWidth = 1.6;
      ctx.setLineDash([5, 5]);
      ctx.beginPath();
      ctx.moveTo(l.jarX0 + 12, l.dangerY);
      ctx.lineTo(l.jarX1 - 12, l.dangerY);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = `rgba(217, 88, 74, ${pulse})`;
      ctx.font = `700 9px ${UI_FONT}`;
      ctx.textAlign = "right";
      ctx.textBaseline = "bottom";
      ctx.fillText("爆罐线", l.jarX1 - 16, l.dangerY - 5);

      const remain = Math.max(0, 3.2 - this.overflowTime);
      const text =
        remain > 0.1
          ? `罐子快撑爆了 · ${remain.toFixed(1)}s`
          : "罐子快撑爆了";
      ctx.font = `700 11px ${UI_FONT}`;
      const width = ctx.measureText(text).width + 26;
      const bx = l.cx - width / 2;
      const by = l.dangerY + 10;

      roundRectPath(ctx, bx, by, width, 26, 13);
      ctx.fillStyle = "rgba(255, 250, 240, 0.94)";
      ctx.fill();
      ctx.strokeStyle = `rgba(217, 88, 74, ${0.55 + progress * 0.35})`;
      ctx.lineWidth = 1.6;
      ctx.stroke();

      ctx.fillStyle = "#d9584a";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(text, l.cx, by + 13);

      roundRectPath(ctx, bx + 10, by + 30, width - 20, 3, 2);
      ctx.fillStyle = "rgba(217, 88, 74, 0.16)";
      ctx.fill();
      if (progress > 0) {
        roundRectPath(ctx, bx + 10, by + 30, (width - 20) * progress, 3, 2);
        ctx.fillStyle = "rgba(217, 88, 74, 0.78)";
        ctx.fill();
      }
      ctx.restore();
    }
  }

  window.addEventListener("DOMContentLoaded", () => {
    const game = new Game();
    window.__gulu = game;
    window.__citroLevelValue = levelDef;
  });
})();
