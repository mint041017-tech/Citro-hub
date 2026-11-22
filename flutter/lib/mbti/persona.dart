import 'models.dart';
import 'scoring.dart';

/// 结果页的「专属切片」：全部由本次维度分与最终确认类型推出来，
/// 不再重复类型资料里的通用段落，让同一类型的不同分数也能读出差別。
class MbtiPersona {
  final String headline;
  final String summary;
  final String strongestLine;
  final String balanceLine;
  final String? atLine;
  final List<String> traits;
  final String tip;

  const MbtiPersona({
    required this.headline,
    required this.summary,
    required this.strongestLine,
    required this.balanceLine,
    required this.atLine,
    required this.traits,
    required this.tip,
  });
}

MbtiPersona buildMbtiPersona({
  required MbtiResult result,
  required MbtiBank bank,
  required TypeContent content,
  String? confirmed,
}) {
  final code = confirmed ?? result.typeRaw;
  final letters = <String, String>{
    for (var i = 0; i < 4; i++) ['EI', 'SN', 'TF', 'JP'][i]: code[i],
    if (result.scores['AT'] != null)
      'AT': confirmed == null
          ? result.scores['AT']!.letter
          : code.length > 4
          ? code[4]
          : result.scores['AT']!.letter,
  };

  final traits = <String>[
    _trait('EI', letters['EI']!),
    _trait('SN', letters['SN']!),
    _trait('TF', letters['TF']!),
    _trait('JP', letters['JP']!),
    if (letters['AT'] != null) _trait('AT', letters['AT']!),
  ];

  final dims = ['EI', 'SN', 'TF', 'JP', if (result.scores['AT'] != null) 'AT'];
  final weighed =
      dims.map((dim) => (dim: dim, score: result.scores[dim]!)).toList()
        ..sort((a, b) => b.score.value.abs().compareTo(a.score.value.abs()));
  final top = weighed.first;
  final topStrong = top.score.band != DimBand.center;
  final topMeta = bank.dimensions[top.dim]!;
  final topLetter = letters[top.dim]!;
  final topPct = topLetter == topMeta.left
      ? top.score.pctLeft
      : top.score.pctRight;
  final topName = topLetter == topMeta.left
      ? topMeta.leftName
      : topMeta.rightName;

  final balanced = dims
      .where((dim) => result.scores[dim]!.band == DimBand.center)
      .toList(growable: false);
  final balanceLine = balanced.isEmpty
      ? '四个主维度都有比较清晰的方向，按这套默认设置走会很省力。'
      : '${balanced.map((d) => bank.dimensions[d]!.leftName).join('、')}这几项更贴线，'
            '不是没主见，而是会看情境切换。';

  final headline = topStrong
      ? '${content.name}的「${_dimTitle(top.dim)}」最鲜明：$topName $topPct%'
      : '四项都贴线，你更像随情境切换的「变色龙型」';

  final summary = '作为${content.name}，${_summary(letters)}';
  final atLine = letters['AT'] == null
      ? null
      : letters['AT'] == 'T'
      ? '情绪底盘偏敏感：你对风险和他人的反应更敏锐，也更容易反复咀嚼一句话。'
      : '情绪底盘偏稳定：压力下更容易维持节奏，但别把“我能扛”当成不需要休息。';

  final tip = _tip(letters, balanced);

  return MbtiPersona(
    headline: headline,
    summary: summary,
    strongestLine: topStrong
        ? '${_dimTitle(top.dim)} · $topName $topPct%'
        : '四项倾向都不算强，你的适配面比单一类型更宽。',
    balanceLine: balanceLine,
    atLine: atLine,
    traits: traits,
    tip: tip,
  );
}

String _dimTitle(String dim) => switch (dim) {
  'EI' => '精力来源',
  'SN' => '信息偏好',
  'TF' => '决策方式',
  'JP' => '生活方式',
  _ => '情绪底盘',
};

String _trait(String dim, String letter) => switch ('$dim-$letter') {
  'EI-E' => '人群充电',
  'EI-I' => '独处回血',
  'SN-S' => '细节实感',
  'SN-N' => '联想可能',
  'TF-T' => '逻辑先行',
  'TF-F' => '感受先行',
  'JP-J' => '计划安心',
  'JP-P' => '弹性留白',
  'AT-A' => '稳定底盘',
  'AT-T' => '高敏雷达',
  _ => '顺势切换',
};

String _summary(Map<String, String> letters) {
  final e = letters['EI']!;
  final n = letters['SN']!;
  final t = letters['TF']!;
  final j = letters['JP']!;
  final clauses = <String>[
    e == 'E' ? '靠互动充电，想法常常边说边成形' : '靠独处回血，习惯先在心里想清楚',
    n == 'N' ? '先抓可能性和关联，脑子里常同时开着几条线' : '先抓事实和细节，更信任验证过的经验',
    t == 'T' ? '做决定先把逻辑摆平，给建议比较直接' : '做决定先照顾人的感受，很容易察觉气氛变化',
    j == 'J' ? '靠计划和定论获得安心，喜欢提前安排好' : '靠弹性和选择保持松弛，临时起意也不慌',
  ];
  return '你${clauses.join('；')}。';
}

String _tip(Map<String, String> letters, List<String> balanced) {
  final tips = <String>[
    if (letters['EI'] == 'I') '给自己留一段不被打扰的独处时间',
    if (letters['EI'] == 'E') '主动约一个低压力的小见面',
    if (letters['SN'] == 'N') '把一个飘着的联想写成一句可执行的话',
    if (letters['SN'] == 'S') '先把手边最小的一件事做完',
    if (letters['TF'] == 'T') '说结论前，先补一句“我理解你的感受”',
    if (letters['TF'] == 'F') '拒绝一次不想做的请求，不必解释太多',
    if (letters['JP'] == 'J') '给今天的计划留出 30 分钟空档',
    if (letters['JP'] == 'P') '把最想拖的那件事先做 10 分钟',
    if (letters['AT'] == 'T') '睡前写下今天已经做好的三件小事',
    if (letters['AT'] == 'A') '在状态很稳的时候，也主动休息一次',
  ];
  if (balanced.isNotEmpty) {
    tips.insert(0, '遇到需要站队的场景，先多给自己十分钟再下结论');
  }
  return '今天可以试试：${tips.take(2).join('；')}。';
}
