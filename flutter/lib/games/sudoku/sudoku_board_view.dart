import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'sudoku_modes.dart';
import 'sudoku_puzzle.dart';

/// 子盘/选中盘配色：重叠、风车模式切换盘时使用。
List<Color> sudokuSubgridPalette(CitroColors c) => [
  c.accent,
  c.mintInk,
  c.accent2,
  c.stamp,
  c.accentInk,
];

/// 杀手笼的图着色：返回每个笼的颜色下标，保证上下左右相邻的笼不同色。
///
/// 笼子把 9×9 网格切成若干区域，邻接图是平面的，六色回溯一定能在
/// 限制内找到解；极端情况下退回贪心并允许下标超出 [colorCount]，
/// 由调用方扩展色板。
List<int> killerCageColorIndices(SudokuPuzzle puzzle, int colorCount) {
  final cages = puzzle.cages;
  final n = cages.length;
  if (n == 0 || colorCount <= 0) return List<int>.filled(n, 0);
  final rows = puzzle.rows;
  final cols = puzzle.cols;
  final owner = List<int>.filled(rows * cols, -1);
  for (var ci = 0; ci < n; ci++) {
    for (final i in cages[ci].cells) {
      if (i >= 0 && i < owner.length) owner[i] = ci;
    }
  }
  final adj = List<Set<int>>.generate(n, (_) => <int>{});
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final i = r * cols + c;
      final a = owner[i];
      if (a < 0) continue;
      if (c + 1 < cols) {
        final b = owner[i + 1];
        if (b >= 0 && b != a) {
          adj[a].add(b);
          adj[b].add(a);
        }
      }
      if (r + 1 < rows) {
        final b = owner[i + cols];
        if (b >= 0 && b != a) {
          adj[a].add(b);
          adj[b].add(a);
        }
      }
    }
  }
  final assigned = List<int>.filled(n, -1);
  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) => adj[b].length.compareTo(adj[a].length));
  var steps = 0;
  bool solve(int k) {
    if (k >= order.length) return true;
    final ci = order[k];
    final used = <int>{};
    for (final nb in adj[ci]) {
      if (assigned[nb] >= 0) used.add(assigned[nb]);
    }
    for (var color = 0; color < colorCount; color++) {
      if (used.contains(color)) continue;
      assigned[ci] = color;
      if (solve(k + 1)) return true;
      assigned[ci] = -1;
      if (++steps > 200000) return false;
    }
    return false;
  }

  if (!solve(0)) {
    assigned.fillRange(0, n, -1);
    for (var ci = 0; ci < n; ci++) {
      final used = <int>{
        for (final nb in adj[ci])
          if (assigned[nb] >= 0) assigned[nb],
      };
      var color = 0;
      while (used.contains(color)) {
        color++;
      }
      assigned[ci] = color;
    }
  }
  return assigned;
}

/// 通用数独棋盘：经典 / 异形 / 雪花 / 重叠 / 奇偶 / 对角 / 不等式 / 杀手 / 3D。
///
/// 用一块 CustomPaint 绘制，避免 13 重（33×33）时创建上千个 Widget。
/// 重叠盘由调用方传 interactive=true，允许双指放大/拖动。
class SudokuBoardView extends StatelessWidget {
  const SudokuBoardView({
    super.key,
    required this.puzzle,
    required this.board,
    required this.notes,
    required this.conflicts,
    required this.selected,
    required this.layer,
    required this.revision,
    this.focusGrid = -1,
    this.onSelect,
    this.maxSide = 500,
    this.interactive = false,
    this.paused = false,
    this.over = false,
  });

  final SudokuPuzzle puzzle;
  final List<int> board;
  final List<Set<int>> notes;
  final Set<int> conflicts;
  final int selected;
  final int layer;
  final int revision;
  final int focusGrid;
  final ValueChanged<int>? onSelect;
  final double maxSide;
  final bool interactive;
  final bool paused;
  final bool over;

