/* Citro 接入层（v1.7.4）
 * 原版 shache.org 只通过两个接口访问后端：
 *   GET  /api/leaderboard?limit=N  -> { entries: [...] }
 *   POST /api/score {nickname,v0,stopTime} -> { ... }
 * 这里把 fetch 拦下来，转交给 Flutter 端：
 *   flutter_inappwebview.callHandler('citroLeaderboard', limit)
 *   flutter_inappwebview.callHandler('citroScore', payload)
 * 于是整套游戏完全离线运行，排行榜走 Citro App 自己的 /api/games/score。
 *
 * v1.7.4：
 *   - bridge 改为调用时再取（原版在 <head> 执行时 flutter_inappwebview
 *     可能还没注入，固定引用会让所有成绩静默丢失）。
 *   - 原版结算面板的昵称输入 + 提交按钮在 Citro 版里已移除，导致成绩
 *     永远不会提交。这里监听结算面板出现，成功刹停后自动上传得分。
 */
(function () {
  var nativeFetch = window.fetch ? window.fetch.bind(window) : null;

  function bridge() {
    return window.flutter_inappwebview || null;
  }

  /* Web 端：iframe 通过 postMessage 交给 Citro 网页宿主处理。
     桌面 WebView 仍优先走 flutter_inappwebview。 */
  var webBridge = window.parent && window.parent !== window;
  var webSeq = 0;
  var webPending = {};
  window.addEventListener('message', function (e) {
    var d = e.data;
    if (!d || d.__citroReply !== 1) return;
    var resolve = webPending[d.id];
    if (!resolve) return;
    delete webPending[d.id];
    resolve(d.result);
  });
  function callParent(name, args) {
    return new Promise(function (resolve) {
      var id = ++webSeq;
      webPending[id] = resolve;
      try {
        window.parent.postMessage(
          { __citro: 1, id: id, name: name, args: args || [] },
          '*'
        );
      } catch (e) {
        delete webPending[id];
        resolve(null);
      }
    });
  }

  function call(name, args) {
    var b = bridge();
    if (!b || !b.callHandler) {
      return webBridge ? callParent(name, args) : Promise.resolve(null);
    }
    return new Promise(function (resolve) {
      try {
        // flutter_inappwebview 的 callHandler(name, ...args) 是可变参数：
        // 之前传数组会被原生端当成「一个 List 参数」，args.first 不是 Map，
        // 成绩就永远被判定为空。这里把参数摊平。
        b.callHandler.apply(b, [name].concat(args || [])).then(resolve, function () {
          resolve(null);
        });
      } catch (e) {
        resolve(null);
      }
    });
  }

  function jsonResponse(obj) {
    return new Response(JSON.stringify(obj), {
      status: 200,
      headers: { 'content-type': 'application/json' }
    });
  }

  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    var method = ((init && init.method) || 'GET').toUpperCase();

    if (url.indexOf('/api/leaderboard') >= 0) {
      var m = /limit=(\d+)/.exec(url);
      var limit = m ? parseInt(m[1], 10) : 50;
      return call('citroLeaderboard', [limit]).then(function (res) {
        return jsonResponse({ entries: (res && res.entries) || [] });
      });
    }

    if (url.indexOf('/api/score') >= 0 && method === 'POST') {
      var body = {};
      try {
        body = JSON.parse((init && init.body) || '{}');
      } catch (e) {}
      return call('citroScore', [body]).then(function (res) {
        return jsonResponse(res || { ok: false });
      });
    }

    if (nativeFetch) return nativeFetch(input, init);
    return Promise.reject(new Error('offline'));
  };

  /* ---------- 成功刹停后自动上传 ---------- */
  function numberFrom(id) {
    var el = document.getElementById(id);
    if (!el) return 0;
    var v = parseFloat(String(el.textContent || '').replace(/[^\d.]/g, ''));
    return isFinite(v) ? v : 0;
  }

  function bootAutoSubmit() {
    var result = document.getElementById('result');
    if (!result) return false;

    var visible = false;
    var timer = 0;
    var lastKey = '';

    function submit() {
      timer = 0;
      var panel = document.getElementById('result');
      if (!panel || panel.classList.contains('hidden')) return;
      var title = document.getElementById('resultTitle');
      if (!title || !title.classList.contains('ok')) return;
      var score = Math.round(numberFrom('statScore'));
      if (!(score > 0)) return;
      var v0 = numberFrom('statV0');
      var stop = numberFrom('statTime');
      var key = score + '|' + v0 + '|' + stop;
      if (key === lastKey) return;
      lastKey = key;

      var msg = document.getElementById('submitMsg');
      if (msg) msg.textContent = '正在上传成绩…';

      call('citroScore', [{ score: score, v0: v0, stopTime: stop }]).then(
        function (res) {
          var el = document.getElementById('submitMsg');
          if (!el) return;
          if (res && res.ok) {
            var rank = parseInt(res.rank, 10) || 0;
            el.textContent = rank > 0
              ? '已上榜 · 当前第 ' + rank + ' 名'
              : '成绩已上榜 · 最高 ' + (res.best || score) + ' 分';
          } else {
            el.textContent = '成绩上传失败，请检查网络后再试';
          }
        }
      );
    }

    function onResultChange() {
      var shown = !result.classList.contains('hidden');
      if (!shown) {
        visible = false;
        lastKey = '';
        if (timer) {
          clearTimeout(timer);
          timer = 0;
        }
        return;
      }
      if (visible) return;
      visible = true;
      // 原版得分有 0.9s 数字滚动，等动画结束再读终值。
      if (timer) clearTimeout(timer);
      timer = setTimeout(submit, 1150);
    }

    new MutationObserver(onResultChange).observe(result, {
      attributes: true,
      attributeFilter: ['class'],
      childList: true,
      subtree: true,
      characterData: true
    });
    onResultChange();
    return true;
  }

  if (!bootAutoSubmit()) {
    var tries = 0;
    var iv = setInterval(function () {
      if (bootAutoSubmit() || ++tries > 100) clearInterval(iv);
    }, 100);
  }

  /* ---------- 制动计时下方的「正在玩」小卡 ---------- */
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (ch) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
  }

  function renderLive(res) {
    var box = document.getElementById('citroLive');
    if (!box) return;
    var list = (res && res.list) || [];
    var rows = '';
    for (var i = 0; i < list.length && i < 3; i++) {
      var e = list[i] || {};
      var name = String(e.name || '游客');
      var initial = name ? name.slice(-1) : '游';
      var you = e.you === true || e.you === 1;
      rows += '<div class="cl-row' + (you ? ' you' : '') + '">' +
        '<span class="cl-av">' + esc(initial) + '</span>' +
        '<span class="cl-name">' + esc(name) + '</span></div>';
    }
    if (!rows) rows = '<div class="cl-empty">还没有人</div>';
    box.innerHTML =
      '<div class="cl-title"><i class="cl-dot"></i><span>正在玩</span><b>' +
      list.length + '</b></div>' + rows;
    box.classList.remove('hidden');
  }

  var liveBooted = false;
  function bootLive() {
    if (liveBooted) return true;
    if (!document.getElementById('citroLive')) return false;
    liveBooted = true;
    var busy = false;
    function tick() {
      if (busy) return;
      busy = true;
      call('citroLive', []).then(function (res) {
        busy = false;
        renderLive(res);
      });
    }
    tick();
    setInterval(tick, 4000);
    return true;
  }

  /* ---------- 制动计时下方的「刹车次数」--------- */
  var brakeBooted = false;
  function bootBrakeCount() {
    if (brakeBooted) return true;
    var btn = document.getElementById('brakeBtn');
    var app = document.getElementById('app');
    var start = document.getElementById('startBtn');
    var retry = document.getElementById('retryBtn');
    var out = document.getElementById('citroBrakeCount');
    if (!btn || !app || !start || !retry || !out) return false;
    brakeBooted = true;
    var count = 0;
    function render() { out.textContent = String(count); }
    function reset() { count = 0; render(); }
    function hit() {
      // 未到 100 km/h 时踏板是禁用态，原版也不会起脚，这里同样不计。
      if (!btn.disabled) { count++; render(); }
    }
    start.addEventListener('click', reset);
    retry.addEventListener('click', reset);
    btn.addEventListener('pointerdown', hit, true);
    app.addEventListener('pointerdown', hit, true);
    render();
    return true;
  }

  /* ---------- 开始页 / 结算页的排行榜按钮 ---------- */
  var rankBooted = false;
  function bootRankButtons() {
    if (rankBooted) return true;
    var ids = ['citroMenuRank', 'citroResultRank'];
    var all = true;
    for (var i = 0; i < ids.length; i++) {
      if (!document.getElementById(ids[i])) all = false;
    }
    if (!all) return false;
    rankBooted = true;
    ids.forEach(function (id) {
      var el = document.getElementById(id);
      el.addEventListener('click', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        call('citroRank', []);
      });
    });
    return true;
  }

  var bootTries = 0;
  var bootIv = setInterval(function () {
    var live = bootLive();
    var count = bootBrakeCount();
    var rank = bootRankButtons();
    if ((live && count && rank) || ++bootTries > 100) clearInterval(bootIv);
  }, 100);
})();
