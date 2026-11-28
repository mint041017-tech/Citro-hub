import 'dart:math' as math;

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

/// MBTI 测量效度审计指标（对齐 Curran 粗心作答审计协议）。
class MbtiAudit {
  final int longstring;
  final double ars;
  final int ersPct;
  final int antonymScore;
  final double medianSec;
  final String validityStatus;
  final bool validityWarn;
  final List<String> warnings;

  const MbtiAudit({
    required this.longstring,
    required this.ars,
    required this.ersPct,
    required this.antonymScore,
    required this.medianSec,
    required this.validityStatus,
    required this.validityWarn,
    required this.warnings,
  });

  Map<String, dynamic> toJson() => {
    'longstring': longstring,
    'ars': ars,
    'ersPct': ersPct,
    'antonymScore': antonymScore,
    'medianSec': medianSec,
    'validityStatus': validityStatus,
    'validityWarn': validityWarn,
    'warnings': warnings,
  };

  factory MbtiAudit.fromJson(Map<String, dynamic> j) => MbtiAudit(
    longstring: (j['longstring'] as num?)?.toInt() ?? 1,
    ars: (j['ars'] as num?)?.toDouble() ?? 0,
    ersPct: (j['ersPct'] as num?)?.toInt() ?? 0,
    antonymScore: (j['antonymScore'] as num?)?.toInt() ?? 100,
    medianSec: (j['medianSec'] as num?)?.toDouble() ?? 0,
    validityStatus: '${j['validityStatus'] ?? '可靠'}',
    validityWarn: j['validityWarn'] == true,
    warnings: ((j['warnings'] as List?) ?? [])
        .map((e) => '$e')
        .toList(growable: false),
  );
}

class MbtiResult {
  final MbtiMode mode;
  final Map<String, DimScore> scores;
  final String typeRaw;

  /// 完整版输出 '-A' / '-T'，其他版本为空串。
  final String atSuffix;
  final AnswerQuality quality;

  /// 测量效度审计结果；旧版本历史记录为 null。
  final MbtiAudit? audit;

  const MbtiResult({
    required this.mode,
    required this.scores,
    required this.typeRaw,
    required this.atSuffix,
    required this.quality,
    this.audit,
  });

  /// 含情绪后缀的完整展示型（如 INFJ-T）。
  String get displayType => '$typeRaw$atSuffix';

  Map<String, dynamic> toJson() => {
    'mode': mode.key,
    'scores': scores.map((k, v) => MapEntry(k, v.toJson())),
    'typeRaw': typeRaw,
    'atSuffix': atSuffix,
    'quality': quality.toJson(),
    if (audit != null) 'audit': audit!.toJson(),
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
      audit: j['audit'] is Map
          ? MbtiAudit.fromJson(Map<String, dynamic>.from(j['audit'] as Map))
          : null,
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
    List<int> timingsMs = const [],
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

    final quality = _quality(qs, answers, durationSec);
    final audit = _audit(qs, answers, durationSec, timingsMs, quality);

    return MbtiResult(
      mode: mode,
      scores: scores,
      typeRaw: typeRaw,
      atSuffix: atSuffix,
      quality: quality,
      audit: audit,
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

  /// 计算完整效度审计指标（Longstring、ARS、ERS、镜像题对一致度与单题中位耗时）。
  static MbtiAudit _audit(
    List<MbtiQuestion> qs,
    Map<String, int> answers,
    int durationSec,
    List<int> timingsMs,
    AnswerQuality quality,
  ) {
    final n = qs.length;
    var longstring = 1;
    var run = 1;
    var arsSum = 0.0;
    var ersCount = 0;

    for (var i = 0; i < n; i++) {
      final a = answers[qs[i].id]!;
      arsSum += (a - 4) / 3.0;
      if (a == 1 || a == 7) ersCount++;
      if (i > 0) {
        if (a == answers[qs[i - 1].id]) {
          run++;
          if (run > longstring) longstring = run;
        } else {
          run = 1;
        }
      }
    }

    final ars = double.parse((arsSum / n).toStringAsFixed(2));
    final ersPct = (ersCount / n * 100).round();

    var pairErr = 0.0;
    var pairCnt = 0;
    final seen = <String>{};
    for (final q in qs) {
      final pairId = q.pair;
      if (pairId == null || seen.contains(q.id)) continue;
      final other = qs.where((e) => e.id == pairId).firstOrNull;
      if (other == null) continue;
      seen.add(q.id);
      seen.add(other.id);
      final s1 = q.scoreOf(answers[q.id]!);
      final s2 = other.scoreOf(answers[other.id]!);
      pairErr += (s1 - s2).abs();
      pairCnt++;
    }
    final antonymScore = pairCnt == 0
        ? 100
        : math.max(0, ((1 - pairErr / (pairCnt * 6)) * 100).round());

    final clean = timingsMs.where((t) => t > 0).toList()..sort();
    final double medianSec;
    if (clean.isNotEmpty) {
      medianSec = double.parse(
        (clean[clean.length ~/ 2] / 1000).toStringAsFixed(1),
      );
    } else if (durationSec < (1 << 29)) {
      medianSec = double.parse((durationSec / n).toStringAsFixed(1));
    } else {
      medianSec = 3.2;
    }

    final warnings = <String>[];
    if (longstring >= 8) {
      warnings.add('最大连续同选达到 $longstring 题（疑似机械作答）');
    } else if (quality.straightLine) {
      warnings.add('单一选项占比过高（疑似缺乏区分度）');
    }
    if (medianSec < 1.2 || quality.fastFinish) {
      warnings.add('单题中位耗时仅 ${medianSec}s（疑似阅读过快）');
    }
    if (antonymScore < 62 || quality.inconsistentPairs >= 2) {
      warnings.add('跨距题对一致性偏低（$antonymScore/100）');
    }
    if (ars.abs() >= .35) {
      warnings.add(
        '存在${ars > 0 ? '赞同' : '否定'}作答风格（ARS=${ars > 0 ? '+' : ''}$ars，已由正反题结构自动抵消）',
      );
    }

    var status = '可靠';
    var warn = false;
    if (longstring >= 10 || (medianSec < 1.0 && antonymScore < 65)) {
      status = '建议重测';
      warn = true;
    } else if (warnings.isNotEmpty || quality.hasWarning) {
      status = '需留意';
      warn = true;
    } else if (antonymScore >= 80 && longstring <= 7) {
      status = '高可靠';
    }

    return MbtiAudit(
      longstring: longstring,
      ars: ars,
      ersPct: ersPct,
      antonymScore: antonymScore,
      medianSec: medianSec,
      validityStatus: status,
      validityWarn: warn,
      warnings: warnings,
    );
  }
}
