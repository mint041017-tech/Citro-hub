import 'dart:math' as math;
import 'dart:typed_data';

import 'sudoku_constraints.dart';
import 'sudoku_modes.dart';
import 'sudoku_puzzle.dart';

/// 对 UI/排行榜暴露的紧凑评级结果。
class SudokuRating {
  const SudokuRating({
    required this.techniqueLevel,
    required this.guesses,
    required this.branches,
    required this.backtracks,
    required this.clues,
    required this.tier,
    required this.score,
  });

  final int techniqueLevel;
  final int guesses;
  final int branches;
  final int backtracks;
  final int clues;

  /// 0 简单 / 1 中等 / 2 困难 / 3 专家。
  final int tier;
  final int score;

  bool atLeast(SudokuDifficulty difficulty) => tier >= difficulty.tier;

  SudokuDifficulty get difficulty => SudokuDifficulty.values[tier];

  @override
  String toString() =>
      'SudokuRating(tier=$tier, level=$techniqueLevel, clues=$clues, '
      'guesses=$guesses, score=$score)';
}

/// 技巧驱动评级。
///
/// 人类技巧链：裸单 → 隐单 → 锁定候选/笼和 → 数对 → X-Wing → 猜测。
/// 分数只解释“解题需要什么”，不把空格数当主指标。
class SudokuGrader {
  const SudokuGrader();

  static const int mediumThreshold = 130;
  static const int hardThreshold = 350;
  static const int expertThreshold = 600;

  SudokuRating rate(SudokuPuzzle puzzle) {
    final index = SudokuConstraintIndex(puzzle);
    final dom = index.initialDomains();
    if (dom == null) {
      return const SudokuRating(
        techniqueLevel: 6,
        guesses: 0,
        branches: 0,
        backtracks: 0,
        clues: 0,
        tier: 3,
        score: 99999,
      );
    }
    final stats = SolveStats();
    final solver = _HumanSolver(index, stats, 40000);
    final solved = solver.solve(Int32List.fromList(dom));
    final clues = _clueCount(puzzle);
    final score = _score(puzzle, stats, solved, solver.budgetExceeded);
    var level = stats.techniqueLevel;
    // 奇偶标记本身是变体约束消元：即使传播只表现为隐单，也按“锁定级”技巧计。
    if ((puzzle.evenCells.isNotEmpty || puzzle.oddCells.isNotEmpty) &&
        level < 2) {
      level = 2;
    }
    return SudokuRating(
      techniqueLevel: level,
      guesses: stats.guesses,
      branches: stats.branches,
      backtracks: stats.backtracks,
      clues: clues,
      tier: _tierFor(puzzle, score, level, clues),
      score: score,
    );
  }

  int _tierFor(SudokuPuzzle puzzle, int score, int level, int clues) {
    var tier = score >= expertThreshold
        ? 3
        : score >= hardThreshold
        ? 2
        : score >= mediumThreshold
        ? 1
        : 0;
    if (level >= 4 && tier < 3) tier = 3;
    if (level == 3 && tier < 2) tier = 2;
    if (level == 2 && tier < 1) tier = 1;

    // 提示数作为难度下限：技巧分决定“有多难”，空格数保证四档不会挤在一起。
    if (clues <= 24 && tier < 3) tier = 3;
    if (clues <= 29 && tier < 2) tier = 2;
    if (clues <= 35 && tier < 1) tier = 1;

    // 杀手笼本身消去大量候选：少量提示定困难，零提示才是专家。
    // （普通提示数下限会把 6 提示的困难局误抬成专家，这里覆盖回来。）
    if (puzzle.variant == SudokuVariant.killer) {
      if (clues == 0) {
        tier = 3;
      } else if (clues <= 12) {
        tier = 2;
      }
    }

    // 重叠盘的结构复杂度按模式标称固定：2/3 为困难，4/5/8/13 为专家。
    // 风车是独立 mode，档位由 mode 决定（hard=2 / expert=3），不被 overlap-4 覆盖。
    if (puzzle.windmill) {
      tier = puzzle.difficulty.tier == 3 ? 3 : 2;
    } else if (puzzle.variant == SudokuVariant.overlap) {
      tier = puzzle.overlapCount >= 4 ? 3 : math.max(tier, 2);
    }
    // 三面立方是大结构变体：档位跟 mode 绑定，技巧分仍保留用于展示/排序。
    if (puzzle.variant == SudokuVariant.cube3d) {
      tier = puzzle.difficulty.tier == 3 ? 3 : 2;
    }
    return tier;
  }

