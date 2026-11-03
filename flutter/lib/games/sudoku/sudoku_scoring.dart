import 'dart:math' as math;

import 'sudoku_modes.dart';
import 'sudoku_puzzle.dart';

// 数独计分模型。所有参数集中在这里，UI、存档与测试共用同一套规则。
//
// 完整公式：
//
//   base  = 基础分（见 sudokuBaseScore）
//   T_ref = activeCount × 每格参考秒数(难度) × 变体系数
//   Qt    = 1 + 0.15 × (1 - 用时 / T_ref)        用时 ≤ T_ref（越快越高）
//         = T_ref / 用时                        用时 > T_ref（反比衰减）
//   Qe    = max(0.55, 1 - 0.06 × 错误数)
//   Qh    = max(0.70, 1 - 0.10 × 已用提示)
//   Qp    = 1.15（零错误且零提示），否则 1.0
//   total = clamp(round(base × Qt × Qe × Qh × Qp), 1,
//                 round(base × 1.15 × 1.15))
//
// 与旧版相比：时间不再是“每秒扣 1–2 分”的线性减法（旧版 60 分钟以上必然
// 掉到 1 分，而 5 分钟通关几乎等于满分）；改成“到参考用时前拿满分、之后按
// 反比平滑衰减”。错误与提示也改成百分比折扣，任何模式都能真正拉开差距。

/// 每格参考用时（秒），按难度递增。
const Map<SudokuDifficulty, int> kSudokuSecondsPerCell =
    <SudokuDifficulty, int>{
      SudokuDifficulty.easy: 4,
      SudokuDifficulty.medium: 5,
      SudokuDifficulty.hard: 7,
      SudokuDifficulty.expert: 9,
    };

/// 每次错误扣掉基础分的比例，以及扣分下限系数。
const double kSudokuErrorPenalty = 0.06;
const double kSudokuErrorFloor = 0.55;

/// 每次提示扣掉基础分的比例，以及扣分下限系数。
const double kSudokuHintPenalty = 0.10;
const double kSudokuHintFloor = 0.70;

/// 零错误 + 零提示的完美奖励系数。
const double kSudokuPerfectBonus = 1.15;

/// 参考用时内的速通奖励：用时无限接近 0 时最多 +15%，到参考用时归零。
const double kSudokuSpeedBonus = 0.15;

/// 基础分：经典沿用旧表；变体按“变体权重 + 难度档 + 重叠数”叠加。
int sudokuBaseScore(SudokuPuzzle puzzle) {
  if (puzzle.variant == SudokuVariant.classic) {
    return switch (puzzle.difficulty) {
      SudokuDifficulty.easy => 3600,
      SudokuDifficulty.medium => 5400,
      SudokuDifficulty.hard => 7200,
      SudokuDifficulty.expert => 9000,
    };
  }
  final weight = switch (puzzle.variant) {
    SudokuVariant.jigsaw => 1,
    SudokuVariant.snowflake => 2,
    SudokuVariant.overlap => 2 + puzzle.overlapCount ~/ 4,
    SudokuVariant.evenOdd => 2,
    SudokuVariant.diagonal => 1,
    SudokuVariant.inequality => 3,
    SudokuVariant.killer => 4,
    SudokuVariant.cube3d => 5,
    SudokuVariant.classic => 0,
  };
  return 2400 +
      weight * 600 +
      puzzle.difficulty.tier * 900 +
      (puzzle.variant == SudokuVariant.overlap ? puzzle.overlapCount * 120 : 0);
}

/// 变体对“每格耗时”的放大系数：约束越绕，参考用时越长。
double sudokuVariantSecondsFactor(SudokuPuzzle puzzle) =>
    switch (puzzle.variant) {
      SudokuVariant.classic => 1.0,
      SudokuVariant.jigsaw => 1.10,
      SudokuVariant.snowflake => 1.15,
      SudokuVariant.overlap => 1 + 0.03 * puzzle.overlapCount,
      SudokuVariant.evenOdd => 1.15,
      SudokuVariant.diagonal => 1.10,
      SudokuVariant.inequality => 1.30,
      SudokuVariant.killer => 1.50,
      SudokuVariant.cube3d => 1.40,
    };

/// 参考用时 T_ref（秒）。用时不超过它时时间系数为 1.0。
int sudokuReferenceSeconds(SudokuPuzzle puzzle) {
  final perCell = kSudokuSecondsPerCell[puzzle.difficulty] ?? 5;
  final raw = puzzle.activeCount * perCell * sudokuVariantSecondsFactor(puzzle);
  return math.max(60, raw.round());
}

/// 一次结算的完整计分明细。
class SudokuScore {
  const SudokuScore({
    required this.base,
    required this.seconds,
    required this.errors,
    required this.hintsUsed,
    required this.referenceSeconds,
    required this.timeFactor,
    required this.errorFactor,
    required this.hintFactor,
    required this.perfectBonus,
    required this.cap,
    required this.total,
  });

  final int base;
  final int seconds;
  final int errors;
  final int hintsUsed;
  final int referenceSeconds;
  final double timeFactor;
  final double errorFactor;
  final double hintFactor;
  final double perfectBonus;

  /// 单局可用上限（基础分 × 完美奖励）。
  final int cap;
  final int total;

  bool get perfect => perfectBonus > 1;

  /// 结算浮层用的简短明细。
  String get detailLabel =>
      '基础 $base · 时间 ×${_fmt(timeFactor)} · '
      '失误 ×${_fmt(errorFactor * hintFactor)}';

  static String _fmt(double value) => value.toStringAsFixed(2);
}

/// 按公式结算一局。
SudokuScore sudokuScoreOf(
  SudokuPuzzle puzzle, {
  required int seconds,
  required int errors,
  required int hintsUsed,
}) {
  final base = sudokuBaseScore(puzzle);
  final reference = sudokuReferenceSeconds(puzzle);
  final elapsed = math.max(1, seconds);
  final safeErrors = math.max(0, errors);
  final safeHints = math.max(0, hintsUsed);

  final timeFactor = elapsed <= reference
      ? 1 + kSudokuSpeedBonus * (1 - elapsed / reference)
      : reference / elapsed;
  final errorFactor = math.max(
    kSudokuErrorFloor,
    1 - kSudokuErrorPenalty * safeErrors,
  );
  final hintFactor = math.max(
    kSudokuHintFloor,
    1 - kSudokuHintPenalty * safeHints,
  );
  final perfectBonus = safeErrors == 0 && safeHints == 0
      ? kSudokuPerfectBonus
      : 1.0;

  final cap = (base * (1 + kSudokuSpeedBonus) * kSudokuPerfectBonus).round();
  final total = (base * timeFactor * errorFactor * hintFactor * perfectBonus)
      .round()
      .clamp(1, cap)
      .toInt();
  return SudokuScore(
    base: base,
    seconds: elapsed,
    errors: safeErrors,
    hintsUsed: safeHints,
    referenceSeconds: reference,
    timeFactor: timeFactor,
    errorFactor: errorFactor,
    hintFactor: hintFactor,
    perfectBonus: perfectBonus,
    cap: cap,
    total: total,
  );
}
