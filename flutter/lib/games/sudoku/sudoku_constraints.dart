import 'dart:math' as math;
import 'dart:typed_data';

import 'sudoku_modes.dart';
import 'sudoku_puzzle.dart';

/// 数独内核内部共享的位掩码与约束索引。
///
/// 公共 API 不直接暴露这个文件；求解器、评级器、出题器共用同一份
/// units / cages / inequalities 解释，避免 UI 与内核各写一套规则。
const int kDigitCount = 9;
const int kAllDigitsMask = (1 << kDigitCount) - 1;

int digitBit(int digit) => 1 << (digit - 1);

int bitValue(int singleBit) => singleBit.bitLength;

bool isSingleBit(int mask) => mask != 0 && (mask & (mask - 1)) == 0;

int popCount9(int mask) {
  var n = 0;
  while (mask != 0) {
    mask &= mask - 1;
    n++;
  }
  return n;
}

int minBitValue(int mask) {
  for (var v = 1; v <= kDigitCount; v++) {
    if (mask & digitBit(v) != 0) return v;
  }
  return 0;
}

int maxBitValue(int mask) {
  for (var v = kDigitCount; v >= 1; v--) {
    if (mask & digitBit(v) != 0) return v;
  }
  return 0;
}

enum SudokuUnitKind { row, col, region, diagonal, vertical }

class SudokuUnitInfo {
  const SudokuUnitInfo(this.kind, this.group, this.layer);

  final SudokuUnitKind kind;

  /// 同组单元共享同一套横向/纵向坐标，X-Wing 只在组内使用。
  final int group;
  final int layer;
}

class SolveStats {
  int nakedSingles = 0;
  int hiddenSingles = 0;
  int lockedCandidates = 0;
  int nakedPairs = 0;
  int hiddenPairs = 0;
  int xWings = 0;
  int cageSteps = 0;
  int edgeSteps = 0;
  int guesses = 0;
  int branches = 0;
  int backtracks = 0;
  int propagationSteps = 0;

  void merge(SolveStats other) {
    nakedSingles += other.nakedSingles;
    hiddenSingles += other.hiddenSingles;
    lockedCandidates += other.lockedCandidates;
    nakedPairs += other.nakedPairs;
    hiddenPairs += other.hiddenPairs;
    xWings += other.xWings;
    cageSteps += other.cageSteps;
    edgeSteps += other.edgeSteps;
    guesses += other.guesses;
    branches += other.branches;
    backtracks += other.backtracks;
    propagationSteps += other.propagationSteps;
  }

  int get advancedSteps =>
      lockedCandidates +
      nakedPairs +
      hiddenPairs +
      xWings +
      cageSteps +
      guesses;

  /// 技巧层级：0 裸单，1 隐单，2 锁定/笼和，3 数对，4 X-Wing，5 猜测。
  int get techniqueLevel {
    if (guesses > 0) return 5;
    if (xWings > 0) return 4;
    if (nakedPairs + hiddenPairs > 0) return 3;
    if (lockedCandidates > 0 || cageSteps > 0 || edgeSteps > 0) return 2;
    if (hiddenSingles > 0) return 1;
    return 0;
  }
}

class CageConstraint {
  const CageConstraint(this.cells, this.sum);

  final Int32List cells;
  final int sum;
}

class LockedPair {
  const LockedPair(this.line, this.region, this.intersection);

  final int line;
  final int region;
  final Int32List intersection;
}

