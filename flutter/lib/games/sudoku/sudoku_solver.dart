import 'dart:math' as math;

import 'sudoku_constraints.dart';
import 'sudoku_generator.dart';
import 'sudoku_modes.dart';
import 'sudoku_puzzle.dart';

/// 数独内核对外入口：生成、判定、冲突、提示、唯一解计数。
class SudokuEngine {
  const SudokuEngine._();

  static SudokuPuzzle generate(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty, {
    int? seed,
  }) => SudokuGenerator.generate(mode, difficulty, seed: seed);

  static Future<SudokuPuzzle> generateAsync(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty, {
    int? seed,
  }) async => generate(mode, difficulty, seed: seed);

  static bool isSolved(SudokuPuzzle puzzle, List<int> board) {
    if (board.length != puzzle.cellCount) return false;
    for (var i = 0; i < board.length; i++) {
      if (!puzzle.isActive(i)) continue;
      final v = board[i];
      if (v < 1 || v > 9) return false;
      final given = puzzle.givens[i];
      if (given != 0 && given != v) return false;
    }
    return conflicts(puzzle, board).isEmpty;
  }

  static Set<int> conflicts(SudokuPuzzle puzzle, List<int> board) {
    final out = <int>{};
    if (board.length != puzzle.cellCount) return out;

    void duplicates(Iterable<int> cells) {
      final byValue = <int, List<int>>{};
      for (final cell in cells) {
        if (!puzzle.isActive(cell)) continue;
        final v = board[cell];
        if (v < 1 || v > 9) continue;
        byValue.putIfAbsent(v, () => <int>[]).add(cell);
      }
      for (final list in byValue.values) {
        if (list.length > 1) out.addAll(list);
      }
    }

    for (final unit in puzzle.units) {
      duplicates(unit);
    }
    for (final cage in puzzle.cages) {
      duplicates(cage.cells);
      var sum = 0;
      var full = true;
      for (final cell in cage.cells) {
        final v = board[cell];
        if (v < 1 || v > 9) {
          full = false;
          continue;
        }
        sum += v;
      }
      if (full && sum != cage.sum) out.addAll(cage.cells);
    }
    for (final edge in puzzle.inequalities) {
      final a = board[edge.a];
      final b = board[edge.b];
      if (a >= 1 && a <= 9 && b >= 1 && b <= 9 && a >= b) {
        out.addAll([edge.a, edge.b]);
      }
    }
    for (final cell in puzzle.evenCells) {
      final v = board[cell];
      if (v >= 1 && v <= 9 && v.isOdd) out.add(cell);
    }
    for (final cell in puzzle.oddCells) {
      final v = board[cell];
      if (v >= 1 && v <= 9 && v.isEven) out.add(cell);
    }
    for (var i = 0; i < board.length; i++) {
      if (!puzzle.isActive(i)) continue;
      final given = puzzle.givens[i];
      if (given != 0 && board[i] != 0 && board[i] != given) out.add(i);
    }
    return out;
  }

  /// 返回一个还没填对（优先空、其次错）的格子；全部正确时返回 null。
  /// 从约束层求下一步：优先冲突格，其次传播后的裸单/隐单，最后 MRV 空格。
  static int? hintCell(SudokuPuzzle puzzle, List<int> board) {
    final bad = conflicts(puzzle, board);
    if (bad.isNotEmpty) return bad.first;
    if (board.length != puzzle.cellCount) return null;
    final index = SudokuConstraintIndex(puzzle);
    final dom = index.initialDomains(board: board);
    if (dom == null) return null;
    if (!index.propagate(dom)) return null;

    var best = -1;
    var bestCount = 10;
    for (final cell in index.activeCells) {
      if (board[cell] != 0) continue;
      final m = dom[cell];
      if (isSingleBit(m)) return cell;
      final count = popCount9(m);
      if (count < bestCount) {
        bestCount = count;
        best = cell;
      }
    }
    return best >= 0 ? best : null;
  }

  static int? hintValue(SudokuPuzzle puzzle, List<int> board) {
    final cell = hintCell(puzzle, board);
    if (cell == null) return null;
    final value = puzzle.solution[cell];
    return value >= 1 && value <= 9 ? value : null;
  }

  static int countSolutions(SudokuPuzzle puzzle, {int limit = 2}) {
    final index = SudokuConstraintIndex(puzzle);
    final dom = index.initialDomains();
    if (dom == null) return 0;
    final result = SudokuSearch(index).countSolutions(dom, limit: limit);
    return result < 0 ? limit : result;
  }

  static int? solutionValue(SudokuPuzzle puzzle, int index) =>
      index >= 0 && index < puzzle.solution.length
      ? puzzle.solution[index]
      : null;

  static int randomSeed([math.Random? rnd]) =>
      (rnd ?? math.Random()).nextInt(1 << 31);
}
