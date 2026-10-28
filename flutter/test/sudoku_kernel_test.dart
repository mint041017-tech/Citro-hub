import 'package:citro/games/sudoku/sudoku_kernel.dart';
import 'package:flutter_test/flutter_test.dart';

bool _connected(List<int> cells, int cols, int rows) {
  if (cells.isEmpty) return true;
  final set = cells.toSet();
  final seen = <int>{cells.first};
  final queue = <int>[cells.first];
  while (queue.isNotEmpty) {
    final i = queue.removeLast();
    final r = i ~/ cols;
    final c = i % cols;
    for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nr = r + dr;
      final nc = c + dc;
      if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
      final ni = nr * cols + nc;
      if (!set.contains(ni) || !seen.add(ni)) continue;
      queue.add(ni);
    }
  }
  return seen.length == cells.length;
}

void _expectRegions(SudokuPuzzle p) {
  final rows = p.rows;
  final cols = p.cols;
  for (var k = 0; k < 9; k++) {
    final cells = <int>[
      for (var i = 0; i < p.cellCount; i++)
        if (p.regionOf[i] == k) i,
    ];
    expect(cells.length, 9, reason: 'region $k');
    expect(
      _connected(cells, cols, rows),
      isTrue,
      reason: 'region $k connected',
    );
    final digits = <int>{for (final i in cells) p.solution[i]};
    expect(digits.length, 9, reason: 'region $k digits');
  }
}

