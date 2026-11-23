import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../services/api.dart';
import '../state/app_state.dart';
import 'game_ui.dart';
import 'game_common.dart' show showGameLeaderboard;
import 'game_web_shell.dart';

Future<void> prewarmBrakeBundle() async {}

/// 网页端嵌入 shache.org 原版 three.js 构建，与桌面端使用同一份资源；
/// 排行榜 / 成绩通过 postMessage 交给 Flutter 宿主。
class GameBrakeWebPage extends StatefulWidget {
  const GameBrakeWebPage({super.key});

  @override
  State<GameBrakeWebPage> createState() => _GameBrakeWebPageState();
}

class _GameBrakeWebPageState extends State<GameBrakeWebPage> {
  final String _viewType =
      'citro-brake-${DateTime.now().microsecondsSinceEpoch}';
  late final web.HTMLIFrameElement _iframe;
  late final JSFunction _messageListener;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _iframe = web.HTMLIFrameElement()
      ..src = Uri.base.resolve('assets/assets/shache/index.html').toString()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..title = '极限刹车挑战';
    _iframe.addEventListener(
      'load',
      ((web.Event _) {
        if (mounted) setState(() => _loading = false);
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
  void dispose() {
    web.window.removeEventListener('message', _messageListener);
    super.dispose();
  }

  void _onMessage(web.MessageEvent event) {
    final data = event.data?.dartify();
    if (data is! Map || data['__citro'] != 1) return;
    final id = data['id'];
    final name = '${data['name'] ?? ''}';
    final rawArgs = data['args'];
    final args = rawArgs is List ? rawArgs : const <Object?>[];
    unawaited(_reply(id, name, args));
  }

  Future<void> _reply(Object? id, String name, List<Object?> args) async {
    Object? result;
    try {
      result = await _handle(name, args);
    } catch (_) {
      result = null;
    }
    _iframe.contentWindow?.postMessage(
      {'__citroReply': 1, 'id': id, 'result': result}.jsify(),
      '*'.toJS,
    );
  }

  Future<Object?> _handle(String name, List<Object?> args) async {
    switch (name) {
      case 'citroScore':
        return _onScore(args);
      case 'citroLeaderboard':
        return _leaderboard(args);
      case 'citroLive':
        final s = AppState.instance;
        return Api.gameLive(
          'gbrake',
          name: s.loggedIn ? null : s.guestName,
          gid: s.loggedIn ? null : s.gid,
        );
      case 'citroRank':
        if (mounted) {
          showGameLeaderboard(context, game: 'brake', title: '极限刹车');
        }
        return null;
      default:
        return null;
    }
  }

  Future<Map<String, Object?>> _onScore(List<Object?> args) async {
    final raw = args.isNotEmpty && args.first is Map ? args.first as Map : null;
    final body = raw == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(raw);
    return submitBrakeScore(body);
  }

  Future<Map<String, Object?>> _leaderboard(List<Object?> args) async {
    final limit = args.isNotEmpty && args.first is num
        ? (args.first as num).toInt()
        : 50;
    final res = await AppState.instance.fetchBoard('brake');
    final raw = res['list'] ?? res['entries'] ?? res['board'] ?? res['data'];
    return {'entries': brakeBoardEntries(raw, limit)};
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameKey: 'gbrake',
      title: '极限刹车',
      showLive: false,
      showSidePanels: false,
      onBack: () => Navigator.maybePop(context),
      board: LayoutBuilder(
        builder: (context, cons) {
          // GameScaffold 的 board 区在滚动视图里：宽度有界、高度无界，
          // 高度按宽度折算（见 BrakeBoardMetrics.boardSize）。
          final board = BrakeBoardMetrics.boardSize(cons.maxWidth);
          return SizedBox(
            width: board.width,
            height: board.height,
            child: Stack(
              children: [
                Positioned.fill(child: HtmlElementView(viewType: _viewType)),
                if (_loading)
                  const Positioned.fill(
                    child: GameWebLinearBoot(
                      key: ValueKey('brake-loading'),
                      label: '正在进入刹车场…',
                      subtitle: '极限刹车 · 原版赛道',
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
