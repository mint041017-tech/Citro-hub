import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'sudoku_puzzle.dart';

/// 三面立方中“当前面”的平面 9×9 视图。
///
/// 与立方体共用 [SudokuPuzzle.cubeFaces] 映射和同一份 board/notes；
/// 手机默认显示它来保证可读性，桌面可切回立体视图。
class SudokuCubeFaceView extends StatelessWidget {
  const SudokuCubeFaceView({
    super.key,
    required this.puzzle,
    required this.face,
    required this.board,
    required this.notes,
    required this.conflicts,
    required this.selected,
    required this.revision,
    this.onSelect,
    this.maxSide = 460,
  });

  final SudokuPuzzle puzzle;
  final SudokuCubeFace face;
  final List<int> board;
  final List<Set<int>> notes;
  final Set<int> conflicts;
  final int selected;
  final int revision;
  final ValueChanged<int>? onSelect;
  final double maxSide;

  SudokuCubeFaceMap? get _map {
    for (final m in puzzle.cubeFaces) {
      if (m.face == face) return m;
    }
    return null;
  }

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
  Widget build(BuildContext context) {
    final c = context.c;
    final map = _map;
    if (map == null) return const SizedBox.shrink();
    final peers = _peers();
    final selectedValue = selected >= 0 && selected < board.length
        ? board[selected]
        : 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxSide;
        final side = math.min(available, maxSide);
        final cell = side / 9;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: RepaintBoundary(
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
                          for (var r = 0; r < 9; r++)
                            Expanded(
                              child: Row(
                                children: [
                                  for (var col = 0; col < 9; col++)
                                    Expanded(
                                      child: _FaceCell(
                                        index: map.cellAt(r, col),
                                        board: board,
                                        given: puzzle.givens,
                                        notes: notes,
                                        conflicts: conflicts,
                                        selected: selected,
                                        peers: peers,
                                        selectedValue: selectedValue,
                                        cell: cell,
                                        onTap: onSelect,
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
                            painter: _FaceGridPainter(
                              cell: cell,
                              line2: c.line2,
                              inkSoft: c.inkSoft,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FaceCell extends StatelessWidget {
  const _FaceCell({
    required this.index,
    required this.board,
    required this.given,
    required this.notes,
    required this.conflicts,
    required this.selected,
    required this.peers,
    required this.selectedValue,
    required this.cell,
    this.onTap,
  });

  final int index;
  final List<int> board;
  final List<int> given;
  final List<Set<int>> notes;
  final Set<int> conflicts;
  final int selected;
  final Set<int> peers;
  final int selectedValue;
  final double cell;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final value = index >= 0 && index < board.length ? board[index] : 0;
    final isGiven = index >= 0 && index < given.length && given[index] != 0;
    final isSelected = index == selected;
    final conflict = conflicts.contains(index);
    final peer = peers.contains(index);
    final same = selectedValue != 0 && value == selectedValue;
    var bg = c.surface2;
    if (peer) bg = c.mintSoft;
    if (same) {
      bg = Color.alphaBlend(c.accent.withValues(alpha: .18), bg);
    }
    if (isSelected) {
      bg = Color.alphaBlend(c.accent.withValues(alpha: .26), bg);
    }
    if (conflict) {
      bg = Color.alphaBlend(
        c.stamp.withValues(alpha: isSelected ? .26 : .14),
        bg,
      );
    }
    final fontSize = (cell * .52).clamp(9.0, 30.0);
    final noteSize = (cell * .2).clamp(5.0, 9.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null || index < 0 ? null : () => onTap!(index),
      child: Container(
        color: bg,
        foregroundDecoration: isSelected
            ? BoxDecoration(
                border: Border.all(
                  color: conflict ? c.stamp : c.accent,
                  width: 2,
                ),
              )
            : null,
        alignment: Alignment.center,
        child: value != 0
            ? Transform.translate(
                // 数字字形视觉中心比行框中心高约 5.6%，下移补正。
                offset: Offset(0, fontSize * .056),
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontFamily: AppFonts.noto,
                    fontFamilyFallback: AppFonts.fallback,
                    fontSize: fontSize,
                    fontWeight: isGiven ? FontWeight.w700 : FontWeight.w600,
                    color: conflict
                        ? c.stamp
                        : (isGiven ? c.ink : c.accentInk),
                    height: 1,
                  ),
                ),
              )
            : (index < 0 ||
                      index >= notes.length ||
                      notes[index].isEmpty ||
                      cell < 26
                  ? null
                  : Column(
                      children: [
                        for (var r = 0; r < 3; r++)
                          Expanded(
                            child: Row(
                              children: [
                                for (var q = 0; q < 3; q++)
                                  Expanded(
                                    child: Center(
                                      child: notes[index].contains(r * 3 + q + 1)
                                          ? Text(
                                              '${r * 3 + q + 1}',
                                              style: TextStyle(
                                                fontFamily: AppFonts.noto,
                                                fontSize: noteSize,
                                                fontWeight: FontWeight.w600,
                                                color: c.ink2,
                                                height: 1,
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    )),
      ),
    );
  }
}

class _FaceGridPainter extends CustomPainter {
  const _FaceGridPainter({
    required this.cell,
    required this.line2,
    required this.inkSoft,
  });

  final double cell;
  final Color line2;
  final Color inkSoft;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = line2
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final thick = Paint()
      ..color = inkSoft
      ..strokeWidth = math.max(1.6, cell * .05)
      ..style = PaintingStyle.stroke;
    for (var k = 1; k <= 9; k++) {
      final p = (k % 3 == 0 || k == 9) ? thick : thin;
      final x = k * cell;
      final y = k * cell;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _FaceGridPainter old) =>
      old.cell != cell || old.line2 != line2 || old.inkSoft != inkSoft;
}