void _checkPuzzle(
  SudokuModeSpec mode,
  SudokuDifficulty difficulty,
  SudokuPuzzle p,
  int elapsedMs,
) {
  expect(p.cellCount, p.cellCountOverride ?? p.rows * p.cols * p.layers);
  expect(p.solution.length, p.cellCount);
  expect(p.givens.length, p.cellCount);
  expect(p.active.length, p.cellCount);
  expect(p.regionOf.length, p.cellCount);

  if (mode.variant == SudokuVariant.classic) {
    expect(elapsedMs, lessThan(2000), reason: '经典出题超过 2s');
  } else {
    expect(elapsedMs, lessThan(5000), reason: '${mode.key} 出题超过 5s');
  }

  for (var i = 0; i < p.cellCount; i++) {
    if (!p.isActive(i)) {
      expect(p.solution[i], 0);
      expect(p.givens[i], 0);
      continue;
    }
    expect(p.solution[i], inInclusiveRange(1, 9));
    if (p.givens[i] != 0) expect(p.givens[i], p.solution[i]);
  }

  for (final unit in p.units) {
    expect(unit.length, 9, reason: '${mode.key} unit length');
    final digits = <int>{};
    for (final i in unit) {
      expect(p.isActive(i), isTrue);
      digits.add(p.solution[i]);
    }
    expect(digits.length, 9, reason: '${mode.key} unit digits');
  }

  for (final cage in p.cages) {
    expect(cage.cells.length, inInclusiveRange(1, 6));
    expect(
      _connected(cage.cells, p.cols, p.rows),
      isTrue,
      reason: 'cage connected',
    );
    final digits = <int>{};
    var sum = 0;
    for (final i in cage.cells) {
      digits.add(p.solution[i]);
      sum += p.solution[i];
    }
    expect(digits.length, cage.cells.length, reason: 'cage no repeat');
    expect(sum, cage.sum);
  }
  if (p.cages.isNotEmpty) {
    final covered = <int>{};
    for (final cage in p.cages) {
      for (final i in cage.cells) {
        expect(covered.add(i), isTrue, reason: 'cage overlap');
      }
    }
    expect(covered.length, p.activeCount);
  }

  if (p.inequalities.isNotEmpty) {
    expect(p.inequalities.length, inInclusiveRange(25, 50));
  }
  for (final edge in p.inequalities) {
    final ar = p.rowOf(edge.a);
    final ac = p.colOf(edge.a);
    final br = p.rowOf(edge.b);
    final bc = p.colOf(edge.b);
    expect((ar - br).abs() + (ac - bc).abs(), 1, reason: 'edge adjacent');
    expect(p.solution[edge.a] < p.solution[edge.b], isTrue);
  }

  if (p.variant == SudokuVariant.evenOdd) {
    // 规则：只标一部分格（参考图五 40–55），未标记格不限奇偶。
    final marked = p.evenCells.length + p.oddCells.length;
    expect(p.evenCells.intersection(p.oddCells), isEmpty);
    expect(marked, inInclusiveRange(40, 55), reason: '奇偶标记数量');
    expect(marked, greaterThan(0));
    expect(marked, lessThan(p.activeCount), reason: '必须保留未标记格');
    expect(p.evenCells, isNotEmpty);
    expect(p.oddCells, isNotEmpty);
    for (final i in p.evenCells) {
      expect(p.isActive(i), isTrue);
      expect(p.solution[i].isEven, isTrue);
    }
    for (final i in p.oddCells) {
      expect(p.isActive(i), isTrue);
      expect(p.solution[i].isOdd, isTrue);
    }
    final index = SudokuConstraintIndex(p);
    for (var i = 0; i < p.cellCount; i++) {
      if (!p.isActive(i)) continue;
      if (p.evenCells.contains(i) || p.oddCells.contains(i)) continue;
      // 未标记格在约束层必须是完整域，不能偷偷限制奇偶。
      expect(index.parity[i], (1 << 9) - 1, reason: '未标记格 $i');
    }
  }

  switch (p.variant) {
    case SudokuVariant.jigsaw:
      _expectRegions(p);
    case SudokuVariant.overlap:
      expect(p.grids.length, p.overlapCount);
      final active = <int>{};
      for (final g in p.grids) {
        expect(g.size, 9);
        expect(g.top, inInclusiveRange(0, p.rows - 9));
        expect(g.left, inInclusiveRange(0, p.cols - 9));
        expect(g.top % 3, 0, reason: '子盘偏移必须是 3 的倍数');
        expect(g.left % 3, 0, reason: '子盘偏移必须是 3 的倍数');
        for (var r = 0; r < 9; r++) {
          for (var c = 0; c < 9; c++) {
            active.add((g.top + r) * p.cols + g.left + c);
          }
        }
      }
      expect(active.length, p.activeCount);
      for (final i in active) {
        expect(p.isActive(i), isTrue);
      }
      if (p.windmill) {
        expect(p.overlapCount, 5);
        expect(p.rows, 21);
        expect(p.cols, 21);
        expect(p.activeCount, 333);
        expect(
          {for (final g in p.grids) (g.top, g.left)},
          {(0, 3), (3, 12), (12, 9), (9, 0), (6, 6)},
        );
        // 风车式：左上角留白，中心盘与每个外盘共享 3×6。
        expect(p.isActive(0), isFalse);
        expect(p.isActive(10 * p.cols + 10), isTrue);
      }
    case SudokuVariant.cube3d:
      expect(p.isCube3d, isTrue);
      expect(p.rows, 9);
      expect(p.cols, 9);
      expect(p.layers, 1);
      expect(p.cellCount, 217);
      expect(p.cubeFaces.length, 3);
      expect(p.units.length, 78);
      final seenCells = <int>{};
      for (final face in p.cubeFaces) {
        expect(face.cells.length, 81);
        for (final index in face.cells) {
          expect(p.isActive(index), isTrue);
          seenCells.add(index);
        }
        // 面内行/列/宫在满解里都是 1–9。
        for (var r = 0; r < 9; r++) {
          final digits = <int>{
            for (var c = 0; c < 9; c++) p.solution[face.cellAt(r, c)],
          };
          expect(digits.length, 9, reason: '${face.face.name} row $r');
        }
        for (var c = 0; c < 9; c++) {
          final digits = <int>{
            for (var r = 0; r < 9; r++) p.solution[face.cellAt(r, c)],
          };
          expect(digits.length, 9, reason: '${face.face.name} col $c');
        }
        for (var br = 0; br < 3; br++) {
          for (var bc = 0; bc < 3; bc++) {
            final digits = <int>{
              for (var r = 0; r < 3; r++)
                for (var c = 0; c < 3; c++)
                  p.solution[face.cellAt(br * 3 + r, bc * 3 + c)],
            };
            expect(digits.length, 9, reason: '${face.face.name} box');
          }
        }
      }
      expect(seenCells.length, 217);
      // 共享边同索引。
      final top = p.cubeFaces[0];
      final left = p.cubeFaces[1];
      final right = p.cubeFaces[2];
      expect(top.face, SudokuCubeFace.top);
      expect(left.face, SudokuCubeFace.frontLeft);
      expect(right.face, SudokuCubeFace.frontRight);
      for (var c = 0; c < 9; c++) {
        expect(top.cellAt(8, c), left.cellAt(0, c));
        expect(top.cellAt(c, 8), right.cellAt(0, c));
      }
      for (var r = 0; r < 9; r++) {
        expect(left.cellAt(r, 8), right.cellAt(r, 8));
      }
      expect(p.cubeRefsOf(top.cellAt(8, 8)).length, 3);
      expect(p.cubeRefsOf(top.cellAt(8, 0)).length, 2);
    case SudokuVariant.classic:
    case SudokuVariant.evenOdd:
    case SudokuVariant.diagonal:
    case SudokuVariant.inequality:
    case SudokuVariant.killer:
      break;
    default:
      break;
  }

  expect(SudokuEngine.isSolved(p, p.solution), isTrue);
  expect(SudokuEngine.conflicts(p, p.solution), isEmpty);
  expect(SudokuEngine.countSolutions(p), 1);

  final rating = const SudokuGrader().rate(p);
  expect(
    rating.tier,
    greaterThanOrEqualTo(SudokuGenerator.targetTier(mode, difficulty)),
    reason: '${mode.key}/${difficulty.key} rating=$rating',
  );
  expect(p.difficultyScore, greaterThan(0));
  expect(
    p.difficultyMet,
    isTrue,
    reason: '${mode.key}/${difficulty.key} 生成器降档',
  );
  if (difficulty == SudokuDifficulty.expert &&
      p.variant != SudokuVariant.overlap &&
      p.variant != SudokuVariant.cube3d) {
    expect(
      rating.techniqueLevel,
      greaterThanOrEqualTo(2),
      reason: '${mode.key} expert 不能只靠裸单',
    );
  }
}

