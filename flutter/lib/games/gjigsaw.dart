import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'game_ui.dart';
import 'jigsaw_layouts.dart';

enum JigsawMode { easy, normal, hard }

extension JigsawModeX on JigsawMode {
  String get key => switch (this) {
    JigsawMode.easy => 'easy',
    JigsawMode.normal => 'normal',
    JigsawMode.hard => 'hard',
  };

  String get label => switch (this) {
    JigsawMode.easy => '简单',
    JigsawMode.normal => '普通',
    JigsawMode.hard => '困难',
  };

  int get n => switch (this) {
    JigsawMode.easy => 5,
    JigsawMode.normal => 6,
    JigsawMode.hard => 9,
  };
  int get holes => switch (this) {
    JigsawMode.easy => 8,
    JigsawMode.normal => 14,
    JigsawMode.hard => 45,
  };
  int get baseScore => switch (this) {
    JigsawMode.easy => 900,
    JigsawMode.normal => 1500,
    JigsawMode.hard => 2600,
  };
}

const _rankDiffs = [('easy', '简单'), ('normal', '普通'), ('hard', '困难')];

List<int> _baseSolution(int n) {
  if (n == 9) {
    return [
      for (var r = 0; r < 9; r++)
        for (var c = 0; c < 9; c++) (r * 3 + r ~/ 3 + c) % 9 + 1,
    ];
  }
  return [
    for (var r = 0; r < n; r++)
      for (var c = 0; c < n; c++) (r + c) % n + 1,
  ];
}

List<int> _decodeLayout(String seed) {
  final cells = <int>[];
  for (var i = 0; i < seed.length; i++) {
    final code = seed.codeUnitAt(i);
    if (code != 0x2F) cells.add(code - 0x30);
  }
  return cells;
}

List<int> _transformGrid(List<int> grid, int n, int turn) {
  final out = List<int>.filled(n * n, 0);
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final src = switch (turn) {
        1 => (n - 1 - c) * n + r,
        2 => (n - 1 - r) * n + (n - 1 - c),
        3 => c * n + (n - 1 - r),
        4 => r * n + (n - 1 - c),
        5 => (n - 1 - r) * n + c,
        6 => c * n + r,
        7 => (n - 1 - c) * n + (n - 1 - r),
        _ => r * n + c,
      };
      out[r * n + c] = grid[src];
    }
  }
  return out;
}

class _JigsawPuzzle {
  final int n;
  final List<int> regions;
  final List<int> solution;
  final List<int> puzzle;

  const _JigsawPuzzle({
    required this.n,
    required this.regions,
    required this.solution,
    required this.puzzle,
  });
}

class _JigsawGenerator {
  _JigsawGenerator(this.rnd);

  final math.Random rnd;
  String _lastLayout = '';

  _JigsawPuzzle next(JigsawMode mode) {
    final n = mode.n;
    final seeds = switch (mode) {
      JigsawMode.easy => jigsawFiveLayouts,
      JigsawMode.normal => jigsawSixLayouts,
      JigsawMode.hard => jigsawNineLayouts,
    };
    final baseSolution = _baseSolution(n);
    while (true) {
      final base = _decodeLayout(seeds[rnd.nextInt(seeds.length)]);
      final turn = rnd.nextInt(8);
      final regions = _transformGrid(base, n, turn);
      final layoutKey = '${mode.key}:${regions.join(',')}';
      if (layoutKey == _lastLayout) continue;
      final digits = List<int>.generate(n, (i) => i + 1)..shuffle(rnd);
      final solution = [
        for (final v in _transformGrid(baseSolution, n, turn)) digits[v - 1],
      ];
      final puzzle = List<int>.from(solution);
      final cells = List<int>.generate(n * n, (i) => i)..shuffle(rnd);
      for (var i = 0; i < mode.holes; i++) {
        puzzle[cells[i]] = 0;
      }
      _lastLayout = layoutKey;
      return _JigsawPuzzle(
        n: n,
        regions: regions,
        solution: solution,
        puzzle: puzzle,
      );
    }
  }
}

class GameJigsawPage extends StatefulWidget {
  const GameJigsawPage({super.key});

  @override
  State<GameJigsawPage> createState() => _GameJigsawPageState();
}

