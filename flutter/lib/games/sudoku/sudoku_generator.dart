import 'dart:math' as math;

import 'sudoku_constraints.dart';
import 'sudoku_grader.dart';
import 'sudoku_layouts.dart';
import 'sudoku_modes.dart';
import 'sudoku_puzzle.dart';

class _Candidate {
  const _Candidate(this.puzzle, this.rating, this.passed);

  final SudokuPuzzle puzzle;
  final SudokuRating rating;
  final bool passed;
}

/// 统一出题器：先构造满解，再挖洞并逐次复核唯一解，最后用技巧/搜索评级。
class SudokuGenerator {
  const SudokuGenerator._();

  static SudokuPuzzle generate(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty, {
    int? seed,
  }) {
    final rnd = math.Random(seed ?? math.Random().nextInt(1 << 31));
    _Candidate? best;
    final attempts = _attempts(mode);
    for (var attempt = 0; attempt < attempts; attempt++) {
      final candidate = mode.key == 'windmill'
          ? _windmill(difficulty, rnd)
          : switch (mode.variant) {
              SudokuVariant.classic => _classic(mode, difficulty, rnd),
              SudokuVariant.jigsaw => _jigsaw(mode, difficulty, rnd),
              SudokuVariant.overlap => _overlap(mode, difficulty, rnd),
              SudokuVariant.evenOdd => _evenOdd(mode, difficulty, rnd),
              SudokuVariant.diagonal => _diagonal(mode, difficulty, rnd),
              SudokuVariant.inequality => _inequality(mode, difficulty, rnd),
              SudokuVariant.killer => _killer(mode, difficulty, rnd),
              SudokuVariant.cube3d => _cube3d(mode, difficulty, rnd),
              // 雪花已由模式目录移除；旧变体不再出题，保留枚举也不影响。
              _ => null,
            };
      if (candidate == null) continue;
      if (best == null ||
          candidate.rating.tier > best.rating.tier ||
          (candidate.rating.tier == best.rating.tier &&
              candidate.rating.score > best.rating.score)) {
        best = candidate;
      }
      if (candidate.passed) return candidate.puzzle;
    }
    // 随机种子下偶尔没有完全达标局；返回当前最好的一局，保证页面可玩。
    if (best != null) return best.puzzle;
    throw StateError('无法生成 ${mode.title} · ${difficulty.label}，请稍后重试');
  }

  static int _attempts(SudokuModeSpec mode) {
    if (mode.key == 'windmill') return 8;
    if (mode.isOverlap) return mode.overlapCount >= 5 ? 20 : 30;
    if (mode.variant == SudokuVariant.cube3d) return 24;
    if (mode.variant == SudokuVariant.killer) return 80;
    if (mode.variant == SudokuVariant.classic) return 120;
    return 80;
  }

  static int _requiredLevel(SudokuModeSpec mode, SudokuDifficulty difficulty) {
    if (mode.key == 'windmill') {
      // 与 overlap-5 同一挖洞档位：结构决定 expert，不强制高级技巧，
      // 避免随机种子触发多次重挖/重评级。
      return 0;
    }
    switch (mode.variant) {
      case SudokuVariant.classic:
        return switch (difficulty) {
          SudokuDifficulty.easy => 0,
          SudokuDifficulty.medium => 1,
          SudokuDifficulty.hard => 2,
          SudokuDifficulty.expert => 3,
        };
      case SudokuVariant.jigsaw:
        return switch (difficulty) {
          SudokuDifficulty.medium => 1,
          SudokuDifficulty.hard => 2,
          SudokuDifficulty.expert => 3,
          _ => 1,
        };
      case SudokuVariant.evenOdd:
        return difficulty == SudokuDifficulty.expert ? 2 : 1;
      case SudokuVariant.diagonal:
        return difficulty == SudokuDifficulty.expert ? 4 : 1;
      case SudokuVariant.inequality:
        return difficulty == SudokuDifficulty.expert ? 4 : 1;
      case SudokuVariant.killer:
        return difficulty == SudokuDifficulty.expert ? 3 : 2;
      case SudokuVariant.cube3d:
        // 三面立方本身约束强；hard 允许基础技巧，expert 要求高级技巧/猜测。
        return difficulty == SudokuDifficulty.expert ? 2 : 0;
      case SudokuVariant.overlap:
        // 大棋盘按尺寸计难度；不再强制高级技巧，避免 13 重叠无法出题。
        return 0;
      default:
        // 雪花已移除；未知变体不强制技巧。
        return 0;
    }
  }

