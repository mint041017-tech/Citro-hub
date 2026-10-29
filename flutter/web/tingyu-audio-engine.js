/* 听隅 Web Audio 引擎。内置录音来自固定 OBS 音频源，导入原件保存在 IndexedDB。
 * tingyuDiagnostics() 返回只读的诊断对象，不提供额外的数据修改入口。
 * performance.now 定时 + AudioParam 预调度不能保证系统挂起/锁屏时可靠执行。
 */
(() => {
  'use strict';
  const W = window;
  const DEFAULT_TRACKS = [
    { id: 'rain', volume: 65 }, { id: 'forest', volume: 25 }, { id: 'brown', volume: 20 },
  ];
  const BUILTINS = new Set(['rain', 'forest', 'stream', 'ocean', 'wind', 'chimes',
    'underwater', 'cafe', 'fire', 'white', 'pink', 'brown',
    'rain_soft', 'rain_roof', 'river', 'waterfall', 'crickets', 'cicadas', 'frogs', 'leaves',
    'train', 'fan', 'traffic', 'clock', 'keyboard', 'fireplace', 'bubbles', 'laundry']);
  const NOISE = new Set(['white', 'pink', 'brown']);
  // 录音只从这个固定地址读取，清单里的 file 字段不能改变音频来源。
  const AUDIO_BASE = 'https://obs.chimu-claw.xyz/ambient%20noise/';
  const AUDIO_NAME = /^[a-z][a-z0-9_]{0,63}$/;
  const MAX_BYTES = 50 * 1024 * 1024;
  const CACHE_BYTES = 64 * 1024 * 1024;
  const FADE = 0.065;
  const clock = () => performance.now();
  const localId = id => typeof id === 'string' && id.startsWith('local:');
  const failure = message => new Error(message);
  const state = {
    playing: false, tracks: DEFAULT_TRACKS.map(t => ({ ...t })), master: 70,
    title: '窗边一页', previewId: null, error: null,
  };
  let timer = { status: 'off', duration: 0, fade: 0, deadline: null };
  let recovery = null;
  let context = null, bus = null, compressor = null, timerGain = null, analyser = null;
  let meter = null, generation = 0, desiredPlaying = false, preview = null;
  let initPromise = null, manifestPromise = null, dbPromise = null, picker = null;
  let manifest = new Map(), manifestError = null, cacheBytes = 0;
  const locals = new Map(), cache = new Map(), inflight = new Map();
  const mainVoices = new Map(), voices = new Set(), jobs = new Set();

  function read(key) {
    try { return W.localStorage.getItem(`tingyu.${String(key)}`) || ''; }
    catch (_) { return ''; }
  }
  function write(key, value) {
    try { W.localStorage.setItem(`tingyu.${String(key)}`, String(value)); return true; }
    catch (_) { return false; }
  }
  function saveDraft() {
    if (!write('draft', JSON.stringify({ tracks: state.tracks, master: state.master, title: state.title }))) {
      state.error = '浏览器无法保存当前混音草稿；本次仍可使用。';
    }
  }
  function number(value, label, min = 0, max = 100) {
    if (typeof value !== 'number' || !Number.isFinite(value)) throw failure(`${label}必须是有效数字。`);
    return Math.min(max, Math.max(min, value));
  }
  function idOf(value) {
    if (typeof value !== 'string' || !value || value.length > 180) throw failure('声音编号无效。');
    return value;
  }
  function trackList(value) {
    if (!Array.isArray(value)) throw failure('混音轨道格式无效。');
    const unique = new Map();
    for (const track of value) {
      if (!track || typeof track !== 'object') throw failure('混音轨道格式无效。');
      const id = idOf(track.id);
      if (!unique.has(id)) unique.set(id, { id, volume: number(track.volume ?? 45, '轨道音量') });
    }
    if (unique.size > 6) throw failure('最多同时播放 6 种声音，请先移除一种。');
    return [...unique.values()];
  }
  try {
    const draft = JSON.parse(read('draft') || 'null');
    if (draft && Array.isArray(draft.tracks)) {
      const tracks = trackList(draft.tracks);
      const master = number(draft.master ?? 70, '总音量');
      state.tracks = tracks;
      state.master = master;
      if (typeof draft.title === 'string') state.title = draft.title.slice(0, 120);
    }
  } catch (_) { /* 无效草稿使用默认值，不自动播放。 */ }

  function hold(param, value) {
    const t = context.currentTime;
    if (typeof param.cancelAndHoldAtTime === 'function') param.cancelAndHoldAtTime(t);
    else param.cancelScheduledValues(t);
    if (value !== undefined) param.setValueAtTime(value, t);
    else if (typeof param.cancelAndHoldAtTime !== 'function') param.setValueAtTime(param.value, t);
  }
  function smooth(param, value, seconds = FADE) {
    hold(param);
    param.linearRampToValueAtTime(value, context.currentTime + seconds);
  }
  function timerValue(now = clock()) {
    if (timer.status === 'expired') return 0;
    const restored = recovery && now < recovery.end
      ? recovery.from + (1 - recovery.from) * Math.max(0, (now - recovery.start) / (recovery.end - recovery.start)) : 1;
    if (timer.deadline === null) return restored;
    const remaining = Math.max(0, (timer.deadline - now) / 1000);
    if (!remaining) return 0;
    if (!timer.fade || remaining >= timer.fade) return restored;
    return Math.sin(remaining / timer.fade * Math.PI / 2) ** 2;
  }
  function scheduleTimer() {
    if (!timerGain) return;
    const now = clock(), t = context.currentTime;
    const value = timerValue(now);
    hold(timerGain.gain, value);
    if (timer.deadline === null) {
      timerGain.gain.linearRampToValueAtTime(timer.status === 'expired' ? 0 : 1, t + FADE);
      return;
    }
    const remaining = Math.max(0, (timer.deadline - now) / 1000);
    if (!remaining) { timerGain.gain.setValueAtTime(0, t); return; }
    if (!timer.fade) {
      timerGain.gain.linearRampToValueAtTime(1, t + Math.min(FADE, remaining));
      timerGain.gain.setValueAtTime(0, t + remaining);
      return;
    }
    const wait = Math.max(0, remaining - timer.fade);
    if (wait > 0 && value < 1) timerGain.gain.linearRampToValueAtTime(1, t + Math.min(FADE, wait));
    const length = Math.min(remaining, timer.fade);
    const curve = new Float32Array(128);
    for (let i = 0; i < curve.length; i++) {
      curve[i] = Math.sin((length / timer.fade) * (1 - i / (curve.length - 1)) * Math.PI / 2) ** 2;
    }
    // 预排整条曲线；JS interval 仅作状态核对，不负责逐步降低音量。
    timerGain.gain.setValueCurveAtTime(curve, t + wait, length);
  }
  function mediaState() {
    try {
      if (!navigator.mediaSession) return;
      navigator.mediaSession.playbackState =
        state.playing || (preview && preview.started) ? 'playing' : 'paused';
      if (typeof W.MediaMetadata === 'function') {
        navigator.mediaSession.metadata = new W.MediaMetadata({
          title: state.title || '听隅',
          artist: '听隅 · 给自己，留一小片安静。',
          album: '声音空间',
          artwork: [{ src: new URL('assets/images/rain-nook.webp', document.baseURI).href,
            sizes: '1200x667', type: 'image/webp' }],
        });
      }
    } catch (_) { /* Media Session 是渐进增强，不声称拥有原生音频焦点。 */ }
  }
  function makeContext() {
    if (context && context.state !== 'closed') return context;
    const AudioContext = W.AudioContext || W.webkitAudioContext;
    if (!AudioContext) throw failure('此浏览器不支持 Web Audio，请使用新版 Chrome、Edge 或 Safari。');
    try {
      context = new AudioContext({ latencyHint: 'playback' });
      bus = context.createGain();
      compressor = context.createDynamicsCompressor();
      timerGain = context.createGain();
      analyser = context.createAnalyser();
      compressor.threshold.value = -9;
      compressor.knee.value = 12;
      compressor.ratio.value = 4;
      compressor.attack.value = 0.005;
      compressor.release.value = 0.25;
      bus.gain.value = 0;
      timerGain.gain.value = timerValue();
      analyser.fftSize = 2048;
      analyser.smoothingTimeConstant = 0.65;
      meter = new Float32Array(analyser.fftSize);
      bus.connect(compressor); compressor.connect(timerGain);
      timerGain.connect(analyser); analyser.connect(context.destination);
      context.addEventListener('statechange', () => {
        try {
          reconcile();
          if (context.state === 'running') scheduleTimer();
          if (context.state === 'closed') {
            pauseNow();
            state.error = '音频设备已关闭，请再次点击播放。';
          }
        } catch (_) { state.error = '音频设备状态发生变化，请再次点击播放。'; }
      });
      updateBus();
      return context;
    } catch (error) {
      throw failure('无法创建音频设备，请检查浏览器的声音权限。');
    }
  }
  // 必须在调用栈尚属于用户手势时执行；调用者只能在此函数之后 await。
  function audioReady() {
    const ctx = makeContext();
    try {
      return Promise.resolve(ctx.state === 'running' ? undefined : ctx.resume()).then(() => {
        reconcile();
        if (ctx.state !== 'running') throw failure('浏览器尚未允许播放，请再次点击播放按钮。');
        scheduleTimer();
      }, () => { throw failure('浏览器阻止了声音播放，请点击播放按钮重试。'); });
    } catch (_) { throw failure('无法恢复音频设备，请点击播放按钮重试。'); }
  }
  function normalization() {
    const sum = preview ? 0.7 : state.tracks.reduce((total, track) => total + track.volume / 100, 0);
    return 0.85 / Math.max(1, sum);
  }
  function updateBus() {
    if (bus) smooth(bus.gain, state.master / 100 * normalization());
  }
  function cleanVoice(voice) {
    if (voice.cleaned) return;
    voice.cleaned = true;
    clearTimeout(voice.cleanup);
    try { voice.source.disconnect(); voice.gain.disconnect(); } catch (_) { /* 已断开 */ }
    voices.delete(voice);
    if (mainVoices.get(voice.id) === voice) mainVoices.delete(voice.id);
  }
  function retire(voice, immediate = false) {
    if (!voice || voice.cleaned || (voice.retiring && !immediate)) return;
    voice.retiring = true;
    if (mainVoices.get(voice.id) === voice) mainVoices.delete(voice.id);
    try {
      if (immediate) {
        hold(voice.gain.gain, 0);
        voice.source.stop();
      } else {
        smooth(voice.gain.gain, 0);
        voice.source.stop(context.currentTime + FADE);
      }
    } catch (_) { /* Source 已停止时同样断开。 */ }
    // 即使 context 被挂起，也最终断开节点，不遗留可恢复的旧声音。
    if (immediate) cleanVoice(voice);
    else voice.cleanup = setTimeout(() => cleanVoice(voice), FADE * 1000 + 35);
  }
  function stopMain(immediate = false) {
    for (const voice of [...mainVoices.values()]) retire(voice, immediate);
    mainVoices.clear();
    state.playing = false;
    mediaState();
  }
  function clearPreview() {
    const old = preview;
    preview = null;
    state.previewId = null;
    if (old) { clearTimeout(old.timeout); retire(old.voice); }
    mediaState();
    return old;
  }
  function pauseNow() {
    generation++;
    desiredPlaying = false;
    clearPreview();
    stopMain();
    updateBus();
  }
  function expireTimer() {
    timer.status = 'expired';
    generation++;
    desiredPlaying = false;
    clearPreview();
    stopMain(true);
    for (const voice of [...voices]) retire(voice, true);
    if (timerGain) hold(timerGain.gain, 0);
    updateBus();
  }
  function reconcile() {
    const now = clock();
    if (timer.deadline !== null && timer.status !== 'expired') {
      const remaining = (timer.deadline - now) / 1000;
      if (remaining <= 0) expireTimer();
      else timer.status = timer.fade > 0 && remaining <= timer.fade ? 'fading' : 'running';
    }
    if (preview && preview.started && now >= preview.endAt) {
      const old = preview;
      finishPreview(old.generation).catch(error => { state.error = error.message; });
    }
  }
  function startArmedTimer() {
    if (timer.status === 'expired') timer = { status: 'off', duration: 0, fade: 0, deadline: null };
    if (timer.status === 'armed') {
      timer.deadline = clock() + timer.duration * 1000;
      timer.status = 'running';
    }
    reconcile();
    scheduleTimer();
  }
  function setTimer(payload) {
    const seconds = payload.seconds, fade = payload.fadeSeconds ?? 0;
    if (!Number.isInteger(seconds) || seconds < 1 || seconds > 43200) {
      throw failure('定时时长须为 1 至 720 分钟。');
    }
    if (typeof fade !== 'number' || !Number.isFinite(fade) || fade < 0 || fade > Math.min(seconds / 2, 120)) {
      throw failure('渐弱时长不能超过总时长的一半或 120 秒。');
    }
    const previous = timerValue();
    timer = { status: 'armed', duration: seconds, fade, deadline: null };
    recovery = { from: previous, start: clock(), end: clock() + FADE * 1000 };
    if (timerGain) { hold(timerGain.gain, previous); timerGain.gain.linearRampToValueAtTime(1, context.currentTime + FADE); }
    if (state.playing || (preview && preview.started)) startArmedTimer();
  }
  function cancelTimer() {
    const previous = timerValue();
    timer = { status: 'off', duration: 0, fade: 0, deadline: null };
    recovery = { from: previous, start: clock(), end: clock() + FADE * 1000 };
    if (timerGain) { hold(timerGain.gain, previous); timerGain.gain.linearRampToValueAtTime(1, context.currentTime + FADE); }
  }

  function openDB() {
    if (dbPromise) return dbPromise;
    dbPromise = new Promise((resolve, reject) => {
      if (!W.indexedDB) { reject(failure('浏览器不支持本地音频存储（IndexedDB）。')); return; }
      let settled = false, request;
      const fail = message => { if (!settled) { settled = true; clearTimeout(timeout); reject(failure(message)); } };
      const timeout = setTimeout(() => fail('本地音频数据库打开超时，请关闭其他标签页后重试。'), 8000);
      try { request = W.indexedDB.open('tingyu-audio', 1); }
      catch (_) { fail('浏览器禁止了本地音频存储，请检查隐私或存储设置。'); return; }
      request.onupgradeneeded = () => {
        if (!request.result.objectStoreNames.contains('audio')) request.result.createObjectStore('audio', { keyPath: 'id' });
      };
      request.onerror = () => fail('无法打开本地音频数据库；导入内容未保存。');
      request.onblocked = () => fail('本地音频数据库被其他标签页占用，请关闭后重试。');
      request.onsuccess = () => {
        if (settled) { request.result.close(); return; }
        settled = true; clearTimeout(timeout);
        const db = request.result;
        db.onversionchange = () => { db.close(); dbPromise = null; };
        resolve(db);
      };
    }).catch(error => { dbPromise = null; throw error; });
    return dbPromise;
  }
  async function dbOperation(mode, operation, message) {
    const db = await openDB();
    return new Promise((resolve, reject) => {
      let transaction, request, result;
      try {
        transaction = db.transaction('audio', mode);
        request = operation(transaction.objectStore('audio'));
        request.onsuccess = () => { result = request.result; };
        transaction.oncomplete = () => resolve(result);
        transaction.onabort = transaction.onerror = () => reject(failure(message));
      } catch (_) { reject(failure(message)); }
    });
  }
  function assetURL(file) {
    if (typeof file !== 'string') throw failure('声音清单缺少本地音频文件地址。');
    let decoded;
    try { decoded = decodeURIComponent(file); } catch (_) { throw failure('声音文件地址无效。'); }
    if (!decoded.startsWith('assets/audio/') || /[\\?#\u0000-\u001f]/.test(decoded) || decoded.split('/').includes('..')) {
      throw failure('仅允许使用本站 assets/audio 目录内的音频，不访问外部音频地址。');
    }
    const root = new URL('assets/audio/', document.baseURI);
    const url = new URL(file, document.baseURI);
    const origin = W.location ? W.location.origin : root.origin;
    if (url.origin !== origin || url.origin !== root.origin || !url.pathname.startsWith(root.pathname)) {
      throw failure('不允许访问外部音频地址。');
    }
    return url.href;
  }
  function audioURL(id) {
    if (!AUDIO_NAME.test(id) || !BUILTINS.has(id)) throw failure('这个声音没有可用的远程音频。');
    return new URL(`${id}.wav`, AUDIO_BASE).href;
  }
  function getManifest() {
    if (manifestPromise) return manifestPromise;
    manifestPromise = (async () => {
      try {
        const response = await fetch(assetURL('assets/audio/manifest.json'), { credentials: 'same-origin', redirect: 'error' });
        if (!response.ok) throw failure(`声音清单加载失败（HTTP ${response.status}）。`);
        const data = await response.json();
        if (!data || !Array.isArray(data.sounds)) throw failure('声音清单格式无效。');
        const entries = new Map();
        for (const item of data.sounds) {
          if (!item || !BUILTINS.has(item.id) || entries.has(item.id)) continue;
          entries.set(item.id, { id: item.id, name: typeof item.name === 'string' ? item.name : item.id,
            kind: item.kind || 'recording', file: item.file });
        }
        manifest = entries;
        manifestError = null;
      } catch (error) {
        manifestError = error.message && /[\u3400-\u9fff]/.test(error.message) ? error.message : '声音清单加载失败，请检查本站资源是否已部署。';
        throw failure(manifestError);
      }
    })().catch(error => { manifestPromise = null; throw error; });
    return manifestPromise;
  }
  function initialize() {
    if (initPromise) return initPromise;
    initPromise = (async () => {
      const warnings = [];
      await Promise.all([
        dbOperation('readonly', store => store.getAll(), '无法读取已导入的本地音频。').then(rows => {
          for (const row of rows || []) {
            if (row && localId(row.id) && typeof row.name === 'string' && Number.isFinite(row.duration) && row.blob) {
              locals.set(row.id, { id: row.id, name: row.name, duration: row.duration, size: row.size });
            }
          }
          const valid = state.tracks.filter(track => !localId(track.id) || locals.has(track.id));
          if (valid.length !== state.tracks.length) { state.tracks = valid; saveDraft(); }
        }).catch(error => { warnings.push(error.message); }),
        getManifest().catch(error => { warnings.push(error.message); }),
      ]);
      if (warnings.length) state.error = warnings.join(' ');
      return { warnings };
    })();
    return initPromise;
  }
  async function available(id) {
    if (NOISE.has(id)) return;
    if (localId(id)) {
      if (!locals.has(id)) throw failure('这段本地音频已不存在，请重新导入。');
      return;
    }
    if (!BUILTINS.has(id)) throw failure(`声音“${id}”不可用。`);
    if (!manifestPromise) {
      try { await getManifest(); } catch (_) { /* 下方给出逐条声音说明。 */ }
    }
    const item = manifest.get(id);
    if (!item) throw failure(`声音“${id}”尚未提供本地素材，暂时不可用。${manifestError || ''}`);
    if (item.kind === 'synth') {
      if (id !== 'underwater') throw failure(`声音“${item.name}”没有可用的实录素材。`);
    } else audioURL(id);
  }
  function evict(id) {
    const item = cache.get(id);
    if (item) { cacheBytes -= item.bytes; cache.delete(id); }
  }
  function remember(id, buffer) {
    evict(id);
    const bytes = buffer.length * buffer.numberOfChannels * 4;
    if (bytes > CACHE_BYTES || (localId(id) && !locals.has(id))) return;
    while (cache.size && (cacheBytes + bytes > CACHE_BYTES || cache.size >= 12)) evict(cache.keys().next().value);
    cache.set(id, { buffer, bytes });
    cacheBytes += bytes;
  }
  // 仅对接缝约 120ms 做交叉混合，旋转起点；不是把整段音频淡入淡出。
  function loopBuffer(original) {
    const n = original.length;
    const cross = Math.min(Math.floor(original.sampleRate * 0.12), Math.floor(n / 10));
    if (cross < 2) throw failure('这段声音过短，无法制作循环接缝。');
    const output = context.createBuffer(original.numberOfChannels, n - cross, original.sampleRate);
    for (let channel = 0; channel < original.numberOfChannels; channel++) {
      const input = original.getChannelData(channel), out = output.getChannelData(channel);
      out.set(input.subarray(cross, n - cross));
      for (let i = 0; i < cross; i++) {
        const mix = (1 - Math.cos(Math.PI * i / (cross - 1))) / 2;
        out[n - 2 * cross + i] = input[n - cross + i] * (1 - mix) + input[i] * mix;
      }
    }
    return output;
  }
  function noiseBuffer(id) {
    const sampleRate = context.sampleRate;
    const buffer = context.createBuffer(1, Math.ceil(sampleRate * 24), sampleRate);
    const data = buffer.getChannelData(0);
    let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0, brown = 0;
    let low1 = 0, low2 = 0, sum = 0;
    const alpha = 1 - Math.exp(-2 * Math.PI * 190 / sampleRate);
    for (let i = 0; i < data.length; i++) {
      const white = Math.random() * 2 - 1;
      let sample;
      if (id === 'white') sample = white;
      else if (id === 'pink') {
        b0 = 0.99886 * b0 + white * 0.0555179;
        b1 = 0.99332 * b1 + white * 0.0750759;
        b2 = 0.969 * b2 + white * 0.153852;
        b3 = 0.8665 * b3 + white * 0.3104856;
        b4 = 0.55 * b4 + white * 0.5329522;
        b5 = -0.7616 * b5 - white * 0.016898;
        sample = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362;
        b6 = white * 0.115926;
      } else {
        brown = (brown + 0.02 * white) / 1.02;
        sample = brown * 3.5;
        if (id === 'underwater') {
          low1 += alpha * (sample - low1); low2 += alpha * (low1 - low2);
          sample = low2 * (0.88 + 0.12 * Math.sin(2 * Math.PI * i / sampleRate / 7));
        }
      }
      data[i] = sample; sum += sample;
    }
    const mean = sum / data.length;
    let energy = 0, peak = 0;
    for (let i = 0; i < data.length; i++) {
      data[i] -= mean; energy += data[i] * data[i]; peak = Math.max(peak, Math.abs(data[i]));
    }
    const gain = Math.min(0.2 / Math.max(1e-8, Math.sqrt(energy / data.length)), 0.85 / Math.max(1e-8, peak));
    for (let i = 0; i < data.length; i++) data[i] *= gain;
    return loopBuffer(buffer);
  }
  async function decode(bytes, label) {
    try {
      const buffer = await context.decodeAudioData(bytes);
      if (!buffer || !Number.isFinite(buffer.duration) || buffer.duration <= 0) throw failure('空音频');
      return buffer;
    } catch (_) { throw failure(`无法解码“${label}”：文件可能损坏，或此浏览器不支持该音频格式。可尝试 WAV、MP3 或 OGG。`); }
  }
  async function bufferFor(id) {
    await available(id);
    if (cache.has(id)) {
      const item = cache.get(id); cache.delete(id); cache.set(id, item); return item.buffer;
    }
    if (inflight.has(id)) return inflight.get(id);
    const promise = (async () => {
      let buffer;
      if (NOISE.has(id) || (id === 'underwater' && manifest.get(id)?.kind === 'synth')) buffer = noiseBuffer(id);
      else if (localId(id)) {
        const record = await dbOperation('readonly', store => store.get(id), '读取这段本地音频失败，请重试。');
        if (!record || !record.blob) throw failure('这段本地音频的文件已丢失，请重新导入。');
        buffer = loopBuffer(await decode(await record.blob.arrayBuffer(), record.name));
      } else {
        const item = manifest.get(id);
        let response;
        try {
          response = await fetch(audioURL(id), {
            mode: 'cors', credentials: 'omit', redirect: 'error',
          });
        } catch (_) { throw failure(`无法加载“${item.name}”的远程音频，请检查网络后重试。`); }
        if (!response.ok) throw failure(`“${item.name}”加载失败（HTTP ${response.status}），没有使用替代噪声。`);
        let bytes;
        try { bytes = await response.arrayBuffer(); }
        catch (_) { throw failure(`读取“${item.name}”的音频文件失败。`); }
        if (bytes.byteLength > MAX_BYTES) throw failure(`“${item.name}”文件超过网页版 50MB 限制。`);
        buffer = loopBuffer(await decode(bytes, item.name));
      }
      remember(id, buffer);
      return buffer;
    })();
    inflight.set(id, promise);
    try { return await promise; } finally { if (inflight.get(id) === promise) inflight.delete(id); }
  }
  function createVoice(id, buffer, volume, role) {
    const source = context.createBufferSource(), gain = context.createGain();
    const voice = { id, source, gain, role, target: volume / 100, cleaned: false, retiring: false };
    voices.add(voice);
    try {
      source.buffer = buffer; source.loop = true;
      source.loopStart = 0; source.loopEnd = buffer.duration;
      gain.gain.value = 0;
      source.connect(gain); gain.connect(bus);
      source.onended = () => cleanVoice(voice); // 清理而非重播。
      source.start();
      smooth(gain.gain, voice.target);
      if (role === 'main') mainVoices.set(id, voice);
      return voice;
    } catch (_) { retire(voice, true); throw failure('无法启动音频轨道，请重试播放。'); }
  }
  function current(g) { reconcile(); return generation === g; }
  async function syncMix(g) {
    await initialize();
    if (!current(g) || !desiredPlaying) return { cancelled: true };
    if (!state.tracks.length) throw failure('请先添加至少一种声音。');
    const tracks = state.tracks.map(t => ({ ...t }));
    const loaded = await Promise.all(tracks.map(async track => ({ ...track,
      buffer: mainVoices.has(track.id) ? mainVoices.get(track.id).source.buffer : await bufferFor(track.id) })));
    if (!current(g) || !desiredPlaying) return { cancelled: true };
    for (const voice of [...mainVoices.values()]) {
      if (!state.tracks.some(track => track.id === voice.id)) retire(voice);
    }
    updateBus();
    try {
      for (const track of loaded) {
        const actual = state.tracks.find(t => t.id === track.id);
        if (actual && !mainVoices.has(track.id)) createVoice(track.id, track.buffer, actual.volume, 'main');
      }
      state.playing = mainVoices.size > 0;
      startArmedTimer();
      mediaState();
      return {};
    } catch (error) { stopMain(); throw error; }
  }
  function guardScene(g, promise) {
    return promise.catch(error => {
      if (generation !== g) return { cancelled: true };
      desiredPlaying = false;
      clearPreview(); stopMain(); updateBus();
      throw error;
    });
  }
  function play() {
    const g = ++generation;
    desiredPlaying = true;
    clearPreview(); updateBus();
    return guardScene(g, (async () => {
      await audioReady(); // 立即 resume，早于任何资源/数据库 await。
      if (!current(g)) return { cancelled: true };
      return syncMix(g);
    })());
  }
  function load(payload) {
    const tracks = trackList(payload.tracks);
    const autoplay = payload.autoplay !== false;
    if (payload.title !== undefined && typeof payload.title !== 'string') throw failure('混音标题格式无效。');
    const g = ++generation;
    desiredPlaying = autoplay;
    clearPreview(); stopMain();
    state.tracks = tracks;
    state.title = (payload.title ?? '自定义混音').slice(0, 120);
    saveDraft(); updateBus();
    return guardScene(g, (async () => {
      if (autoplay) await audioReady();
      await initialize();
      if (!current(g)) return { cancelled: true };
      if (autoplay) return syncMix(g);
      await Promise.all(tracks.map(track => available(track.id)));
      return current(g) ? {} : { cancelled: true };
    })());
  }
  function previewSound(id) {
    idOf(id);
    const resume = desiredPlaying || state.playing || Boolean(preview && preview.resume);
    const g = ++generation;
    desiredPlaying = false;
    clearPreview(); stopMain();
    preview = { id, generation: g, resume, started: false, voice: null, endAt: Infinity };
    state.previewId = id;
    updateBus();
    return guardScene(g, (async () => {
      await audioReady(); await initialize();
      if (!current(g)) return { cancelled: true };
      const buffer = await bufferFor(id);
      if (!current(g)) return { cancelled: true };
      const voice = createVoice(id, buffer, 70, 'preview');
      preview.voice = voice; preview.started = true; preview.endAt = clock() + 8000;
      // Audio 时钟也限制试听长度；恢复主混音仍受 generation 与绝对时间检查。
      voice.gain.gain.setValueAtTime(0.7, context.currentTime + 8 - FADE);
      voice.gain.gain.linearRampToValueAtTime(0, context.currentTime + 8);
      voice.source.stop(context.currentTime + 8);
      preview.timeout = setTimeout(() => {
        if (preview && preview.generation === g) {
          finishPreview(g).catch(error => { state.error = error.message; });
        }
      }, 8000);
      startArmedTimer(); mediaState();
      return {};
    })());
  }
  async function finishPreview(g) {
    if (!preview || preview.generation !== g || generation !== g) return { cancelled: true };
    // 到期优先于试听自动恢复。
    if (timer.deadline !== null && clock() >= timer.deadline) { expireTimer(); return {}; }
    const resume = preview.resume;
    clearPreview(); updateBus();
    if (!resume) { generation++; return Promise.resolve({}); }
    return withJob(() => play());
  }
  function add(payload) {
    const id = idOf(payload.id), volume = number(payload.volume ?? 45, '轨道音量');
    if (state.tracks.some(track => track.id === id)) return Promise.resolve({ alreadyAdded: true });
    if (state.tracks.length >= 6) throw failure('最多同时播放 6 种声音，请先移除一种。');
    const g = ++generation;
    // 编辑混音时结束试听，但不把暂停的混音自动启动。
    if (preview) { clearPreview(); desiredPlaying = false; }
    state.tracks.push({ id, volume });
    saveDraft(); updateBus();
    return (async () => {
      try {
        if (desiredPlaying) await audioReady();
        await initialize();
        if (!current(g)) return { cancelled: true };
        await available(id);
        if (!current(g)) return { cancelled: true };
        return desiredPlaying ? await syncMix(g) : {};
      } catch (error) {
        if (!current(g)) return { cancelled: true };
        state.tracks = state.tracks.filter(track => track.id !== id);
        retire(mainVoices.get(id));
        saveDraft(); updateBus();
        // 添加失败不破坏原来的混音，也不登记一个不可用的新轨道。
        if (desiredPlaying && state.tracks.length) {
          try { await syncMix(g); }
          catch (_) { if (generation === g) { desiredPlaying = false; stopMain(); } }
        }
        if (!current(g)) return { cancelled: true };
        throw error;
      }
    })();
  }
  function remove(id) {
    idOf(id);
    const hadTrack = state.tracks.some(track => track.id === id);
    if (!hadTrack && (!preview || preview.id !== id)) return Promise.resolve({});
    if (preview && preview.id !== id) {
      // 删除主混音的一轨不能中断正在试听的另一声音。
      state.tracks = state.tracks.filter(track => track.id !== id);
      if (!state.tracks.length) { preview.resume = false; cancelTimer(); }
      retire(mainVoices.get(id));
      saveDraft(); updateBus();
      return Promise.resolve({});
    }
    const g = ++generation;
    state.tracks = state.tracks.filter(track => track.id !== id);
    retire(mainVoices.get(id));
    if (preview) {
      // 改轨取消正在加载的试听；只恢复之前已播放的主混音。
      desiredPlaying = preview.resume;
      clearPreview();
    }
    if (!state.tracks.length) { desiredPlaying = false; stopMain(); cancelTimer(); }
    saveDraft(); updateBus();
    return desiredPlaying ? guardScene(g, syncMix(g)) : Promise.resolve({});
  }

  function importFile() {
    if (picker) throw failure('已有一个音频文件选择或导入任务，请先完成或取消。');
    const input = document.getElementById('local-audio-file');
    if (!input || input.type !== 'file') throw failure('找不到本地音频选择框，请刷新页面后重试。');
    input.accept = 'audio/*,.wav,.mp3,.ogg,.m4a,.aac,.flac,.webm';
    input.disabled = false;
    input.value = '';
    return new Promise((resolve, reject) => {
      let processing = false, settled = false, focusTimer;
      const token = {};
      picker = token;
      const done = (error, result) => {
        if (settled) return;
        settled = true; clearTimeout(focusTimer);
        input.removeEventListener('change', onChange); input.removeEventListener('cancel', onCancel);
        W.removeEventListener('focus', onFocus);
        input.disabled = false;
        if (picker === token) picker = null;
        if (error) reject(error); else resolve(result);
      };
      const onCancel = () => { if (!processing) done(null, { cancelled: true }); };
      const onFocus = () => {
        clearTimeout(focusTimer);
        focusTimer = setTimeout(() => {
          if (!processing && (!input.files || input.files.length === 0)) onCancel();
        }, 500);
      };
      const onChange = () => {
        if (processing || settled) return;
        const file = input.files && input.files[0];
        if (!file) { onCancel(); return; }
        processing = true;
        (async () => {
          if (!file.size || file.size > MAX_BYTES) throw failure('请选择非空且不超过 50MB 的音频文件。');
          // 解码不需要播放权限；创建 context 在 change 用户事件内完成。
          makeContext();
          await initialize();
          const decoded = await decode(await file.arrayBuffer(), file.name || '本地音频');
          if (decoded.duration < 5 || decoded.duration > 600) throw failure('网页版仅支持时长 5 秒至 10 分钟的本地音频。');
          const id = `local:${W.crypto && W.crypto.randomUUID ? W.crypto.randomUUID() : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`}`;
          const metadata = { id, name: (file.name || '本地音频').slice(0, 180), duration: decoded.duration, size: file.size };
          const buffer = loopBuffer(decoded);
          await dbOperation('readwrite', store => store.put({ ...metadata, blob: file }), '本地音频保存失败，可能是存储空间不足；没有登记此文件。');
          locals.set(id, metadata);
          remember(id, buffer);
          return { id };
        })().then(result => done(null, result), error => done(error));
      };
      input.addEventListener('change', onChange); input.addEventListener('cancel', onCancel);
      W.addEventListener('focus', onFocus);
      try { input.click(); } catch (_) { done(failure('浏览器未能打开文件选择器，请再点击一次导入。')); }
    });
  }
  async function deleteLocal(id) {
    idOf(id);
    await initialize();
    if (!localId(id) || !locals.has(id)) throw failure('找不到要删除的本地音频。');
    // 确认由 UI 负责；这里只删除明确指定的一个 ID，不提供批量清库入口。
    await dbOperation('readwrite', store => store.delete(id), '删除本地音频失败；文件仍保留，请重试。');
    locals.delete(id); evict(id);
    await remove(id);
    return { id };
  }
  function levels() {
    if (!analyser || !context || context.state !== 'running') return { rms: 0, peak: 0 };
    try {
      analyser.getFloatTimeDomainData(meter);
      let energy = 0, peak = 0;
      for (const sample of meter) { energy += sample * sample; peak = Math.max(peak, Math.abs(sample)); }
      return { rms: Math.sqrt(energy / meter.length), peak };
    } catch (_) { return { rms: 0, peak: 0 }; }
  }
  function snapshot() {
    reconcile();
    return {
      playing: state.playing, busy: jobs.size > 0, tracks: state.tracks.map(track => ({ ...track })),
      master: state.master,
      timer: { status: timer.status, remaining: timer.status === 'armed' ? timer.duration :
        timer.deadline === null || timer.status === 'expired' ? 0 : Math.max(0, (timer.deadline - clock()) / 1000),
      duration: timer.duration, fade: timer.fade },
      previewId: state.previewId,
      previewRemaining: preview && preview.started ? Math.max(0, (preview.endAt - clock()) / 1000) : 0,
      locals: [...locals.values()].map(item => ({ ...item })),
      error: state.error, title: state.title, level: levels().rms,
    };
  }
  function withJob(operation) {
    const token = {};
    jobs.add(token);
    let result;
    try { result = operation(); }
    catch (error) { jobs.delete(token); throw error; }
    return Promise.resolve(result).finally(() => jobs.delete(token));
  }
  function dispatch(action, payload) {
    switch (action) {
      case 'init': return initialize();
      case 'play': return play();
      case 'pause': pauseNow(); return {};
      case 'toggle': if (desiredPlaying || state.playing || preview) { pauseNow(); return {}; } return play();
      case 'load': return load(payload);
      case 'add': return add(payload);
      case 'remove': return remove(payload.id);
      case 'volume': {
        const id = idOf(payload.id), track = state.tracks.find(item => item.id === id);
        if (!track) throw failure('此声音不在当前混音中。');
        track.volume = number(payload.value, '轨道音量');
        const voice = mainVoices.get(id);
        if (voice) { voice.target = track.volume / 100; smooth(voice.gain.gain, voice.target); }
        saveDraft(); updateBus(); return {};
      }
      case 'master': state.master = number(payload.value, '总音量'); saveDraft(); updateBus(); return {};
      case 'preview': return previewSound(payload.id);
      case 'stopPreview': return preview ? finishPreview(preview.generation) : {};
      case 'timer': setTimer(payload); return {};
      case 'cancelTimer': cancelTimer(); return {};
      case 'stop': pauseNow(); cancelTimer(); return {};
      case 'import': return importFile();
      case 'deleteLocal': return deleteLocal(payload.id);
      default: throw failure('未知的音频操作。');
    }
  }
  W.tingyuRead = read;
  W.tingyuWrite = write;
  W.tingyuSnapshot = () => {
    try { return JSON.stringify(snapshot()); }
    catch (_) { state.error = '读取音频状态失败，请重试。'; return JSON.stringify({ ...state, busy: jobs.size > 0,
      timer: { status: timer.status, remaining: 0, duration: timer.duration, fade: timer.fade }, locals: [...locals.values()], level: 0 }); }
  };
  W.tingyuCommand = (action, payloadJSON = '{}') => {
    // 不把 dispatch 放到 Promise.then 中，以免丢失用户手势/文件选择权限。
    try {
      reconcile();
      const payload = JSON.parse(payloadJSON || '{}');
      if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw failure('音频操作参数格式无效。');
      state.error = null;
      return withJob(() => dispatch(action, payload)).then(result => JSON.stringify({ ok: true, ...(result || {}) }), error => {
        state.error = error && typeof error.message === 'string' && /[\u3400-\u9fff]/.test(error.message)
          ? error.message : '音频操作失败，请检查文件或浏览器权限后重试。';
        return JSON.stringify({ ok: false, error: state.error });
      });
    } catch (error) {
      state.error = error instanceof SyntaxError ? '音频操作参数不是有效的 JSON。' :
        error && /[\u3400-\u9fff]/.test(error.message) ? error.message : '音频操作失败，请重试。';
      return Promise.resolve(JSON.stringify({ ok: false, error: state.error }));
    }
  };
  W.tingyuDiagnostics = () => {
    reconcile();
    const measurement = levels();
    const sources = [...voices].map(voice => Object.freeze({ id: voice.id, role: voice.role,
      loop: voice.source.loop, duration: voice.source.buffer?.duration || 0,
      volume: voice.target, retiring: voice.retiring, gain: voice.gain.gain.value }));
    return Object.freeze({ context: Object.freeze({ state: context ? context.state : 'uninitialized',
      sampleRate: context ? context.sampleRate : null, currentTime: context ? context.currentTime : 0 }),
    sources: Object.freeze(sources), ...measurement, normalization: normalization(),
    cache: Object.freeze({ entries: cache.size, bytes: cacheBytes, limitBytes: CACHE_BYTES, loading: inflight.size }),
    generation, timerGain: timerValue(), deadline: timer.deadline, desiredPlaying });
  };
  try {
    if (navigator.mediaSession) {
      for (const action of ['play', 'pause', 'stop']) {
        try { navigator.mediaSession.setActionHandler(action, () => { W.tingyuCommand(action, '{}'); }); }
        catch (_) { /* 单个系统动作可能不受支持。 */ }
      }
    }
  } catch (_) { /* 非浏览器或不支持 Media Session。 */ }
  setInterval(() => { try { reconcile(); } catch (_) { state.error = '定时状态核对失败，请手动暂停声音。'; } }, 200);
  document.addEventListener('visibilitychange', () => {
    try { reconcile(); if (context && context.state === 'running') scheduleTimer(); } catch (_) { /* 下次快照再次核对。 */ }
  });
})();
