// 数织（Nonogram）页 —— 纸面网格，按内容区约束自适应。
// 版式：难度 / 填色模式分段器（GameSegTabs）→ HUD → 棋盘 → 操作行 → 正在玩。
// cell 由内容宽算出并夹在 32–72：手机竖屏 15 阶会超出内容区，
// 由 InteractiveViewer 提供双指缩放 + 拖动；横屏 / 平板 / 桌面自动放大。
// 配色只来自 GameIdentity：格线 identity.soft 低透明、填色格 identity.primary、
// 标记叉 identity.deep、提示数字 identity.primaryInk（完成行划线 + 降饱和）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/browser_effects.dart';
import 'game_identity.dart';
import 'game_ui.dart';

class GameNonoPage extends StatefulWidget {
  const GameNonoPage({super.key});

  @override
  State<GameNonoPage> createState() => _GameNonoPageState();
}

class _GameNonoPageState extends State<GameNonoPage> {
  static const _diffs = {
    'easy': ('简单 5×5', 5, 1800),
    'std': ('标准 10×10', 10, 3600),
    'hard': ('困难 15×15', 15, 7200),
  };

  String diff = 'std';
  int size = 10;
  List<List<int>> solution = [];
  List<List<int>> grid = [];
  List<List<int>> marks = [];
  List<List<int>> rowHints = [];
  List<List<int>> colHints = [];
  int seconds = 0;
  bool over = false;
  bool submitted = false;
  Timer? timer;
  final _progress = ValueNotifier<String>('');

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
    super.dispose();
  }

  void _newGame() {
    timer?.cancel();
    size = _meta.$2;
    final rnd = math.Random();
    solution = List.generate(
      size,
      (_) => List.generate(size, (_) => rnd.nextDouble() < .45 ? 1 : 0),
    );
    // 避免空题
    if (solution.every((row) => row.every((v) => v == 0))) solution[1][1] = 1;
    grid = List.generate(size, (_) => List.filled(size, 0));
    marks = List.generate(size, (_) => List.filled(size, 0));
    rowHints = [for (var r = 0; r < size; r++) _hints(solution[r])];
    colHints = [
      for (var c = 0; c < size; c++)
        _hints([for (var r = 0; r < size; r++) solution[r][c]]),
    ];
    seconds = 0;
    over = false;
    submitted = false;
    _startTimer();
    _progress.value = '${_meta.$1} · 用时 0:00';
    setState(() {});
  }

  List<int> _hints(List<int> line) {
    final out = <int>[];
    var run = 0;
    for (final v in line) {
      if (v == 1) {
        run++;
      } else if (run > 0) {
        out.add(run);
        run = 0;
      }
    }
    if (run > 0) out.add(run);
    return out.isEmpty ? [0] : out;
  }

  void _startTimer() {
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || over) return;
      setState(() => seconds++);
      _progress.value = '${_meta.$1} · 用时 ${gameFmtDuration(seconds)}';
    });
  }

  void _tap(int r, int c) {
    if (over) return;
    setState(() {
      grid[r][c] = grid[r][c] == 1 ? 0 : 1;
      if (grid[r][c] == 1) marks[r][c] = 0;
    });
    GameSfx.move();
    _checkWin();
  }

  void _mark(int r, int c) {
    if (over) return;
    setState(() {
      marks[r][c] = marks[r][c] == 1 ? 0 : 1;
      if (marks[r][c] == 1) grid[r][c] = 0;
    });
    GameSfx.tap();
  }

  void _checkWin() {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (grid[r][c] != solution[r][c]) return;
      }
    }
    over = true;
    timer?.cancel();
    GameSfx.win();
    final score = math.max(1, _meta.$3 - seconds);
    context.app.saveLocalBest('nono:$diff', score);
    if (!submitted) {
      submitted = true;
      context.app.submitScore('nono:$diff', score);
    }
    setState(() {});
  }

  void _changeDiff(String key) {
    if (diff == key) return;
    setState(() => diff = key);
    _newGame();
  }

  void _openRank() {
    showGameRank(
      context,
      game: 'nono',
      title: '数织',
      difficulties: const [('easy', '简单'), ('std', '标准'), ('hard', '困难')],
      initial: diff,
    );
  }

  bool _lineDone(List<int> cells, List<int> hints) {
    final filled = [for (final v in cells) v == 1 ? 1 : 0];
    final runs = _hints(filled);
    if (runs.length != hints.length) return false;
    for (var i = 0; i < runs.length; i++) {
      if (runs[i] != hints[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bestScore = context.app.localBest('nono:$diff');
    final bestSecs = bestScore > 0 ? math.max(1, _meta.$3 - bestScore) : 0;
    final rowDone = [
      for (var r = 0; r < size; r++) _lineDone(grid[r], rowHints[r]),
    ];
    final colDone = [
      for (var c = 0; c < size; c++)
        _lineDone([for (var r = 0; r < size; r++) grid[r][c]], colHints[c]),
    ];
    return GameNonoView(
      diff: diff,
      size: size,
      grid: grid,
      marks: marks,
      rowHints: rowHints,
      colHints: colHints,
      rowDone: rowDone,
      colDone: colDone,
      seconds: seconds,
      bestSeconds: bestSecs,
      over: over,
      score: math.max(1, _meta.$3 - seconds),
      liveProgress: _progress,
      onDiff: _changeDiff,
      onNew: _newGame,
      onRank: _openRank,
      onTap: _tap,
      onMark: _mark,
      onRetry: _newGame,
    );
  }
}

/// 纯视觉层 —— 可在 golden 测试中用固定数据渲染。
///
/// 「填色 / 标记」是视图层的输入模式（[onTap] 路由到填色或标记），
/// 页面状态机与长按标记手势都不变；默认仍是填色。
class GameNonoView extends StatefulWidget {
  const GameNonoView({
    super.key,
    this.diff = 'std',
    this.size = 10,
    this.grid = const [],
    this.marks = const [],
    this.rowHints = const [],
    this.colHints = const [],
    this.rowDone = const [],
    this.colDone = const [],
    this.seconds = 0,
    this.bestSeconds = 0,
    this.over = false,
    this.score = 0,
    this.liveProgress,
    this.onDiff,
    this.onNew,
    this.onRank,
    this.onTap,
    this.onMark,
    this.onRetry,
  });

  final String diff;
  final int size;
  final List<List<int>> grid;
  final List<List<int>> marks;
  final List<List<int>> rowHints;
  final List<List<int>> colHints;
  final List<bool> rowDone;
  final List<bool> colDone;
  final int seconds;
  final int bestSeconds;
  final bool over;
  final int score;
  final ValueNotifier<String>? liveProgress;
  final ValueChanged<String>? onDiff;
  final VoidCallback? onNew;
  final VoidCallback? onRank;
  final void Function(int r, int c)? onTap;
  final void Function(int r, int c)? onMark;
  final VoidCallback? onRetry;

  @override
  State<GameNonoView> createState() => _GameNonoViewState();
}

class _GameNonoViewState extends State<GameNonoView> {
  bool _markMode = false;

  void _handleTap(int r, int c) {
    if (_markMode) {
      widget.onMark?.call(r, c);
    } else {
      widget.onTap?.call(r, c);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameKey: 'gnono',
      title: '数织',
      liveProgress: widget.liveProgress,
      rankDifficulties: const [('easy', '简单'), ('std', '标准'), ('hard', '困难')],
      rankInitial: widget.diff,
      above: [
        GameSegTabs<String>(
          items: const [
            ('easy', '简单 5×5'),
            ('std', '标准 10×10'),
            ('hard', '困难 15×15'),
          ],
          value: widget.diff,
          onChanged: (v) => widget.onDiff?.call(v),
        ),
        GameSegTabs<String>(
          items: const [('fill', '填色'), ('mark', '标记')],
          value: _markMode ? 'mark' : 'fill',
          onChanged: (v) => setState(() => _markMode = v == 'mark'),
          dense: true,
        ),
      ],
      pills: [
        GameScorePill(label: '用时', value: gameFmtDuration(widget.seconds)),
        GameScorePill(
          label: '最佳',
          value: widget.bestSeconds > 0
              ? gameFmtDuration(widget.bestSeconds)
              : '--',
        ),
      ],
      actions: [
        GameActionButton(
          label: '新游戏',
          icon: GameIcons.refresh,
          primary: true,
          onTap: widget.onNew,
        ),
        GameRankAction(
          child: GameActionButton(
            label: '排行榜',
            icon: GameIcons.trophy,
            onTap: widget.onRank,
          ),
        ),
      ],
      board: _NonoBoard(
        size: widget.size,
        grid: widget.grid,
        marks: widget.marks,
        rowHints: widget.rowHints,
        colHints: widget.colHints,
        rowDone: widget.rowDone,
        colDone: widget.colDone,
        over: widget.over,
        seconds: widget.seconds,
        score: widget.score,
        onTap: _handleTap,
        onMark: widget.onMark,
        onRetry: widget.onRetry,
      ),
    );
  }
}

/// 棋盘：纸卡画框 + 行/列提示 + 可缩放网格。
///
/// cell 只吃内容区宽度（[LayoutBuilder]），夹在 32–72 之间：手机竖屏
/// 15 阶算出的 cell 会小于 32，夹到 32 后棋盘宽于内容区，由
/// [InteractiveViewer] 提供双指缩放 + 拖动；横屏 / 平板 / 桌面按剩余
/// 宽度自动放大，不再读 MediaQuery。
class _NonoBoard extends StatefulWidget {
  const _NonoBoard({
    required this.size,
    required this.grid,
    required this.marks,
    required this.rowHints,
    required this.colHints,
    required this.rowDone,
    required this.colDone,
    this.over = false,
    this.seconds = 0,
    this.score = 0,
    this.onTap,
    this.onMark,
    this.onRetry,
  });

  final int size;
  final List<List<int>> grid;
  final List<List<int>> marks;
  final List<List<int>> rowHints;
  final List<List<int>> colHints;
  final List<bool> rowDone;
  final List<bool> colDone;
  final bool over;
  final int seconds;
  final int score;
  final void Function(int r, int c)? onTap;
  final void Function(int r, int c)? onMark;
  final VoidCallback? onRetry;

  @override
  State<_NonoBoard> createState() => _NonoBoardState();
}

class _NonoBoardState extends State<_NonoBoard> {
  static const double _pad = 8;
  static const double _gap = 2;
  // RoundedCN 700 的数字步进是 0.589em（13px 下 7.66px），留 0.84px 余量。
  static const double _hintDigitW = 8.5;
  static const double _hintGap = 3;
  static const double _hintPad = 6;
  static const double _hintLineH = 13;
  static const double _minCell = 32;
  static const double _maxCell = 72;

  final TransformationController _viewer = TransformationController();
  bool _interacted = false;
  double? _fitScale;
  Offset? _fitOffset;

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _NonoBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换难度 / 重开题面会改变提示宽度与棋盘尺寸，重置缩放让初始适配重新生效。
    if (oldWidget.size != widget.size ||
        !identical(oldWidget.rowHints, widget.rowHints) ||
        !identical(oldWidget.colHints, widget.colHints)) {
      _interacted = false;
      _fitScale = null;
      _fitOffset = null;
    }
  }

  int get _maxRowHints {
    var m = 1;
    for (final h in widget.rowHints) m = math.max(m, h.length);
    return m;
  }

  int get _maxColHints {
    var m = 1;
    for (final h in widget.colHints) m = math.max(m, h.length);
    return m;
  }

  double get _hintColW =>
      _maxRowHints * _hintDigitW + (_maxRowHints - 1) * _hintGap + _hintPad;

  double get _hintRowH =>
      _maxColHints * _hintLineH + (_maxColHints - 1) * 2 + _hintPad;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final availW = cons.maxWidth.isFinite && cons.maxWidth > 0
            ? cons.maxWidth
            : 360.0;
        final hintColW = _hintColW;
        final hintRowH = _hintRowH;
        final cell =
            ((availW - 2 * _pad - hintColW - widget.size * _gap) / widget.size)
                .clamp(_minCell, _maxCell);
        final boardW = 2 * _pad + hintColW + widget.size * (cell + _gap);
        final boardH = 2 * _pad + hintRowH + widget.size * (cell + _gap);
        // 高度约束在共享骨架里是未定的（棋盘区可滚动），退化成方形视口，
        // 保证双向都能拖动；有界时用真实视口高。
        final viewportW = availW;
        final viewportH = cons.maxHeight.isFinite && cons.maxHeight > 0
            ? cons.maxHeight
            : availW;
        final board = _buildBoard(
          context,
          cell,
          hintColW,
          hintRowH,
          boardW,
          boardH,
        );
        final fits = boardW <= viewportW && boardH <= viewportH;
        if (fits) return Center(child: board);
        // 初始缩放到整盘可见并居中；用户可再双指缩放 / 拖动。
        final scale = math.min(
          1.0,
          math.min(viewportW / boardW, viewportH / boardH),
        );
        final offset = Offset(
          (viewportW - boardW * scale) / 2,
          (viewportH - boardH * scale) / 2,
        );
        if (!_interacted && (_fitScale != scale || _fitOffset != offset)) {
          _fitScale = scale;
          _fitOffset = offset;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _viewer.value = Matrix4.identity()
              ..translate(offset.dx, offset.dy)
              ..scale(scale);
          });
        }
        return SizedBox(
          width: viewportW,
          height: viewportH,
          child: InteractiveViewer(
            transformationController: _viewer,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.25,
            maxScale: 4,
            onInteractionStart: (_) => _interacted = true,
            child: board,
          ),
        );
      },
    );
  }

  Widget _buildBoard(
    BuildContext context,
    double cell,
    double hintColW,
    double hintRowH,
    double boardW,
    double boardH,
  ) {
    final c = context.c;
    final id = GameIdentityScope.of(context);
    // 深色主题下不能继续用固定纸白：整块棋盘会变成刺眼的亮岛。
    // 用深卡面混一点身份色做主纸面，提示、叉号再按主题换墨色。
    final paper = c.dark
        ? Color.alphaBlend(id.primary.withValues(alpha: .10), c.surface2)
        : GameIdentity.paper;
    return SizedBox(
      width: boardW,
      height: boardH,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(CitroColors.radii.card),
                border: Border.all(
                  color: (c.dark ? id.primary : id.deep).withAlpha(80),
                ),
                boxShadow: CitroColors.shadows.card(c),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(_pad),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // 格线：身份色浅端低透明，只暗示网格，不抢格面。
                  color: id.soft.withAlpha(c.dark ? 60 : 120),
                  borderRadius: BorderRadius.circular(CitroColors.radii.small),
                ),
                child: _grid(cell, hintColW, hintRowH, paper),
              ),
            ),
          ),
          if (widget.over)
            Positioned.fill(
              child: _NonoOverlay(
                seconds: widget.seconds,
                score: widget.score,
                onRetry: widget.onRetry,
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(
    double cell,
    double hintColW,
    double hintRowH,
    Color paper,
  ) {
    // 纸面谜题：空格与提示区铺同一张纸，格线由 2px 间隙里的
    // identity.soft 低透明透出来；浅色用固定纸白，深色用深卡面。
    final gap = const SizedBox(width: _gap, height: _gap);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 列提示行
        SizedBox(
          height: hintRowH,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: hintColW, height: hintRowH, color: paper),
              for (var col = 0; col < widget.size; col++) ...[
                gap,
                Container(
                  width: cell,
                  color: paper,
                  child: _ColHint(
                    hints: widget.colHints.length > col
                        ? widget.colHints[col]
                        : const [0],
                    done: widget.colDone.length > col && widget.colDone[col],
                  ),
                ),
              ],
            ],
          ),
        ),
        // 每行：行提示 + 格子
        for (var r = 0; r < widget.size; r++) ...[
          const SizedBox(height: _gap),
          SizedBox(
            height: cell,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: hintColW,
                  height: cell,
                  color: paper,
                  child: _RowHint(
                    hints: widget.rowHints.length > r
                        ? widget.rowHints[r]
                        : const [0],
                    done: widget.rowDone.length > r && widget.rowDone[r],
                  ),
                ),
                for (var col = 0; col < widget.size; col++) ...[
                  gap,
                  _NonoCell(
                    size: cell,
                    filled:
                        widget.grid.length > r &&
                        widget.grid[r].length > col &&
                        widget.grid[r][col] == 1,
                    marked:
                        widget.marks.length > r &&
                        widget.marks[r].length > col &&
                        widget.marks[r][col] == 1,
                    emptyCell: paper,
                    onTap: () => widget.onTap?.call(r, col),
                    onLongPress: () => widget.onMark?.call(r, col),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RowHint extends StatelessWidget {
  const _RowHint({required this.hints, required this.done});

  final List<int> hints;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final c = context.c;
    // 深色纸面用提亮身份色；完成行再用弱墨，避免深绿线压在深底上。
    final hintInk = c.dark
        ? Color.lerp(c.ink, id.primary, .18)!
        : id.primaryInk;
    final doneInk = c.dark ? c.inkSoft : id.deep;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: FittedBox(
        // 提示值可能是两位数，按「一位数」预算的列宽会不够；
        // scaleDown 让整行缩一点，而不是溢出到第一格上。
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          for (var i = 0; i < hints.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Text(
              '${hints[i]}',
              style: context
                  .body(
                    size: CitroType.meta,
                    weight: CitroType.strong,
                    // 完成行：划线 + 降饱和的深色，不用低对比的浅色。
                    color: done ? doneInk : hintInk,
                  )
                  .copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: doneInk,
                    decorationThickness: 1.5,
                  ),
            ),
          ],
        ],
        ),
      ),
    );
  }
}