class SudokuConstraintIndex {
  SudokuConstraintIndex(this.puzzle) {
    final count = puzzle.cellCount;
    final activeList = <int>[];
    active = Int32List(count);
    for (var i = 0; i < count; i++) {
      if (puzzle.active[i]) {
        active[i] = 1;
        activeList.add(i);
      }
    }
    activeCells = Int32List.fromList(activeList);

    final seenUnits = <String>{};
    final rawUnits = <Int32List>[];
    final rawMeta = <SudokuUnitInfo>[];
    for (final unit in puzzle.units) {
      if (unit.isEmpty) continue;
      final key = unit.join(',');
      if (!seenUnits.add(key)) continue;
      final cells = Int32List.fromList(unit);
      rawUnits.add(cells);
      rawMeta.add(_classifyUnit(cells));
    }
    units = List<Int32List>.unmodifiable(rawUnits);
    unitInfos = List<SudokuUnitInfo>.unmodifiable(rawMeta);

    final cellUnitsRaw = List<List<int>>.generate(count, (_) => <int>[]);
    for (var u = 0; u < units.length; u++) {
      for (final cell in units[u]) {
        cellUnitsRaw[cell].add(u);
      }
    }
    cellUnits = List<List<int>>.unmodifiable(
      cellUnitsRaw.map((e) => List<int>.unmodifiable(e)),
    );

    cages = List<CageConstraint>.unmodifiable([
      for (final cage in puzzle.cages)
        CageConstraint(Int32List.fromList(cage.cells), cage.sum),
    ]);

    final edgePairs = <(int, int)>[];
    for (final edge in puzzle.inequalities) {
      if (puzzle.isActive(edge.a) && puzzle.isActive(edge.b)) {
        edgePairs.add((edge.a, edge.b));
      }
    }
    edges = List.unmodifiable(edgePairs);

    parity = Int32List(count);
    for (var i = 0; i < count; i++) {
      parity[i] = kAllDigitsMask;
    }
    for (final i in puzzle.evenCells) {
      if (i >= 0 && i < count) parity[i] &= _evenMask;
    }
    for (final i in puzzle.oddCells) {
      if (i >= 0 && i < count) parity[i] &= _oddMask;
    }

    rowUnits = <int>[];
    colUnits = <int>[];
    regionUnits = <int>[];
    for (var u = 0; u < units.length; u++) {
      switch (unitInfos[u].kind) {
        case SudokuUnitKind.row:
          rowUnits.add(u);
        case SudokuUnitKind.col:
          colUnits.add(u);
        case SudokuUnitKind.region:
          regionUnits.add(u);
        case SudokuUnitKind.diagonal:
        case SudokuUnitKind.vertical:
          break;
      }
    }

    xwingGroups = <int, List<int>>{};
    for (final u in rowUnits) {
      xwingGroups.putIfAbsent(unitInfos[u].group, () => <int>[]).add(u);
    }
    xwingColGroups = <int, List<int>>{};
    for (final u in colUnits) {
      xwingColGroups.putIfAbsent(unitInfos[u].group, () => <int>[]).add(u);
    }

    // 锁定候选：区域单元与同层行/列单元的交集。
    final locked = <LockedPair>[];
    final regionSet = regionUnits.toSet();
    final lineSet = <int>{...rowUnits, ...colUnits};
    if (puzzle.variant != SudokuVariant.overlap) {
      for (final r in regionSet) {
        final regionCells = units[r];
        final regionCellSet = regionCells.toSet();
        for (final l in lineSet) {
          if (unitInfos[l].layer != unitInfos[r].layer) continue;
          final inter = <int>[];
          for (final cell in units[l]) {
            if (regionCellSet.contains(cell)) inter.add(cell);
          }
          if (inter.length >= 2) {
            locked.add(LockedPair(l, r, Int32List.fromList(inter)));
          }
        }
      }
    }
    lockedPairs = List.unmodifiable(locked);
  }

  static const int _evenMask =
      (1 << 1) | (1 << 3) | (1 << 5) | (1 << 7); // 2,4,6,8
  static const int _oddMask =
      (1 << 0) | (1 << 2) | (1 << 4) | (1 << 6) | (1 << 8); // 1,3,5,7,9

  final SudokuPuzzle puzzle;
  late final Int32List active;
  late final Int32List activeCells;
  late final List<Int32List> units;
  late final List<SudokuUnitInfo> unitInfos;
  late final List<List<int>> cellUnits;
  late final List<CageConstraint> cages;
  late final List<(int, int)> edges;
  late final Int32List parity;
  late final List<int> rowUnits;
  late final List<int> colUnits;
  late final List<int> regionUnits;
  late final Map<int, List<int>> xwingGroups;
  late final Map<int, List<int>> xwingColGroups;
  late final List<LockedPair> lockedPairs;

  int get cellCount => puzzle.cellCount;

  Int32List? initialDomains({List<int>? board, bool useGivens = true}) {
    final dom = Int32List(cellCount);
    for (final i in activeCells) {
      dom[i] = parity[i];
      if (dom[i] == 0) return null;
    }
    if (useGivens) {
      for (var i = 0; i < cellCount; i++) {
        final v = puzzle.givens[i];
        if (v == 0) continue;
        if (!puzzle.active[i] || v < 1 || v > kDigitCount) return null;
        final bit = digitBit(v);
        if (dom[i] & bit == 0) return null;
        dom[i] = bit;
      }
    }
    if (board != null) {
      if (board.length != cellCount) return null;
      for (var i = 0; i < cellCount; i++) {
        final v = board[i];
        if (v == 0) continue;
        if (!puzzle.active[i] || v < 1 || v > kDigitCount) return null;
        final bit = digitBit(v);
        if (dom[i] & bit == 0) return null;
        dom[i] = bit;
      }
    }
    return dom;
  }