class _GameJigsawPageState extends State<GameJigsawPage> {
  final _progress = ValueNotifier<String>('');
  final _rnd = math.Random();
  late final _generator = _JigsawGenerator(_rnd);
  JigsawMode _mode = JigsawMode.easy;
  late _JigsawPuzzle _puzzle;
  late List<int> _board;
  late List<bool> _given;
  int _selected = -1;
  int _errors = 0;
  int _hints = 3;
  int _seconds = 0;
  bool _paused = false;
  bool _over = false;
  bool _submitted = false;
  Timer? _timer;
  late final FocusNode _focus = FocusNode(debugLabel: 'jigsaw');

  int get _n => _puzzle.n;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _newGame() {
    _timer?.cancel();
    _puzzle = _generator.next(_mode);
    _board = List<int>.from(_puzzle.puzzle);
    _given = [for (final v in _puzzle.puzzle) v != 0];
    _selected = -1;
    _errors = 0;
    _hints = 3;
    _seconds = 0;
    _paused = false;
    _over = false;
    _submitted = false;
    _syncProgress();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused || _over) return;
      setState(() => _seconds++);
      _syncProgress();
    });
    if (mounted) {
      setState(() {});
      if (_focus.canRequestFocus) _focus.requestFocus();
    }
  }

  void _syncProgress() {
    final filled = _board.where((v) => v != 0).length;
    final total = _board.length;
    _progress.value =
        '${_mode.label} · ${_fmtTime(_seconds)} · 已填 $filled/$total';
  }

  int _firstEmpty() {
    for (var i = 0; i < _board.length; i++) {
      if (_board[i] == 0) return i;
    }
    return -1;
  }

  bool _conflicts(int index, int value) {
    if (value == 0) return false;
    final n = _n;
    final r = index ~/ n, c = index % n;
    final region = _puzzle.regions[index];
    for (var i = 0; i < _board.length; i++) {
      if (i == index || _board[i] != value) continue;
      final ir = i ~/ n, ic = i % n;
      if (ir == r || ic == c || _puzzle.regions[i] == region) return true;
    }
    return false;
  }

  void _select(int index) {
    if (_paused || _over) return;
    setState(() => _selected = index);
  }

  void _input(int value) {
    if (_paused || _over || _selected < 0 || _given[_selected]) return;
    setState(() {
      _board[_selected] = value;
      if (_conflicts(_selected, value)) _errors++;
    });
    GameSfx.tap();
    _syncProgress();
    _checkWin();
  }

  void _erase() {
    if (_paused || _over || _selected < 0 || _given[_selected]) return;
    setState(() => _board[_selected] = 0);
    _syncProgress();
  }

  void _hint() {
    if (_paused || _over || _hints <= 0) return;
    var index = _selected;
    if (index < 0 || _given[index] || _board[index] != 0) {
      index = _firstEmpty();
    }
    if (index < 0) return;
    setState(() {
      _board[index] = _puzzle.solution[index];
      _given[index] = true;
      _hints--;
      _selected = index;
    });
    _syncProgress();
    _checkWin();
  }

  bool _isComplete() {
    if (_board.any((v) => v == 0)) return false;
    final n = _n;
    for (var r = 0; r < n; r++) {
      final seen = <int>{};
      for (var c = 0; c < n; c++) {
        if (!seen.add(_board[r * n + c])) return false;
      }
    }
    for (var c = 0; c < n; c++) {
      final seen = <int>{};
      for (var r = 0; r < n; r++) {
        if (!seen.add(_board[r * n + c])) return false;
      }
    }
    for (var k = 0; k < n; k++) {
      final seen = <int>{};
      for (var i = 0; i < _board.length; i++) {
        if (_puzzle.regions[i] == k && !seen.add(_board[i])) return false;
      }
    }
    return true;
  }

  void _checkWin() {
    if (_over || _submitted || !_isComplete()) return;
    _over = true;
    _submitted = true;
    _timer?.cancel();
    GameSfx.win();
    final score = math.max(
      10,
      _mode.baseScore - _seconds * 2 - _errors * 20 - (3 - _hints) * 15,
    );
    unawaited(_submit(score));
  }

  Future<void> _submit(int score) async {
    final res = await AppState.instance.submitScore(
      'jigsaw:${_mode.key}',
      score,
    );
    if (!mounted) return;
    final rank = res['rank'];
    await showCitroDialog<void>(
      context,
      builder: (ctx) => PaperDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('恭喜通关！', style: ctx.heading(size: 24)),
            const SizedBox(height: 8),
            Text(
              '${_mode.label} · 用时 ${_fmtTime(_seconds)} · 错误 $_errors 次',
              textAlign: TextAlign.center,
              style: ctx.body(size: 12, color: ctx.c.inkSoft, height: 1.6),
            ),
            if (rank is num && rank > 0) ...[
              const SizedBox(height: 4),
              Text(
                '排行榜第 $rank 名',
                style: ctx.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: ctx.c.accentInk,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GameActionButton(
                    label: '再来一局',
                    primary: true,
                    onTap: () {
                      Navigator.pop(ctx);
                      _newGame();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameActionButton(
                    label: '排行榜',
                    onTap: () {
                      Navigator.pop(ctx);
                      _openRank();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openRank() {
    showGameRank(
      context,
      game: 'jigsaw',
      title: '异形数独',
      difficulties: _rankDiffs,
      initial: _mode.key,
    );
  }

  void _changeMode(JigsawMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _newGame();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _erase();
      return KeyEventResult.handled;
    }
    final char = event.character;
    final value = int.tryParse(char ?? '');
    if (value != null && value >= 1 && value <= _n) {
      _input(value);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final screenW = MediaQuery.sizeOf(context).width;
    final boardW = screenW >= 900
        ? math.min(kIsWeb ? 500.0 : 520.0, screenW - GameMetrics.sidePad * 2)
        : math.min(screenW * 0.9, 470.0);
    return GameScaffold(
      gameKey: 'gjigsaw',
      title: '异形数独',
      rankGame: 'jigsaw',
      rankDifficulties: _rankDiffs,
      rankInitial: _mode.key,
      liveProgress: _progress,
      liveInScroll: true,
      above: [_ModeTabs(mode: _mode, onChanged: _changeMode)],
      pills: [
        GameScorePill(label: '用时', value: _fmtTime(_seconds)),
        GameScorePill(label: '错误', value: '$_errors'),
        GameScorePill(label: '提示', value: '$_hints'),
      ],
      actions: [
        GameActionButton(
          label: '提示',
          icon: GameIcons.lightbulb,
          enabled: _hints > 0 && !_over,
          onTap: _hint,
        ),
        GameActionButton(label: '重开', icon: GameIcons.refresh, onTap: _newGame),
        GameActionButton(
          label: '排行榜',
          icon: GameIcons.trophy,
          onTap: _openRank,
        ),
      ],
      board: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: boardW),
              child: _JigGrid(
                puzzle: _puzzle,
                board: _board,
                given: _given,
                selected: _selected,
                onSelect: _select,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: boardW),
              child: _NumberPad(n: _n, onInput: _input, onErase: _erase),
            ),
            const SizedBox(height: 8),
            Text(
              '每行、每列、每个粗线异形区域都填 1–$_n，且不重复',
              textAlign: TextAlign.center,
              style: context.body(size: 11, color: c.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _ModeTabs extends StatelessWidget {
  final JigsawMode mode;
  final ValueChanged<JigsawMode> onChanged;

  const _ModeTabs({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in JigsawMode.values) ...[
              if (m != JigsawMode.easy) const SizedBox(width: 4),
              Pressable(
                onTap: () => onChanged(m),
                borderRadius: BorderRadius.circular(999),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: m == mode ? c.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    m.label,
                    style: context.body(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: m == mode ? const Color(0xFF2E2C22) : c.ink2,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JigGrid extends StatelessWidget {
  final _JigsawPuzzle puzzle;
  final List<int> board;
  final List<bool> given;
  final int selected;
  final ValueChanged<int> onSelect;

  const _JigGrid({
    required this.puzzle,
    required this.board,
    required this.given,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, 520.0);
        final n = puzzle.n;
        final cell = side / n;
        final selectedRow = selected >= 0 ? selected ~/ n : -1;
        final selectedCol = selected >= 0 ? selected % n : -1;
        final selectedRegion = selected >= 0 ? puzzle.regions[selected] : -1;
        final selectedValue = selected >= 0 ? board[selected] : 0;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.line2),
                boxShadow: CitroColors.shadows.paper(c),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        for (var r = 0; r < n; r++)
                          SizedBox(
                            height: cell,
                            child: Row(
                              children: [
                                for (var col = 0; col < n; col++)
                                  SizedBox(
                                    width: cell,
                                    height: cell,
                                    child: _cell(
                                      context,
                                      r * n + col,
                                      r,
                                      col,
                                      selectedRow,
                                      selectedCol,
                                      selectedRegion,
                                      selectedValue,
                                      cell,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _JigBorderPainter(
                            regions: puzzle.regions,
                            n: n,
                            cell: cell,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cell(
    BuildContext context,
    int index,
    int r,
    int col,
    int selectedRow,
    int selectedCol,
    int selectedRegion,
    int selectedValue,
    double cell,
  ) {
    final c = context.c;
    final value = board[index];
    final isSelected = index == selected;
    final peer =
        selected >= 0 &&
        (r == selectedRow ||
            col == selectedCol ||
            puzzle.regions[index] == selectedRegion);
    final same = selected >= 0 && value != 0 && value == selectedValue;
    final conflict = value != 0 && _conflictIn(board, puzzle, index, value);
    var color = c.surface2;
    if (peer) color = c.mintSoft;
    if (same) {
      color = Color.alphaBlend(c.accent.withValues(alpha: .18), c.surface2);
    }
    if (isSelected) {
      color = Color.alphaBlend(c.accent.withValues(alpha: .26), c.surface2);
    }
    if (conflict) {
      color = Color.alphaBlend(
        c.stamp.withValues(alpha: isSelected ? .26 : .14),
        c.surface2,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(index),
      child: Container(
        width: cell,
        height: cell,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(
            color: c.inkSoft.withAlpha(c.dark ? 110 : 125),
            width: .8,
          ),
        ),
        foregroundDecoration: isSelected
            ? BoxDecoration(
                border: Border.all(
                  color: conflict ? c.stamp : c.accent,
                  width: 2,
                ),
              )
            : null,
        alignment: Alignment.center,
        child: value == 0
            ? null
            : Text(
                '$value',
                style: TextStyle(
                  fontFamily: AppFonts.kalam,
                  fontFamilyFallback: AppFonts.fallback,
                  fontSize: cell * .46,
                  height: 1.25,
                  fontWeight: FontWeight.w400,
                  color: conflict
                      ? c.stamp
                      : given[index]
                      ? c.ink
                      : c.accentInk,
                ),
              ),
      ),
    );
  }
}

bool _conflictIn(List<int> board, _JigsawPuzzle puzzle, int index, int value) {
  final n = puzzle.n;
  final r = index ~/ n, c = index % n;
  final region = puzzle.regions[index];
  for (var i = 0; i < board.length; i++) {
    if (i == index || board[i] != value) continue;
    if (i ~/ n == r || i % n == c || puzzle.regions[i] == region) {
      return true;
    }
  }
  return false;
}

class _JigBorderPainter extends CustomPainter {
  final List<int> regions;
  final int n;
  final double cell;
  final Color color;

  const _JigBorderPainter({
    required this.regions,
    required this.n,
    required this.cell,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final i = r * n + c;
        if (c == n - 1 || regions[i] != regions[i + 1]) {
          path.moveTo((c + 1) * cell, r * cell);
          path.lineTo((c + 1) * cell, (r + 1) * cell);
        }
        if (r == n - 1 || regions[i] != regions[i + n]) {
          path.moveTo(c * cell, (r + 1) * cell);
          path.lineTo((c + 1) * cell, (r + 1) * cell);
        }
      }
    }
    path.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        const Radius.circular(11),
      ),
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _JigBorderPainter old) =>
      old.color != color || old.regions != regions || old.cell != cell;
}

class _NumberPad extends StatelessWidget {
  final int n;
  final ValueChanged<int> onInput;
  final VoidCallback onErase;

  const _NumberPad({
    required this.n,
    required this.onInput,
    required this.onErase,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var v = 1; v <= n; v++)
          Pressable(
            onTap: () => onInput(v),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 44,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.line2),
                boxShadow: CitroColors.shadows.paper(c),
              ),
              child: Text(
                '$v',
                style: context.display(
                  size: 21,
                  weight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
            ),
          ),
        Pressable(
          onTap: onErase,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line2),
            ),
            child: gameIcon(GameIcons.eraser, size: 18, color: c.ink2),
          ),
        ),
      ],
    );
  }
}