  bool _active(int index) =>
      index >= 0 && index < puzzle.active.length ? puzzle.active[index] : true;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxSide;
        final side = math.min(available, maxSide);
        final cell = side / puzzle.cols;
        final height = cell * puzzle.rows;
        final boardWidget = SizedBox(
          width: side,
          height: height,
          child: RepaintBoundary(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: onSelect == null
                  ? null
                  : (details) {
                      final dx = details.localPosition.dx;
                      final dy = details.localPosition.dy;
                      final col = (dx / cell).floor();
                      final row = (dy / cell).floor();
                      if (row < 0 ||
                          row >= puzzle.rows ||
                          col < 0 ||
                          col >= puzzle.cols) {
                        return;
                      }
                      final index =
                          layer * puzzle.rows * puzzle.cols +
                          row * puzzle.cols +
                          col;
                      if (!_active(index)) return;
                      onSelect!(index);
                    },
              child: CustomPaint(
                painter: _SudokuBoardPainter(
                  puzzle: puzzle,
                  board: board,
                  notes: notes,
                  conflicts: conflicts,
                  selected: selected,
                  layer: layer,
                  focusGrid: focusGrid,
                  revision: revision,
                  cell: cell,
                  colors: c,
                  paused: paused,
                  over: over,
                ),
                size: Size(side, height),
              ),
            ),
          ),
        );
        if (!interactive) return Center(child: boardWidget);
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          panEnabled: true,
          scaleEnabled: true,
          child: boardWidget,
        );
      },
    );
  }
}

class _SudokuBoardPainter extends CustomPainter {
  _SudokuBoardPainter({
    required this.puzzle,
    required this.board,
    required this.notes,
    required this.conflicts,
    required this.selected,
    required this.layer,
    required this.revision,
    this.focusGrid = -1,
    required this.cell,
    required this.colors,
    required this.paused,
    required this.over,
  });

  final SudokuPuzzle puzzle;
  final List<int> board;
  final List<Set<int>> notes;
  final Set<int> conflicts;
  final int selected;
  final int layer;
  final int focusGrid;
  final int revision;
  final double cell;
  final CitroColors colors;
  final bool paused;
  final bool over;

  int get _rows => puzzle.rows;
  int get _cols => puzzle.cols;
  int get _base => layer * _rows * _cols;

  bool _active(int index) =>
      index >= 0 && index < puzzle.active.length ? puzzle.active[index] : true;

  int? _valueAt(int index) =>
      index >= 0 && index < board.length ? board[index] : 0;

  Set<int> _peers() {
    final result = <int>{};
    if (selected < 0) return result;
    for (final unit in puzzle.units) {
      if (!unit.contains(selected)) continue;
      result.addAll(unit);
    }
    result.remove(selected);
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    _paintBoardBackground(canvas, size);
    _paintCellFills(canvas);
    _paintParitySymbols(canvas);
    _paintDiagonalBands(canvas, size);
    _paintValuesAndNotes(canvas);
    _paintGrid(canvas, size);
    _paintKillerCages(canvas);
    _paintInequalities(canvas);
    canvas.restore();
  }

  void _paintBoardBackground(Canvas canvas, Size size) {
    // 风车/重叠棋盘的空缺区域留白，和格面同色，只靠粗线勾出五盘轮廓。
    final paint = Paint()
      ..color = puzzle.variant == SudokuVariant.overlap
          ? colors.surface2
          : colors.bg2;
    canvas.drawRect(Offset.zero & size, paint);
  }

  Rect _cellRect(int row, int col) =>
      Rect.fromLTWH(col * cell, row * cell, cell, cell);