  SudokuUnitInfo _classifyUnit(Int32List cells) {
    if (puzzle.isCube3d) return _classifyCubeUnit(cells);
    final first = cells[0];
    final firstLayer = puzzle.layerOf(first);
    var sameLayer = true;
    var sameRow = true;
    var sameCol = true;
    var diagMain = true;
    var diagAnti = true;
    final row = puzzle.rowOf(first);
    final col = puzzle.colOf(first);

    for (final cell in cells) {
      final layer = puzzle.layerOf(cell);
      final r = puzzle.rowOf(cell);
      final c = puzzle.colOf(cell);
      if (layer != firstLayer) sameLayer = false;
      if (r != row) sameRow = false;
      if (c != col) sameCol = false;
      if (r != c) diagMain = false;
      if (r + c != puzzle.rows - 1) diagAnti = false;
    }

    if (!sameLayer) {
      return SudokuUnitInfo(SudokuUnitKind.vertical, firstLayer, -1);
    }

    final cols = <int>[];
    final rows = <int>[];
    for (final cell in cells) {
      cols.add(puzzle.colOf(cell));
      rows.add(puzzle.rowOf(cell));
    }
    cols.sort();
    rows.sort();
    final groupBase = firstLayer * 100000;

    if (sameRow) {
      return SudokuUnitInfo(
        SudokuUnitKind.row,
        groupBase + _signature(cols),
        firstLayer,
      );
    }
    if (sameCol) {
      return SudokuUnitInfo(
        SudokuUnitKind.col,
        groupBase + _signature(rows),
        firstLayer,
      );
    }
    if (diagMain || diagAnti) {
      return SudokuUnitInfo(
        SudokuUnitKind.diagonal,
        groupBase + (diagMain ? 1 : 2),
        firstLayer,
      );
    }
    return SudokuUnitInfo(SudokuUnitKind.region, groupBase, firstLayer);
  }

  /// 3D 的 units 来自三个面；rowOf/colOf 对 217 个去重格没有意义，
  /// 必须按 face 的局部坐标分类，X-Wing 才能落在同一面内。
  SudokuUnitInfo _classifyCubeUnit(Int32List cells) {
    final key = (List<int>.from(cells)..sort()).join(',');
    for (var fi = 0; fi < puzzle.cubeFaces.length; fi++) {
      final face = puzzle.cubeFaces[fi];
      for (var r = 0; r < 9; r++) {
        final row = [for (var c = 0; c < 9; c++) face.cellAt(r, c)]..sort();
        if (row.join(',') == key) {
          return SudokuUnitInfo(SudokuUnitKind.row, fi * 100000 + 1, fi);
        }
      }
      for (var c = 0; c < 9; c++) {
        final col = [for (var r = 0; r < 9; r++) face.cellAt(r, c)]..sort();
        if (col.join(',') == key) {
          return SudokuUnitInfo(SudokuUnitKind.col, fi * 100000 + 2, fi);
        }
      }
    }
    // 其余是某一面的 3×3 宫。
    var faceIndex = 0;
    for (var fi = 0; fi < puzzle.cubeFaces.length; fi++) {
      final face = puzzle.cubeFaces[fi];
      for (var br = 0; br < 3; br++) {
        for (var bc = 0; bc < 3; bc++) {
          final box = [
            for (var r = 0; r < 3; r++)
              for (var c = 0; c < 3; c++) face.cellAt(br * 3 + r, bc * 3 + c),
          ]..sort();
          if (box.join(',') == key) {
            faceIndex = fi;
            return SudokuUnitInfo(SudokuUnitKind.region, fi * 100000, fi);
          }
        }
      }
    }
    return SudokuUnitInfo(SudokuUnitKind.region, faceIndex * 100000, faceIndex);
  }

  int _signature(List<int> values) {
    var h = 17;
    for (final v in values) {
      h = h * 31 + v;
    }
    return h & 0x3fffffff;
  }