  /// 上限让四档真正分开：困难不靠猜测，专家才允许 X-Wing/猜测。
  static int? _maxLevel(SudokuModeSpec mode, SudokuDifficulty difficulty) {
    if (mode.key == 'windmill') {
      // 多盘结构本身决定档位；不因随机种子出现猜测而整局降档。
      return null;
    }
    switch (mode.variant) {
      case SudokuVariant.classic:
        return switch (difficulty) {
          SudokuDifficulty.easy => 1,
          SudokuDifficulty.medium => 2,
          SudokuDifficulty.hard => 3,
          SudokuDifficulty.expert => null,
        };
      case SudokuVariant.jigsaw:
        return switch (difficulty) {
          SudokuDifficulty.medium => 2,
          SudokuDifficulty.hard => 3,
          SudokuDifficulty.expert => null,
          _ => 2,
        };
      case SudokuVariant.evenOdd:
      case SudokuVariant.diagonal:
      case SudokuVariant.inequality:
        return difficulty == SudokuDifficulty.expert ? null : 3;
      case SudokuVariant.killer:
        return difficulty == SudokuDifficulty.expert ? null : 3;
      case SudokuVariant.cube3d:
        // 大结构变体按 mode 档位评级，不用技巧上限反复卡随机种子。
        return null;
      case SudokuVariant.overlap:
        return null;
      default:
        return null;
    }
  }

  /// 对外暴露目标档，测试与 UI 都可以核对“这局是否达到标称难度”。
  static int targetTier(SudokuModeSpec mode, SudokuDifficulty difficulty) =>
      _targetTier(mode, difficulty);

  static int _targetTier(SudokuModeSpec mode, SudokuDifficulty difficulty) {
    if (mode.key == 'windmill') return difficulty.tier;
    if (mode.variant == SudokuVariant.jigsaw) {
      return difficulty.tier;
    }
    if (mode.variant == SudokuVariant.overlap) {
      return mode.overlapCount >= 4 ? 3 : 2;
    }
    return difficulty.tier;
  }

  static _Candidate? _finalize(
    SudokuPuzzle base,
    List<int> givens,
    SudokuDifficulty difficulty,
    int targetTier, {
    int minLevel = 0,
    int? maxLevel,
  }) {
    final puzzle = base.copyWith(givens: givens, difficulty: difficulty);
    final rating = const SudokuGrader().rate(puzzle);
    // 简单/中等/困难尽量精确落在本档；专家允许更高。未完全达标时仍返回候选，
    // 由 generate 在所有尝试结束后挑选最好的一局，避免随机种子导致整局失败。
    final tierOk = targetTier >= 3
        ? rating.tier >= targetTier
        : rating.tier == targetTier;
    final passed =
        tierOk &&
        rating.techniqueLevel >= minLevel &&
        (maxLevel == null || rating.techniqueLevel <= maxLevel);
    return _Candidate(
      puzzle.copyWith(difficultyScore: rating.score, difficultyMet: passed),
      rating,
      passed,
    );
  }

