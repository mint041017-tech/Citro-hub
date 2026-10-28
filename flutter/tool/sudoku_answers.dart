import 'dart:convert';
import 'dart:io';

import 'package:citro/games/sudoku/sudoku_kernel.dart';

/// 生成 docs/sudoku-answers-v2.md：
/// 1) 每个可见模式 × 难度抽检 10 个固定种子，复核唯一解/可解性；
/// 2) 每个模式 × 难度生成一局代表性题，输出题面、约束与答案。
void main() {
  final modes = kSudokuModes.where((m) => !m.hidden).toList(growable: false);
  final configs = <_Config>[];
  var index = 0;
  for (final mode in modes) {
    for (final diff in mode.difficulties) {
      configs.add(_Config(mode, diff, index++));
    }
  }

  final sweeps = <_Sweep>[];
  final reps = <_Rep>[];
  for (final cfg in configs) {
    sweeps.add(_sweep(cfg));
    reps.add(_representative(cfg));
  }

  final doc = StringBuffer();
  doc.writeln('# 数独全模式答案与唯一解复核');
  doc.writeln();
  doc.writeln('生成时间：2026-10-28（本机）');
  doc.writeln();
  doc.writeln('## 复核范围与方法');
  doc.writeln();
  doc.writeln(
    '- 覆盖 `kSudokuModes` 中所有可见模式 × 难度（排除 hidden 雪花）：'
    '${configs.length} 个配置。',
  );
  doc.writeln(
    '- 每个配置抽检 10 个固定种子：共 ${configs.length * 10} 局；'
    '逐局用 `SudokuEngine.countSolutions(limit: 2)` 数解，要求恰好 1 解；'
    '并要求 `isSolved(solution)` 为真、`conflicts(solution)` 为空。',
  );
  doc.writeln(
    '- 答案区为每个配置的一局代表性题（固定 seed）。网页端每局是运行时随机生成，'
    '因此本文档是“固定种子代表局”的答案，不是网页当前随机局的实时答案。',
  );
  doc.writeln();
  doc.writeln('## 汇总');
  doc.writeln();
  doc.writeln(
    '| 模式 | 难度 | 抽检 | 唯一解 | 解合法 | 最大耗时 | 代表 seed | 提示数 | 评级 | 达标 |',
  );
  doc.writeln('|---|---|---:|---:|---:|---:|---:|---:|---|---|');
  for (var i = 0; i < configs.length; i++) {
    final cfg = configs[i];
    final sw = sweeps[i];
    final rep = reps[i];
    doc.writeln(
      '| ${cfg.mode.title} | ${cfg.diff.label} | ${sw.total} | '
      '${sw.unique}/${sw.total} | ${sw.valid}/${sw.total} | '
      '${sw.maxMs} ms | ${rep.puzzle.difficultyScore > 0 ? rep.seed : rep.seed} | '
      '${rep.rating.clues} | tier ${rep.rating.tier} / level ${rep.rating.techniqueLevel} | '
      '${rep.puzzle.difficultyMet ? '是' : '否'} |',
    );
  }
  doc.writeln();
  final failed = sweeps
      .where((s) => s.unique != s.total || s.valid != s.total)
      .toList(growable: false);
  if (failed.isEmpty) {
    doc.writeln(
      '**抽检结论：${configs.length * 10} 局全部唯一解、全部解合法。**',
    );
  } else {
    doc.writeln('**抽检发现失败：**');
    for (final s in failed) {
      doc.writeln('- ${s.label}：unique ${s.unique}/${s.total}，'
          'valid ${s.valid}/${s.total}；${s.failures.join('；')}');
    }
  }
  doc.writeln();
  doc.writeln('## 代表局答案');
  doc.writeln();

  for (var i = 0; i < configs.length; i++) {
    final cfg = configs[i];
    final rep = reps[i];
    final p = rep.puzzle;
    doc.writeln('### ${cfg.mode.title} · ${cfg.diff.label}');
    doc.writeln();
    doc.writeln(
      '- seed：`${rep.seed}`　提示数：${rep.rating.clues}　'
      '评级：tier ${rep.rating.tier} / level ${rep.rating.techniqueLevel}　'
      '达标：${p.difficultyMet ? '是' : '否'}　'
      '唯一解：${rep.solutions == 1 ? '是' : '否'}',
    );
    if (cfg.mode.variant == SudokuVariant.overlap) {
      doc.writeln(
        '- 子盘：${p.grids.map((g) => '(${g.top},${g.left})').join(' ')}　'
        '包围盒：${p.rows}×${p.cols}　有效格：${p.activeCount}'
        '${p.windmill ? '　风车' : ''}',
      );
    }
    if (cfg.mode.variant == SudokuVariant.cube3d) {
      doc.writeln(
        '- 三面：${p.cubeFaces.map((m) => m.face.name).join(' / ')}　'
        '去重格：${p.cellCount}',
      );
    }
    doc.writeln();
    doc.writeln('**题面**');
    doc.writeln();
    doc.writeln('```text');
    _writePuzzle(doc, p);
    doc.writeln('```');
    doc.writeln();
    doc.writeln('**答案**');
    doc.writeln();
    doc.writeln('```text');
    _writeSolution(doc, p);
    doc.writeln('```');
    doc.writeln();
    _writeExtras(doc, p);
    doc.writeln();
  }

  final out = File('docs/sudoku-answers-v2.md');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(doc.toString(), encoding: utf8);
  stdout.writeln('wrote ${out.path}');
  stdout.writeln(
    'configs=${configs.length} sweep=${configs.length * 10} '
    'failures=${failed.length}',
  );
}

