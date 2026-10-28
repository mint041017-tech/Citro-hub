import 'package:citro/games/sudoku/sudoku_board_view.dart';
import 'package:citro/games/sudoku/sudoku_modes.dart';
import 'package:citro/games/sudoku/sudoku_puzzle.dart';
import 'package:citro/games/sudoku/sudoku_solver.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _classicSolution() => [
  for (var r = 0; r < 9; r++)
    for (var c = 0; c < 9; c++) (r * 3 + r ~/ 3 + c) % 9 + 1,
];

List<int> _classicRegions() => [
  for (var r = 0; r < 9; r++)
    for (var c = 0; c < 9; c++) (r ~/ 3) * 3 + c ~/ 3,
];

List<List<int>> _classicUnits() => [
  for (var r = 0; r < 9; r++) [for (var c = 0; c < 9; c++) r * 9 + c],
  for (var c = 0; c < 9; c++) [for (var r = 0; r < 9; r++) r * 9 + c],
  for (var br = 0; br < 3; br++)
    for (var bc = 0; bc < 3; bc++)
      [
        for (var r = 0; r < 3; r++)
          for (var c = 0; c < 3; c++) (br * 3 + r) * 9 + bc * 3 + c,
      ],
];

SudokuPuzzle _classic() {
  final solution = _classicSolution();
  final givens = List<int>.from(solution);
  for (final i in [0, 4, 8, 12, 20, 31, 45, 56, 67, 78]) {
    givens[i] = 0;
  }
  return SudokuPuzzle(
    variant: SudokuVariant.classic,
    difficulty: SudokuDifficulty.medium,
    overlapCount: 0,
    rows: 9,
    cols: 9,
    layers: 1,
    solution: solution,
    givens: givens,
    regionOf: _classicRegions(),
    active: List<bool>.filled(81, true),
    grids: const [],
    units: _classicUnits(),
  );
}

SudokuPuzzle _overlap13() {
  const rows = 33;
  const cols = 33;
  final active = List<bool>.filled(rows * cols, false);
  final grids = <SudokuSubGrid>[];
  for (var dr = -2; dr <= 2; dr++) {
    for (var dc = -2; dc <= 2; dc++) {
      if (dr.abs() + dc.abs() > 2) continue;
      final top = 12 + dr * 6;
      final left = 12 + dc * 6;
      grids.add(SudokuSubGrid(top: top, left: left));
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          active[(top + r) * cols + left + c] = true;
        }
      }
    }
  }
  return SudokuPuzzle(
    variant: SudokuVariant.overlap,
    difficulty: SudokuDifficulty.expert,
    overlapCount: 13,
    rows: rows,
    cols: cols,
    layers: 1,
    solution: List<int>.filled(rows * cols, 0),
    givens: List<int>.filled(rows * cols, 0),
    regionOf: List<int>.filled(rows * cols, -1),
    active: active,
    grids: grids,
    units: const [],
  );
}

Widget _host(Widget board) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildCitroTheme(CitroColors.light),
  home: Scaffold(body: Center(child: board)),
);

void main() {
  testWidgets('board renders classic with notes and selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final puzzle = _classic();
    final board = List<int>.from(puzzle.givens);
    final notes = List<Set<int>>.generate(81, (_) => <int>{});
    notes[0] = {2, 5, 7};
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          child: SudokuBoardView(
            puzzle: puzzle,
            board: board,
            notes: notes,
            conflicts: const {},
            selected: 0,
            layer: 0,
            revision: 1,
            maxSide: 360,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('board renders 13-grid overlap without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final puzzle = _overlap13();
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          child: SudokuBoardView(
            puzzle: puzzle,
            board: puzzle.givens,
            notes: List<Set<int>>.generate(
              puzzle.cellCount,
              (_) => <int>{},
            ),
            conflicts: const {},
            selected: 200,
            layer: 0,
            revision: 1,
            maxSide: 360,
            interactive: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('killer adjacent cages never share a color index', () {
    final mode = kSudokuModes.firstWhere((m) => m.key == 'killer');
    for (final seed in [120, 2046, 20261048]) {
      final puzzle = SudokuEngine.generate(
        mode,
        SudokuDifficulty.hard,
        seed: seed,
      );
      final colors = killerCageColorIndices(puzzle, 6);
      expect(colors.length, puzzle.cages.length);
      final owner = List<int>.filled(puzzle.rows * puzzle.cols, -1);
      for (var ci = 0; ci < puzzle.cages.length; ci++) {
        for (final i in puzzle.cages[ci].cells) {
          owner[i] = ci;
        }
      }
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          final a = owner[r * 9 + c];
          if (c + 1 < 9) {
            final b = owner[r * 9 + c + 1];
            if (a != b) {
              expect(colors[a], isNot(colors[b]), reason: 'seed $seed');
            }
          }
          if (r + 1 < 9) {
            final b = owner[(r + 1) * 9 + c];
            if (a != b) {
              expect(colors[a], isNot(colors[b]), reason: 'seed $seed');
            }
          }
        }
      }
    }
  });
}
