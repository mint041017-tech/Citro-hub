import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 测试版本：快速 28 题 / 标准 64 题 / 完整 96 题（含情绪维度 A-T）。
enum MbtiMode { quick, standard, full }

extension MbtiModeX on MbtiMode {
  String get label => switch (this) {
    MbtiMode.quick => '快速版',
    MbtiMode.standard => '标准版',
    MbtiMode.full => '完整版',
  };

  String get desc => switch (this) {
    MbtiMode.quick => '28 题 · 约 3 分钟 · 只出四字母，精度有限',
    MbtiMode.standard => '64 题 · 约 8 分钟 · 推荐，维度分更稳定',
    MbtiMode.full => '96 题 · 约 12 分钟 · 额外测情绪稳定性（-A/-T）',
  };

  String get key => name;

  static MbtiMode fromKey(String? key) => switch (key) {
    'quick' => MbtiMode.quick,
    'full' => MbtiMode.full,
    _ => MbtiMode.standard,
  };
}

class DimMeta {
  final String left;
  final String right;
  final String leftName;
  final String rightName;

  const DimMeta({
    required this.left,
    required this.right,
    required this.leftName,
    required this.rightName,
  });

  factory DimMeta.fromJson(Map<String, dynamic> j) => DimMeta(
    left: j['left'] as String,
    right: j['right'] as String,
    leftName: j['leftName'] as String,
    rightName: j['rightName'] as String,
  );
}

class MbtiQuestion {
  final String id;
  final String dim;
  final String facet;
  final String text;

  /// right = 同意该陈述偏向右端字母（I/N/F/P/T）；left = 偏向左端（E/S/T/J/A）。
  final String keyed;
  final bool std;
  final bool quick;
  final String? pair;

  const MbtiQuestion({
    required this.id,
    required this.dim,
    required this.facet,
    required this.text,
    required this.keyed,
    required this.std,
    required this.quick,
    this.pair,
  });

  factory MbtiQuestion.fromJson(Map<String, dynamic> j) => MbtiQuestion(
    id: j['id'] as String,
    dim: j['dim'] as String,
    facet: j['facet'] as String,
    text: j['text'] as String,
    keyed: j['keyed'] as String,
    std: j['std'] as bool? ?? false,
    quick: j['quick'] as bool? ?? false,
    pair: j['pair'] as String?,
  );

  /// 作答值 a∈[1,7] 映射到 [-3,3]，正值表示偏右端。
  int scoreOf(int a) => keyed == 'right' ? a - 4 : 4 - a;
}

class MbtiBank {
  final int version;
  final List<String> scaleLabels;
  final Map<String, DimMeta> dimensions;
  final List<MbtiQuestion> questions;

  const MbtiBank({
    required this.version,
    required this.scaleLabels,
    required this.dimensions,
    required this.questions,
  });

  /// 测试注入：flutter_test 的 fake async 环境下 rootBundle 二次加载会挂起，
  /// 测试时直接注入文件内容；生产环境保持 null，走资产包。
  static String? debugRaw;

  static Future<MbtiBank> load() async {
    final raw =
        debugRaw ?? await rootBundle.loadString('assets/mbti/questions.json');
    return MbtiBank.parse(raw);
  }

  static MbtiBank parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final dims = <String, DimMeta>{};
    (j['dimensions'] as Map<String, dynamic>).forEach((k, v) {
      dims[k] = DimMeta.fromJson(v as Map<String, dynamic>);
    });
    final scale = j['scale'] as Map<String, dynamic>;
    return MbtiBank(
      version: j['version'] as int? ?? 1,
      scaleLabels: (scale['labels'] as List).cast<String>(),
      dimensions: dims,
      questions: (j['questions'] as List)
          .map((e) => MbtiQuestion.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 按版本抽题，保持四维交替的作答顺序（避免同维连答产生节奏偏差）。
  List<MbtiQuestion> questionsFor(MbtiMode mode) {
    final selected = questions.where((q) {
      switch (mode) {
        case MbtiMode.quick:
          return q.quick;
        case MbtiMode.standard:
          return q.std;
        case MbtiMode.full:
          return true;
      }
    }).toList();
    // 分组后按轮次交错：EI/SN/TF/JP(/AT) 轮流出现。
    final byDim = <String, List<MbtiQuestion>>{};
    for (final q in selected) {
      byDim.putIfAbsent(q.dim, () => []).add(q);
    }
    final order = ['EI', 'SN', 'TF', 'JP', 'AT'].where(byDim.containsKey);
    final out = <MbtiQuestion>[];
    var index = 0;
    while (out.length < selected.length) {
      for (final dim in order) {
        final list = byDim[dim]!;
        if (index < list.length) out.add(list[index]);
      }
      index++;
    }
    return out;
  }
}

class TypeContent {
  final String code;
  final String name;
  final String group;
  final String tagline;
  final List<String> keywords;
  final List<String> strengths;
  final List<String> pitfalls;
  final Map<String, String> scenes;
  final List<String> growth;
  final List<String> stack;
  final String stackText;

  const TypeContent({
    required this.code,
    required this.name,
    required this.group,
    required this.tagline,
    required this.keywords,
    required this.strengths,
    required this.pitfalls,
    required this.scenes,
    required this.growth,
    required this.stack,
    required this.stackText,
  });

  factory TypeContent.fromJson(Map<String, dynamic> j) => TypeContent(
    code: j['code'] as String,
    name: j['name'] as String,
    group: j['group'] as String,
    tagline: j['tagline'] as String,
    keywords: (j['keywords'] as List).cast<String>(),
    strengths: (j['strengths'] as List).cast<String>(),
    pitfalls: (j['pitfalls'] as List).cast<String>(),
    scenes: (j['scenes'] as Map).map((k, v) => MapEntry('$k', '$v')),
    growth: (j['growth'] as List).cast<String>(),
    stack: (j['stack'] as List).cast<String>(),
    stackText: j['stackText'] as String,
  );
}

class TypeLibrary {
  final Map<String, String> groupNames;
  final Map<String, String> groupDescs;
  final Map<String, TypeContent> types;

  const TypeLibrary({
    required this.groupNames,
    required this.groupDescs,
    required this.types,
  });

  /// 测试注入，同 [MbtiBank.debugRaw]。
  static String? debugRaw;

  static Future<TypeLibrary> load() async {
    final raw =
        debugRaw ?? await rootBundle.loadString('assets/mbti/types.json');
    return TypeLibrary.parse(raw);
  }

  static TypeLibrary parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final groups = <String, String>{};
    final descs = <String, String>{};
    (j['groups'] as Map<String, dynamic>).forEach((k, v) {
      groups[k] = (v as Map)['name'] as String;
      descs[k] = (v)['desc'] as String;
    });
    final types = <String, TypeContent>{};
    for (final e in (j['types'] as List)) {
      final t = TypeContent.fromJson(e as Map<String, dynamic>);
      types[t.code] = t;
    }
    return TypeLibrary(groupNames: groups, groupDescs: descs, types: types);
  }

  TypeContent? byCode(String? code) => code == null ? null : types[code];
}