  int _score(
    SudokuPuzzle puzzle,
    SolveStats stats,
    bool solved,
    bool budgetExceeded,
  ) {
    final levelBase = switch (stats.techniqueLevel) {
      0 => 0,
      1 => 30,
      2 => 140,
      3 => 300,
      4 => 470,
      _ => 650,
    };
    var score = levelBase;
    score += math.min(60, stats.hiddenSingles * 2 + stats.nakedSingles ~/ 2);
    score += math.min(
      140,
      stats.lockedCandidates * 18 +
          stats.nakedPairs * 35 +
          stats.hiddenPairs * 40 +
          stats.xWings * 90 +
          stats.cageSteps * 12 +
          stats.edgeSteps * 2,
    );
    score += stats.guesses * 70 + stats.branches * 10 + stats.backtracks * 6;
    score += math.min(30, stats.propagationSteps ~/ 100);
    score += _variantBonus(puzzle);
    if (!solved || budgetExceeded) score += 40;
    return score;
  }

  int _variantBonus(SudokuPuzzle puzzle) {
    if (puzzle.windmill) return 80;
    return switch (puzzle.variant) {
      SudokuVariant.classic => 0,
      SudokuVariant.jigsaw => 50,
      SudokuVariant.overlap => 0,
      SudokuVariant.evenOdd => 30,
      SudokuVariant.diagonal => 30,
      SudokuVariant.inequality => 40,
      SudokuVariant.killer => 60,
      SudokuVariant.cube3d => 100,
      // 雪花已从模式目录移除；旧枚举保留时也不再有生成路径。
      _ => 0,
    };
  }

  int _clueCount(SudokuPuzzle puzzle) {
    var n = 0;
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (puzzle.active[i] && puzzle.givens[i] != 0) n++;
    }
    return n;
  }
}

class _HumanSolver {
  _HumanSolver(this.index, this.stats, this.maxNodes);

  final SudokuConstraintIndex index;
  final SolveStats stats;
  final int maxNodes;
  int nodes = 0;
  bool budgetExceeded = false;

  bool get _useAdvanced => index.activeCells.length <= 320;

  /// 3D 的 rowOf/colOf 对 217 个去重格没有意义；按 unit 所属面取局部坐标。
  int _colInUnit(int cell, int unit) {
    if (!index.puzzle.isCube3d) return index.puzzle.colOf(cell);
    final face = index.puzzle.cubeFaces[index.unitInfos[unit].layer];
    for (var c = 0; c < 9; c++) {
      for (var r = 0; r < 9; r++) {
        if (face.cellAt(r, c) == cell) return c;
      }
    }
    return -1;
  }

  int _rowInUnit(int cell, int unit) {
    if (!index.puzzle.isCube3d) return index.puzzle.rowOf(cell);
    final face = index.puzzle.cubeFaces[index.unitInfos[unit].layer];
    for (var c = 0; c < 9; c++) {
      for (var r = 0; r < 9; r++) {
        if (face.cellAt(r, c) == cell) return r;
      }
    }
    return -1;
  }