  /// 基础传播：赋值唯一化、单元隐单、笼和、不等式、奇偶。
  ///
  /// 返回 false 表示矛盾。这个函数是幂等的，循环到不动点。
  bool propagate(
    Int32List dom, {
    SolveStats? stats,
    bool countTechniques = false,
    int maxRounds = 2048,
  }) {
    var rounds = 0;
    var changed = true;
    while (changed) {
      if (++rounds > maxRounds) return false;
      changed = false;
      if (stats != null) stats.propagationSteps++;

      // 1. 单元内已赋值数字从其它候选剔除，并查重。
      for (final unit in units) {
        var used = 0;
        for (final cell in unit) {
          final m = dom[cell];
          if (m == 0) return false;
          if (isSingleBit(m)) {
            if (used & m != 0) return false;
            used |= m;
          }
        }
        if (used == 0) continue;
        for (final cell in unit) {
          final m = dom[cell];
          if (isSingleBit(m)) continue;
          final next = m & ~used;
          if (next != m) {
            if (next == 0) return false;
            dom[cell] = next;
            if (countTechniques && isSingleBit(next)) {
              stats?.nakedSingles++;
            }
            changed = true;
          }
        }
      }

      // 2. 单元隐单。
      for (final unit in units) {
        var used = 0;
        final counts = List<int>.filled(kDigitCount, 0);
        final where = List<int>.filled(kDigitCount, -1);
        for (final cell in unit) {
          final m = dom[cell];
          if (isSingleBit(m)) {
            used |= m;
          } else {
            for (var d = 0; d < kDigitCount; d++) {
              if (m & (1 << d) != 0) {
                counts[d]++;
                where[d] = cell;
              }
            }
          }
        }
        for (var d = 0; d < kDigitCount; d++) {
          final bit = 1 << d;
          if (used & bit != 0) continue;
          if (counts[d] == 0) return false;
          if (counts[d] == 1) {
            final cell = where[d];
            if (dom[cell] != bit) {
              dom[cell] = bit;
              if (countTechniques) stats?.hiddenSingles++;
              changed = true;
            }
          }
        }
      }

      // 3. 笼：去重、和上下界、唯一空格。
      for (final cage in cages) {
        var cageChanged = false;
        var used = 0;
        for (final cell in cage.cells) {
          final m = dom[cell];
          if (m == 0) return false;
          if (isSingleBit(m)) {
            if (used & m != 0) return false;
            used |= m;
          }
        }
        if (used != 0) {
          for (final cell in cage.cells) {
            final m = dom[cell];
            if (isSingleBit(m)) continue;
            final next = m & ~used;
            if (next != m) {
              if (next == 0) return false;
              dom[cell] = next;
              cageChanged = true;
            }
          }
        }

        var assignedSum = 0;
        var empty = 0;
        var minSum = 0;
        var maxSum = 0;
        var lastEmpty = -1;
        for (final cell in cage.cells) {
          final m = dom[cell];
          if (isSingleBit(m)) {
            assignedSum += bitValue(m);
          } else {
            empty++;
            lastEmpty = cell;
            final mn = minBitValue(m);
            final mx = maxBitValue(m);
            if (mn == 0 || mx == 0) return false;
            minSum += mn;
            maxSum += mx;
          }
        }
        if (empty == 0) {
          if (assignedSum != cage.sum) return false;
          continue;
        }
        if (assignedSum + minSum > cage.sum ||
            assignedSum + maxSum < cage.sum) {
          return false;
        }
        if (empty == 1) {
          final need = cage.sum - assignedSum;
          if (need < 1 || need > kDigitCount) return false;
          final bit = digitBit(need);
          if (dom[lastEmpty] & bit == 0) return false;
          if (dom[lastEmpty] != bit) {
            dom[lastEmpty] = bit;
            cageChanged = true;
          }
        } else {
          // 基础上下界裁剪：去掉会让剩余格无法凑出和的值。
          for (final cell in cage.cells) {
            final m = dom[cell];
            if (isSingleBit(m)) continue;
            final mn = minBitValue(m);
            final mx = maxBitValue(m);
            final othersMin = minSum - mn;
            final othersMax = maxSum - mx;
            var next = m;
            for (var d = 0; d < kDigitCount; d++) {
              final bit = 1 << d;
              if (m & bit == 0) continue;
              final remain = cage.sum - assignedSum - (d + 1);
              if (remain < othersMin || remain > othersMax) {
                next &= ~bit;
              }
            }
            if (next == 0) return false;
            if (next != m) {
              dom[cell] = next;
              cageChanged = true;
            }
          }
        }
        if (cageChanged) {
          changed = true;
          if (countTechniques) stats?.cageSteps++;
        }
      }

      // 4. 不等式。
      for (final (a, b) in edges) {
        final da = dom[a];
        final db = dom[b];
        if (da == 0 || db == 0) return false;
        var na = da;
        for (var d = 0; d < kDigitCount; d++) {
          final bit = 1 << d;
          if (da & bit == 0) continue;
          final greater = kAllDigitsMask & ~((1 << (d + 1)) - 1);
          if (db & greater == 0) na &= ~bit;
        }
        var nb = db;
        for (var d = 0; d < kDigitCount; d++) {
          final bit = 1 << d;
          if (db & bit == 0) continue;
          final less = (1 << d) - 1;
          if (da & less == 0) nb &= ~bit;
        }
        if (na == 0 || nb == 0) return false;
        if (na != da) {
          dom[a] = na;
          changed = true;
          if (countTechniques) stats?.edgeSteps++;
        }
        if (nb != db) {
          dom[b] = nb;
          changed = true;
          if (countTechniques) stats?.edgeSteps++;
        }
      }
    }
    return true;
  }

