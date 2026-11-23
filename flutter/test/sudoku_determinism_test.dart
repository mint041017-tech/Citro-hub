// 数独出题器随机源确定性测试：
//
// 不传入显式 seed，改由 GameRandom.debugSeed 播种。要求：
//   1. 同一种子生成两次，题目网格（givens）与答案（solution）逐格相同；
//   2. 两个不同种子生成不同题目，证明种子确实参与了出题，而不是恒返回同一套。
//
// 显式 seed 的确定性回归由 sudoku_kernel_test.dart 覆盖，这里只补 debugSeed 路径。
import 'package:citro/games/game_random.dart';
import 'package:citro/games/sudoku/sudoku_kernel.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectCellsEqual(List<int> a, List<int> b, String label) {
  expect(a.length, b.length, reason: '$label 长度一致');
  for (var i = 0; i < a.length; i++) {
    expect(a[i], b[i], reason: '$label 第 $i 格相同');
  }
}

void main() {
  setUpAll(() {
    GameRandom.debugSeed = 7;
  });

  tearDownAll(() {
    GameRandom.debugSeed = null;
  });

  test('same debugSeed reproduces givens and solution cell-by-cell', () {
    final classic = sudokuModeByKey('classic');
    final jigsaw = sudokuModeByKey('jigsaw');

    final a1 = SudokuEngine.generate(classic, SudokuDifficulty.medium);
    final a2 = SudokuEngine.generate(classic, SudokuDifficulty.medium);
    _expectCellsEqual(a1.givens, a2.givens, 'classic givens');
    _expectCellsEqual(a1.solution, a2.solution, 'classic solution');
    _expectCellsEqual(a1.regionOf, a2.regionOf, 'classic regions');

    final b1 = SudokuEngine.generate(jigsaw, SudokuDifficulty.medium);
    final b2 = SudokuEngine.generate(jigsaw, SudokuDifficulty.medium);
    _expectCellsEqual(b1.givens, b2.givens, 'jigsaw givens');
    _expectCellsEqual(b1.solution, b2.solution, 'jigsaw solution');
    _expectCellsEqual(b1.regionOf, b2.regionOf, 'jigsaw regions');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('different debugSeeds produce different puzzles', () {
    final classic = sudokuModeByKey('classic');

    GameRandom.debugSeed = 7;
    final p1 = SudokuEngine.generate(classic, SudokuDifficulty.medium);
    GameRandom.debugSeed = 42;
    final p2 = SudokuEngine.generate(classic, SudokuDifficulty.medium);

    final givensDiffer =
        p1.givens.join(',') != p2.givens.join(',');
    final solutionDiffer =
        p1.solution.join(',') != p2.solution.join(',');
    expect(givensDiffer || solutionDiffer, isTrue,
        reason: '两个种子至少有一处网格/答案不同');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
