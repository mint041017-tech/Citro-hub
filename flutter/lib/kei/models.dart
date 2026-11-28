import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class KeiDimensionMeta {
  final String id;
  final String code;
  final String name;
  final String low;
  final String high;
  final String desc;

  const KeiDimensionMeta({
    required this.id,
    required this.code,
    required this.name,
    required this.low,
    required this.high,
    required this.desc,
  });

  factory KeiDimensionMeta.fromJson(Map<String, dynamic> j) => KeiDimensionMeta(
    id: '${j['id']}',
    code: '${j['code']}',
    name: '${j['name']}',
    low: '${j['low']}',
    high: '${j['high']}',
    desc: '${j['desc']}',
  );
}

class KeiQuestion {
  final String dim;
  final int dir;
  final String? mirror;
  final String text;

  const KeiQuestion({
    required this.dim,
    required this.dir,
    this.mirror,
    required this.text,
  });

  factory KeiQuestion.fromJson(Map<String, dynamic> j) => KeiQuestion(
    dim: '${j['dim']}',
    dir: (j['dir'] as num).toInt(),
    mirror: j['mirror']?.toString(),
    text: '${j['text']}',
  );
}

class KeiPrototype {
  final String id;
  final String name;
  final String en;
  final String accent;
  final String rgb;
  final List<double> dir;
  final String tagline;
  final String mechanism;
  final String behavior;
  final String blindspot;

  const KeiPrototype({
    required this.id,
    required this.name,
    required this.en,
    required this.accent,
    required this.rgb,
    required this.dir,
    required this.tagline,
    required this.mechanism,
    required this.behavior,
    required this.blindspot,
  });

  factory KeiPrototype.fromJson(Map<String, dynamic> j) => KeiPrototype(
    id: '${j['id']}',
    name: '${j['name']}',
    en: '${j['en']}',
    accent: '${j['accent']}',
    rgb: '${j['rgb']}',
    dir: (j['dir'] as List).map((e) => (e as num).toDouble()).toList(),
    tagline: '${j['tagline']}',
    mechanism: '${j['mechanism']}',
    behavior: '${j['behavior']}',
    blindspot: '${j['blindspot']}',
  );
}

class KeiBank {
  final int version;
  final List<KeiDimensionMeta> dimensions;
  final List<KeiQuestion> questions;
  final List<KeiPrototype> prototypes;

  const KeiBank({
    required this.version,
    required this.dimensions,
    required this.questions,
    required this.prototypes,
  });

  static String? debugRaw;

  static Future<KeiBank> load() async {
    final raw = debugRaw ?? await rootBundle.loadString('assets/kei/kei.json');
    return KeiBank.parse(raw);
  }

