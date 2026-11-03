import 'package:citro/games/sudoku/sudoku_modes.dart';
import 'package:citro/games/sudoku/sudoku_puzzle.dart';
import 'package:citro/games/sudoku/sudoku_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

SudokuPuzzle _puzzle({
  SudokuVariant variant = SudokuVariant.classic,
  SudokuDifficulty difficulty = SudokuDifficulty.easy,
  int overlapCount = 0,
  int cells = 81,
  int? cellCountOverride,
}) => SudokuPuzzle(
  variant: variant,
  difficulty: difficulty,
  overlapCount: overlapCount,
  rows: 9,
  cols: 9,
  layers: 1,
  solution: List<int>.filled(cells, 1),
  givens: List<int>.filled(cells, 0),
  regionOf: List<int>.filled(cells, 0),
  active: List<bool>.filled(cells, true),
  grids: const [],
  units: const [],
  cellCountOverride: cellCountOverride,
);

void main() {
  test('经典基础分与参考用时按难度递增', () {
    expect(sudokuBaseScore(_puzzle()), 3600);
    expect(sudokuBaseScore(_puzzle(difficulty: SudokuDifficulty.expert)), 9000);
    expect(sudokuReferenceSeconds(_puzzle()), 81 * 4);
    expect(
      sudokuReferenceSeconds(_puzzle(difficulty: SudokuDifficulty.expert)),
      81 * 9,
    );
  });

  test('参考用时处拿满分，越快分数越高直到上限', () {
    final puzzle = _puzzle(difficulty: SudokuDifficulty.expert);
    final reference = sudokuReferenceSeconds(puzzle);
    final atReference = sudokuScoreOf(
      puzzle,
      seconds: reference,
      errors: 0,
      hintsUsed: 0,
    );
    expect(atReference.timeFactor, 1);
    expect(atReference.perfect, isTrue);
    expect(atReference.total, (9000 * kSudokuPerfectBonus).round());
    expect(
      atReference.cap,
      (9000 * (1 + kSudokuSpeedBonus) * kSudokuPerfectBonus).round(),
    );

    final fastest = sudokuScoreOf(puzzle, seconds: 1, errors: 0, hintsUsed: 0);
    expect(fastest.total, greaterThan(atReference.total));
    expect(fastest.total, lessThanOrEqualTo(fastest.cap));
  });

  test('参考用时内越快分数越高，且单调不回头', () {
    final puzzle = _puzzle(difficulty: SudokuDifficulty.expert);
    final reference = sudokuReferenceSeconds(puzzle);
    var previous = 1 << 30;
    for (final ratio in <double>[0.05, 0.25, 0.5, 0.75, 0.99, 1.0]) {
      final seconds = (reference * ratio).round();
      final score = sudokuScoreOf(
        puzzle,
        seconds: seconds,
        errors: 0,
        hintsUsed: 0,
      );
      expect(score.total, lessThanOrEqualTo(previous));
      previous = score.total;
    }
  });

  test('参考用时两侧曲线连续，不会突然掉档', () {
    final puzzle = _puzzle(difficulty: SudokuDifficulty.expert);
    final reference = sudokuReferenceSeconds(puzzle);
    final before = sudokuScoreOf(
      puzzle,
      seconds: reference,
      errors: 0,
      hintsUsed: 0,
    );
    final after = sudokuScoreOf(
      puzzle,
      seconds: reference + 1,
      errors: 0,
      hintsUsed: 0,
    );
    expect(before.total - after.total, lessThan(20));
  });

  test('超出参考用时后按反比平滑衰减', () {
    final reference = sudokuReferenceSeconds(_puzzle());
    final score = sudokuScoreOf(
      _puzzle(),
      seconds: reference * 3,
      errors: 0,
      hintsUsed: 0,
    );
    expect(score.timeFactor, closeTo(1 / 3, 1e-9));
    expect(score.total, (3600 * (1 / 3) * kSudokuPerfectBonus).round());
  });

  test('错误与提示按比例扣分且单调', () {
    final puzzle = _puzzle(difficulty: SudokuDifficulty.expert);
    final clean = sudokuScoreOf(puzzle, seconds: 700, errors: 0, hintsUsed: 0);
    final oneError = sudokuScoreOf(
      puzzle,
      seconds: 700,
      errors: 1,
      hintsUsed: 0,
    );
    final twoErrors = sudokuScoreOf(
      puzzle,
      seconds: 700,
      errors: 2,
      hintsUsed: 0,
    );
    expect(oneError.total, lessThan(clean.total));
    expect(twoErrors.total, lessThan(oneError.total));
    expect(oneError.errorFactor, closeTo(1 - kSudokuErrorPenalty, 1e-9));

    final oneHint = sudokuScoreOf(
      puzzle,
      seconds: 700,
      errors: 0,
      hintsUsed: 1,
    );
    expect(oneHint.total, lessThan(clean.total));
    expect(oneHint.hintFactor, closeTo(1 - kSudokuHintPenalty, 1e-9));
  });

  test('错误与提示系数有下限，总分始终在 1 到上限之间', () {
    final worst = sudokuScoreOf(
      _puzzle(),
      seconds: 1,
      errors: 99,
      hintsUsed: 99,
    );
    expect(worst.errorFactor, kSudokuErrorFloor);
    expect(worst.hintFactor, kSudokuHintFloor);
    expect(worst.perfect, isFalse);

    for (final seconds in <int>[1, 100, 10000, 1000000]) {
      final score = sudokuScoreOf(
        _puzzle(),
        seconds: seconds,
        errors: 99,
        hintsUsed: 99,
      );
      expect(score.total, greaterThanOrEqualTo(1));
      expect(score.total, lessThanOrEqualTo(score.cap));
    }
  });

  test('越慢分数越低', () {
    final fast = sudokuScoreOf(
      _puzzle(),
      seconds: 300,
      errors: 0,
      hintsUsed: 0,
    );
    final slow = sudokuScoreOf(
      _puzzle(),
      seconds: 900,
      errors: 0,
      hintsUsed: 0,
    );
    expect(slow.total, lessThan(fast.total));
  });

  test('变体基础分与参考用时随约束复杂度增长', () {
    final killer = _puzzle(
      variant: SudokuVariant.killer,
      difficulty: SudokuDifficulty.expert,
    );
    expect(sudokuBaseScore(killer), 7500);
    expect(
      sudokuReferenceSeconds(killer),
      (81 * 9 * sudokuVariantSecondsFactor(killer)).round(),
    );

    final cube = _puzzle(
      variant: SudokuVariant.cube3d,
      difficulty: SudokuDifficulty.expert,
      cells: 217,
      cellCountOverride: 217,
    );
    expect(
      sudokuReferenceSeconds(cube),
      (217 * 9 * sudokuVariantSecondsFactor(cube)).round(),
    );
    expect(
      sudokuReferenceSeconds(cube),
      greaterThan(sudokuReferenceSeconds(killer)),
    );
  });
}
