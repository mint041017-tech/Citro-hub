import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../services/api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'game_ui.dart';

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
          showGameRank(context, game: 'brake', title: '极限刹车');
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

  Future<Map<String, Object?>> _leaderboard(List<Object?> args) async {
    final limit = args.isNotEmpty && args.first is num
        ? (args.first as num).toInt()
        : 50;
    final res = await AppState.instance.fetchBoard('brake');
    final raw = res['list'] ?? res['entries'] ?? res['board'] ?? res['data'];
    final entries = <Map<String, Object?>>[];
    if (raw is List) {
      for (final item in raw.take(limit)) {
        if (item is! Map) continue;
        entries.add({
          'nickname': '${item['name'] ?? item['nickname'] ?? '游客'}',
          'score':
              ((item['score'] ?? item['best'] ?? item['value'] ?? 0) as num)
                  .toInt(),
          'v0': item['v0'] ?? 0,
          'stopTime': item['stopTime'] ?? 0,
        });
      }
    }
    return {'entries': entries};
  }

  @override
  Widget build(BuildContext context) {
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
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: HtmlElementView(viewType: _viewType)),
                if (_loading) const Positioned.fill(child: _BrakeLoading()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrakeLoading extends StatelessWidget {
  const _BrakeLoading();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF120D10),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFFFCE8E),
              ),
            ),
            SizedBox(height: 14),
            Text(
              '正在进入刹车场…',
              style: TextStyle(
                color: Color(0xB3FFF8EA),
                fontSize: 12,
                letterSpacing: .4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
