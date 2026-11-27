import 'dart:math' as math;

import 'models.dart';

class KeiScoring {
  const KeiScoring._();

  static const double sigma = .68;
  static const double radius = 1.25;
  static const int monteCarloSamples = 600;
  static const double seFloor = .04;

  static KeiResult analyze({
    required KeiBank bank,
    required List<int> answers,
    List<int> timings = const [],
  }) {
    final buckets = <String, List<double>>{
      for (final d in bank.dimensions) d.id: [],
    };
    for (var i = 0; i < bank.questions.length; i++) {
      final q = bank.questions[i];
      buckets[q.dim]!.add((answers[i] * q.dir) / 3);
    }

    final dims = <KeiDimensionScore>[];
    for (final meta in bank.dimensions) {
      final values = buckets[meta.id]!;
      final n = values.length;
      final mean = values.reduce((a, b) => a + b) / n;
      final variance =
          values.fold<double>(0, (s, v) => s + (v - mean) * (v - mean)) /
          math.max(1, n - 1);
      final sd = math.sqrt(variance);
      final se = math.max(seFloor, sd / math.sqrt(n));
      dims.add(
        KeiDimensionScore(
          id: meta.id,
          code: meta.code,
          name: meta.name,
          low: meta.low,
          high: meta.high,
          mean: mean,
          se: se,
          ciLow: (mean - 1.96 * se).clamp(-1.0, 1.0),
          ciHigh: (mean + 1.96 * se).clamp(-1.0, 1.0),
        ),
      );
    }

    final vec = dims.map((d) => d.mean).toList();
    final norm = math.sqrt(vec.fold<double>(0, (s, v) => s + v * v));
    final denom = 2 * sigma * sigma;
    final scored = <KeiTypeScore>[];
    for (final p in bank.prototypes) {
      final pv = normalizedVec(p);
      final dist = _dist(vec, pv);
      scored.add(
        KeiTypeScore(id: p.id, name: p.name, prob: 0, pct: 0, dist: dist),
      );
    }
    final weights = <String, double>{
      for (var i = 0; i < bank.prototypes.length; i++)
        bank.prototypes[i].id: math.exp(
          -(scored[i].dist * scored[i].dist) / denom,
        ),
    };
    final total = weights.values.reduce((a, b) => a + b);
    final ranked = <KeiTypeScore>[];
    for (var i = 0; i < scored.length; i++) {
      final s = scored[i];
      final prob = weights[s.id]! / total;
      ranked.add(
        KeiTypeScore(
          id: s.id,
          name: s.name,
          prob: prob,
          pct: double.parse((prob * 100).toStringAsFixed(1)),
          dist: s.dist,
        ),
      );
    }
    ranked.sort((a, b) => b.prob.compareTo(a.prob));

    final entropy = -ranked.fold<double>(
      0,
      (s, e) => s + (e.prob > 0 ? e.prob * math.log(e.prob) : 0),
    );
    final entropyNorm = entropy / math.log(bank.prototypes.length);
    final sharpness = ((1 - entropyNorm) * 100).round().clamp(0, 100);

    final wins = <String, int>{for (final p in bank.prototypes) p.id: 0};
    final random = math.Random();
    for (var i = 0; i < monteCarloSamples; i++) {
      final draw = dims
          .map((d) => (d.mean + _randn(random) * d.se).clamp(-1.0, 1.0))
          .toList();
      var bestId = bank.prototypes.first.id;
      var best = double.infinity;
      for (final p in bank.prototypes) {
        final d = _dist(draw, normalizedVec(p));
        if (d < best) {
          best = d;
          bestId = p.id;
        }
      }
      wins[bestId] = wins[bestId]! + 1;
    }
    final top = ranked.first;
    final stability = ((wins[top.id]! / monteCarloSamples) * 100).round();
    final drift = wins.entries
        .where((e) => e.key != top.id && e.value > 0)
        .fold<MapEntry<String, int>?>(
          null,
          (best, e) => best == null || e.value > best.value ? e : best,
        );

    final x1 = vec[0];
    final x2 = vec[1];
    var attachment = '弹性均衡态';
    if (x1.abs() >= .18 || x2.abs() >= .18) {
      if (x1 <= 0 && x2 <= 0) {
        attachment = '安全型依恋';
      } else if (x1 > 0 && x2 <= 0) {
        attachment = '焦虑痴迷型';
      } else if (x1 <= 0 && x2 > 0) {
        attachment = '疏离回避型';
      } else {
        attachment = '恐惧回避型';
      }
    }
    final gap12 = ranked[0].pct - ranked[1].pct;
    var profileMode = '清晰单核构型';
    if (norm < .45) {
      profileMode = '高弹性均衡构型';
    } else if (stability < 55 || gap12 < 2.2) {
      profileMode = '双主核过渡构型';
    } else if (stability >= 82) {
      profileMode = '高稳态极化构型';
    }

    final topProto = bank.byId(top.id);
    final synthesis = _buildSynthesis(
      main: top,
      aux: ranked[1],
      mainVec: normalizedVec(topProto!),
      auxVec: normalizedVec(bank.byId(ranked[1].id)!),
      norm: norm,
      stability: stability,
      driftName: drift == null ? null : bank.byId(drift.key)?.name,
      driftPct: drift == null
          ? null
          : ((drift.value / monteCarloSamples) * 100).round(),
    );
    final compat = bank.prototypes.map((p) => _dynamics(vec, p)).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final audit = _audit(bank: bank, answers: answers, timings: timings);
    return KeiResult(
      typeId: top.id,
      typeName: topProto.name,
      vec: vec,
      dimensions: dims,
      ranked: ranked,
      stabilityPct: stability,
      driftName: drift == null ? null : bank.byId(drift.key)?.name,
      driftPct: drift == null
          ? null
          : ((drift.value / monteCarloSamples) * 100).round(),
      profileMode: profileMode,
      attachment: attachment,
      sharpness: sharpness,
      norm: norm,
      synthesis: synthesis,
      compatBest: compat.take(3).toList(),
      compatHard: compat.reversed.take(2).toList(),
      audit: audit,
    );
  }

