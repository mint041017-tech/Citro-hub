import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'liquid_board_metrics.dart';
import 'game_ui.dart'
    show
        GameActionButton,
        GameIcons,
        GameIdentityScope,
        GameScaffold,
        GameScorePill,
        showGameRank;

/// 咕噜果冻铺 Web 版：资源内联进单页 HTML。
/// 与其它游戏一致，统一走 GameScaffold 标准外壳（顶栏 + HUD + 棋盘 + 操作 + 正在玩），
/// 手机 / 横屏同一套骨架；网页内部按 citro-standard 隐藏自己的 HUD，读分交给 Flutter。
class GameLiquidPage extends StatefulWidget {
  const GameLiquidPage({super.key});

  @override
  State<GameLiquidPage> createState() => _GameLiquidPageState();
}

class _GameLiquidPageState extends State<GameLiquidPage> {
  InAppWebViewController? _web;
  String? _html;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _isDark = false;
  bool _themeInitialized = false;
  int _score = 0;
  int _best = 0;
  List<int> _next = const [];
  final ValueNotifier<String> _liveProgress = ValueNotifier('开局准备中');

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
    _liveProgress.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (mounted) setState(() => _error = null);
    try {
      final html = await _buildHtml();
      if (!mounted) return;
      _html = html;
      final web = _web;
      if (web != null) await _loadInto(web, html);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadInto(InAppWebViewController web, String html) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
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
    final score = (body['score'] as num?)?.toInt() ?? 0;
    if (score <= 0) {
      unawaited(AppState.instance.noteGameRound());
      return {'ok': false};
    }
    if (_submitting) return {'ok': false};
    _submitting = true;
    try {
      final res = await AppState.instance.submitScore('liquid', score);
      if (mounted) {
        final rank = res['rank'];
        AppToast.show(
          context,
          rank is num && rank > 0 ? '已计入排行榜 · 第 $rank 名' : '成绩已记录',
        );
      }
      return {'ok': res['ok'] != false, 'rank': res['rank'] ?? 0};
    } finally {
      _submitting = false;
    }
  }

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  void _handleLiveState(Map<String, dynamic> body) {
    final progress = '${body['progress'] ?? ''}'.trim();
    if (progress.isNotEmpty && _liveProgress.value != progress) {
      _liveProgress.value = progress;
    }
    final score = _asInt(body['score']);
    final best = _asInt(body['best']);
    final rawNext = body['next'];
    final next = rawNext is List
        ? rawNext.map(_asInt).where((v) => v > 0).toList(growable: false)
        : const <int>[];
    final changed = score != _score || best != _best || !_sameInts(next, _next);
    if (changed && mounted) {
      setState(() {
        _score = score;
        _best = best;
        _next = next;
      });
    }
  }

  bool _sameInts(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
      liveProgress: _liveProgress,
      onBack: () => Navigator.maybePop(context),
      pills: [
        GameScorePill(label: '分数', value: '$_score'),
        GameScorePill(label: '最高分', value: '${math.max(_best, _score)}'),
        GameScorePill(
          label: '接下来',
          value: _next.isEmpty ? '—' : _next.join('·'),
          minWidth: 96,
        ),
      ],
      actions: [
        GameActionButton(
          label: '重开',
          icon: GameIcons.refresh,
          onTap: () => unawaited(_restartGame()),
        ),
        GameActionButton(
          label: '排行榜',
          icon: GameIcons.trophy,
          onTap: () => showGameRank(context, game: 'liquid', title: '咕噜果冻铺'),
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
                  _handleLiveState(body);
                  return true;
                },
              );
              final html = _html;
              if (html != null) {
                unawaited(_loadInto(controller, html));
              }
            },
            onLoadStop: (controller, _) {
              if (mounted) setState(() => _loading = false);
              unawaited(
                controller.evaluateJavascript(source: _disableSelectionScript),
              );
              unawaited(_applyThemeMode());
              unawaited(_applyStandardShell());
            },
            onReceivedError: (_, request, error) {
              if (!mounted || request.isForMainFrame != true) return;
              setState(() {
                _error = error.description;
                _loading = false;
              });
            },
          ),
        ),
        if (_loading && _error == null)
          const Positioned.fill(child: _LiquidBoot()),
        if (_error != null)
          Positioned.fill(
            child: _LiquidBootError(message: _error!, onRetry: _retry),
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

/// 加载态：身份色进度屏（浅色端底 + 主色进度条 + 深色端文字），替代白底转圈。
class _LiquidBoot extends StatelessWidget {
  const _LiquidBoot();

  @override
  Widget build(BuildContext context) {
    final identity = GameIdentityScope.of(context);
    return ColoredBox(
      color: identity.soft,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 132,
              height: 4,
              child: LinearProgressIndicator(
                minHeight: 4,
                color: identity.primary,
                backgroundColor: identity.primary.withAlpha(40),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '正在准备果冻铺',
              style: context.body(
                size: CitroType.body,
                weight: CitroType.strong,
                color: identity.deep,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '咕噜果冻铺 · 软体合并',
              style: context.body(
                size: CitroType.small,
                color: identity.primaryInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 错误态：身份色底 + 主色实底按钮（按钮文字走 identity.onPrimary）。
class _LiquidBootError extends StatelessWidget {
  const _LiquidBootError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final identity = GameIdentityScope.of(context);
    return ColoredBox(
      color: identity.soft,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '果冻铺没有开门',
                style: context.heading(
                  size: CitroType.titleLg,
                  color: identity.deep,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.body(
                  size: CitroType.caption,
                  color: identity.primaryInk,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              GameActionButton(label: '重试', primary: true, onTap: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}
