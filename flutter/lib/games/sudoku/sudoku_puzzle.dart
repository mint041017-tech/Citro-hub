import 'sudoku_modes.dart';

/// 一个 9×9 子盘在全局棋盘中的位置。重叠数独用它描述每个子盘。
class SudokuSubGrid {
  const SudokuSubGrid({required this.top, required this.left, this.size = 9});

  final int top;
  final int left;
  final int size;

  @override
  String toString() => 'SudokuSubGrid($top,$left,$size)';
}

/// 杀手数独笼：cells 为全局索引，笼内数字互不重复且和等于 [sum]。
class SudokuCage {
  const SudokuCage({required this.cells, required this.sum});

  final List<int> cells;
  final int sum;
}

/// 不等式边：value[a] < value[b]。
class SudokuEdge {
  const SudokuEdge(this.a, this.b);

  final int a;
  final int b;
}

/// 3D 三面立方的可见面。三面共享边上的物理格只存一份。
enum SudokuCubeFace { top, frontLeft, frontRight }

/// 一个可见面的局部坐标到全局 cell 索引的映射。
///
/// [cells] 长度 81，`cells[r * 9 + c]` 是该面 (r,c) 的全局索引。
/// 共享边两侧返回同一个全局索引，因此天然满足“共享边同数”。
class SudokuCubeFaceMap {
  const SudokuCubeFaceMap({
    required this.face,
    required this.cells,
    required this.sharedEdgeCells,
  });

  final SudokuCubeFace face;
  final List<int> cells;

  /// 该面位于共享边上的局部索引（r*9+c），用于 UI 描粗边。
  final Set<int> sharedEdgeCells;

  int cellAt(int row, int col) => cells[row * 9 + col];

  bool isShared(int row, int col) => sharedEdgeCells.contains(row * 9 + col);
}

/// 一个全局 cell 在某个面上的局部坐标；共享边格会有两个 ref。
class SudokuCubeCellRef {
  const SudokuCubeCellRef(this.face, this.row, this.col);

  final SudokuCubeFace face;
  final int row;
  final int col;

  @override
  String toString() => 'SudokuCubeCellRef(${face.name},$row,$col)';
}

/// 一道已出好的数独题。
///
/// 索引约定：index = layer * rows * cols + row * cols + col。
/// - 经典/异形/高级阶数：layers = 1，rows = cols = 9。
/// - 重叠数独/风车：layers = 1，rows/cols 为所有子盘的包围盒，
///   active 标记真正参与的子盘覆盖格；风车额外置 [windmill]。
/// - 3D 三面立方：rows = cols = 9，layers = 1，物理格去重后
///   [cellCount] = 217（用 [cellCountOverride] 覆盖矩形乘积），
///   面内坐标必须走 [cubeFaces]，不能再用 rowOf/colOf 猜面。
///
/// inactive 格子的 solution/givens 固定为 0，regionOf 为 -1。
class SudokuPuzzle {
  const SudokuPuzzle({
    required this.variant,
    required this.difficulty,
    required this.overlapCount,
    required this.rows,
    required this.cols,
    required this.layers,
    required this.solution,
    required this.givens,
    required this.regionOf,
    required this.active,
    required this.grids,
    required this.units,
    this.cages = const [],
    this.inequalities = const [],
    this.evenCells = const {},
    this.oddCells = const {},
    this.difficultyScore = 0,
    this.difficultyMet = true,
    this.windmill = false,
    this.cubeFaces = const [],
    this.cellCountOverride,
  });

  final SudokuVariant variant;
  final SudokuDifficulty difficulty;
  final int overlapCount;
  final int rows;
  final int cols;
  final int layers;

  /// 完整解，长度 = cellCount。
  final List<int> solution;

  /// 题面，0 表示空格。长度 = cellCount。
  final List<int> givens;

  /// 每格所属区域；异形/经典为 0–8，3D 三面为 0–26，重叠为 -1。
  final List<int> regionOf;

  /// 该格是否参与游戏。重叠数独的包围盒内可能存在不参与格。
  final List<bool> active;

  /// 重叠数独的各个 9×9 子盘；其他模式为空。
  final List<SudokuSubGrid> grids;

  /// 全部 9 格约束单元（行、列、区域、对角线、重叠子盘、3D 面等）。
  /// 求解、提示、冲突检测都只依赖这一份定义。
  final List<List<int>> units;

  final List<SudokuCage> cages;
  final List<SudokuEdge> inequalities;
  final Set<int> evenCells;
  final Set<int> oddCells;

