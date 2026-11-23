import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'game_common.dart';
import 'game_random.dart';
import 'game_ui.dart';

class GameSlidePage extends StatefulWidget {
  const GameSlidePage({super.key});
  @override
  State<GameSlidePage> createState() => _GameSlidePageState();
}

class _GameSlidePageState extends State<GameSlidePage> {
  /// (标签, 边长, 满分秒数基准)
  static const _diffs = <String, (String, int, int)>{
    'easy': ('简单 3×3', 3, 1200),
    'std': ('标准 4×4', 4, 3000),
    'hard': ('困难 5×5', 5, 6000),
  };

  String diff = 'std';
  int size = 4;
  List<int> tiles = <int>[];
  int empty = 0;
  int moves = 0;
  int seconds = 0;
  bool started = false;
  bool over = false;
  bool submitted = false;
  Timer? timer;
  final _progress = ValueNotifier<String>('步数 0');
  final FocusNode _focus = FocusNode();

  (String, int, int) get _meta => _diffs[diff]!;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  @override
  void dispose() {
    timer?.cancel();
    _progress.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _newGame() {
    timer?.cancel();
    final meta = _meta;
    size = meta.$2;
    final n = size * size;
    tiles = List<int>.generate(n, (i) => i == n - 1 ? 0 : i + 1);
    empty = n - 1;
    _shuffle();
    if (_solved()) {
      // 极低概率：洗牌后仍是完成态，交换一次打破
      final nb = _neighbors(empty).first;
      _swap(nb);
    }
    moves = 0;
    seconds = 0;
    started = false;
    over = false;
    submitted = false;
    _progress.value = '步数 0';
    setState(() {});
    _focus.requestFocus();
  }

  void _shuffle() {
    final rnd = GameRandom.create();
    var last = -1;
    for (var i = 0; i < size * size * 40; i++) {
      final nbs = _neighbors(empty).where((n) => n != last).toList();
      if (nbs.isEmpty) continue;
      final n = nbs[rnd.nextInt(nbs.length)];
      last = empty;
      _swap(n);
    }
  }

  List<int> _neighbors(int i) {
    final r = i ~/ size, c = i % size;
    return [
      if (r > 0) i - size,
      if (r < size - 1) i + size,
      if (c > 0) i - 1,
      if (c < size - 1) i + 1,
    ];
  }

  void _swap(int i) {
    final t = tiles[i];
    tiles[i] = tiles[empty];
    tiles[empty] = t;
    empty = i;
  }

  bool _solved() {
    for (var i = 0; i < tiles.length - 1; i++) {
      if (tiles[i] != i + 1) return false;
    }
    return tiles.last == 0;
  }

  void _start() {
    if (started) return;
    started = true;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || over) return;
      setState(() => seconds++);
    });
  }

  void _tap(int i) {
    if (over) return;
    if (!_neighbors(empty).contains(i)) return;
    _start();
    setState(() {
      _swap(i);
      moves++;
      _progress.value = '步数 $moves';
    });
    GameSfx.move();
    _checkWin();
  }

  void _checkWin() {
    if (!_solved()) return;
    over = true;
    timer?.cancel();
    GameSfx.win();
    final score = math.max(1, _meta.$3 - seconds);
    context.app.saveLocalBest('slide:$diff', score);
    if (!submitted) {
      submitted = true;
      context.app.submitScore('slide:$diff', score);
    }
    setState(() {});
  }

  void _key(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final col = empty % size, row = empty ~/ size;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (col < size - 1) _tap(empty + 1);
        break;
      case LogicalKeyboardKey.arrowRight:
        if (col > 0) _tap(empty - 1);
        break;
      case LogicalKeyboardKey.arrowUp:
        if (row < size - 1) _tap(empty + size);
        break;
      case LogicalKeyboardKey.arrowDown:
        if (row > 0) _tap(empty - size);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bestScore = context.app.localBest('slide:$diff');
    final bestSeconds = bestScore > 0 ? math.max(1, _meta.$3 - bestScore) : 0;
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: GameSlideView(
        size: size,
        tiles: tiles,
        empty: empty,
        moves: moves,
        seconds: seconds,
        bestSeconds: bestSeconds,
        diff: diff,
        over: over,
        score: math.max(1, _meta.$3 - seconds),
        onDiff: (d) {
          setState(() => diff = d);
          _newGame();
        },
        onNewGame: _newGame,
        onTap: _tap,
        onRetry: _newGame,
        liveProgress: _progress,
        onRank: () => showGameLeaderboard(
          context,
          game: 'slide',
          title: '数字华容道',
          difficulties: const [('easy', '简单'), ('std', '标准'), ('hard', '困难')],
          initial: diff,
        ),
      ),
    );
  }
}

/// 数字华容道视觉层（golden 用固定牌面渲染）
class GameSlideView extends StatelessWidget {
  const GameSlideView({
    super.key,
    required this.size,
    required this.tiles,
    required this.empty,
    required this.moves,
    required this.seconds,
    required this.bestSeconds,
    required this.diff,
    this.over = false,
    this.score = 0,
    this.onDiff,
    this.onNewGame,
    this.onTap,
    this.onRetry,
    this.onRank,
    this.liveProgress,
  });

  final int size;
  final List<int> tiles;
  final int empty;
  final int moves;
  final int seconds;
  final int bestSeconds;
  final String diff;
  final bool over;
  final int score;
  final ValueChanged<String>? onDiff;
  final VoidCallback? onNewGame;
  final ValueChanged<int>? onTap;
  final VoidCallback? onRetry;
  final VoidCallback? onRank;
  final ValueNotifier<String>? liveProgress;

