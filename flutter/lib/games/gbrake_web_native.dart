import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/api.dart';
import '../services/refresh_rate.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'game_ui.dart';

/// 极限刹车：内嵌原始版（three.js 构建产物），完全离线、不依赖任何 URL。
///
/// v1.7.2：修复「打开一片白」。
/// 之前用 `InAppLocalhostServer` + `http://localhost:8731` 加载，白屏可能来自
/// 端口占用 / 明文流量拦截 / MIME 不匹配 / 服务器与 WebView 的启动竞态。
/// 现在改为**把 index.html / app.js / app.css / citro-bridge.js 内联拼成
/// 一个完整的 HTML 字符串**，用 `loadData` 直接喂给 WebView：
/// 不发任何网络请求、不写临时文件、不受 origin 与 MIME 影响。
/// 空闲时预拼内嵌页面，重复进入不再现场读包。
Future<void> prewarmBrakeBundle() => _GameBrakeWebPageState.prewarm();

class GameBrakeWebPage extends StatefulWidget {
  const GameBrakeWebPage({super.key});

  @override
  State<GameBrakeWebPage> createState() => _GameBrakeWebPageState();
}

class _GameBrakeWebPageState extends State<GameBrakeWebPage> {
  static const _assetDir = 'assets/shache';

  InAppWebViewController? _web;
  bool _loading = true;
  String? _bootError;

  /// 加载阶段文案（0 打包资源 → 1 初始化三维场景 → 2 就绪）。
  int _stage = 0;

  /// 拼好的单文件 HTML（内联 JS/CSS），null 表示还在准备。
  String? _html;

  /// 原始版 three.js 资源拼装较费时（约 800KB 文本），静态缓存后
  /// 第二次进入/预热后直接复用，避免重复读包与字符串拼接。
  static String? _bundleCache;
  static Future<String>? _bundleFuture;

