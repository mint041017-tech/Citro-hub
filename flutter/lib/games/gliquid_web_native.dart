import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/api.dart';
import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/paper.dart';
import 'liquid_board_metrics.dart';
import 'game_ui.dart'
    show
        GameActionButton,
        GameHead,
        GameIcons,
        GameLiveBar,
        GameScaffold,
        GameScorePill,
        gameIcon,
        showGameRank;

/// 咕噜果冻铺 Web 版：资源内联进单页 HTML。
/// 桌面 / iPad 横屏使用标准 GameScaffold；手机保留原有的紧凑游戏外壳。
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
  bool _standardShell = false;
  String _progress = '开局准备中';
  int _score = 0;
  int _best = 0;
  List<int> _next = const [];
  List<dynamic> _live = const [];
  Timer? _liveTimer;
  final ValueNotifier<String> _liveProgress = ValueNotifier('开局准备中');

  static const _baseUrl = 'https://liquid2048.local/';

  @override
  void initState() {
    super.initState();
    if (platform.isTest) return;
    unawaited(_prepare());
    _startLive();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _liveProgress.dispose();
    final state = AppState.instance;
    unawaited(
      Api.gameLive(
        'gliquid',
        leave: true,
        name: state.loggedIn ? null : state.guestName,
        gid: state.loggedIn ? null : state.gid,
      ).catchError((_) => <String, dynamic>{}),
    );
    super.dispose();
  }

  void _startLive() {
    _liveTimer?.cancel();
    unawaited(_tickLive());
    _liveTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_tickLive()),
    );
  }

  Future<void> _tickLive() async {
    if (!mounted) return;
    try {
      final state = AppState.instance;
      final j = await Api.gameLive(
        'gliquid',
        progress: _progress,
        name: state.loggedIn ? null : state.guestName,
        gid: state.loggedIn ? null : state.gid,
      );
      if (!mounted) return;
      setState(() => _live = (j['list'] as List?) ?? const []);
    } catch (_) {}
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
    if (score <= 0 || _submitting) return {'ok': false};
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
    if (progress.isNotEmpty) {
      _progress = progress;
      if (_liveProgress.value != progress) _liveProgress.value = progress;
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

  Future<void> _applyShellMode(bool standard) async {
    final web = _web;
    if (web == null) return;
    try {
      await web.evaluateJavascript(
        source:
            "document.body.classList.toggle('citro-standard', ${standard ? 'true' : 'false'});",
      );
    } catch (_) {}
  }

  Future<void> _restartGame() async {
    final web = _web;
    if (web == null) return;
    try {
      await web.evaluateJavascript(
        source:
            "window.__gulu && (window.__gulu.state === 'start' ? window.__gulu.startGame() : window.__gulu.startNewRound('restart'));",
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

  void _syncShellMode(bool standard) {
    if (_standardShell == standard) return;
    _standardShell = standard;
    if (standard) {
      _liveTimer?.cancel();
      _liveTimer = null;
    } else {
      _startLive();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_applyShellMode(standard));
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    // 与 Web 的 GameScaffold 判定保持一致：横屏一律标准壳，同窗口同罐子。
    final standard = media.width > media.height;
    _syncShellMode(standard);
    return standard ? _buildStandardShell(context) : _buildPhoneShell(context);
  }

  Widget _buildPhoneShell(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.surface,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: GameHead(
              onBack: () => Navigator.maybePop(context),
              buttonSize: 42,
              iconSize: 20,
              centerBrand: true,
              extraActions: [
                _RankButton(
                  onTap: () =>
                      showGameRank(context, game: 'liquid', title: '咕噜果冻铺'),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) {
                final media = MediaQuery.sizeOf(context);
                final boardW = LiquidBoardMetrics.boardWidth(
                  math.min(
                    cons.maxWidth,
                    media.width - LiquidBoardMetrics.sidePad * 2,
                  ),
                );
                final boardH = LiquidBoardMetrics.compactBoardHeight(
                  media,
                  MediaQuery.paddingOf(context),
                );
                return Center(
                  child: SizedBox(
                    width: boardW,
                    height: boardH,
                    child: platform.isTest
                        ? _testBody(context)
                        : _webPanel(context),
                  ),
                );
              },
            ),
          ),
          if (!platform.isTest)
            SafeArea(top: false, child: GameLiveBar(list: _live)),
        ],
      ),
    );
  }

  Widget _buildStandardShell(BuildContext context) {
    return GameScaffold(
      gameKey: 'gliquid',
      title: '咕噜果冻铺',
      rankGame: 'liquid',
      showLive: true,
      liveProgress: _liveProgress,
      onBack: () => Navigator.maybePop(context),
      pills: [
        GameScorePill(label: '分数', value: '$_score'),
        GameScorePill(
          label: '最高分',
          value: '${math.max(_best, _score)}',
        ),
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
          onTap: () =>
              showGameRank(context, game: 'liquid', title: '咕噜果冻铺'),
        ),
      ],
      boardGap: 12,
      board: LayoutBuilder(
        builder: (context, cons) {
          final media = MediaQuery.sizeOf(context);
          final avail = cons.maxWidth.isFinite
              ? cons.maxWidth
              : LiquidBoardMetrics.maxBoardWidth;
          final boardW = LiquidBoardMetrics.boardWidth(avail);
          final boardH = LiquidBoardMetrics.standardBoardHeight(
            media,
            MediaQuery.paddingOf(context),
          );
          return SizedBox(
            width: boardW,
            height: boardH,
            child: platform.isTest
                ? _testBody(context)
                : _webPanel(context, clipped: true),
          );
        },
      ),
    );
  }

  Widget _webPanel(BuildContext context, {bool clipped = false}) {
    final c = context.c;
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
            onLoadStop: (_, _) {
              if (mounted) setState(() => _loading = false);
              unawaited(_applyShellMode(_standardShell));
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
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFFF5ECDB),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: c.accent,
                  ),
                ),
              ),
            ),
          ),
        if (_error != null)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFFF5ECDB),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '果冻铺没有开门',
                        style: context.heading(
                          size: 20,
                          color: const Color(0xFF26313F),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.body(
                          size: 11.5,
                          color: const Color(0xFF66727E),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _retry,
                        style: FilledButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: const Color(0xFF2E2C22),
                        ),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (!clipped) return panel;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: panel,
    );
  }

  Widget _testBody(BuildContext context) {
    return Container(
      color: const Color(0xFFF5ECDB),
      alignment: Alignment.center,
      child: Text(
        '咕噜果冻铺',
        style: context.heading(size: 24, color: const Color(0xFF26313F)),
      ),
    );
  }
}

class _RankButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RankButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: c.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: c.line2),
        ),
        child: Center(
          child: gameIcon(GameIcons.trophy, size: 17, color: c.ink2),
        ),
      ),
    );
  }
}
