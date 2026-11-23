import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/api.dart';
import '../services/refresh_rate.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'game_identity.dart';
import 'game_ui.dart';
import 'game_common.dart' show showGameLeaderboard;
import 'game_web_shell.dart';

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

class _GameBrakeWebPageState extends State<GameBrakeWebPage>
    with WebBootState<GameBrakeWebPage> {
  static const _assetDir = 'assets/shache';

  InAppWebViewController? _web;

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
      markBootFailed('内置页面构建失败：$e');
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
    resetBoot();
    setState(() => _stage = _html == null ? 0 : 1);
    if (_html == null) {
      await _buildBundle();
    } else {
      await _load();
    }
  }

  /// App 榜单 → 原版页面需要的 entries 结构。
  Future<List<Map<String, Object?>>> _entries(int limit) async {
    final res = await AppState.instance.fetchBoard('brake');
    final raw = res['list'] ?? res['entries'] ?? res['board'] ?? res['data'];
    return brakeBoardEntries(raw, limit);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final identity = identityOf('gbrake');
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: context.c.bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: true,
        // 本页是全屏 WebView，不走 GameScaffold；在这里注入身份色，
        // GameHead / 加载态 / 错误态才不会回落到中性灰。
        child: GameIdentityScope(
          identity: identity,
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
                                final body =
                                    args.isNotEmpty && args.first is Map
                                    ? Map<String, dynamic>.from(
                                        args.first as Map,
                                      )
                                    : <String, dynamic>{};
                                return submitBrakeScore(body);
                              },
                            );
                            controller.addJavaScriptHandler(
                              handlerName: 'citroLeaderboard',
                              callback: (args) async {
                                final limit =
                                    args.isNotEmpty && args.first is num
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
                                  showGameLeaderboard(
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
                                    source:
                                        "!!document.querySelector('canvas')",
                                  );
                              if (!mounted) return;
                              if (hasCanvas != true) {
                                markBootFailed(
                                  '页面已加载但画布未初始化（WebGL 不可用？）',
                                  keepLoading: true,
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
                              });
                              markBootReady();
                            } catch (_) {}
                          },
                        ),
                      ),
                      if (loading && bootError == null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: GameWebArcBoot(
                              stage: _stage,
                              labels: const [
                                '正在准备赛道资源',
                                '正在初始化三维场景',
                                '准备就绪',
                              ],
                              subtitle: '极限刹车 · 原版赛道',
                            ),
                          ),
                        ),
                      if (bootError != null)
                        Positioned.fill(
                          child: GameWebBootError(
                            title: '游戏加载失败',
                            message: bootError!,
                            retryLabel: '重新加载',
                            onRetry: _retry,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                            ),
                            titleGap: 8,
                            buttonGap: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