  /// 人类技巧评级分数，生成时写入，可直接展示/排序。
  final int difficultyScore;

  /// 生成器是否真的达到了 mode+difficulty 的标称档。
  ///
  /// 极端随机种子下生成器可能退回当前最好的一局；此时为 false，
  /// UI 应明确提示“本局难度未达标”或允许重开，而不是静默当作标称档。
  final bool difficultyMet;

  /// 风车模式：variant 仍为 [SudokuVariant.overlap]，但它是独立玩法/排行榜。
  final bool windmill;

  /// 3D 三面立方的面映射；其他模式为空。
  final List<SudokuCubeFaceMap> cubeFaces;

  /// 非矩形棋盘的真实格数；null 时按 rows*cols*layers 计算。
  final int? cellCountOverride;

  int get cellCount => cellCountOverride ?? rows * cols * layers;

  bool get isCube3d => variant == SudokuVariant.cube3d;

  bool get isWindmill => windmill;

  int get activeCount {
    var n = 0;
    for (final a in active) {
      if (a) n++;
    }
    return n;
  }

  int indexOf(int layer, int row, int col) =>
      layer * rows * cols + row * cols + col;

  int layerOf(int index) => index ~/ (rows * cols);

  int rowOf(int index) => (index % (rows * cols)) ~/ cols;

  int colOf(int index) => index % cols;

  /// 3D 面内坐标 → 全局索引。共享边两侧返回同一索引。
  int cubeIndex(SudokuCubeFace face, int row, int col) {
    for (final map in cubeFaces) {
      if (map.face == face) return map.cellAt(row, col);
    }
    throw ArgumentError('cube face ${face.name} not found');
  }

  /// 一个全局格对应的所有面内坐标；共享边格返回两个 ref。
  List<SudokuCubeCellRef> cubeRefsOf(int index) {
    final refs = <SudokuCubeCellRef>[];
    for (final map in cubeFaces) {
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          if (map.cells[r * 9 + c] == index) {
            refs.add(SudokuCubeCellRef(map.face, r, c));
          }
        }
      }
    }
    return refs;
  }

  bool isActive(int index) =>
      index >= 0 && index < active.length && active[index];

  SudokuPuzzle copyWith({
    SudokuDifficulty? difficulty,
    List<int>? givens,
    List<int>? solution,
    int? difficultyScore,
    bool? difficultyMet,
  }) {
    return SudokuPuzzle(
      variant: variant,
      difficulty: difficulty ?? this.difficulty,
      overlapCount: overlapCount,
      rows: rows,
      cols: cols,
      layers: layers,
      solution: solution ?? this.solution,
      givens: givens ?? this.givens,
      regionOf: regionOf,
      active: active,
      grids: grids,
      units: units,
      cages: cages,
      inequalities: inequalities,
      evenCells: evenCells,
      oddCells: oddCells,
      difficultyScore: difficultyScore ?? this.difficultyScore,
      difficultyMet: difficultyMet ?? this.difficultyMet,
      windmill: windmill,
      cubeFaces: cubeFaces,
      cellCountOverride: cellCountOverride,
    );
  }

  /// 仅用于调试/题库导出的紧凑描述。
  Map<String, Object?> toJson() => {
    'variant': variant.name,
    'difficulty': difficulty.name,
    'overlap': overlapCount,
    'windmill': windmill,
    'rows': rows,
    'cols': cols,
    'layers': layers,
    'cellCount': cellCount,
    'score': difficultyScore,
    'difficultyMet': difficultyMet,
    'solution': solution.join(','),
    'givens': givens.join(','),
    'regionOf': regionOf.join(','),
    'active': active.map((e) => e ? '1' : '0').join(),
    'grids': [for (final g in grids) '${g.top},${g.left},${g.size}'],
    'cubeFaces': [
      for (final f in cubeFaces) '${f.face.name}:${f.cells.join(".")}',
    ],
    'cages': [for (final c in cages) '${c.sum}:${c.cells.join('.')}'],
    'inequalities': [for (final e in inequalities) '${e.a},${e.b}'],
    'even': (evenCells.toList()..sort()).join(','),
    'odd': (oddCells.toList()..sort()).join(','),
    'units': units.length,
  };

  @override
  String toString() =>
      'SudokuPuzzle(${variant.name}, ${difficulty.name}, '
      '${rows}x${cols}x$layers, clues=${givens.where((v) => v != 0).length}, '
      'score=$difficultyScore)';
}
