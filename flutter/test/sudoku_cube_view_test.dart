import 'package:citro/games/sudoku/sudoku_cube_view.dart';
import 'package:citro/games/sudoku/sudoku_modes.dart';
import 'package:citro/games/sudoku/sudoku_puzzle.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SudokuPuzzle _cubePuzzle() {
  final topCells = List<int>.generate(81, (i) => i);
  final flCells = List<int>.filled(81, 0);
  final frCells = List<int>.filled(81, 0);
  for (var c = 0; c < 9; c++) {
    flCells[c] = 72 + c;
    frCells[c] = c * 9 + 8;
  }
  for (var r = 1; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      flCells[r * 9 + c] = 81 + (r - 1) * 9 + c;
    }
    for (var c = 0; c < 8; c++) {
      frCells[r * 9 + c] = 153 + (r - 1) * 8 + c;
    }
    frCells[r * 9 + 8] = 80 + r * 9;
  }
  final topShared = <int>{
    for (var c = 0; c < 9; c++) 72 + c,
    for (var r = 0; r < 9; r++) r * 9 + 8,
  };
  final flShared = <int>{
    for (var c = 0; c < 9; c++) c,
    for (var r = 0; r < 9; r++) r * 9 + 8,
  };
  final frShared = <int>{
    for (var c = 0; c < 9; c++) c,
    for (var r = 0; r < 9; r++) r * 9 + 8,
  };
  final maps = [
    SudokuCubeFaceMap(
      face: SudokuCubeFace.top,
      cells: topCells,
      sharedEdgeCells: topShared,
    ),
    SudokuCubeFaceMap(
      face: SudokuCubeFace.frontLeft,
      cells: flCells,
      sharedEdgeCells: flShared,
    ),
    SudokuCubeFaceMap(
      face: SudokuCubeFace.frontRight,
      cells: frCells,
      sharedEdgeCells: frShared,
    ),
  ];
  final units = <List<int>>[];
  for (final map in maps) {
    for (var r = 0; r < 9; r++) {
      units.add([for (var c = 0; c < 9; c++) map.cellAt(r, c)]);
    }
    for (var c = 0; c < 9; c++) {
      units.add([for (var r = 0; r < 9; r++) map.cellAt(r, c)]);
    }
    for (var br = 0; br < 3; br++) {
      for (var bc = 0; bc < 3; bc++) {
        units.add([
          for (var r = 0; r < 3; r++)
            for (var c = 0; c < 3; c++)
              map.cellAt(br * 3 + r, bc * 3 + c),
        ]);
      }
    }
  }
  final solution = List<int>.generate(217, (i) => i % 9 + 1);
  final givens = List<int>.generate(
    217,
    (i) => i % 7 == 0 ? solution[i] : 0,
  );
  return SudokuPuzzle(
    variant: SudokuVariant.cube3d,
    difficulty: SudokuDifficulty.hard,
    overlapCount: 0,
    rows: 9,
    cols: 9,
    layers: 1,
    solution: solution,
    givens: givens,
    regionOf: List<int>.generate(217, (i) => (i % 9) ~/ 3 * 3 + i % 3),
    active: List<bool>.filled(217, true),
    grids: const [],
    units: units,
    cubeFaces: maps,
    cellCountOverride: 217,
  );
}

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildCitroTheme(CitroColors.light),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('cube view renders three faces and hits a cell', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final puzzle = _cubePuzzle();
    int? picked;
    SudokuCubeFace? pickedFace;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          child: SudokuCubeView(
            puzzle: puzzle,
            board: puzzle.givens,
            notes: List<Set<int>>.generate(217, (_) => <int>{}),
            conflicts: const {},
            selected: 0,
            focusFace: SudokuCubeFace.top,
            revision: 1,
            maxSide: 360,
            onSelect: (index, face) {
              picked = index;
              pickedFace = face;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final box = tester.getRect(find.byType(SudokuCubeView));
    await tester.tapAt(
      Offset(box.center.dx, box.top + box.height * .30),
    );
    await tester.pump();
    expect(picked, isNotNull);
    expect(pickedFace, isNotNull);
    expect(picked, inInclusiveRange(0, 216));
  });

  testWidgets('cube view rotates by drag and resets from the corner button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final puzzle = _cubePuzzle();
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          child: SudokuCubeView(
            puzzle: puzzle,
            board: puzzle.givens,
            notes: List<Set<int>>.generate(217, (_) => <int>{}),
            conflicts: const {},
            selected: 0,
            focusFace: SudokuCubeFace.top,
            revision: 1,
            maxSide: 360,
            onSelect: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('拖动旋转查看'), findsOneWidget);
    expect(find.byIcon(Icons.restart_alt_rounded), findsNothing);
    await tester.drag(find.byType(SudokuCubeView), const Offset(60, 30));
    await tester.pump();
    expect(find.text('拖动旋转查看'), findsNothing);
    expect(find.byIcon(Icons.restart_alt_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.restart_alt_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.restart_alt_rounded), findsNothing);
    expect(find.text('拖动旋转查看'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cube view switches focus face without errors', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final puzzle = _cubePuzzle();
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 300,
          child: SudokuCubeView(
            puzzle: puzzle,
            board: puzzle.givens,
            notes: List<Set<int>>.generate(217, (_) => <int>{}),
            conflicts: const {},
            selected: 80,
            focusFace: SudokuCubeFace.frontLeft,
            revision: 2,
            maxSide: 300,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