  static KeiAudit _audit({
    required KeiBank bank,
    required List<int> answers,
    required List<int> timings,
  }) {
    var longstring = 1;
    var run = 1;
    for (var i = 1; i < answers.length; i++) {
      if (answers[i] == answers[i - 1]) {
        run++;
        if (run > longstring) longstring = run;
      } else {
        run = 1;
      }
    }
    final ars = double.parse(
      ((answers.reduce((a, b) => a + b) / answers.length) / 3).toStringAsFixed(
        2,
      ),
    );
    final ersPct =
        (answers.where((a) => a.abs() == 3).length / answers.length * 100)
            .round();

    final pairs = <String, List<double>>{};
    for (var i = 0; i < bank.questions.length; i++) {
      final q = bank.questions[i];
      final mirror = q.mirror;
      if (mirror == null) continue;
      (pairs[mirror] ??= []).add(answers[i] * q.dir / 3);
    }
    var pairErr = 0.0;
    var pairCnt = 0;
    for (final pair in pairs.values) {
      if (pair.length == 2) {
        pairErr += (pair[0] - pair[1]).abs();
        pairCnt++;
      }
    }
    final antonymScore = pairCnt == 0
        ? 100
        : math.max(0, ((1 - pairErr / (pairCnt * 2)) * 100).round());

    final clean = timings.where((t) => t > 0).toList()..sort();
    final medianSec = clean.isEmpty
        ? 3.2
        : double.parse((clean[clean.length ~/ 2] / 1000).toStringAsFixed(1));

    final warnings = <String>[];
    if (longstring >= 8) {
      warnings.add('最大连续同选达到 $longstring 题（疑似机械作答）');
    }
    if (medianSec < 1.2) {
      warnings.add('单题中位耗时仅 ${medianSec}s（疑似阅读过快）');
    }
    if (antonymScore < 62) {
      warnings.add('跨距反义题一致性偏低（$antonymScore/100）');
    }
    if (ars.abs() >= .35) {
      warnings.add(
        '存在${ars > 0 ? '赞同' : '否定'}作答风格（ARS=${ars > 0 ? '+' : ''}$ars，已由对称计分自动抵消）',
      );
    }

    var status = '可靠';
    var warn = false;
    if (longstring >= 10 || (medianSec < 1.0 && antonymScore < 65)) {
      status = '建议重测';
      warn = true;
    } else if (warnings.isNotEmpty) {
      status = '需留意';
      warn = true;
    } else if (antonymScore >= 80 && longstring <= 5) {
      status = '高可靠';
    }
    return KeiAudit(
      longstring: longstring,
      ars: ars,
      ersPct: ersPct,
      antonymScore: antonymScore.toInt(),
      medianSec: medianSec,
      validityStatus: status,
      validityWarn: warn,
      warnings: warnings,
    );
  }

