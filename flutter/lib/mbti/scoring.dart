import 'models.dart';

/// 倾向强度分档：center = 贴线（倾向不明显），mild = 温和，clear = 明确。
enum DimBand { center, mild, clear }

class DimScore {
  final String dim;

  /// 归一化维度分，[-1,1]；正值偏右端字母。
  final double value;
  final String letter;
  final int pctLeft;
  final int pctRight;
  final DimBand band;

  const DimScore({
    required this.dim,
    required this.value,
    required this.letter,
    required this.pctLeft,
    required this.pctRight,
    required this.band,
  });

  Map<String, dynamic> toJson() => {
    'dim': dim,
    'value': value,
    'letter': letter,
    'pctLeft': pctLeft,
    'pctRight': pctRight,
    'band': band.name,
  };

  factory DimScore.fromJson(Map<String, dynamic> j) => DimScore(
    dim: j['dim'] as String,
    value: (j['value'] as num).toDouble(),
    letter: j['letter'] as String,
    pctLeft: j['pctLeft'] as int,
    pctRight: j['pctRight'] as int,
    band: DimBand.values.firstWhere((b) => b.name == j['band']),
  );
}

class AnswerQuality {
  final bool fastFinish;
  final bool straightLine;
  final int inconsistentPairs;

  const AnswerQuality({
    required this.fastFinish,
    required this.straightLine,
    required this.inconsistentPairs,
  });

  bool get hasWarning => fastFinish || straightLine || inconsistentPairs >= 2;

  Map<String, dynamic> toJson() => {
    'fastFinish': fastFinish,
    'straightLine': straightLine,
    'inconsistentPairs': inconsistentPairs,
  };

  factory AnswerQuality.fromJson(Map<String, dynamic> j) => AnswerQuality(
    fastFinish: j['fastFinish'] as bool? ?? false,
    straightLine: j['straightLine'] as bool? ?? false,
    inconsistentPairs: j['inconsistentPairs'] as int? ?? 0,
  );
}

class MbtiResult {
  final MbtiMode mode;
  final Map<String, DimScore> scores;
  final String typeRaw;

  /// 完整版输出 '-A' / '-T'，其他版本为空串。
  final String atSuffix;
  final AnswerQuality quality;

  const MbtiResult({
    required this.mode,
    required this.scores,
    required this.typeRaw,
    required this.atSuffix,
    required this.quality,
  });

  /// 含情绪后缀的完整展示型（如 INFJ-T）。
  String get displayType => '$typeRaw$atSuffix';

  Map<String, dynamic> toJson() => {
    'mode': mode.key,
    'scores': scores.map((k, v) => MapEntry(k, v.toJson())),
    'typeRaw': typeRaw,
    'atSuffix': atSuffix,
    'quality': quality.toJson(),
  };

  factory MbtiResult.fromJson(Map<String, dynamic> j) {
    final scores = <String, DimScore>{};
    (j['scores'] as Map<String, dynamic>).forEach((k, v) {
      scores[k] = DimScore.fromJson(v as Map<String, dynamic>);
    });
    return MbtiResult(
      mode: MbtiModeX.fromKey(j['mode'] as String?),
      scores: scores,
      typeRaw: j['typeRaw'] as String,
      atSuffix: j['atSuffix'] as String? ?? '',
      quality: AnswerQuality.fromJson(j['quality'] as Map<String, dynamic>),
    );
  }
}

class MbtiScoring {
  /// 贴线阈值：|D| 小于该值视为倾向不明显。
  static double centerThreshold(MbtiMode mode) =>
      mode == MbtiMode.quick ? 0.20 : 0.15;

  /// 明确倾向阈值：|D| 达到该值视为明确。
  static const double clearThreshold = 0.35;

  static MbtiResult score({
    required MbtiBank bank,
    required MbtiMode mode,
    required Map<String, int> answers,
    int durationSec = 1 << 30,
  }) {
    final qs = bank.questionsFor(mode);
    final sums = <String, int>{};
    final counts = <String, int>{};
    for (final q in qs) {
      final a = answers[q.id];
      if (a == null) {
        throw ArgumentError('题目 ${q.id} 未作答');
      }
      if (a < 1 || a > 7) {
        throw ArgumentError('题目 ${q.id} 作答值越界: $a');
      }
      sums[q.dim] = (sums[q.dim] ?? 0) + q.scoreOf(a);
      counts[q.dim] = (counts[q.dim] ?? 0) + 1;
    }

    final center = centerThreshold(mode);
    final scores = <String, DimScore>{};
    for (final dim in counts.keys) {
      final n = counts[dim]!;
      final d = sums[dim]! / (3.0 * n);
      final meta = bank.dimensions[dim]!;
      final letter = d >= 0 ? meta.right : meta.left;
      final pctRight = ((d + 1) / 2 * 100).round().clamp(0, 100);
      final abs = d.abs();
      scores[dim] = DimScore(
        dim: dim,
        value: d,
        letter: letter,
        pctLeft: 100 - pctRight,
        pctRight: pctRight,
        band: abs < center
            ? DimBand.center
            : abs < clearThreshold
            ? DimBand.mild
            : DimBand.clear,
      );
    }

    final typeRaw = ['EI', 'SN', 'TF', 'JP']
        .map((d) => scores[d]?.letter ?? '')
        .join();
    final atSuffix = scores.containsKey('AT')
        ? '-${scores['AT']!.letter}'
        : '';

    return MbtiResult(
      mode: mode,
      scores: scores,
      typeRaw: typeRaw,
      atSuffix: atSuffix,
      quality: _quality(qs, answers, durationSec),
    );
  }

  static AnswerQuality _quality(
    List<MbtiQuestion> qs,
    Map<String, int> answers,
    int durationSec,
  ) {
    final n = qs.length;
    // 作答过快：平均每题不足 1.5 秒。
    final fast = durationSec < (n * 1.5).floor();
    // 直线作答：同一选项连续 ≥12 题，或某选项占比 >80%。
    var maxRun = 0;
    var run = 0;
    var prev = -1;
    final freq = <int, int>{};
    for (final q in qs) {
      final a = answers[q.id]!;
      freq[a] = (freq[a] ?? 0) + 1;
      if (a == prev) {
        run++;
      } else {
        run = 1;
        prev = a;
      }
      if (run > maxRun) maxRun = run;
    }
    final dominant = freq.values.fold<int>(0, (m, v) => v > m ? v : m);
    final straight = maxRun >= 12 || dominant / n > 0.8;
    // 一致性题对：语义相近的两题，答案差 ≥4 档记一次矛盾。
    var inconsistent = 0;
    final seen = <String>{};
    for (final q in qs) {
      final pairId = q.pair;
      if (pairId == null || seen.contains(q.id)) continue;
      final other = qs.where((e) => e.id == pairId).firstOrNull;
      if (other == null) continue;
      seen.add(q.id);
      seen.add(other.id);
      // 题对方向可能相反，先换算成同向得分再比较。
      final s1 = q.scoreOf(answers[q.id]!);
      final s2 = other.scoreOf(answers[other.id]!);
      if ((s1 - s2).abs() >= 4) inconsistent++;
    }
    return AnswerQuality(
      fastFinish: fast,
      straightLine: straight,
      inconsistentPairs: inconsistent,
    );
  }
}
