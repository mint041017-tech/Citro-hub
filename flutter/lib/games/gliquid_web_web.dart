import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'liquid_board_metrics.dart';
import 'game_common.dart' show showGameLeaderboard;
import 'game_ui.dart'
    show
        GameActionButton,
        GameIcons,
        GameScaffold;
import 'game_web_shell.dart';

/// Web 端用 iframe 装载同一份 liquid2048 资源；桌面 / iPad 与 Web 统一标准骨架。
class GameLiquidPage extends StatefulWidget {
  const GameLiquidPage({super.key});

  @override
  State<GameLiquidPage> createState() => _GameLiquidPageState();
}

class _GameLiquidPageState extends State<GameLiquidPage>
    with LiquidWebShellState<GameLiquidPage> {
  final String _viewType =
      'citro-liquid-${DateTime.now().microsecondsSinceEpoch}';
  late final web.HTMLIFrameElement _iframe;
  late final JSFunction _messageListener;
  bool _loading = true;
  bool _themeInitialized = false;
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    _iframe = web.HTMLIFrameElement()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..title = '咕噜果冻铺';
    _iframe.addEventListener(
      'load',
      ((web.Event _) {
        if (!mounted) return;
        setState(() => _loading = false);
        _sendShellMode();
      }).toJS,
    );
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _iframe,
    );
    _messageListener = ((web.MessageEvent event) => _onMessage(event)).toJS;
    web.window.addEventListener('message', _messageListener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!_themeInitialized) {
      _themeInitialized = true;
      _isDark = dark;
      _loadIframe();
    } else if (_isDark != dark) {
      _isDark = dark;
      _loadIframe();
    }
  }

  void _loadIframe() {
    final theme = _isDark ? 'dark' : 'light';
    _iframe.src =
        '${Uri.base.resolve('assets/assets/liquid2048/index.html')}?theme=$theme';
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _messageListener);
    disposeLiveProgress();
    super.dispose();
  }

  void _post(Map<String, dynamic> data) {
    _iframe.contentWindow?.postMessage(data.jsify(), '*'.toJS);
  }

  void _sendShellMode() {
    _post({'__citroShell': 'standard'});
  }

  void _onMessage(web.MessageEvent event) {
    final data = event.data?.dartify();
    if (data is! Map || data['__citroLiquid'] != 1) return;
    final type = '${data['type'] ?? ''}';
    if (type == 'live') {
      applyLiveState(data);
      return;
    }
    if (type == 'over') {
      final score = LiquidWebShellState.asInt(data['score']);
      unawaited(submitLiquidScore(score));
    }
  }

  void _restartGame() {
    _post({'__citroCommand': 'restart'});
  }

  @override
  Widget build(BuildContext context) {
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
          onTap: _restartGame,
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
            child: Stack(
              children: [
                Positioned.fill(child: HtmlElementView(viewType: _viewType)),
                if (_loading)
                  const Positioned.fill(
                    child: GameWebLinearBoot(
                      label: '正在准备果冻铺',
                      subtitle: '咕噜果冻铺 · 软体合并',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