  bool solve(Int32List dom) {
    nodes++;
    if (nodes > maxNodes) {
      budgetExceeded = true;
      return false;
    }
    while (true) {
      if (!index.propagate(dom, stats: stats, countTechniques: true)) {
        return false;
      }
      final branch = _firstBranch(dom);
      if (branch == -2) return false;
      if (branch < 0) return true;
      if (!_useAdvanced) break;
      if (_applyLocked(dom)) continue;
      if (_applyNakedPair(dom)) continue;
      if (_applyHiddenPair(dom)) continue;
      if (_applyXWing(dom)) continue;
      break;
    }

    final branch = _firstBranch(dom);
    if (branch == -2) return false;
    if (branch < 0) return true;
    final mask = dom[branch];
    for (var d = 0; d < kDigitCount; d++) {
      final bit = 1 << d;
      if (mask & bit == 0) continue;
      stats.guesses++;
      stats.branches++;
      final next = Int32List.fromList(dom);
      next[branch] = bit;
      if (solve(next)) return true;
      stats.backtracks++;
    }
    return false;
  }

  int _firstBranch(Int32List dom) {
    var best = -1;
    var bestCount = 10;
    for (final cell in index.activeCells) {
      final m = dom[cell];
      if (m == 0) return -2;
      if (isSingleBit(m)) continue;
      final count = popCount9(m);
      if (count < bestCount) {
        bestCount = count;
        best = cell;
        if (count == 2) break;
      }
    }
    return best;
  }

