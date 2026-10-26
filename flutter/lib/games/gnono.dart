// 数织（Nonogram）页 —— 像素级复刻 web 版 #gnonoPage（390×844 light）。
// 视觉基准：_tmp/ref/games/gnono-m-l.png
// web 结构来源：index.html `#gnonoPage`（h1 → gnono-hud → g-hud → gnono-wrap →
// gnono-board → gnono-overlay → g-live）与 styles/citro-games.css 第 10 节。
// 移动端实测（390 宽）：h1 顶 129.2；难度条 50..340 × 184..217（290×33，
// 三个 82/97/97 药丸、gap6、选中 accent）；HUD 行 56.64 高（2 个 62 宽 pill +
// 2 个 103.73×56.64 按钮）；棋盘 382×402 @ (6,315)：border1 #D2C8B0、bg #E4DCC9、
// radius14、inset 阴影；内部 padding6 + gap2，行提示列 48、列提示行 68、格子 30。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../widgets/browser_effects.dart';
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
class GameNonoView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GameScaffold(
      gameKey: 'gnono',
      title: '数织',
      liveProgress: liveProgress,
      rankDifficulties: const [('easy', '简单'), ('std', '标准'), ('hard', '困难')],
      rankInitial: diff,
      hud: _NonoHud(
        diff: diff,
        seconds: seconds,
        bestSeconds: bestSeconds,
        onDiff: onDiff,
        onNew: onNew,
        onRank: onRank,
      ),
      board: _NonoBoard(
        size: size,
        grid: grid,
        marks: marks,
        rowHints: rowHints,
        colHints: colHints,
        rowDone: rowDone,
        colDone: colDone,
        over: over,
        seconds: seconds,
        score: score,
        onTap: onTap,
        onMark: onMark,
        onRetry: onRetry,
      ),
    );
  }
}

/// HUD：4 + 难度条 33 + 12 + 56.64 单行 + 12（与 web 竖向链条一致）。
class _NonoHud extends StatelessWidget {
  const _NonoHud({
    required this.diff,
    required this.seconds,
    required this.bestSeconds,
    this.onDiff,
    this.onNew,
    this.onRank,
  });

  final String diff;
  final int seconds;
  final int bestSeconds;
  final ValueChanged<String>? onDiff;
  final VoidCallback? onNew;
  final VoidCallback? onRank;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        _NonoTabs(value: diff, onChanged: onDiff),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 9,
          runSpacing: 8,
          children: [
            GameScorePill(label: '用时', value: gameFmtDuration(seconds)),
            GameScorePill(
              label: '最佳',
              value: bestSeconds > 0 ? gameFmtDuration(bestSeconds) : '--',
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NonoButton(
                  label: '新游戏',
                  icon: GameIcons.refresh,
                  primary: true,
                  onTap: onNew,
                ),
                const SizedBox(width: 8),
                _NonoButton(
                  label: '排行榜',
                  icon: GameIcons.trophy,
                  onTap: onRank,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 11.4),
      ],
    );
  }
}

/// 难度分段器（web .gnono-diff：290×33、bg #DFD7C4、border #E4DCC9、
/// gap6、三个按钮 82/97/97、选中 accent）。
class _NonoTabs extends StatelessWidget {
  const _NonoTabs({required this.value, this.onChanged});

