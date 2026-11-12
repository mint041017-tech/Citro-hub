import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../services/api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
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
    return GameScaffold(
      gameKey: 'gbrake',
      title: '极限刹车',
      showLive: false,
      showSidePanels: false,
      onBack: () => Navigator.maybePop(context),
      board: LayoutBuilder(
        builder: (context, cons) {
          // GameScaffold 的 board 区在滚动视图里：宽度有界、高度无界，
          // 高度按宽度折算（见 _brakeBoardSize）。
          final board = _brakeBoardSize(cons.maxWidth);
          return SizedBox(
            width: board.width,
            height: board.height,
            child: Stack(
              children: [
                Positioned.fill(child: HtmlElementView(viewType: _viewType)),
                if (_loading)
                  const Positioned.fill(
                    child: _BrakeLoading(key: ValueKey('brake-loading')),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 刹车棋盘（内嵌网页视口）按内容区约束推导。
///
/// 内容区宽度有界、高度无界，所以高度按宽度折算：窄内容区（手机）给竖屏
/// 比例，宽内容区（桌面横屏）给接近 16:10 的驾驶视角。
const double _kBrakeMaxWidth = 900;
const double _kBrakeMaxHeight = 640;
const double _kBrakeCompactRatio = 1.35;
const double _kBrakeWideRatio = 0.62;
const double _kBrakeCompactMaxWidth = 560;

Size _brakeBoardSize(double maxWidth) {
  final w = math.min(maxWidth, _kBrakeMaxWidth);
  final ratio = w < _kBrakeCompactMaxWidth
      ? _kBrakeCompactRatio
      : _kBrakeWideRatio;
  final h = (w * ratio).clamp(240.0, _kBrakeMaxHeight).toDouble();
  return Size(w, h);
}

/// 加载态：身份色进度屏（浅色端底 + 主色进度条 + 深色端文字）。
class _BrakeLoading extends StatelessWidget {
  const _BrakeLoading({super.key});

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
              '正在进入刹车场…',
              style: context.body(
                size: CitroType.body,
                weight: CitroType.strong,
                color: identity.deep,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '极限刹车 · 原版赛道',
              style: context.body(
                size: CitroType.small,
                color: identity.deep.withAlpha(160),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