class _Config {
  const _Config(this.mode, this.diff, this.index);

  final SudokuModeSpec mode;
  final SudokuDifficulty diff;
  final int index;

  String get label => '${mode.title}/${diff.label}';
}

class _Sweep {
  _Sweep(this.label, this.total);

  final String label;
  final int total;
  final List<String> failures = [];
  int unique = 0;
  int valid = 0;
  int maxMs = 0;
  int slowSeed = 0;
  int totalMs = 0;
}

class _Rep {
  const _Rep(this.seed, this.puzzle, this.rating, this.solutions);

  final int seed;
  final SudokuPuzzle puzzle;
  final SudokuRating rating;
  final int solutions;
}

_Sweep _sweep(_Config cfg) {
  final result = _Sweep(cfg.label, 10);
  for (var i = 0; i < 10; i++) {
    final seed = 500000 + cfg.index * 100 + i;
    final sw = Stopwatch()..start();
    final p = SudokuEngine.generate(cfg.mode, cfg.diff, seed: seed);
    final n = SudokuEngine.countSolutions(p, limit: 2);
    final solved = SudokuEngine.isSolved(p, p.solution);
    final noConflict = SudokuEngine.conflicts(p, p.solution).isEmpty;
    sw.stop();
    result.totalMs += sw.elapsedMilliseconds;
    if (sw.elapsedMilliseconds > result.maxMs) {
      result.maxMs = sw.elapsedMilliseconds;
      result.slowSeed = seed;
    }
    if (n == 1) {
      result.unique++;
    } else {
      result.failures.add('seed $seed 数解=$n');
    }
    if (solved && noConflict) {
      result.valid++;
    } else {
      result.failures.add('seed $seed solved=$solved conflict=${!noConflict}');
    }
  }
  return result;
}

_Rep _representative(_Config cfg) {
  final seed = 20261028 + cfg.index;
  final p = SudokuEngine.generate(cfg.mode, cfg.diff, seed: seed);
  final rating = const SudokuGrader().rate(p);
  final n = SudokuEngine.countSolutions(p, limit: 2);
  return _Rep(seed, p, rating, n);
}

String _cell(int v) => v == 0 ? '.' : '$v';

void _writePuzzle(StringBuffer doc, SudokuPuzzle p) {
  if (p.variant == SudokuVariant.cube3d) {
    for (final m in p.cubeFaces) {
      doc.writeln('${_faceLabel(m.face)} 题面');
      for (var r = 0; r < 9; r++) {
        doc.writeln([
          for (var c = 0; c < 9; c++) _cell(p.givens[m.cellAt(r, c)]),
        ].join(' '));
      }
      doc.writeln();
    }
    return;
  }
  if (p.variant == SudokuVariant.overlap) {
    for (var r = 0; r < p.rows; r++) {
      doc.writeln([
        for (var c = 0; c < p.cols; c++)
          _cell(p.active[r * p.cols + c] ? p.givens[r * p.cols + c] : 0),
      ].join(' '));
    }
    return;
  }
  for (var r = 0; r < 9; r++) {
    doc.writeln([
      for (var c = 0; c < 9; c++) _cell(p.givens[r * 9 + c]),
    ].join(' '));
  }
}