  static const _tabs = <(String, String)>[
    ('easy', '简单 3×3'),
    ('std', '标准 4×4'),
    ('hard', '困难 5×5'),
  ];

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameKey: 'gslide',
      title: '数字华容道',
      liveProgress: liveProgress,
      rankDifficulties: const [('easy', '简单'), ('std', '标准'), ('hard', '困难')],
      rankInitial: diff,
      above: [_DiffTabs(diff: diff, onChanged: onDiff)],
      pills: [
        GameScorePill(label: '步数', value: '$moves'),
        GameScorePill(label: '用时', value: fmtDuration(seconds)),
        GameScorePill(
          label: '最佳',
          value: bestSeconds > 0 ? fmtDuration(bestSeconds) : '--',
          minWidth: 63,
        ),
      ],
      actions: [
        GameActionButton(
          label: '新游戏',
          icon: GameIcons.reset,
          primary: true,
          onTap: onNewGame,
        ),
        GameActionButton(label: '排行榜', icon: GameIcons.trophy, onTap: onRank),
      ],
      boardGap: 30,
      // 按内容区宽度自适应：横屏扣掉左右侧栏、平板扣掉 rail 之后自动跟上。
      board: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
          final boardW = math.min(w * .94, 500.0);
          return SizedBox(
            width: boardW,
            height: boardW,
            child: _board(context, boardW),
          );
        },
      ),
    );
  }

  /// .gslide-board：凹版底 + 空格 + 数字块 + 结算浮层
  Widget _board(BuildContext context, double boardW) {
    final c = context.c;
    final id = GameIdentityScope.of(context);
    final n = size;
    final pad = 10.0;
    final gap = 8.0;
    final border = 1.0;
    final cell = (boardW - border * 2 - pad * 2 - gap * (n - 1)) / n;
    final originX = border + pad;
    final originY = border + pad;
    final radius = CitroColors.radii.card; // 14
    final inner = CitroColors.radii.inner; // 10

    Widget tileAt(int index, int value) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null ? null : () => onTap!(index),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: id.primary,
            borderRadius: BorderRadius.circular(inner),
            boxShadow: CitroColors.shadows.sm(c),
          ),
          child: Text(
            '$value',
            style: context.hand(
              size: cell * 0.34,
              weight: CitroType.strong,
              color: id.onPrimary,
            ),
          ),
        ),
      );
    }

    final emptyCol = empty % n, emptyRow = empty ~/ n;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: id.primary.withAlpha(60)),
              boxShadow: CitroColors.shadows.card(c),
            ),
          ),
        ),
        // 空格
        Positioned(
          left: originX + emptyCol * (cell + gap),
          top: originY + emptyRow * (cell + gap),
          width: cell,
          height: cell,
          child: Container(
            decoration: BoxDecoration(
              color: id.soft.withAlpha(120),
              borderRadius: BorderRadius.circular(inner),
              border: Border.all(color: id.deep.withAlpha(60), width: 1),
            ),
          ),
        ),
        for (var i = 0; i < tiles.length; i++)
          if (tiles[i] != 0)
            AnimatedPositioned(
              key: ValueKey<int>(tiles[i]),
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              left: originX + (i % n) * (cell + gap),
              top: originY + (i ~/ n) * (cell + gap),
              width: cell,
              height: cell,
              child: tileAt(i, tiles[i]),
            ),
        if (over) Positioned.fill(child: _overlay(context)),
      ],
    );
  }

  /// 结算浮层 —— v1.6.1 起与淘气小球结算卡同一套样式
  /// （半透明纸面 / 圆角 22 / Kalam 标题 / 灰描述金棕数字 / 主按钮垂直居中）。
  Widget _overlay(BuildContext context) {
    final c = context.c;
    final id = GameIdentityScope.of(context);
    return Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.96),
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '恭喜通关！',
            style: context.heading(size: CitroType.subtitle, color: c.ink),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '用时 '),
                  TextSpan(
                    text: fmtDuration(seconds),
                    style: TextStyle(
                      color: id.primaryInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' · 步数 $moves · 得分 '),
                  TextSpan(
                    text: '$score',
                    style: TextStyle(
                      color: id.primaryInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: c.ink2),
            ),
          ),
          const SizedBox(height: 10),
          GameActionButton(label: '再来一局', primary: true, onTap: onRetry),
        ],
      ),
    );
  }
}

/// .gslide-diff：高度 33、bg2 底、line 描边、内部 31 高分段按钮
class _DiffTabs extends StatelessWidget {
  const _DiffTabs({required this.diff, this.onChanged});

  final String diff;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 33,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < GameSlideView._tabs.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  right: i == GameSlideView._tabs.length - 1 ? 0 : 6,
                ),
                child: _tab(context, GameSlideView._tabs[i]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, (String, String) item) {
    final c = context.c;
    final on = diff == item.$1;
    return GameHover(
      enabled: onChanged != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(item.$1),
        child: Container(
          height: 31,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? GameIdentityScope.of(context).primary : Colors.transparent,
            borderRadius: BorderRadius.circular(CitroColors.radii.button),
            border: Border.all(color: Colors.transparent),
          ),
          child: Text(
            item.$2,
            style: context.body(
              size: CitroType.caption,
              weight: CitroType.strong,
              color: on ? GameIdentityScope.of(context).onPrimary : c.ink2,
            ),
          ),
        ),
      ),
    );
  }
}