  static Future<void> prewarm() async {
    try {
      await _bundleText();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    RefreshRate.acquire();
    _buildBundle();
  }

  @override
  void dispose() {
    RefreshRate.release();
    try {
      final s = AppState.instance;
      unawaited(
        Api.gameLive(
          'gbrake',
          leave: true,
          name: s.loggedIn ? null : s.guestName,
          gid: s.loggedIn ? null : s.gid,
        ).then((_) {}, onError: (_) {}),
      );
    } catch (_) {}
    super.dispose();
  }

  Future<void> _buildBundle() async {
    try {
      final html = await _bundleText();
      if (!mounted) return;
      // 构建完成 → 进入「初始化三维场景」阶段，加载动画继续显示，
      // 直到 onLoadStop 里确认画布已创建才撤掉。
      setState(() {
        _html = html;
        _stage = 1;
      });
      await _load();
    } catch (e) {
      debugPrint('brake bundle build failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _bootError = '内置页面构建失败：$e';
        });
      }
    }
  }

  static Future<String> _bundleText() {
    final cached = _bundleCache;
    if (cached != null) return Future<String>.value(cached);
    final pending = _bundleFuture;
    if (pending != null) return pending;
    final future = _assembleBundle();
    _bundleFuture = future;
    future.then(
      (value) {
        _bundleCache = value;
        _bundleFuture = null;
      },
      onError: (_) {
        _bundleFuture = null;
      },
    );
    return future;
  }

  static Future<String> _assembleBundle() async {
    final html = await rootBundle.loadString('$_assetDir/index.html');
    final js = await rootBundle.loadString('$_assetDir/app.js');
    final css = await rootBundle.loadString('$_assetDir/app.css');
    final bridge = await rootBundle.loadString('$_assetDir/citro-bridge.js');

    // JS 里若出现 </script> 会提前闭合标签，做转义
    String safe(String s) => s.replaceAll('</script', r'<\/script');

    var out = html
        .replaceAll('<script src="citro-bridge.js"></script>', '')
        .replaceAll(
          '<script type="module" crossorigin="" src="app.js"></script>',
          '<!-- app.js 内联 -->',
        )
        .replaceAll('href="app.css"', 'id="__citro_css"');

    // 1) 在 <head> 最前面塞 localStorage 兜底（data: 或特殊 origin 下
    //    localStorage 可能抛异常，原版会在启动时读它）。
    const guard = '''
<script>
(function(){
  try { localStorage.setItem('__citro_t','1'); localStorage.removeItem('__citro_t'); }
  catch (e) {
    var m = {};
    window.localStorage = {
      getItem: function(k){ return (k in m) ? m[k] : null; },
      setItem: function(k,v){ m[k] = String(v); },
      removeItem: function(k){ delete m[k]; },
      clear: function(){ m = {}; },
      key: function(i){ return Object.keys(m)[i] || null; },
      get length(){ return Object.keys(m).length; }
    };
  }
})();
</script>
''';
    out = out.replaceFirst('<head>', '<head>\n$guard');

    // 2) 桥接脚本内联（必须在 app.js 之前执行）
    out = out.replaceFirst(
      '</head>',
      '<script>\n${safe(bridge)}\n</script>\n</head>',
    );

    // 3) app.js 以 module 内联；CSS 内联
    out = out.replaceFirst(
      '<!-- app.js 内联 -->',
      '<script type="module">\n${safe(js)}\n</script>',
    );
    out = out.replaceFirst(
      '<link rel="stylesheet" crossorigin="" id="__citro_css">',
      '<style>\n$css\n</style>',
    );
    // 兜底：万一样式链接没被替换成功，直接追加到 head
    if (!out.contains('<style>')) {
      out = out.replaceFirst('</head>', '<style>\n$css\n</style>\n</head>');
    }
    return out;
  }

  Future<void> _load() async {
    final web = _web;
    final html = _html;
    if (web == null || html == null) return;
    await web.loadData(
      data: html,
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: WebUri('https://shache.local/'),
    );
  }

  Future<void> _retry() async {
    setState(() {
      _bootError = null;
      _loading = true;
      _stage = _html == null ? 0 : 1;
    });
    if (_html == null) {
      await _buildBundle();
    } else {
      await _load();
    }
  }

  /// App 榜单 → 原版页面需要的 entries 结构。
  Future<List<Map<String, dynamic>>> _entries(int limit) async {
    final res = await AppState.instance.fetchBoard('brake');
    final raw = res['list'] ?? res['entries'] ?? res['board'] ?? res['data'];
    final out = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw.take(limit)) {
        if (e is! Map) continue;
        out.add({
          'nickname': '${e['name'] ?? e['nickname'] ?? '游客'}',
          'score': ((e['score'] ?? e['best'] ?? e['value'] ?? 0) as num)
              .toInt(),
          'v0': e['v0'] ?? 0,
          'stopTime': e['stopTime'] ?? 0,
        });
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> _fetchLive() async {
    try {
      final s = AppState.instance;
      return await Api.gameLive(
        'gbrake',
        name: s.loggedIn ? null : s.guestName,
        gid: s.loggedIn ? null : s.gid,
      );
    } catch (_) {
      return <String, dynamic>{'list': const <dynamic>[]};
    }
  }

  Future<Map<String, dynamic>> _onScore(Map body) async {
    final v0 = (body['v0'] as num?)?.toDouble() ?? 0;
    final stop = (body['stopTime'] as num?)?.toDouble() ?? 0;
    final reported = (body['score'] as num?)?.toInt() ?? 0;
    final computed = stop > 0 ? (v0 * v0 / stop).round() : 0;
    final score = reported > 0 ? reported : computed;
    if (body['failed'] == true) {
      await AppState.instance.noteGameRound();
      return {'ok': false, 'failed': true};
    }
    if (score <= 0) return {'ok': false, 'err': 'empty score'};
    final res = await AppState.instance.submitScore('brake', score);
    return {
      'ok': res['ok'] != false,
      'score': score,
      'best': res['best'] ?? score,
      'rank': res['rank'] ?? 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: const Color(0xFF120D10),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: context.c.surface,
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: GameHead(
                  onBack: () => Navigator.maybePop(context),
                  buttonSize: 42,
                  iconSize: 20,
                  centerBrand: true,
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: InAppWebView(
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          domStorageEnabled: true,
                          mediaPlaybackRequiresUserGesture: false,
                          allowsInlineMediaPlayback: true,
                          hardwareAcceleration: true,
                          transparentBackground: false,
                          supportZoom: false,
                          isTextInteractionEnabled: false,
                          disableContextMenu: true,
                          allowsLinkPreview: false,
                          safeBrowsingEnabled: false,
                          disableVerticalScroll: true,
                          disableHorizontalScroll: true,
                          useOnDownloadStart: false,
                          allowFileAccess: false,
                          allowContentAccess: false,
                        ),
                        onWebViewCreated: (controller) {
                          _web = controller;
                          controller.addJavaScriptHandler(
                            handlerName: 'citroScore',
                            callback: (args) async {
                              final body = args.isNotEmpty && args.first is Map
                                  ? Map<String, dynamic>.from(args.first as Map)
                                  : <String, dynamic>{};
                              return _onScore(body);
                            },
                          );
                          controller.addJavaScriptHandler(
                            handlerName: 'citroLeaderboard',
                            callback: (args) async {
                              final limit = args.isNotEmpty && args.first is num
                                  ? (args.first as num).toInt()
                                  : 50;
                              return {'entries': await _entries(limit)};
                            },
                          );
                          controller.addJavaScriptHandler(
                            handlerName: 'citroLive',
                            callback: (args) async => _fetchLive(),
                          );
                          controller.addJavaScriptHandler(
                            handlerName: 'citroRank',
                            callback: (args) {
                              if (mounted) {
                                showGameRank(
                                  context,
                                  game: 'brake',
                                  title: '极限刹车',
                                );
                              }
                              return {'ok': true};
                            },
                          );
                          _load();
                        },
                        onLoadStop: (controller, url) async {
                          if (!mounted) return;
                          setState(() => _stage = 1);
                          try {
                            final hasCanvas = await controller
                                .evaluateJavascript(
                                  source: "!!document.querySelector('canvas')",
                                );
                            if (!mounted) return;
                            if (hasCanvas != true) {
                              setState(
                                () => _bootError = '页面已加载但画布未初始化（WebGL 不可用？）',
                              );
                              return;
                            }
                            // 画布出现后等一帧让首屏渲染完成，再撤掉加载动画
                            await Future<void>.delayed(
                              const Duration(milliseconds: 260),
                            );
                            if (!mounted) return;
                            setState(() {
                              _stage = 2;
                              _loading = false;
                            });
                          } catch (_) {}
                        },
                      ),
                    ),
                    if (_loading && _bootError == null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _BrakeLoading(stage: _stage),
                        ),
                      ),
                    if (_bootError != null)
                      Positioned.fill(
                        child: ColoredBox(
                          color: const Color(0xFF120D10),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '游戏加载失败',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFF1DCAE),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _bootError!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: Color(0xB3F5EFE6),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  GestureDetector(
                                    onTap: _retry,
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 26,
                                      ),
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFFF6E5BF),
                                            Color(0xFFC9A86C),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(14),
                                        ),
                                      ),
                                      child: const Text(
                                        '重新加载',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF20170C),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 加载动画：暗色底 + 旋转金色弧 + 速度表意象 + 阶段文案。