void _writeSolution(StringBuffer doc, SudokuPuzzle p) {
  if (p.variant == SudokuVariant.cube3d) {
    for (final m in p.cubeFaces) {
      doc.writeln('${_faceLabel(m.face)} 答案');
      for (var r = 0; r < 9; r++) {
        doc.writeln([
          for (var c = 0; c < 9; c++) _cell(p.solution[m.cellAt(r, c)]),
        ].join(' '));
      }
      doc.writeln();
    }
    return;
  }
  if (p.variant == SudokuVariant.overlap) {
    for (var r = 0; r < p.rows; r++) {
      doc.writeln([
        for (var c = 0; c < p.cols; c++)
          _cell(p.active[r * p.cols + c] ? p.solution[r * p.cols + c] : 0),
      ].join(' '));
    }
    return;
  }
  for (var r = 0; r < 9; r++) {
    doc.writeln([
      for (var c = 0; c < 9; c++) _cell(p.solution[r * 9 + c]),
    ].join(' '));
  }
}

void _writeExtras(StringBuffer doc, SudokuPuzzle p) {
  if (p.variant == SudokuVariant.jigsaw) {
    doc.writeln('**宫形**（0–8，按行）');
    doc.writeln();
    doc.writeln('```text');
    for (var r = 0; r < 9; r++) {
      doc.writeln([
        for (var c = 0; c < 9; c++) '${p.regionOf[r * 9 + c]}',
      ].join(' '));
    }
    doc.writeln('```');
    doc.writeln();
  }
  if (p.variant == SudokuVariant.evenOdd) {
    doc.writeln('**奇偶标记**（E=偶数，O=奇数，.=未标记）');
    doc.writeln();
    doc.writeln('```text');
    for (var r = 0; r < 9; r++) {
      doc.writeln([
        for (var c = 0; c < 9; c++)
          p.evenCells.contains(r * 9 + c)
              ? 'E'
              : p.oddCells.contains(r * 9 + c)
              ? 'O'
              : '.',
      ].join(' '));
    }
    doc.writeln('```');
    doc.writeln();
  }
  if (p.variant == SudokuVariant.killer) {
    doc.writeln('**杀手笼**（和: (行,列) ...）');
    doc.writeln();
    doc.writeln('```text');
    for (final cage in p.cages) {
      doc.writeln(
        '${cage.sum}: ${cage.cells.map((i) => '(${p.rowOf(i)},${p.colOf(i)})').join(' ')}',
      );
    }
    doc.writeln('```');
    doc.writeln();
  }
  if (p.variant == SudokuVariant.inequality) {
    doc.writeln('**不等式**（左 < 右）');
    doc.writeln();
    doc.writeln('```text');
    for (final e in p.inequalities) {
      doc.writeln(
        '(${p.rowOf(e.a)},${p.colOf(e.a)}) < (${p.rowOf(e.b)},${p.colOf(e.b)})',
      );
    }
    doc.writeln('```');
    doc.writeln();
  }
  if (p.variant == SudokuVariant.overlap) {
    doc.writeln('**子盘**');
    doc.writeln();
    doc.writeln('```text');
    for (var i = 0; i < p.grids.length; i++) {
      final g = p.grids[i];
      doc.writeln('盘 ${i + 1}: top=${g.top}, left=${g.left}, size=${g.size}');
    }
    doc.writeln('```');
    doc.writeln();
  }
  if (p.variant == SudokuVariant.cube3d) {
    doc.writeln('**面映射**（cells 为全局索引；共享边两侧同一索引）');
    doc.writeln();
    doc.writeln('```text');
    for (final m in p.cubeFaces) {
      doc.writeln(
        '${_faceLabel(m.face)}: ${m.cells.join(',')}',
      );
      doc.writeln(
        '共享边局部格: ${(m.sharedEdgeCells.toList()..sort()).join(',')}',
      );
    }
    doc.writeln('```');
    doc.writeln();
  }
}

String _faceLabel(SudokuCubeFace f) => switch (f) {
  SudokuCubeFace.top => '顶面',
  SudokuCubeFace.frontLeft => '左面',
  SudokuCubeFace.frontRight => '右面',
};