  static String _buildSynthesis({
    required KeiTypeScore main,
    required KeiTypeScore aux,
    required List<double> mainVec,
    required List<double> auxVec,
    required double norm,
    required int stability,
    required String? driftName,
    required int? driftPct,
  }) {
    if (norm < .45) {
      return '你的五维向量模长仅为 ${norm.toStringAsFixed(2)}，说明你在依恋模式、情绪外显与主导权上高度均衡，并未固化于单一关系脚本。'
          '当前坐标轻微偏向「${main.name}」与「${aux.name}」（稳定率 $stability%），代表较高的情境弹性，能随伴侣状态自然调节相处姿态。';
    }
    final gap = _dist(mainVec, auxVec);
    final bridge = gap > 1.5
        ? '「${main.name}」与「${aux.name}」在五维空间中的几何间距较大（Δ=${gap.toStringAsFixed(2)}），构成一组自带反差张力的双核结构：'
              '外部互动常以${main.name}为主轴，而当核心脆弱点被触发时，${aux.name}的潜流会迅速浮现。'
        : '「${main.name}」与「${aux.name}」在底层坐标上彼此邻近（Δ=${gap.toStringAsFixed(2)}），两者相互强化，'
              '使你在亲密关系中呈现出高度一致且辨识度鲜明的行为轮廓。';
    final mc = driftName != null && stability < 75
        ? '统计误差模拟显示，你约有 $stability% 概率落于${main.name}，另有 $driftPct% 概率向$driftName偏移，建议将两者合并阅读。'
        : '在 600 次测量误差蒙特卡洛模拟中，你的主原型以 $stability% 的高概率稳定收敛于${main.name}，分类边界清晰。';
    return '$bridge$mc';
  }

  static KeiCompat _dynamics(List<double> u, KeiPrototype target) {
    final x1 = u[0], x2 = u[1], x3 = u[2], x4 = u[3], x5 = u[4];
    final v = normalizedVec(target);
    final y1 = v[0], y2 = v[1], y3 = v[2], y4 = v[3], y5 = v[4];

    final trap =
        math.max(0, x1) * math.max(0, y2) + math.max(0, y1) * math.max(0, x2);
    final doubleAnx = math.max(0, x1) * math.max(0, y1);
    final anchor =
        math.max(0, x1) * math.max(0, -y1) * (.5 + .5 * math.max(0, y4)) +
        math.max(0, y1) * math.max(0, -x1) * (.5 + .5 * math.max(0, x4)) +
        .6 * math.max(0, -x1) * math.max(0, -y1);
    final security = (72 - trap * 56 - doubleAnx * 24 + anchor * 32)
        .clamp(15, 98)
        .round();
    final boundary = (96 - (x2 - y2).abs() * 44).clamp(18, 98).round();
    final doubleLow = math.max(0, -x4) * math.max(0, -y4);
    final doubleHighTense =
        math.max(0, x4) * math.max(0, y4) * math.max(.15, (x1 + y1 + 1) / 2);
    final comp = x4 * y4 < 0 ? math.min(.9, (x4 - y4).abs() * .55) : 0.0;
    final agency = (76 + comp * 22 - doubleLow * 42 - doubleHighTense * 26)
        .clamp(20, 98)
        .round();
    final channel = (94 - (x3 - y3).abs() * 22 - (x5 - y5).abs() * 24)
        .clamp(20, 98)
        .round();
    final total =
        (security * .40 + boundary * .24 + agency * .18 + channel * .18)
            .round();

    final notes = <String>[];
    if (trap > .36) {
      notes.add(
        math.max(0, x1) * math.max(0, y2) >= math.max(0, y1) * math.max(0, x2)
            ? '你的求证焦虑易撞上对方的边界防御，存在显著的“追—逃”负反馈风险。'
            : '对方的焦虑试探容易触发你的抽离防御，相处中易产生压迫与内耗。',
      );
    } else if (security >= 84) {
      notes.add('依恋安全缓冲极强，能有效消解猜忌并稳住关系底盘。');
    }
    if (boundary >= 80) {
      notes.add('双方对亲密密度与独处留白的预期高度同频。');
    } else if (boundary <= 46) {
      notes.add('一方偏好深度绑定，另一方坚持独立空间，陪伴频率需要明确协商。');
    }
    if (doubleLow > .32) {
      notes.add('双方主导承接力均偏低，遇到僵局容易互相等待安抚而停摆。');
    } else if (channel <= 52) {
      notes.add('情绪表达外显度或务实/意象频道存在温差，沟通需减少隐晦猜测。');
    } else if (notes.length < 2 && agency >= 84) {
      notes.add('关系节奏与主导权形成良性互补，日常协作阻力较低。');
    }
    if (notes.isEmpty) {
      notes.add('四项互动因子整体平稳，无结构性冲突，相处质量取决于日常沟通意愿。');
    }
    return KeiCompat(
      id: target.id,
      name: target.name,
      total: total,
      sub: {
        '依恋安全': security,
        '边界契合': boundary,
        '主导协同': agency,
        '表达频道': channel,
      },
      note: notes.take(2).join(),
    );
  }

  static List<double> normalizedVec(KeiPrototype p) {
    final mag = math.sqrt(p.dir.fold<double>(0, (s, v) => s + v * v));
    if (mag == 0) return List<double>.filled(p.dir.length, 0);
    return p.dir.map((v) => v / mag * radius).toList();
  }

  static double _dist(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return math.sqrt(sum);
  }

  static double _randn(math.Random random) {
    double u = 0;
    double v = 0;
    while (u == 0) {
      u = random.nextDouble();
    }
    while (v == 0) {
      v = random.nextDouble();
    }
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }
}