class _ColHint extends StatelessWidget {
  const _ColHint({required this.hints, required this.done});

  final List<int> hints;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final c = context.c;
    final hintInk = c.dark
        ? Color.lerp(c.ink, id.primary, .18)!
        : id.primaryInk;
    final doneInk = c.dark ? c.inkSoft : id.deep;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < hints.length; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            Text(
              '${hints[i]}',
              style: context
                  .body(
                    size: CitroType.meta,
                    weight: CitroType.strong,
                    height: 1,
                    color: done ? doneInk : hintInk,
                  )
                  .copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: doneInk,
                    decorationThickness: 1.5,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NonoCell extends StatelessWidget {
  const _NonoCell({
    required this.size,
    required this.filled,
    required this.marked,
    required this.emptyCell,
    this.onTap,
    this.onLongPress,
  });

  final double size;
  final bool filled;
  final bool marked;
  final Color emptyCell;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? id.primary : emptyCell,
          borderRadius: BorderRadius.circular(CitroColors.radii.xs),
          border: filled
              ? Border.all(color: id.deep.withAlpha(140), width: 1)
              : null,
        ),
        child: marked
            ? Center(
                child: Text(
                  '×',
                  style: context.body(
                    size: (size * 0.42).clamp(14.0, 26.0),
                    weight: CitroType.strong,
                    color: c.dark ? Color.lerp(c.ink, id.primary, .18) : id.deep,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _NonoOverlay extends StatelessWidget {
  const _NonoOverlay({
    required this.seconds,
    required this.score,
    this.onRetry,
  });

  final int seconds;
  final int score;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final id = GameIdentityScope.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(CitroColors.radii.card),
      child: CitroBackdropBlur(
        sigma: 6,
        child: Container(
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: 0.96),
            border: Border.all(color: id.deep.withAlpha(80)),
            borderRadius: BorderRadius.circular(CitroColors.radii.card),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '恭喜完成！',
                style: context.heading(
                  size: CitroType.heading,
                  color: c.dark ? id.onDark() : id.primaryInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '用时 ${gameFmtDuration(seconds)} · 得分 $score',
                style: context.body(size: CitroType.meta, color: c.ink2),
              ),
              const SizedBox(height: 10),
              _NonoRetryButton(onTap: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

class _NonoRetryButton extends StatelessWidget {
  const _NonoRetryButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GameActionButton(label: '再来一局', primary: true, onTap: onTap);
  }
}