  static int _targetClues(SudokuModeSpec mode, SudokuDifficulty difficulty) {
    switch (mode.variant) {
      case SudokuVariant.classic:
        return switch (difficulty) {
          SudokuDifficulty.easy => 42,
          SudokuDifficulty.medium => 34,
          SudokuDifficulty.hard => 28,
          SudokuDifficulty.expert => 24,
        };
      case SudokuVariant.jigsaw:
        return switch (difficulty) {
          SudokuDifficulty.medium => 30,
          SudokuDifficulty.hard => 26,
          SudokuDifficulty.expert => 22,
          _ => 30,
        };
      case SudokuVariant.overlap:
        // 重叠盘/风车按 activeCount 在各自分支里计算，这里不使用。
        return 0;
      case SudokuVariant.evenOdd:
        return difficulty == SudokuDifficulty.expert ? 24 : 26;
      case SudokuVariant.diagonal:
        return difficulty == SudokuDifficulty.expert ? 24 : 28;
      case SudokuVariant.inequality:
        return difficulty == SudokuDifficulty.expert ? 24 : 29;
      case SudokuVariant.killer:
        return difficulty == SudokuDifficulty.expert ? 0 : 5;
      case SudokuVariant.cube3d:
        // 三面立方在 _cube3d 里按 217 格另行计算。
        return 0;
      default:
        return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // 经典 / 异形 / 雪花
  // ---------------------------------------------------------------------------

  static _Candidate? _classic(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty,
    math.Random rnd,
  ) {
    final solution = _randomClassicSolution(rnd);
    final base = _buildPuzzle(
      variant: SudokuVariant.classic,
      difficulty: difficulty,
      solution: solution,
      givens: List<int>.filled(81, 0),
      regionOf: standardRegions(),
      active: List<bool>.filled(81, true),
      units: classicUnits(),
    );
    final givens = _dig(
      base,
      rnd,
      targetClues: _targetClues(mode, difficulty),
      batch: 1,
      maxNodes: 90000,
    );
    return _finalize(
      base,
      givens,
      difficulty,
      difficulty.tier,
      minLevel: _requiredLevel(mode, difficulty),
      maxLevel: _maxLevel(mode, difficulty),
    );
  }

  static _Candidate? _jigsaw(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty,
    math.Random rnd,
  ) {
    final layout = randomJigsawLayout(rnd);
    if (!regionsMatchSolution(layout.regions, layout.solution)) return null;
    final base = _buildPuzzle(
      variant: SudokuVariant.jigsaw,
      difficulty: difficulty,
      solution: layout.solution,
      givens: List<int>.filled(81, 0),
      regionOf: layout.regions,
      active: List<bool>.filled(81, true),
      units: [...classicUnits().take(18), ...regionUnits(layout.regions)],
    );
    final givens = _dig(
      base,
      rnd,
      targetClues: _targetClues(mode, difficulty),
      batch: 1,
      maxNodes: 120000,
    );
    return _finalize(
      base,
      givens,
      difficulty,
      _targetTier(mode, difficulty),
      minLevel: _requiredLevel(mode, difficulty),
      maxLevel: _maxLevel(mode, difficulty),
    );
  }

  // ---------------------------------------------------------------------------
  // 重叠 / 风车
  // ---------------------------------------------------------------------------

  static _Candidate? _overlap(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty,
    math.Random rnd,
  ) {
    final count = mode.overlapCount;
    final layout = overlapLayout(count);
    final active = overlapActive(layout.grids, layout.rows, layout.cols);
    final raw = overlapSolution(layout.rows, layout.cols);
    final digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(rnd);
    final solution = [
      for (var i = 0; i < raw.length; i++) active[i] ? digits[raw[i] - 1] : 0,
    ];
    final base = _buildPuzzle(
      variant: SudokuVariant.overlap,
      difficulty: difficulty,
      overlapCount: count,
      rows: layout.rows,
      cols: layout.cols,
      solution: solution,
      givens: List<int>.filled(raw.length, 0),
      regionOf: List<int>.filled(raw.length, -1),
      active: active,
      grids: layout.grids,
      units: overlapUnits(layout.grids, layout.rows, layout.cols),
    );
    final ratio = switch (count) {
      2 || 3 => .58,
      4 => .55,
      5 || 8 => .52,
      13 => .56,
      _ => .55,
    };
    final target = (base.activeCount * ratio).round();
    final givens = _dig(
      base,
      rnd,
      targetClues: target,
      batch: count >= 5 ? 12 : 6,
      maxNodes: 220000,
    );
    return _finalize(base, givens, difficulty, _targetTier(mode, difficulty));
  }

  /// 风车：独立 mode（key=windmill），按参考图一采用五盘风车式错位
  /// （中心 + 四个外盘共享 3×6，21×21，active 333）；与 overlap-5 的
  /// Samurai 四角布局不同。[SudokuPuzzle.windmill] 区分两者。
  static _Candidate? _windmill(SudokuDifficulty difficulty, math.Random rnd) {
    final layout = windmillLayout();
    final active = overlapActive(layout.grids, layout.rows, layout.cols);
    final raw = overlapSolution(layout.rows, layout.cols);
    final digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(rnd);
    final solution = [
      for (var i = 0; i < raw.length; i++) active[i] ? digits[raw[i] - 1] : 0,
    ];
    final base = _buildPuzzle(
      variant: SudokuVariant.overlap,
      difficulty: difficulty,
      overlapCount: 5,
      rows: layout.rows,
      cols: layout.cols,
      solution: solution,
      givens: List<int>.filled(raw.length, 0),
      regionOf: List<int>.filled(raw.length, -1),
      active: active,
      grids: layout.grids,
      units: overlapUnits(layout.grids, layout.rows, layout.cols),
      windmill: true,
    );
    // 复用 overlap-5 的快速挖洞路径：专家约 55% 提示（369×0.55≈203），
    // 远离“局部最小”唯一解边界；最小化挖洞曾在个别 seed 上 >60s。
    // 这里只挖到固定提示量，随后交给 _finalize 做一次评级。
    final ratio = difficulty == SudokuDifficulty.expert ? .55 : .60;
    final target = (base.activeCount * ratio).round();
    final givens = _dig(
      base,
      rnd,
      targetClues: target,
      batch: 12,
      maxNodes: 220000,
    );
    return _finalize(base, givens, difficulty, difficulty.tier);
  }

  // ---------------------------------------------------------------------------
  // 高级阶数
  // ---------------------------------------------------------------------------

  static _Candidate? _evenOdd(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty,
    math.Random rnd,
  ) {
    final solution = _randomClassicSolution(rnd);
    // 参考图五：只标一部分格（40–55），未标记格不限奇偶。
    // 固定 48 格，奇偶各取一半，避免随机种子把某一种标记抽空。
    const markedCount = 48;
    final evenPool = <int>[
      for (var i = 0; i < 81; i++)
        if (solution[i].isEven) i,
    ]..shuffle(rnd);
    final oddPool = <int>[
      for (var i = 0; i < 81; i++)
        if (solution[i].isOdd) i,
    ]..shuffle(rnd);
    final even = evenPool.take(markedCount ~/ 2).toSet();
    final odd = oddPool.take(markedCount - even.length).toSet();
    final base = _buildPuzzle(
      variant: SudokuVariant.evenOdd,
      difficulty: difficulty,
      solution: solution,
      givens: List<int>.filled(81, 0),
      regionOf: standardRegions(),
      active: List<bool>.filled(81, true),
      units: classicUnits(),
      evenCells: even,
      oddCells: odd,
    );
    final givens = _dig(
      base,
      rnd,
      targetClues: _targetClues(mode, difficulty),
      batch: 1,
      maxNodes: 120000,
    );
    return _finalize(
      base,
      givens,
      difficulty,
      difficulty.tier,
      minLevel: _requiredLevel(mode, difficulty),
      maxLevel: _maxLevel(mode, difficulty),
    );
  }

  static _Candidate? _diagonal(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty,
    math.Random rnd,
  ) {
    final units = classicUnits(diagonal: true);
    final solution = _solveFull(units, rnd, standardRegions());
    if (solution == null) return null;
    final permuted = digitsPermuted(solution, rnd);
    final base = _buildPuzzle(
      variant: SudokuVariant.diagonal,
      difficulty: difficulty,
      solution: permuted,
      givens: List<int>.filled(81, 0),
      regionOf: standardRegions(),
      active: List<bool>.filled(81, true),
      units: units,
    );
    final givens = _dig(
      base,
      rnd,
      targetClues: _targetClues(mode, difficulty),
      batch: 1,
      maxNodes: 120000,
    );
    return _finalize(
      base,
      givens,
      difficulty,
      difficulty.tier,
      minLevel: _requiredLevel(mode, difficulty),
      maxLevel: _maxLevel(mode, difficulty),
    );
  }

  static _Candidate? _inequality(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty,
    math.Random rnd,
  ) {
    final solution = _randomClassicSolution(rnd);
    final edges = _randomEdges(solution, rnd, 34);
    final base = _buildPuzzle(
      variant: SudokuVariant.inequality,
      difficulty: difficulty,
      solution: solution,
      givens: List<int>.filled(81, 0),
      regionOf: standardRegions(),
      active: List<bool>.filled(81, true),
      units: classicUnits(),
      inequalities: edges,
    );
    final givens = _dig(
      base,
      rnd,
      targetClues: _targetClues(mode, difficulty),
      batch: 1,
      maxNodes: 140000,
    );
    return _finalize(
      base,
      givens,
      difficulty,
      difficulty.tier,
      minLevel: _requiredLevel(mode, difficulty),
      maxLevel: _maxLevel(mode, difficulty),
    );
  }

  static _Candidate? _killer(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty,
    math.Random rnd,
  ) {
    final solution = _randomClassicSolution(rnd);
    final cages = _randomCages(
      solution,
      rnd,
      minSize: 2,
      maxSize: difficulty == SudokuDifficulty.expert ? 4 : 3,
    );
    final base = _buildPuzzle(
      variant: SudokuVariant.killer,
      difficulty: difficulty,
      solution: solution,
      givens: List<int>.filled(81, 0),
      regionOf: standardRegions(),
      active: List<bool>.filled(81, true),
      units: classicUnits(),
      cages: cages,
    );
    final checker = _UniqueChecker(base);
    final givens = List<int>.filled(81, 0);
    var unique = checker.isUnique(givens, maxNodes: 220000);
    if (!unique) {
      final order = List<int>.generate(81, (i) => i)..shuffle(rnd);
      for (final i in order) {
        givens[i] = solution[i];
        if (checker.isUnique(givens, maxNodes: 220000)) {
          unique = true;
          break;
        }
        if (givens.where((v) => v != 0).length >= 10) break;
      }
    }
    if (!unique) return null;
    if (difficulty == SudokuDifficulty.hard) {
      // 困难档留少量提示，专家档保持纯杀手。
      final empty = List<int>.generate(81, (i) => i)
        ..removeWhere((i) => givens[i] != 0)
        ..shuffle(rnd);
      for (var i = 0; i < 5 && i < empty.length; i++) {
        givens[empty[i]] = solution[empty[i]];
      }
    }
    return _finalize(
      base,
      givens,
      difficulty,
      difficulty.tier,
      minLevel: _requiredLevel(mode, difficulty),
      maxLevel: _maxLevel(mode, difficulty),
    );
  }

  /// 3D 三面立方：top / frontLeft / frontRight 各 9×9，共享边去重后 217 格。
  /// 满解取固定模板 + 数字置换，再逐格挖洞并复核唯一解；彩色环带只是视觉。
  static _Candidate? _cube3d(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty,
    math.Random rnd,
  ) {
    final layout = cubeFaceLayout();
    final raw = decodeSolution(
      kCubeFaceSolutions[rnd.nextInt(kCubeFaceSolutions.length)],
    );
    final digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(rnd);
    final solution = [for (final v in raw) digits[v - 1]];
    final base = _buildPuzzle(
      variant: SudokuVariant.cube3d,
      difficulty: difficulty,
      rows: 9,
      cols: 9,
      layers: 1,
      cellCountOverride: layout.cellCount,
      solution: solution,
      givens: List<int>.filled(layout.cellCount, 0),
      regionOf: layout.regions,
      active: List<bool>.filled(layout.cellCount, true),
      cubeFaces: layout.faces,
      units: layout.units,
    );
    final target = difficulty == SudokuDifficulty.expert ? 0 : 96;
    final givens = _dig(
      base,
      rnd,
      targetClues: target,
      batch: 6,
      maxNodes: 320000,
    );
    return _finalize(
      base,
      givens,
      difficulty,
      difficulty.tier,
      minLevel: _requiredLevel(mode, difficulty),
      maxLevel: _maxLevel(mode, difficulty),
    );
  }

  // ---------------------------------------------------------------------------
  // 通用
  // ---------------------------------------------------------------------------

  static List<int> _randomClassicSolution(math.Random rnd) {
    final digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(rnd);
    final base = [for (final v in standardSolution()) digits[v - 1]];
    return permuteGrid(base, 9, bandRows(rnd), bandCols(rnd));
  }

  static List<int>? _solveFull(
    List<List<int>> units,
    math.Random rnd,
    List<int> regions,
  ) {
    final base = SudokuPuzzle(
      variant: SudokuVariant.jigsaw,
      difficulty: SudokuDifficulty.expert,
      overlapCount: 0,
      rows: 9,
      cols: 9,
      layers: 1,
      solution: List<int>.filled(81, 0),
      givens: List<int>.filled(81, 0),
      regionOf: regions,
      active: List<bool>.filled(81, true),
      grids: const [],
      units: units,
    );
    final index = SudokuConstraintIndex(base);
    final dom = index.initialDomains();
    if (dom == null) return null;
    return SudokuSearch(index).findSolution(dom, random: rnd, maxNodes: 300000);
  }

  static SudokuPuzzle _buildPuzzle({
    required SudokuVariant variant,
    required SudokuDifficulty difficulty,
    required List<int> solution,
    required List<int> givens,
    required List<int> regionOf,
    required List<bool> active,
    required List<List<int>> units,
    int overlapCount = 0,
    int rows = 9,
    int cols = 9,
    int layers = 1,
    List<SudokuSubGrid> grids = const [],
    List<SudokuCage> cages = const [],
    List<SudokuEdge> inequalities = const [],
    Set<int> evenCells = const {},
    Set<int> oddCells = const {},
    bool windmill = false,
    List<SudokuCubeFaceMap> cubeFaces = const [],
    int? cellCountOverride,
  }) => SudokuPuzzle(
    variant: variant,
    difficulty: difficulty,
    overlapCount: overlapCount,
    rows: rows,
    cols: cols,
    layers: layers,
    solution: solution,
    givens: givens,
    regionOf: regionOf,
    active: active,
    grids: grids,
    units: units,
    cages: cages,
    inequalities: inequalities,
    evenCells: evenCells,
    oddCells: oddCells,
    windmill: windmill,
    cubeFaces: cubeFaces,
    cellCountOverride: cellCountOverride,
  );

  static List<int> _dig(
    SudokuPuzzle base,
    math.Random rnd, {
    required int targetClues,
    int batch = 1,
    int maxNodes = 120000,
  }) {
    final checker = _UniqueChecker(base);
    final givens = List<int>.from(base.solution);
    for (var i = 0; i < givens.length; i++) {
      if (!base.isActive(i)) givens[i] = 0;
    }
    final order = [
      for (var i = 0; i < givens.length; i++)
        if (base.isActive(i) && givens[i] != 0) i,
    ]..shuffle(rnd);
    var clues = order.length;
    final step = math.max(1, batch);

    for (var start = 0; start < order.length; start += step) {
      if (clues <= targetClues) break;
      final take = <int>[];
      for (var j = start; j < order.length && take.length < step; j++) {
        final i = order[j];
        if (givens[i] != 0) take.add(i);
      }
      if (take.isEmpty) continue;
      final old = <int, int>{for (final i in take) i: givens[i]};
      for (final i in take) {
        givens[i] = 0;
      }
      if (checker.isUnique(givens, maxNodes: maxNodes)) {
        clues -= take.length;
      } else {
        for (final entry in old.entries) {
          givens[entry.key] = entry.value;
        }
      }
    }

    if (clues > targetClues) {
      for (final i in order) {
        if (clues <= targetClues) break;
        if (givens[i] == 0) continue;
        final old = givens[i];
        givens[i] = 0;
        if (checker.isUnique(givens, maxNodes: maxNodes)) {
          clues--;
        } else {
          givens[i] = old;
        }
      }
    }
    return givens;
  }

  static List<SudokuEdge> _randomEdges(
    List<int> solution,
    math.Random rnd,
    int count,
  ) {
    final candidates = <SudokuEdge>[];
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        final i = r * 9 + c;
        if (c < 8) {
          final j = i + 1;
          candidates.add(
            solution[i] < solution[j] ? SudokuEdge(i, j) : SudokuEdge(j, i),
          );
        }
        if (r < 8) {
          final j = i + 9;
          candidates.add(
            solution[i] < solution[j] ? SudokuEdge(i, j) : SudokuEdge(j, i),
          );
        }
      }
    }
    candidates.shuffle(rnd);
    return candidates.take(count).toList(growable: false);
  }