  bool _applyLocked(Int32List dom) {
    if (index.lockedPairs.isEmpty) return false;
    for (final pair in index.lockedPairs) {
      final line = index.units[pair.line];
      final region = index.units[pair.region];
      final intersection = pair.intersection;
      for (var d = 0; d < kDigitCount; d++) {
        final bit = 1 << d;
        var lineCount = 0;
        var lineAllInside = true;
        for (final cell in line) {
          if (dom[cell] & bit != 0) {
            lineCount++;
            if (!intersection.contains(cell)) lineAllInside = false;
          }
        }
        if (lineCount >= 2 && lineAllInside) {
          var changed = false;
          for (final cell in region) {
            if (intersection.contains(cell)) continue;
            if (dom[cell] & bit == 0) continue;
            dom[cell] &= ~bit;
            if (dom[cell] == 0) return false;
            changed = true;
          }
          if (changed) {
            stats.lockedCandidates++;
            return true;
          }
        }

        var regionCount = 0;
        var regionAllInside = true;
        for (final cell in region) {
          if (dom[cell] & bit != 0) {
            regionCount++;
            if (!intersection.contains(cell)) regionAllInside = false;
          }
        }
        if (regionCount >= 2 && regionAllInside) {
          var changed = false;
          for (final cell in line) {
            if (intersection.contains(cell)) continue;
            if (dom[cell] & bit == 0) continue;
            dom[cell] &= ~bit;
            if (dom[cell] == 0) return false;
            changed = true;
          }
          if (changed) {
            stats.lockedCandidates++;
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _applyNakedPair(Int32List dom) {
    for (final unit in index.units) {
      final pairCells = <int>[];
      final pairMasks = <int>[];
      for (final cell in unit) {
        final m = dom[cell];
        if (popCount9(m) == 2) {
          pairCells.add(cell);
          pairMasks.add(m);
        }
      }
      if (pairCells.length < 2) continue;
      for (var i = 0; i < pairCells.length; i++) {
        for (var j = i + 1; j < pairCells.length; j++) {
          if (pairMasks[i] != pairMasks[j]) continue;
          final mask = pairMasks[i];
          var changed = false;
          for (final cell in unit) {
            if (cell == pairCells[i] || cell == pairCells[j]) continue;
            final before = dom[cell];
            final after = before & ~mask;
            if (after != before) {
              if (after == 0) return false;
              dom[cell] = after;
              changed = true;
            }
          }
          if (changed) {
            stats.nakedPairs++;
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _applyHiddenPair(Int32List dom) {
    for (final unit in index.units) {
      final positions = List<List<int>>.generate(kDigitCount, (_) => <int>[]);
      for (final cell in unit) {
        final m = dom[cell];
        for (var d = 0; d < kDigitCount; d++) {
          if (m & (1 << d) != 0) positions[d].add(cell);
        }
      }
      for (var d1 = 0; d1 < kDigitCount; d1++) {
        final p1 = positions[d1];
        if (p1.length != 2) continue;
        for (var d2 = d1 + 1; d2 < kDigitCount; d2++) {
          final p2 = positions[d2];
          if (p2.length != 2) continue;
          if (p1[0] != p2[0] || p1[1] != p2[1]) continue;
          final mask = (1 << d1) | (1 << d2);
          var changed = false;
          for (final cell in p1) {
            final before = dom[cell];
            final after = before & mask;
            if (after != before) {
              if (after == 0) return false;
              dom[cell] = after;
              changed = true;
            }
          }
          if (changed) {
            stats.hiddenPairs++;
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _applyXWing(Int32List dom) {
    for (final group in index.xwingGroups.values) {
      if (group.length < 2) continue;
      for (var d = 0; d < kDigitCount; d++) {
        final bit = 1 << d;
        final byColumns = <int, List<int>>{};
        for (final unit in group) {
          final cols = <int>[];
          for (final cell in index.units[unit]) {
            if (dom[cell] & bit != 0) cols.add(_colInUnit(cell, unit));
          }
          if (cols.length != 2) continue;
          cols.sort();
          final key = cols[0] * 9 + cols[1];
          byColumns.putIfAbsent(key, () => <int>[]).add(unit);
        }
        for (final entry in byColumns.entries) {
          if (entry.value.length < 2) continue;
          final c1 = entry.key ~/ 9;
          final c2 = entry.key % 9;
          for (var i = 0; i < entry.value.length; i++) {
            for (var j = i + 1; j < entry.value.length; j++) {
              final rows = {entry.value[i], entry.value[j]};
              var changed = false;
              for (final unit in group) {
                if (rows.contains(unit)) continue;
                for (final cell in index.units[unit]) {
                  final c = _colInUnit(cell, unit);
                  if (c != c1 && c != c2) continue;
                  if (dom[cell] & bit == 0) continue;
                  dom[cell] &= ~bit;
                  if (dom[cell] == 0) return false;
                  changed = true;
                }
              }
              if (changed) {
                stats.xWings++;
                return true;
              }
            }
          }
        }
      }
    }

    for (final group in index.xwingColGroups.values) {
      if (group.length < 2) continue;
      for (var d = 0; d < kDigitCount; d++) {
        final bit = 1 << d;
        final byRows = <int, List<int>>{};
        for (final unit in group) {
          final rows = <int>[];
          for (final cell in index.units[unit]) {
            if (dom[cell] & bit != 0) rows.add(_rowInUnit(cell, unit));
          }
          if (rows.length != 2) continue;
          rows.sort();
          final key = rows[0] * 9 + rows[1];
          byRows.putIfAbsent(key, () => <int>[]).add(unit);
        }
        for (final entry in byRows.entries) {
          if (entry.value.length < 2) continue;
          final r1 = entry.key ~/ 9;
          final r2 = entry.key % 9;
          for (var i = 0; i < entry.value.length; i++) {
            for (var j = i + 1; j < entry.value.length; j++) {
              final cols = {entry.value[i], entry.value[j]};
              var changed = false;
              for (final unit in group) {
                if (cols.contains(unit)) continue;
                for (final cell in index.units[unit]) {
                  final r = _rowInUnit(cell, unit);
                  if (r != r1 && r != r2) continue;
                  if (dom[cell] & bit == 0) continue;
                  dom[cell] &= ~bit;
                  if (dom[cell] == 0) return false;
                  changed = true;
                }
              }
              if (changed) {
                stats.xWings++;
                return true;
              }
            }
          }
        }
      }
    }
    return false;
  }
}