  bool boardHasNoConflict(Int32List dom) {
    for (final i in activeCells) {
      if (dom[i] == 0) return false;
    }
    return true;
  }

  List<int> solutionFromDomains(Int32List dom) {
    final out = List<int>.filled(cellCount, 0);
    for (final i in activeCells) {
      final m = dom[i];
      if (!isSingleBit(m)) continue;
      out[i] = bitValue(m);
    }
    return out;
  }
}

class SudokuSearch {
  SudokuSearch(this.index);

  final SudokuConstraintIndex index;

  /// 返回解的数量，最多数到 [limit]。超过节点预算时返回 -1。
  int countSolutions(Int32List initial, {int limit = 2, int? maxNodes}) {
    var nodes = 0;
    final state = Int32List.fromList(initial);
    int search(Int32List dom, int remainingLimit) {
      nodes++;
      if (maxNodes != null && nodes > maxNodes) return -1;
      if (!index.propagate(dom)) return 0;
      var best = -1;
      var bestCount = 10;
      for (final cell in index.activeCells) {
        final m = dom[cell];
        if (m == 0) return 0;
        if (isSingleBit(m)) continue;
        final c = popCount9(m);
        if (c < bestCount) {
          bestCount = c;
          best = cell;
          if (c == 2) break;
        }
      }
      if (best < 0) return 1;
      var total = 0;
      final mask = dom[best];
      for (var d = 0; d < kDigitCount; d++) {
        final bit = 1 << d;
        if (mask & bit == 0) continue;
        final next = Int32List.fromList(dom);
        next[best] = bit;
        final got = search(next, remainingLimit - total);
        if (got < 0) return -1;
        total += got;
        if (total >= remainingLimit) break;
      }
      return total;
    }

    final result = search(state, limit);
    return result;
  }

  /// 找一解。传 [random] 时在分支处随机化数字顺序。
  List<int>? findSolution(
    Int32List initial, {
    math.Random? random,
    int? maxNodes,
  }) {
    var nodes = 0;
    final state = Int32List.fromList(initial);

    List<int>? search(Int32List dom) {
      nodes++;
      if (maxNodes != null && nodes > maxNodes) return null;
      if (!index.propagate(dom)) return null;
      var best = -1;
      var bestCount = 10;
      for (final cell in index.activeCells) {
        final m = dom[cell];
        if (m == 0) return null;
        if (isSingleBit(m)) continue;
        final c = popCount9(m);
        if (c < bestCount) {
          bestCount = c;
          best = cell;
          if (c == 2) break;
        }
      }
      if (best < 0) return index.solutionFromDomains(dom);

      final digits = <int>[];
      final mask = dom[best];
      for (var d = 0; d < kDigitCount; d++) {
        if (mask & (1 << d) != 0) digits.add(1 << d);
      }
      if (random != null) {
        digits.shuffle(random);
      }
      for (final bit in digits) {
        final next = Int32List.fromList(dom);
        next[best] = bit;
        final got = search(next);
        if (got != null) return got;
      }
      return null;
    }

    return search(state);
  }
}