  void _paintCellFills(Canvas canvas) {
    // 杀手盘以笼色为主，选中后不再叠加同行/列/宫与同数字的引导色。
    final guides = puzzle.variant != SudokuVariant.killer;
    final peers = guides ? _peers() : const <int>{};
    final selectedValue = guides && selected >= 0
        ? (_valueAt(selected) ?? 0)
        : 0;
    final focusColor = _focusColor();
    final cageOf = puzzle.variant == SudokuVariant.killer
        ? _cageMap()
        : const <int>[];
    final cageFill = puzzle.variant == SudokuVariant.killer
        ? _cageColors()
        : const <Color>[];
    final cover = puzzle.variant == SudokuVariant.overlap
        ? _coverGrids()
        : const <List<int>>[];
    final fill = Paint();
    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _cols; col++) {
        final index = _base + row * _cols + col;
        if (!_active(index)) continue;
        final value = _valueAt(index) ?? 0;
        var color = colors.surface2;
        if (puzzle.variant == SudokuVariant.killer &&
            index < cageOf.length &&
            cageOf[index] >= 0 &&
            cageOf[index] < cageFill.length) {
          color = cageFill[cageOf[index]];
        }
        if (puzzle.variant == SudokuVariant.overlap &&
            index < cover.length &&
            cover[index].length > 1) {
          // 参考图一样式：只有共享格铺淡黄/淡粉，整盘不上色。
          final pair = cover[index][0] < cover[index][1]
              ? cover[index][0]
              : cover[index][1];
          color = Color.alphaBlend(
            (pair.isEven ? colors.noteY : colors.noteP).withValues(
              alpha: colors.dark ? .16 : .38,
            ),
            color,
          );
        }
        if (peers.contains(index)) {
          if (puzzle.variant == SudokuVariant.overlap) {
            color = Color.alphaBlend(focusColor.withValues(alpha: .10), color);
          } else {
            color = Color.alphaBlend(colors.mintSoft, color);
          }
        }
        if (selectedValue != 0 && value == selectedValue) {
          color = Color.alphaBlend(focusColor.withValues(alpha: .18), color);
        }
        if (index == selected &&
            puzzle.variant != SudokuVariant.killer) {
          color = Color.alphaBlend(focusColor.withValues(alpha: .28), color);
        }
        if (conflicts.contains(index)) {
          color = Color.alphaBlend(
            colors.stamp.withValues(alpha: index == selected ? .26 : .14),
            color,
          );
        }
        fill.color = color;
        canvas.drawRect(_cellRect(row, col), fill);
      }
    }
    if (selected >= 0 && selected < _rows * _cols * _maxLayers) {
      final row = (selected - _base) ~/ _cols;
      final col = (selected - _base) % _cols;
      if (row >= 0 && row < _rows && col >= 0 && col < _cols) {
        final r = _cellRect(row, col);
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, cell * .055)
          ..color = conflicts.contains(selected) ? colors.stamp : focusColor;
        canvas.drawRect(r.deflate(stroke.strokeWidth / 2), stroke);
      }
    }
  }

  Color _focusColor() {
    if (puzzle.variant != SudokuVariant.overlap ||
        focusGrid < 0 ||
        focusGrid >= puzzle.grids.length) {
      return colors.accent;
    }
    final palette = sudokuSubgridPalette(colors);
    return palette[focusGrid % palette.length];
  }

  void _paintParitySymbols(Canvas canvas) {
    if (puzzle.variant != SudokuVariant.evenOdd) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, cell * .035)
      ..color = colors.inkSoft.withValues(alpha: colors.dark ? .55 : .42);
    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _cols; col++) {
        final index = _base + row * _cols + col;
        if (!_active(index)) continue;
        final even = puzzle.evenCells.contains(index);
        final odd = puzzle.oddCells.contains(index);
        if (!even && !odd) continue;
        final box = _cellRect(row, col).deflate(cell * .18);
        if (even) {
          canvas.drawRect(box, paint);
        } else {
          canvas.drawOval(box, paint);
        }
      }
    }
  }

  int get _maxLayers => math.max(1, puzzle.layers);

  List<List<int>> _coverGrids() {
    final cover = List<List<int>>.generate(
      _rows * _cols * _maxLayers,
      (_) => <int>[],
    );
    for (var gi = 0; gi < puzzle.grids.length; gi++) {
      final g = puzzle.grids[gi];
      for (var r = 0; r < g.size; r++) {
        for (var c = 0; c < g.size; c++) {
          final row = g.top + r;
          final col = g.left + c;
          if (row < 0 || row >= _rows || col < 0 || col >= _cols) continue;
          cover[row * _cols + col].add(gi);
        }
      }
    }
    return cover;
  }

  List<int> _cageMap() {
    final map = List<int>.filled(
      _rows * _cols * _maxLayers,
      -1,
      growable: false,
    );
    for (var ci = 0; ci < puzzle.cages.length; ci++) {
      for (final index in puzzle.cages[ci].cells) {
        if (index >= 0 && index < map.length) map[index] = ci;
      }
    }
    return map;
  }

  /// 六种色相明确的浅色笼底；相邻笼由 [_cageColors] 保证不同色。
  List<Color> _cageFillPalette() {
    final warm = colors.dark ? .18 : .26;
    final pastel = colors.dark ? .16 : .70;
    Color tint(Color base, double alpha) =>
        Color.alphaBlend(base.withValues(alpha: alpha), colors.surface2);
    return [
      tint(colors.accentLt, warm),
      tint(colors.mint, warm),
      tint(colors.noteB, pastel),
      tint(colors.noteP, pastel),
      tint(colors.noteY, pastel),
      tint(colors.line2, colors.dark ? .30 : .50),
    ];
  }

  List<Color> _cageColors() {
    final palette = _cageFillPalette();
    final indices = killerCageColorIndices(puzzle, palette.length);
    final out = <Color>[];
    for (final c in indices) {
      while (c >= palette.length) {
        final i = palette.length;
        palette.add(
          Color.alphaBlend(
            colors.accentLt.withValues(alpha: .12 + .04 * (i % 4)),
            colors.surface2,
          ),
        );
      }
      out.add(palette[c]);
    }
    return out;
  }

  void _paintDiagonalBands(Canvas canvas, Size size) {
    if (puzzle.variant != SudokuVariant.diagonal) return;
    final paint = Paint()
      ..color = colors.accent.withValues(alpha: .20)
      ..strokeWidth = cell * .72
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  void _paintValuesAndNotes(Canvas canvas) {
    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _cols; col++) {
        final index = _base + row * _cols + col;
        if (!_active(index)) continue;
        final value = _valueAt(index) ?? 0;
        final given = index < puzzle.givens.length
            ? puzzle.givens[index] != 0
            : false;
        final box = _cellRect(row, col);
        if (value != 0) {
          _paintDigit(canvas, box, value, given, conflicts.contains(index));
        } else if (cell >= 14 &&
            index < notes.length &&
            notes[index].isNotEmpty) {
          _paintNotes(canvas, box, notes[index]);
        }
      }
    }
  }

  void _paintDigit(
    Canvas canvas,
    Rect box,
    int value,
    bool given,
    bool conflict,
  ) {
    final fontSize = (cell * (cell >= 28 ? .52 : .60)).clamp(7.0, 34.0);
    final tp = TextPainter(
      text: TextSpan(
        text: '$value',
        style: TextStyle(
          fontFamily: AppFonts.noto,
          fontFamilyFallback: AppFonts.fallback,
          fontSize: fontSize,
          fontWeight: given ? FontWeight.w700 : FontWeight.w600,
          color: conflict
              ? colors.stamp
              : (given ? colors.ink : colors.accentInk),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = box.left + (box.width - tp.width) / 2;
    final dy = box.top + (box.height - tp.height) / 2 - 1;
    tp.paint(canvas, Offset(dx, dy));
  }

  void _paintNotes(Canvas canvas, Rect box, Set<int> values) {
    final fontSize = math.min(cell * .23, 10.0);
    for (var n = 1; n <= 9; n++) {
      if (!values.contains(n)) continue;
      final r = (n - 1) ~/ 3;
      final c = (n - 1) % 3;
      final tp = TextPainter(
        text: TextSpan(
          text: '$n',
          style: TextStyle(
            fontFamily: AppFonts.noto,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: colors.ink2,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = box.left + box.width * (c + .5) / 3 - tp.width / 2;
      final top = box.top + box.height * (r + .5) / 3 - tp.height / 2;
      tp.paint(canvas, Offset(left, top));
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    if (puzzle.variant == SudokuVariant.overlap) {
      _paintOverlapGrid(canvas);
      return;
    }
    final thin = Paint()
      ..color = colors.line2
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final thick = Paint()
      ..color = colors.inkSoft
      ..strokeWidth = math.max(1.4, cell * .05)
      ..style = PaintingStyle.stroke;
    final outer = Paint()
      ..color = colors.ink.withValues(alpha: .80)
      ..strokeWidth = math.max(1.8, cell * .06)
      ..style = PaintingStyle.stroke;
    // 细线
    for (var r = 1; r < _rows; r++) {
      final y = r * cell;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), thin);
    }
    for (var c = 1; c < _cols; c++) {
      final x = c * cell;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), thin);
    }
    if (puzzle.variant == SudokuVariant.jigsaw ||
        puzzle.variant == SudokuVariant.snowflake) {
      final regionThick = Paint()
        ..color = colors.ink
        ..strokeWidth = math.max(2.0, cell * .07)
        ..style = PaintingStyle.stroke;
      _paintRegionBorders(canvas, regionThick);
    } else {
      for (final k in const [3, 6]) {
        final y = k * cell;
        final x = k * cell;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), thick);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), thick);
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(
        outer.strokeWidth / 2,
        outer.strokeWidth / 2,
        size.width - outer.strokeWidth,
        size.height - outer.strokeWidth,
      ),
      outer,
    );
  }

  void _paintRegionBorders(Canvas canvas, Paint thick) {
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final index = r * _cols + c;
        final region = index < puzzle.regionOf.length
            ? puzzle.regionOf[index]
            : -1;
        if (c == _cols - 1 ||
            (index + 1 < puzzle.regionOf.length &&
                puzzle.regionOf[index + 1] != region)) {
          final x = (c + 1) * cell;
          canvas.drawLine(
            Offset(x, r * cell),
            Offset(x, (r + 1) * cell),
            thick,
          );
        }
        if (r == _rows - 1 ||
            (index + _cols < puzzle.regionOf.length &&
                puzzle.regionOf[index + _cols] != region)) {
          final y = (r + 1) * cell;
          canvas.drawLine(
            Offset(c * cell, y),
            Offset((c + 1) * cell, y),
            thick,
          );
        }
        if (r == 0) {
          canvas.drawLine(
            Offset(c * cell, 0),
            Offset((c + 1) * cell, 0),
            thick,
          );
        }
        if (c == 0) {
          canvas.drawLine(
            Offset(0, r * cell),
            Offset(0, (r + 1) * cell),
            thick,
          );
        }
      }
    }
  }

  void _paintOverlapGrid(Canvas canvas) {
    final thin = Paint()
      ..color = colors.ink.withValues(alpha: .34)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final thick = Paint()
      ..color = colors.ink.withValues(alpha: .78)
      ..strokeWidth = math.max(1.4, cell * .05)
      ..style = PaintingStyle.stroke;
    final palette = sudokuSubgridPalette(colors);
    for (var gi = 0; gi < puzzle.grids.length; gi++) {
      final g = puzzle.grids[gi];
      final left = g.left * cell;
      final top = g.top * cell;
      final side = g.size * cell;
      final rect = Rect.fromLTWH(left, top, side, side);
      final focused = gi == focusGrid;
      final color = palette[gi % palette.length];
      canvas.save();
      canvas.clipRect(rect);
      for (var k = 1; k < g.size; k++) {
        final x = left + k * cell;
        final y = top + k * cell;
        final isThick = k % 3 == 0;
        canvas.drawLine(
          Offset(x, top),
          Offset(x, top + side),
          isThick ? thick : thin,
        );
        canvas.drawLine(
          Offset(left, y),
          Offset(left + side, y),
          isThick ? thick : thin,
        );
      }
      canvas.restore();
      final border = Paint()
        ..color = focused
            ? color.withValues(alpha: .96)
            : colors.ink.withValues(alpha: .62)
        ..strokeWidth = focused
            ? math.max(2.2, cell * .075)
            : math.max(1.4, cell * .04)
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect.deflate(border.strokeWidth / 2), border);
    }
  }

  void _paintKillerCages(Canvas canvas) {
    if (puzzle.cages.isEmpty) return;
    final cageOf = List<int>.filled(
      _rows * _cols * _maxLayers,
      -1,
      growable: false,
    );
    for (var ci = 0; ci < puzzle.cages.length; ci++) {
      for (final index in puzzle.cages[ci].cells) {
        if (index >= 0 && index < cageOf.length) cageOf[index] = ci;
      }
    }
    final line = Paint()
      ..color = colors.ink.withValues(alpha: .64)
      ..strokeWidth = math.max(1.3, cell * .040)
      ..style = PaintingStyle.stroke;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final index = _base + r * _cols + c;
        if (!_active(index)) continue;
        final id = index < cageOf.length ? cageOf[index] : -1;
        if (c == _cols - 1 ||
            index + 1 >= cageOf.length ||
            cageOf[index + 1] != id) {
          _dashedLine(
            canvas,
            Offset((c + 1) * cell, r * cell),
            Offset((c + 1) * cell, (r + 1) * cell),
            line,
          );
        }
        if (r == _rows - 1 ||
            index + _cols >= cageOf.length ||
            cageOf[index + _cols] != id) {
          _dashedLine(
            canvas,
            Offset(c * cell, (r + 1) * cell),
            Offset((c + 1) * cell, (r + 1) * cell),
            line,
          );
        }
        if (r == 0) {
          _dashedLine(
            canvas,
            Offset(c * cell, 0),
            Offset((c + 1) * cell, 0),
            line,
          );
        }
        if (c == 0) {
          _dashedLine(
            canvas,
            Offset(0, r * cell),
            Offset(0, (r + 1) * cell),
            line,
          );
        }
      }
    }
    for (var ci = 0; ci < puzzle.cages.length; ci++) {
      final cage = puzzle.cages[ci];
      if (cage.cells.isEmpty) continue;
      var topRow = _rows;
      var leftCol = _cols;
      for (final index in cage.cells) {
        final row = (index - _base) ~/ _cols;
        final col = (index - _base) % _cols;
        if (row < topRow || (row == topRow && col < leftCol)) {
          topRow = row;
          leftCol = col;
        }
      }
      if (topRow < 0 || topRow >= _rows || leftCol < 0 || leftCol >= _cols) {
        continue;
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '${cage.sum}',
          style: TextStyle(
            fontFamily: AppFonts.kalam,
            fontSize: math.max(10, math.min(cell * .42, 16)),
            fontWeight: FontWeight.w700,
            color: colors.ink,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(leftCol * cell + 2, topRow * cell + 1),
      );
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    final dash = math.max(2.0, cell * .18);
    final gap = math.max(1.6, cell * .12);
    var t = 0.0;
    while (t < total) {
      final end = math.min(t + dash, total);
      canvas.drawLine(a + dir * t, a + dir * end, paint);
      t = end + gap;
    }
  }

  void _paintInequalities(Canvas canvas) {
    if (puzzle.inequalities.isEmpty) return;
    final stroke = Paint()
      ..color = colors.accentInk
      ..strokeWidth = math.max(1.2, cell * .045)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final halo = Paint()..color = colors.surface2.withValues(alpha: .82);
    for (final edge in puzzle.inequalities) {
      final a = edge.a - _base;
      final b = edge.b - _base;
      if (a < 0 || b < 0 || a >= _rows * _cols || b >= _rows * _cols) {
        continue;
      }
      final ar = a ~/ _cols;
      final ac = a % _cols;
      final br = b ~/ _cols;
      final bc = b % _cols;
      if (ar == br && (bc - ac).abs() == 1) {
        final left = math.min(ac, bc).toDouble();
        final center = Offset((left + 1) * cell, (ar + .5) * cell);
        canvas.drawCircle(center, cell * .17, halo);
        final dir = bc > ac ? 1.0 : -1.0;
        _arrow(canvas, center, dir, 0, stroke);
      } else if (ac == bc && (br - ar).abs() == 1) {
        final top = math.min(ar, br).toDouble();
        final center = Offset((ac + .5) * cell, (top + 1) * cell);
        canvas.drawCircle(center, cell * .17, halo);
        final dir = br > ar ? 1.0 : -1.0;
        _arrow(canvas, center, 0, dir, stroke);
      }
    }
  }

  void _arrow(Canvas canvas, Offset center, double dx, double dy, Paint p) {
    final d = cell * .12;
    if (dx != 0) {
      final tip = center + Offset(d * dx, 0);
      canvas.drawLine(tip, tip + Offset(-d * 1.3 * dx, -d), p);
      canvas.drawLine(tip, tip + Offset(-d * 1.3 * dx, d), p);
    } else {
      final tip = center + Offset(0, d * dy);
      canvas.drawLine(tip, tip + Offset(-d, -d * 1.3 * dy), p);
      canvas.drawLine(tip, tip + Offset(d, -d * 1.3 * dy), p);
    }
  }

  @override
  bool shouldRepaint(covariant _SudokuBoardPainter old) =>
      old.revision != revision ||
      old.selected != selected ||
      old.layer != layer ||
      old.focusGrid != focusGrid ||
      old.cell != cell ||
      old.paused != paused ||
      old.over != over ||
      old.puzzle != puzzle ||
      old.colors != colors ||
      old.colors.ink != colors.ink ||
      old.colors.surface2 != colors.surface2;
}