  static KeiBank parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return KeiBank(
      version: (j['version'] as num?)?.toInt() ?? 1,
      dimensions: (j['dimensions'] as List)
          .map((e) => KeiDimensionMeta.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      questions: (j['questions'] as List)
          .map((e) => KeiQuestion.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      prototypes: (j['prototypes'] as List)
          .map((e) => KeiPrototype.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  KeiPrototype? byId(String? id) {
    if (id == null) return null;
    for (final p in prototypes) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class KeiDimensionScore {
  final String id;
  final String code;
  final String name;
  final String low;
  final String high;
  final double mean;
  final double se;
  final double ciLow;
  final double ciHigh;

  const KeiDimensionScore({
    required this.id,
    required this.code,
    required this.name,
    required this.low,
    required this.high,
    required this.mean,
    required this.se,
    required this.ciLow,
    required this.ciHigh,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'low': low,
    'high': high,
    'mean': mean,
    'se': se,
    'ciLow': ciLow,
    'ciHigh': ciHigh,
  };

  factory KeiDimensionScore.fromJson(Map<String, dynamic> j) =>
      KeiDimensionScore(
        id: '${j['id']}',
        code: '${j['code']}',
        name: '${j['name']}',
        low: '${j['low']}',
        high: '${j['high']}',
        mean: (j['mean'] as num).toDouble(),
        se: (j['se'] as num).toDouble(),
        ciLow: (j['ciLow'] as num).toDouble(),
        ciHigh: (j['ciHigh'] as num).toDouble(),
      );
}

class KeiTypeScore {
  final String id;
  final String name;
  final double prob;
  final double pct;
  final double dist;

  const KeiTypeScore({
    required this.id,
    required this.name,
    required this.prob,
    required this.pct,
    required this.dist,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prob': prob,
    'pct': pct,
    'dist': dist,
  };

  factory KeiTypeScore.fromJson(Map<String, dynamic> j) => KeiTypeScore(
    id: '${j['id']}',
    name: '${j['name']}',
    prob: (j['prob'] as num).toDouble(),
    pct: (j['pct'] as num).toDouble(),
    dist: (j['dist'] as num).toDouble(),
  );
}

class KeiCompat {
  final String id;
  final String name;
  final int total;
  final Map<String, int> sub;
  final String note;

  const KeiCompat({
    required this.id,
    required this.name,
    required this.total,
    required this.sub,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'total': total,
    'sub': sub,
    'note': note,
  };

  factory KeiCompat.fromJson(Map<String, dynamic> j) => KeiCompat(
    id: '${j['id']}',
    name: '${j['name']}',
    total: (j['total'] as num?)?.toInt() ?? 0,
    sub:
        (j['sub'] as Map?)?.map((k, v) => MapEntry('$k', (v as num).toInt())) ??
        const {},
    note: '${j['note'] ?? ''}',
  );
}

class KeiAudit {
  final int longstring;
  final double ars;
  final int ersPct;
  final int antonymScore;
  final double medianSec;
  final String validityStatus;
  final bool validityWarn;
  final List<String> warnings;

  const KeiAudit({
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

  factory KeiAudit.fromJson(Map<String, dynamic> j) => KeiAudit(
    longstring: (j['longstring'] as num?)?.toInt() ?? 1,
    ars: (j['ars'] as num?)?.toDouble() ?? 0,
    ersPct: (j['ersPct'] as num?)?.toInt() ?? 0,
    antonymScore: (j['antonymScore'] as num?)?.toInt() ?? 0,
    medianSec: (j['medianSec'] as num?)?.toDouble() ?? 0,
    validityStatus: '${j['validityStatus'] ?? '可靠'}',
    validityWarn: j['validityWarn'] == true,
    warnings: ((j['warnings'] as List?) ?? [])
        .map((e) => '$e')
        .toList(growable: false),
  );
}

class KeiResult {
  final String typeId;
  final String typeName;
  final List<double> vec;
  final List<KeiDimensionScore> dimensions;
  final List<KeiTypeScore> ranked;
  final int stabilityPct;
  final String? driftName;
  final int? driftPct;
  final String profileMode;
  final String attachment;
  final int sharpness;
  final double norm;
  final String synthesis;
  final List<KeiCompat> compatBest;
  final List<KeiCompat> compatHard;
  final KeiAudit? audit;

  const KeiResult({
    required this.typeId,
    required this.typeName,
    required this.vec,
    required this.dimensions,
    required this.ranked,
    required this.stabilityPct,
    this.driftName,
    this.driftPct,
    required this.profileMode,
    required this.attachment,
    required this.sharpness,
    required this.norm,
    this.synthesis = '',
    this.compatBest = const [],
    this.compatHard = const [],
    this.audit,
  });

  Map<String, dynamic> toJson() => {
    'typeId': typeId,
    'typeName': typeName,
    'vec': vec,
    'dims': dimensions.map((e) => e.toJson()).toList(),
    'ranked': ranked.map((e) => e.toJson()).toList(),
    'stabilityPct': stabilityPct,
    'driftName': driftName,
    'driftPct': driftPct,
    'profileMode': profileMode,
    'attachment': attachment,
    'sharpness': sharpness,
    'norm': norm,
    'synthesis': synthesis,
    'compatBest': compatBest.map((e) => e.toJson()).toList(),
    'compatHard': compatHard.map((e) => e.toJson()).toList(),
    'audit': audit?.toJson(),
  };

  factory KeiResult.fromJson(Map<String, dynamic> j) => KeiResult(
    typeId: '${j['typeId']}',
    typeName: '${j['typeName']}',
    vec: (j['vec'] as List).map((e) => (e as num).toDouble()).toList(),
    dimensions: (j['dims'] as List)
        .map((e) => KeiDimensionScore.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    ranked: (j['ranked'] as List)
        .map((e) => KeiTypeScore.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    stabilityPct: (j['stabilityPct'] as num?)?.toInt() ?? 0,
    driftName: j['driftName']?.toString(),
    driftPct: (j['driftPct'] as num?)?.toInt(),
    profileMode: '${j['profileMode'] ?? ''}',
    attachment: '${j['attachment'] ?? ''}',
    sharpness: (j['sharpness'] as num?)?.toInt() ?? 0,
    norm: (j['norm'] as num?)?.toDouble() ?? 0,
    synthesis: '${j['synthesis'] ?? ''}',
    compatBest: ((j['compatBest'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => KeiCompat.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    compatHard: ((j['compatHard'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => KeiCompat.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    audit: j['audit'] is Map
        ? KeiAudit.fromJson(Map<String, dynamic>.from(j['audit'] as Map))
        : null,
  );
}

class KeiRecord {
  final String id;
  final int takenAtMs;
  final int updatedAtMs;
  final KeiResult result;

  /// CiCi 生成的个性化解读文案；旧记录或未生成时为空。
  final String? aiInsight;

  const KeiRecord({
    required this.id,
    required this.takenAtMs,
    required this.result,
    this.aiInsight,
    this.updatedAtMs = 0,
  });

  int get effectiveUpdatedAt => updatedAtMs > 0 ? updatedAtMs : takenAtMs;

  /// 复制记录并按需更新 AI 解读或修改时间戳。
  KeiRecord copyWith({
    String? aiInsight,
    int? updatedAtMs,
  }) => KeiRecord(
    id: id,
    takenAtMs: takenAtMs,
    result: result,
    aiInsight: aiInsight ?? this.aiInsight,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'takenAt': takenAtMs,
    'updatedAt': effectiveUpdatedAt,
    'result': result.toJson(),
    if (aiInsight != null) 'aiInsight': aiInsight,
  };

  factory KeiRecord.fromJson(Map<String, dynamic> j) {
    final taken = j['takenAt'];
    final updated = j['updatedAt'];
    return KeiRecord(
      id: '${j['id'] ?? ''}',
      takenAtMs: taken is num ? taken.toInt() : 0,
      updatedAtMs: updated is num ? updated.toInt() : 0,
      result: KeiResult.fromJson(Map<String, dynamic>.from(j['result'] as Map)),
      aiInsight: j['aiInsight'] as String?,
    );
  }
}
