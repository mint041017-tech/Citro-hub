import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'liquid_board_metrics.dart';
import 'game_common.dart' show showGameLeaderboard;
import 'game_ui.dart'
    show
        GameActionButton,
        GameIcons,
        GameScaffold;
import 'game_web_shell.dart';

/// 咕噜果冻铺 Web 版：资源内联进单页 HTML。
/// 与其它游戏一致，统一走 GameScaffold 标准外壳（顶栏 + HUD + 棋盘 + 操作 + 正在玩），
/// 手机 / 横屏同一套骨架；网页内部按 citro-standard 隐藏自己的 HUD，读分交给 Flutter。
class GameLiquidPage extends StatefulWidget {
  const GameLiquidPage({super.key});

  @override
  State<GameLiquidPage> createState() => _GameLiquidPageState();
}

class _GameLiquidPageState extends State<GameLiquidPage>
    with WebBootState<GameLiquidPage>, LiquidWebShellState<GameLiquidPage> {
  InAppWebViewController? _web;
  String? _html;
  bool _isDark = false;
  bool _themeInitialized = false;

  static const _baseUrl = 'https://liquid2048.local/';
  static const _disableSelectionScript = '''
(function () {
  document.documentElement.style.userSelect = 'none';
  document.documentElement.style.webkitUserSelect = 'none';
  document.documentElement.style.webkitTouchCallout = 'none';
  if (window.__citroSelectionGuard) return;
  window.__citroSelectionGuard = true;
  ['contextmenu', 'selectstart', 'dragstart'].forEach(function (type) {
    document.addEventListener(type, function (event) {
      event.preventDefault();
    }, { passive: false });
  });
})();
''';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (platform.isTest) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!_themeInitialized) {
      _themeInitialized = true;
      _isDark = dark;
      unawaited(_prepare());
    } else if (_isDark != dark) {
      _isDark = dark;
      unawaited(_applyThemeMode());
    }
  }

  @override
  void dispose() {
    // 正在玩的轮询与离房由 GameScaffold 统一负责（与其它游戏一致）。
    disposeLiveProgress();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (mounted) resetBoot();
    try {
      final html = await _buildHtml();
      if (!mounted) return;
      _html = html;
      final web = _web;
      if (web != null) await _loadInto(web, html);
    } catch (e) {
      markBootFailed(e);
    }
  }

  Future<void> _loadInto(InAppWebViewController web, String html) async {
    resetBoot();
    await web.loadData(
      data: html,
      mimeType: 'text/html',
      baseUrl: WebUri(_baseUrl),
    );
  }

  Future<String> _buildHtml() async {
    final index = await rootBundle.loadString('assets/liquid2048/index.html');
    final css = await rootBundle.loadString('assets/liquid2048/styles.css');
    final scripts = <String, String>{
      for (final name in const ['audio', 'softbody', 'game'])
        name: await rootBundle.loadString('assets/liquid2048/js/$name.js'),
    };
    var html = index.replaceFirst(RegExp(r'<link rel="icon"[^>]*>'), '');
    if (_isDark) {
      html = html.replaceFirst(
        '<html lang="zh-CN">',
        '<html lang="zh-CN" class="citro-dark">',
      );
    }
    html = html.replaceFirst(
      '<link rel="stylesheet" href="styles.css">',
      '<style>$css</style>',
    );
    for (final entry in scripts.entries) {
      final tag = '<script src="js/${entry.key}.js"></script>';
      html = html.replaceFirst(
        tag,
        '<script>${entry.value.replaceAll(RegExp(r'</script', caseSensitive: false), r'<\/script')}</script>',
      );
    }
    if (html.contains('<script src="js/')) {
      throw StateError('liquid2048 脚本内联失败');
    }
    return html;
  }

  Future<Map<String, dynamic>> _onScore(Map<String, dynamic> body) async {
    final score = LiquidWebShellState.asInt(body['score']);
    final result = await submitLiquidScore(score);
    return Map<String, dynamic>.from(result);
  }

  Future<void> _applyThemeMode() async {
    final web = _web;
    if (web == null) return;
    try {
      await web.evaluateJavascript(
        source:
            "document.documentElement.classList.toggle('citro-dark', ${_isDark ? 'true' : 'false'});"
            "window.__gulu && window.__gulu.setDarkMode(${_isDark ? 'true' : 'false'});",
      );
    } catch (_) {}
  }

  /// 网页内部按 citro-standard 隐藏自己的 HUD / 玩法提示，标题、分数、操作、
  /// 正在玩都由 Flutter 的 GameScaffold 提供（与其它游戏同一套外壳）。
  Future<void> _applyStandardShell() async {
    final web = _web;
    if (web == null) return;
    try {
      await web.evaluateJavascript(
        source: "document.body.classList.add('citro-standard');",
      );
    } catch (_) {}
  }

  Future<void> _restartGame() async {
    final web = _web;
    if (web == null) return;
    try {
      await web.evaluateJavascript(
        source: "window.__gulu && (window.__gulu.state === 'start' ? window.__gulu.startGame() : window.__gulu.startNewRound('restart'));",
      );
    } catch (_) {}
  }

  void _retry() {
    final web = _web;
    if (web != null && _html != null) {
      unawaited(_loadInto(web, _html!));
    } else {
      unawaited(_prepare());
    }
  }

  @override
  Widget build(BuildContext context) {
    // 与其它游戏一致：始终 GameScaffold 标准外壳，手机 / 横屏同一套骨架。
    return _buildShell(context);
  }

  Widget _buildShell(BuildContext context) {
    return GameScaffold(
      gameKey: 'gliquid',
      title: '咕噜果冻铺',
      rankGame: 'liquid',
      showLive: true,
      liveProgress: liveProgress,
      onBack: () => Navigator.maybePop(context),
      pills: liquidPills(),
      actions: [
        GameActionButton(
          label: '重开',
          icon: GameIcons.refresh,
          onTap: () => unawaited(_restartGame()),
        ),
        GameActionButton(
          label: '排行榜',
          icon: GameIcons.trophy,
          onTap: () => showGameLeaderboard(context, game: 'liquid', title: '咕噜果冻铺'),
        ),
      ],
      boardGap: 12,
      board: LayoutBuilder(
        builder: (context, cons) {
          // GameScaffold 的 board 区在滚动视图里：宽度有界、高度无界，
          // 高度按宽度折算（见 LiquidBoardMetrics.boardSizeFor）。
          final size = LiquidBoardMetrics.boardSizeFor(maxWidth: cons.maxWidth);
          return SizedBox(
            width: size.width,
            height: size.height,
            child: platform.isTest ? _testBody(context) : _webPanel(context),
          );
        },
      ),
    );
  }

  Widget _webPanel(BuildContext context) {
    final panel = Stack(
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
              disableLongPressContextMenuOnLinks: true,
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
                handlerName: 'citroLiveState',
                callback: (args) {
                  final body = args.isNotEmpty && args.first is Map
                      ? Map<String, dynamic>.from(args.first as Map)
                      : <String, dynamic>{};
                  applyLiveState(body);
                  return true;
                },
              );
              final html = _html;
              if (html != null) {
                unawaited(_loadInto(controller, html));
              }
            },
            onLoadStop: (controller, _) {
              markBootReady();
              unawaited(
                controller.evaluateJavascript(source: _disableSelectionScript),
              );
              unawaited(_applyThemeMode());
              unawaited(_applyStandardShell());
            },
            onReceivedError: (_, request, error) {
              if (!mounted || request.isForMainFrame != true) return;
              markBootFailed(error.description);
            },
          ),
        ),
        if (loading && bootError == null)
          const Positioned.fill(
            child: GameWebLinearBoot(
              label: '正在准备果冻铺',
              subtitle: '咕噜果冻铺 · 软体合并',
            ),
          ),
        if (bootError != null)
          Positioned.fill(
            child: GameWebBootError(
              title: '果冻铺没有开门',
              message: bootError!,
              retryLabel: '重试',
              onRetry: _retry,
              messageMaxLines: 3,
            ),
          ),
      ],
    );
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: panel);
  }

  Widget _testBody(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.surface,
      alignment: Alignment.center,
      child: Text(
        '咕噜果冻铺',
        style: context.heading(size: CitroType.titleLg, color: c.ink),
      ),
    );
  }
}
