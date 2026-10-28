(function () {
  const STORE_KEY = "gulu-jelly-muted-v1";

  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

  const Audio = {
    ctx: null,
    master: null,
    enabled: true,
    noise: null,

    init() {
      if (this.ctx) {
        if (this.ctx.state === "suspended") this.ctx.resume();
        return;
      }
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;

      this.ctx = new Ctx();
      const comp = this.ctx.createDynamicsCompressor();
      comp.threshold.value = -18;
      comp.knee.value = 20;
      comp.ratio.value = 5;
      comp.attack.value = 0.004;
      comp.release.value = 0.24;

      this.master = this.ctx.createGain();
      this.master.gain.value = this.enabled ? 0.34 : 0.0001;
      this.master.connect(comp);
      comp.connect(this.ctx.destination);

      const length = Math.floor(this.ctx.sampleRate * 0.45);
      const buf = this.ctx.createBuffer(1, length, this.ctx.sampleRate);
      const data = buf.getChannelData(0);
      for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1;
      this.noise = buf;

      this.readMuted();
    },

    readMuted() {
      try {
        if (localStorage.getItem(STORE_KEY) === "1") this.enabled = false;
      } catch (err) {
        /* storage unavailable */
      }
    },

    saveMuted() {
      try {
        localStorage.setItem(STORE_KEY, this.enabled ? "0" : "1");
      } catch (err) {
        /* storage unavailable */
      }
    },

    setEnabled(value) {
      this.enabled = !!value;
      this.saveMuted();
      if (this.ctx && this.master) {
        const target = this.enabled ? 0.34 : 0.0001;
        this.master.gain.cancelScheduledValues(this.ctx.currentTime);
        this.master.gain.setTargetAtTime(target, this.ctx.currentTime, 0.03);
      }
    },

    tone(opts) {
      if (!this.ctx || !this.enabled) return;
      const o = opts || {};
      const t0 = this.ctx.currentTime + (o.delay || 0);
      const dur = o.dur || 0.16;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();

      osc.type = o.type || "sine";
      osc.frequency.setValueAtTime(Math.max(30, o.freq || 220), t0);
      if (o.endFreq) {
        osc.frequency.exponentialRampToValueAtTime(
          Math.max(30, o.endFreq),
          t0 + dur
        );
      }

      gain.gain.setValueAtTime(0.0001, t0);
      gain.gain.exponentialRampToValueAtTime(
        Math.max(0.0002, o.gain || 0.08),
        t0 + (o.attack || 0.008)
      );
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);

      osc.connect(gain);
      gain.connect(this.master);
      osc.start(t0);
      osc.stop(t0 + dur + 0.03);
    },

    noiseSweep(opts) {
      if (!this.ctx || !this.enabled || !this.noise) return;
      const o = opts || {};
      const t0 = this.ctx.currentTime + (o.delay || 0);
      const dur = o.dur || 0.12;
      const src = this.ctx.createBufferSource();
      src.buffer = this.noise;

      const filter = this.ctx.createBiquadFilter();
      filter.type = "bandpass";
      filter.Q.value = o.q || 0.9;
      filter.frequency.setValueAtTime(
        clamp(o.from || 1600, 80, 12000),
        t0
      );
      filter.frequency.exponentialRampToValueAtTime(
        clamp(o.to || 260, 60, 12000),
        t0 + dur
      );

      const gain = this.ctx.createGain();
      gain.gain.setValueAtTime(0.0001, t0);
      gain.gain.exponentialRampToValueAtTime(
        Math.max(0.0002, o.gain || 0.05),
        t0 + 0.01
      );
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);

      src.connect(filter);
      filter.connect(gain);
      gain.connect(this.master);
      src.start(t0);
      src.stop(t0 + dur + 0.02);
    },

    shoot(power) {
      const p = clamp(power || 0, 0, 1);
      this.tone({
        freq: 170 + p * 120,
        endFreq: 62,
        dur: 0.15,
        type: "sine",
        gain: 0.13,
      });
      this.noiseSweep({
        dur: 0.12,
        from: 1600 + p * 1500,
        to: 240,
        gain: 0.035 + p * 0.025,
      });
    },

    merge(level, combo) {
      const lv = clamp(level || 2, 1, 9);
      const base = clamp(300 * Math.pow(0.89, lv - 2), 92, 320);
      const c = Math.min(combo || 1, 8);
      const gain = 0.11 + Math.min(0.05, lv * 0.006);

      this.tone({
        freq: base * 1.72,
        endFreq: base * 2.25,
        dur: 0.1,
        type: "sine",
        gain,
      });
      this.tone({
        freq: base * 1.08,
        endFreq: base * 0.82,
        dur: 0.24,
        type: "triangle",
        gain: gain * 0.55,
        delay: 0.025,
      });
      this.tone({
        freq: 760 + c * 90,
        endFreq: 1080 + c * 100,
        dur: 0.07,
        type: "sine",
        gain: 0.025,
        delay: 0.075,
      });
      if (lv >= 7) {
        this.noiseSweep({
          dur: 0.18,
          from: 1800,
          to: 600,
          gain: 0.025,
          delay: 0.02,
        });
      }
    },

    pop() {
      this.tone({
        freq: 560,
        endFreq: 980,
        dur: 0.08,
        type: "sine",
        gain: 0.045,
      });
    },

    warn() {
      this.tone({
        freq: 250,
        endFreq: 220,
        dur: 0.18,
        type: "triangle",
        gain: 0.055,
      });
      this.tone({
        freq: 186,
        endFreq: 164,
        dur: 0.22,
        type: "triangle",
        gain: 0.045,
        delay: 0.14,
      });
    },

    over() {
      this.tone({
        freq: 300,
        endFreq: 92,
        dur: 0.65,
        type: "triangle",
        gain: 0.1,
      });
      this.tone({
        freq: 150,
        endFreq: 60,
        dur: 0.7,
        type: "sine",
        gain: 0.09,
        delay: 0.06,
      });
      this.noiseSweep({ dur: 0.35, from: 700, to: 120, gain: 0.03 });
    },

    burst() {
      // 闷响：罐子被撑开的那一下
      this.tone({
        freq: 170,
        endFreq: 44,
        dur: 0.5,
        type: "sine",
        gain: 0.16,
      });
      this.tone({
        freq: 96,
        endFreq: 38,
        dur: 0.62,
        type: "triangle",
        gain: 0.12,
        delay: 0.02,
      });
      // 玻璃碎片：几串高频短噪声
      for (let i = 0; i < 6; i++) {
        this.noiseSweep({
          dur: 0.07 + Math.random() * 0.1,
          from: 2600 + Math.random() * 2600,
          to: 900 + Math.random() * 1100,
          gain: 0.03,
          q: 2.2,
          delay: 0.015 + i * 0.032,
        });
      }
      this.noiseSweep({ dur: 0.5, from: 1900, to: 160, gain: 0.045 });
    },

    start() {
      this.tone({
        freq: 392,
        endFreq: 523,
        dur: 0.12,
        type: "triangle",
        gain: 0.06,
      });
      this.tone({
        freq: 523,
        endFreq: 784,
        dur: 0.16,
        type: "triangle",
        gain: 0.055,
        delay: 0.1,
      });
    },

    ui() {
      this.tone({
        freq: 620,
        endFreq: 720,
        dur: 0.05,
        type: "sine",
        gain: 0.025,
      });
    },
  };

  window.GuluAudio = Audio;
})();