  static List<SudokuCage> _randomCages(
    List<int> solution,
    math.Random rnd, {
    required int minSize,
    required int maxSize,
  }) {
    final assigned = List<bool>.filled(81, false);
    final cages = <SudokuCage>[];
    final order = List<int>.generate(81, (i) => i)..shuffle(rnd);
    for (final seed in order) {
      if (assigned[seed]) continue;
      final target = minSize + rnd.nextInt(math.max(1, maxSize - minSize + 1));
      final cells = <int>[seed];
      final usedValues = <int>{solution[seed]};
      assigned[seed] = true;
      while (cells.length < target) {
        final candidates = <int>[];
        for (final i in cells) {
          final r = i ~/ 9;
          final c = i % 9;
          for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final nr = r + dr;
            final nc = c + dc;
            if (nr < 0 || nr >= 9 || nc < 0 || nc >= 9) continue;
            final ni = nr * 9 + nc;
            if (!assigned[ni] && !usedValues.contains(solution[ni])) {
              candidates.add(ni);
            }
          }
        }
        if (candidates.isEmpty) break;
        candidates.shuffle(rnd);
        final next = candidates.first;
        assigned[next] = true;
        usedValues.add(solution[next]);
        cells.add(next);
      }
      var sum = 0;
      for (final i in cells) {
        sum += solution[i];
      }
      cages.add(SudokuCage(cells: cells, sum: sum));
    }
    return cages;
  }
}

class _UniqueChecker {
  _UniqueChecker(SudokuPuzzle puzzle) : index = SudokuConstraintIndex(puzzle);

  final SudokuConstraintIndex index;

  bool isUnique(List<int> board, {int maxNodes = 120000}) {
    final dom = index.initialDomains(board: board, useGivens: false);
    if (dom == null) return false;
    final count = SudokuSearch(index)
        .countSolutions(dom, limit: 2, maxNodes: maxNodes);
    return count == 1;
  }
}