/// 原版页面初始化 three.js 需要一两百毫秒到数秒（视机型），这里做成
/// 有明确进度的等待，而不是一个白色空屏。
class _BrakeLoading extends StatefulWidget {
  const _BrakeLoading({required this.stage});

  /// 0 = 准备资源，1 = 初始化三维场景，2 = 就绪。
  final int stage;

  @override
  State<_BrakeLoading> createState() => _BrakeLoadingState();
}

class _BrakeLoadingState extends State<_BrakeLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _label => switch (widget.stage) {
    0 => '正在准备赛道资源',
    1 => '正在初始化三维场景',
    _ => '准备就绪',
  };

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF120D10),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 112,
              height: 112,
              child: AnimatedBuilder(
                animation: _c,
                builder: (ctx, _) => CustomPaint(
                  painter: _LoadingArcPainter(t: _c.value),
                  child: Center(
                    child: Opacity(
                      opacity: 0.75 + 0.25 * (1 - (_c.value - 0.5).abs() * 2),
                      child: const Icon(
                        Icons.speed_rounded,
                        size: 34,
                        color: Color(0xFFF1DCAE),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _label,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: Color(0xE6F5EFE6),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '极限刹车 · 原版赛道',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                letterSpacing: 0.6,
                color: Color(0x73F5EFE6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingArcPainter extends CustomPainter {
  const _LoadingArcPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: r);

    // 底线圆环
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = const Color(0x26D8C39A),
    );

    // 旋转的进度弧（金色渐变 + 圆头）
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t * 6.28318);
    canvas.translate(-center.dx, -center.dy);
    final shader = const SweepGradient(
      startAngle: 0,
      endAngle: 3.14159,
      colors: [Color(0x00F1DCAE), Color(0xFFF1DCAE)],
    ).createShader(rect);
    canvas.drawArc(
      rect,
      -1.5708,
      3.14159,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
    canvas.restore();

    // 刻度点（速度表意象）
    for (var i = 0; i < 12; i++) {
      final a = i * 0.5236 - 1.5708;
      final p1 = center + Offset(math.cos(a) * (r - 9), math.sin(a) * (r - 9));
      final p2 = center + Offset(math.cos(a) * (r - 5), math.sin(a) * (r - 5));
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..strokeWidth = 1.4
          ..color = Color.lerp(
            const Color(0x1FD8C39A),
            const Color(0x8CF1DCAE),
            ((i / 12) + t) % 1,
          )!,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LoadingArcPainter old) => old.t != t;
}