  static const _items = [
    ('easy', '简单 5×5', 82.0),
    ('std', '标准 10×10', 97.0),
    ('hard', '困难 15×15', 97.0),
  ];

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _tab(context, c, _items[i]),
          ],
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    CitroColors c,
    (String, String, double) it,
  ) {
    final on = it.$1 == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged?.call(it.$1),
      child: Container(
        width: it.$3,
        height: 31,
        alignment: Alignment.center,
        decoration: on
            ? BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(999),
              )
            : null,
        child: Text(
          it.$2,
          style: TextStyle(
            fontFamily: AppFonts.noto,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: on ? const Color(0xFF2E2C22) : const Color(0xFF4E4A40),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

/// 单行 HUD 里的拉伸按钮（web .g-actions stretch → 103.73×56.64）。
class _NonoButton extends StatelessWidget {
  const _NonoButton({
    required this.label,
    required this.icon,
    this.primary = false,
    this.onTap,
  });

  final String label;
  final String icon;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = primary ? const Color(0xFF3B2A10) : c.ink2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CssShadowLayer(
        radius: 999,
        shadows: primary
            ? const [
                CssShadowSpec(
                  color: Color(0xA694530A),
                  offset: Offset(0, 11),
                  blur: 22,
                  spread: -12,
                ),
              ]
            : const [
                CssShadowSpec(
                  color: Color(0x803C301A),
                  offset: Offset(0, 4),
                  blur: 12,
                  spread: -8,
                ),
              ],
        child: SizedBox(
          width: 103.73,
          height: 56.64,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: primary
                  ? null
                  : (c.dark ? c.surface2 : const Color(0xB8FFFCF4)),
              gradient: primary
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF9C98C), Color(0xFFF0A85C)],
                    )
                  : null,
              border: Border.all(
                color: primary
                    ? const Color(0x2E94530A)
                    : (c.dark ? c.line2 : const Color(0x294A3A22)),
              ),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  gameIcon(icon, size: 15, color: fg),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .26,
                      color: fg,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 棋盘：382×402 的米黄画框 + 行/列提示 + 30×30 白格。
class _NonoBoard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = context.c;
    final media = MediaQuery.sizeOf(context);
    final tablet = media.width >= 900;
    final duoPortrait =
        CitroForm.duoInner(media) && media.height >= media.width;
    final cell = size == 5
        ? (tablet
              ? 64.0
              : duoPortrait
              ? 58.0
              : 48.0)
        : size == 10
        ? (tablet
              ? 48.0
              : duoPortrait
              ? 38.0
              : 30.0)
        : (tablet
              ? 30.0
              : duoPortrait
              ? 23.0
              : 18.0);
    var maxRowHints = 1;
    for (final h in rowHints) {
      maxRowHints = math.max(maxRowHints, h.length);
    }
    var maxColHints = 1;
    for (final h in colHints) {
      maxColHints = math.max(maxColHints, h.length);
    }
    final hintColW = maxRowHints * 6.0 + (maxRowHints - 1) * 3.0 + 6.0;
    final hintRowH = maxColHints * 10.0 + (maxColHints - 1) * 3.0 + 6.0;
    final boardW = 14.0 + hintColW + size * cell + size * 2.0;
    final boardH = 14.0 + hintRowH + size * cell + size * 2.0;

    return SizedBox(
      width: double.infinity,
      height: boardH,
      child: OverflowBox(
        minWidth: boardW,
        maxWidth: boardW,
        minHeight: boardH,
        maxHeight: boardH,
        alignment: Alignment.center,
        child: Transform.translate(
          offset: const Offset(2, 0),
          child: SizedBox(
            width: boardW,
            height: boardH,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.line,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.line2),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: CustomPaint(painter: _NonoInsetShadowPainter()),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: _grid(context, c, cell, hintColW, hintRowH),
                  ),
                ),
                if (over)
                  Positioned.fill(
                    child: _NonoOverlay(
                      seconds: seconds,
                      score: score,
                      onRetry: onRetry,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    CitroColors c,
    double cell,
    double hintColW,
    double hintRowH,
  ) {
    final gap = SizedBox(width: 2, height: 2);
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
              SizedBox(width: hintColW, height: hintRowH),
              for (var col = 0; col < size; col++) ...[
                gap,
                SizedBox(
                  width: cell,
                  child: _ColHint(
                    hints: colHints.length > col ? colHints[col] : const [0],
                    done: colDone.length > col && colDone[col],
                  ),
                ),
              ],
            ],
          ),
        ),
        // 每行：行提示 + 格子
        for (var r = 0; r < size; r++) ...[
          SizedBox(height: 2),
          SizedBox(
            height: cell,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: hintColW,
                  child: _RowHint(
                    hints: rowHints.length > r ? rowHints[r] : const [0],
                    done: rowDone.length > r && rowDone[r],
                  ),
                ),
                for (var col = 0; col < size; col++) ...[
                  gap,
                  _NonoCell(
                    size: cell,
                    filled:
                        grid.length > r &&
                        grid[r].length > col &&
                        grid[r][col] == 1,
                    marked:
                        marks.length > r &&
                        marks[r].length > col &&
                        marks[r][col] == 1,
                    onTap: () => onTap?.call(r, col),
                    onLongPress: () => onMark?.call(r, col),
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
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < hints.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Text(
                '${hints[i]}',
                style: TextStyle(
                  fontFamily: AppFonts.noto,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: done ? const Color(0x38F4F1ED) : c.mintInk,
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
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < hints.length; i++) ...[
            if (i > 0) const SizedBox(height: 3),
            Text(
              '${hints[i]}',
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1,
                color: done ? const Color(0x38F4F1ED) : c.mintInk,
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
    this.onTap,
    this.onLongPress,
  });

  final double size;
  final bool filled;
  final bool marked;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(3),
        ),
        child: marked
            ? Center(
                child: Text(
                  '×',
                  style: TextStyle(
                    fontFamily: AppFonts.noto,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: c.inkSoft,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// CSS `inset 0 2px 6px rgba(90,74,44,.09)` 的近似：在内边缘画一圈模糊描边。
class _NonoInsetShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 3, size.width - 2, size.height - 2),
      const Radius.circular(12),
    );
    canvas.save();
    canvas.clipRRect(inner);
    final paint = Paint()
      ..color = const Color(0x155A4A2C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawRRect(inner, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NonoInsetShadowPainter oldDelegate) => false;
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CitroBackdropBlur(
        sigma: 6,
        child: Container(
          decoration: BoxDecoration(
            color: c.dark ? c.surface.withAlpha(0xF0) : const Color(0xF0FBF7EC),
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '恭喜完成！',
                style: TextStyle(
                  fontFamily: AppFonts.zcool,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.68,
                  color: c.mintInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '用时 ${gameFmtDuration(seconds)} · 得分 $score',
                style: TextStyle(
                  fontFamily: AppFonts.noto,
                  fontSize: 13,
                  color: c.ink2,
                  height: 1.7,
                ),
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
    const fg = Color(0xFF3B2A10);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CssShadowLayer(
        radius: 999,
        shadows: const [
          CssShadowSpec(
            color: Color(0xA694530A),
            offset: Offset(0, 11),
            blur: 22,
            spread: -12,
          ),
        ],
        child: SizedBox(
          height: 42,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF9C98C), Color(0xFFF0A85C)],
              ),
              border: Border.all(color: const Color(0x2E94530A)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              // widthFactor:1 —— 没有它 Center 会撑满浮层宽度，
              // 按钮被拉成整条棋盘宽（web 是 inline-flex 内容自适应）。
              child: Center(
                widthFactor: 1,
                child: Text(
                  '再来一局',
                  style: TextStyle(
                    fontFamily: AppFonts.noto,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .26,
                    color: fg,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