const _windmillMode = SudokuModeSpec(
  variant: SudokuVariant.overlap,
  group: SudokuGroup.jigsaw,
  key: 'windmill',
  title: '风车数独',
  blurb: '5 盘风车式错位',
  overlapCount: 5,
  difficulties: [SudokuDifficulty.hard, SudokuDifficulty.expert],
);

void main() {
  test('all sudoku modes × 2 seeds: geometry, rules, unique, difficulty', () {
    var index = 0;
    // hidden 模式（雪花）只保留存档兼容，不进入常规回归。
    for (final mode in kSudokuModes.where((m) => !m.hidden)) {
      for (final difficulty in mode.difficulties) {
        for (final seed in const [100, 2026]) {
          final sw = Stopwatch()..start();
          final p = SudokuEngine.generate(mode, difficulty, seed: seed + index);
          sw.stop();
          _checkPuzzle(mode, difficulty, p, sw.elapsedMilliseconds);
          final rating = const SudokuGrader().rate(p);
          // ignore: avoid_print
          print(
            '${mode.key}/${difficulty.key} seed=${seed + index}: '
            '${sw.elapsedMilliseconds}ms cells=${p.cellCount} '
            'active=${p.activeCount} clues=${rating.clues} '
            'tier=${rating.tier} level=${rating.techniqueLevel} '
            'guesses=${rating.guesses}',
          );
        }
        index++;
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('same seed reproduces exactly', () {
    for (final key in ['classic', 'jigsaw', 'overlap-13', 'killer', 'cube3d']) {
      final mode = sudokuModeByKey(key);
      final difficulty = mode.difficulties.last;
      final a = SudokuEngine.generate(mode, difficulty, seed: 777);
      final b = SudokuEngine.generate(mode, difficulty, seed: 777);
      expect(a.givens, b.givens, reason: key);
      expect(a.solution, b.solution, reason: key);
      expect(a.regionOf, b.regionOf, reason: key);
      expect(a.difficultyScore, b.difficultyScore, reason: key);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('different seeds produce different puzzles/layouts', () {
    final classic = sudokuModeByKey('classic');
    final c1 = SudokuEngine.generate(classic, SudokuDifficulty.medium, seed: 1);
    final c2 = SudokuEngine.generate(classic, SudokuDifficulty.medium, seed: 2);
    expect(c1.givens, isNot(equals(c2.givens)));

    final jigsaw = sudokuModeByKey('jigsaw');
    final j1 = SudokuEngine.generate(jigsaw, SudokuDifficulty.medium, seed: 3);
    final j2 = SudokuEngine.generate(jigsaw, SudokuDifficulty.medium, seed: 4);
    expect(
      j1.regionOf.join(',') != j2.regionOf.join(',') ||
          j1.givens.join(',') != j2.givens.join(','),
      isTrue,
    );

    final w1 = SudokuEngine.generate(
      _windmillMode,
      SudokuDifficulty.expert,
      seed: 5,
    );
    final w2 = SudokuEngine.generate(
      _windmillMode,
      SudokuDifficulty.expert,
      seed: 6,
    );
    expect(w1.givens, isNot(equals(w2.givens)));

    final overlap = sudokuModeByKey('overlap-13');
    final o1 = SudokuEngine.generate(
      overlap,
      overlap.defaultDifficulty,
      seed: 7,
    );
    final o2 = SudokuEngine.generate(
      overlap,
      overlap.defaultDifficulty,
      seed: 8,
    );
    expect(o1.givens, isNot(equals(o2.givens)));

    final cube = sudokuModeByKey('cube3d');
    final b1 = SudokuEngine.generate(cube, SudokuDifficulty.hard, seed: 9);
    final b2 = SudokuEngine.generate(cube, SudokuDifficulty.hard, seed: 10);
    expect(b1.givens, isNot(equals(b2.givens)));
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('jigsaw has at least 30 distinct layouts across 80 seeds', () {
    final mode = sudokuModeByKey('jigsaw');
    final layouts = <String>{};
    for (var i = 0; i < 80; i++) {
      final p = SudokuEngine.generate(
        mode,
        SudokuDifficulty.medium,
        seed: 3000 + i,
      );
      layouts.add(p.regionOf.join(','));
    }
    expect(layouts.length, greaterThanOrEqualTo(30));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('overlap 2/3/13 match the reference-image layouts', () {
    final double = SudokuEngine.generate(
      sudokuModeByKey('overlap-2'),
      SudokuDifficulty.hard,
      seed: 610,
    );
    expect((double.rows, double.cols), (15, 15));
    expect(double.activeCount, 153);
    expect({for (final g in double.grids) (g.top, g.left)}, {(0, 0), (6, 6)});
    // 双盘共享 rows 6–8 × cols 6–8。
    for (var r = 6; r <= 8; r++) {
      for (var c = 6; c <= 8; c++) {
        expect(double.isActive(r * 15 + c), isTrue);
      }
    }

    final triple = SudokuEngine.generate(
      sudokuModeByKey('overlap-3'),
      SudokuDifficulty.hard,
      seed: 611,
    );
    expect((triple.rows, triple.cols), (21, 15));
    expect(triple.activeCount, 207);
    expect(
      {for (final g in triple.grids) (g.top, g.left)},
      {(0, 0), (6, 3), (12, 6)},
    );
    // 相邻盘实际共享 3 行 × 6 列（图三高亮的 3×3 只是其中一个宫块）。
    var shared = 0;
    for (var r = 6; r <= 8; r++) {
      for (var c = 3; c <= 8; c++) {
        if (triple.isActive(r * 15 + c)) shared++;
      }
    }
    expect(shared, 18);

    final thirteen = SudokuEngine.generate(
      sudokuModeByKey('overlap-13'),
      SudokuDifficulty.expert,
      seed: 612,
    );
    expect((thirteen.rows, thirteen.cols), (33, 33));
    expect(thirteen.grids.length, 13);
    expect(thirteen.activeCount, 909);
    expect(
      {for (final g in thirteen.grids) (g.top, g.left)},
      {
        for (var i = 0; i < 5; i++)
          for (var j = 0; j < 5; j++)
            if ((i + j).isEven) (i * 6, j * 6),
      },
    );
    // 只有斜向相邻的子盘重叠，每个共享块正好 3×3。
    for (var a = 0; a < thirteen.grids.length; a++) {
      for (var b = a + 1; b < thirteen.grids.length; b++) {
        final ga = thirteen.grids[a];
        final gb = thirteen.grids[b];
        final r0 = ga.top > gb.top ? ga.top : gb.top;
        final r1 = (ga.top + 9) < (gb.top + 9) ? ga.top + 9 : gb.top + 9;
        final c0 = ga.left > gb.left ? ga.left : gb.left;
        final c1 = (ga.left + 9) < (gb.left + 9) ? ga.left + 9 : gb.left + 9;
        if (r1 <= r0 || c1 <= c0) continue;
        expect((r1 - r0) * (c1 - c0), 9, reason: '13 overlap block');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('windmill: 5-panel pinwheel, unique, rated, reproducible', () {
    for (final difficulty in _windmillMode.difficulties) {
      final sw = Stopwatch()..start();
      final a = SudokuEngine.generate(_windmillMode, difficulty, seed: 9001);
      sw.stop();
      _checkPuzzle(_windmillMode, difficulty, a, sw.elapsedMilliseconds);

      final b = SudokuEngine.generate(_windmillMode, difficulty, seed: 9001);
      expect(a.givens, b.givens, reason: 'windmill ${difficulty.key}');
      expect(a.solution, b.solution);
      expect(a.difficultyScore, b.difficultyScore);
      expect(a.windmill, isTrue);
      expect(a.variant, SudokuVariant.overlap);
      expect(a.grids.length, 5);
      expect(a.activeCount, 333);
      expect(a.rows, 21);
      expect(a.cols, 21);
      expect(
        {for (final g in a.grids) (g.top, g.left)},
        {(0, 3), (3, 12), (12, 9), (9, 0), (6, 6)},
      );
      // 中心盘与每个外盘共享 18 格，外盘之间不重叠。
      var shared = 0;
      final cover = List<int>.filled(21 * 21, 0);
      for (final g in a.grids) {
        for (var r = 0; r < 9; r++) {
          for (var c = 0; c < 9; c++) {
            cover[(g.top + r) * 21 + g.left + c]++;
          }
        }
      }
      for (final n in cover) {
        if (n > 1) {
          shared++;
          expect(n, 2);
        }
      }
      expect(shared, 72);
      expect(_windmillMode.rankKey(SudokuDifficulty.expert), 'windmill-expert');
      expect(_windmillMode.rankKey(SudokuDifficulty.hard), 'windmill-hard');
      expect(
        const SudokuGrader().rate(a).tier,
        difficulty.tier,
        reason: 'windmill ${difficulty.key}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('windmill sweep seeds: generate + countSolutions < 2s each', () {
    final mode = sudokuModeByKey('windmill');
    var maxMs = 0;
    for (var seed = 500700; seed <= 500709; seed++) {
      final sw = Stopwatch()..start();
      final p = SudokuEngine.generate(mode, mode.defaultDifficulty, seed: seed);
      final solutions = SudokuEngine.countSolutions(p, limit: 2);
      sw.stop();
      if (sw.elapsedMilliseconds > maxMs) maxMs = sw.elapsedMilliseconds;
      expect(solutions, 1, reason: 'seed $seed');
      expect(p.activeCount, 333, reason: 'seed $seed');
      expect(p.grids.length, 5, reason: 'seed $seed');
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason: 'windmill seed $seed 超时 ${sw.elapsedMilliseconds}ms',
      );
    }
    // ignore: avoid_print
    print('windmill sweep 500700..500709 max=${maxMs}ms');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('all 3D base solutions satisfy the dedup face units', () {
    final layout = cubeFaceLayout();
    expect(layout.cellCount, 217);
    expect(layout.units.length, 78);
    for (final seed in kCubeFaceSolutions) {
      expect(seed.length, 217);
      final digits = decodeSolution(seed);
      for (final unit in layout.units) {
        final values = <int>{for (final i in unit) digits[i]};
        expect(values.length, 9, reason: 'unit $unit');
      }
    }
  });

  test(
    '3D has three faces, 217 dedup cells, shared edges and unique solve',
    () {
      final mode = sudokuModeByKey('cube3d');
      for (final difficulty in mode.difficulties) {
        final sw = Stopwatch()..start();
        final p = SudokuEngine.generate(mode, difficulty, seed: 7300);
        sw.stop();
        _checkPuzzle(mode, difficulty, p, sw.elapsedMilliseconds);
        expect(p.difficultyMet, isTrue, reason: '3D ${difficulty.key}');
        expect(const SudokuGrader().rate(p).tier, difficulty.tier);

        // 共享边同数（满解与题面都成立）。
        final top = p.cubeFaces[0];
        final left = p.cubeFaces[1];
        final right = p.cubeFaces[2];
        for (var c = 0; c < 9; c++) {
          final t = top.cellAt(8, c);
          final l = left.cellAt(0, c);
          expect(p.solution[t], p.solution[l]);
          expect(p.givens[t], p.givens[l]);
          final tr = top.cellAt(c, 8);
          final rr = right.cellAt(0, c);
          expect(p.solution[tr], p.solution[rr]);
        }
        for (var r = 0; r < 9; r++) {
          final l = left.cellAt(r, 8);
          final rr = right.cellAt(r, 8);
          expect(p.solution[l], p.solution[rr]);
          expect(p.givens[l], p.givens[rr]);
        }

        // 彩色环带只是视觉：没有额外的同色 unit。
        expect(p.units.length, 78);
        expect(p.units.every((u) => u.length == 9), isTrue);
        expect(p.activeCount, 217);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test('solver distinguishes unique / multiple solutions', () {
    final mode = sudokuModeByKey('classic');
    final p = SudokuEngine.generate(mode, SudokuDifficulty.easy, seed: 55);
    final blank = p.copyWith(givens: List<int>.filled(81, 0));
    expect(SudokuEngine.countSolutions(blank, limit: 2), 2);
    expect(SudokuEngine.countSolutions(p), 1);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('hint and conflict respond to board state', () {
    final mode = sudokuModeByKey('classic');
    final p = SudokuEngine.generate(mode, SudokuDifficulty.easy, seed: 56);
    final board = List<int>.from(p.givens);
    expect(SudokuEngine.conflicts(p, board), isEmpty);
    expect(SudokuEngine.isSolved(p, board), isFalse);
    final hint = SudokuEngine.hintCell(p, board);
    expect(hint, isNotNull);
    expect(p.isActive(hint!), isTrue);
    expect(board[hint], 0);
    expect(SudokuEngine.hintValue(p, board), p.solution[hint]);

    final solved = List<int>.from(p.solution);
    solved[hint] = solved[hint] % 9 + 1;
    expect(SudokuEngine.isSolved(p, solved), isFalse);
    expect(SudokuEngine.conflicts(p, solved), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
