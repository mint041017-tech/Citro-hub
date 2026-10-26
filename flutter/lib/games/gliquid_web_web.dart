import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../state/app_state.dart';
import '../widgets/paper.dart';
import 'game_ui.dart'
    show
        GameActionButton,
        GameIcons,
        GameScaffold,
        GameScorePill,
        showGameRank;

/// Web 端用 iframe 装载同一份 liquid2048 资源；桌面 / iPad 与 Web 统一标准骨架。
class GameLiquidPage extends StatefulWidget {
  const GameLiquidPage({super.key});

  @override
  State<GameLiquidPage> createState() => _GameLiquidPageState();
}

class _GameLiquidPageState extends State<GameLiquidPage> {
  final String _viewType =
      'citro-liquid-${DateTime.now().microsecondsSinceEpoch}';
  late final web.HTMLIFrameElement _iframe;
  late final JSFunction _messageListener;
  bool _loading = true;
  bool _submitting = false;
  int _score = 0;
  int _best = 0;
  List<int> _next = const [];
  final ValueNotifier<String> _liveProgress = ValueNotifier('开局准备中');

  @override
  void initState() {
    super.initState();
    _iframe = web.HTMLIFrameElement()
      ..src = Uri.base.resolve('assets/assets/liquid2048/index.html').toString()
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
  void dispose() {
    web.window.removeEventListener('message', _messageListener);
    _liveProgress.dispose();
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
      _handleLiveState(data);
      return;
    }
    if (type == 'over') {
      final score = (data['score'] as num?)?.toInt() ?? 0;
      unawaited(_submitScore(score));
    }
  }

  int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  void _handleLiveState(Map data) {
    final progress = '${data['progress'] ?? ''}'.trim();
    if (progress.isNotEmpty && _liveProgress.value != progress) {
      _liveProgress.value = progress;
    }
    final score = _asInt(data['score']);
    final best = _asInt(data['best']);
    final rawNext = data['next'];
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

  Future<void> _submitScore(int score) async {
    if (score <= 0 || _submitting) return;
    _submitting = true;
    try {
      final res = await AppState.instance.submitScore('liquid', score);
      if (!mounted) return;
      final rank = res['rank'];
      AppToast.show(
        context,
        rank is num && rank > 0 ? '已计入排行榜 · 第 $rank 名' : '成绩已记录',
      );
    } finally {
      _submitting = false;
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
          onTap: _restartGame,
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
          final wide = media.width >= 1100 && media.width > media.height;
          final avail = cons.maxWidth.isFinite ? cons.maxWidth : 760.0;
          final boardW = math.min(avail, 430.0);
          final boardH = wide
              ? math.min(720.0, math.max(400.0, media.height - 300))
              : math.min(620.0, math.max(400.0, media.height - 420));
          return SizedBox(
            width: boardW,
            height: boardH,
            child: Stack(
              children: [
                Positioned.fill(child: HtmlElementView(viewType: _viewType)),
                if (_loading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0xFFF5ECDB),
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
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
