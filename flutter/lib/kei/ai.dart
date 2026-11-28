import '../services/ai.dart';
import 'models.dart';

/// 十二系亲密关系测评的 CiCi 个性化解读。
///
/// 作为离线结构化报告的增量解读：任何请求失败都返回 null，
/// 不影响基础五维、原型与动力学分析的正常展示。
class KeiAi {
  const KeiAi._();

  /// 结合用户的五维向量、依恋象限与原型稳定率生成个性化关系洞察。
  static Future<String?> insight({
    required KeiResult result,
    KeiPrototype? proto,
  }) async {
    final dimLines = <String>[
      for (final d in result.dimensions)
        '${d.name}（${d.low} ↔ ${d.high}）：均值 ${d.mean.toStringAsFixed(2)}'
            '（95% 区间 ${d.ciLow.toStringAsFixed(2)} ~ ${d.ciHigh.toStringAsFixed(2)}）',
    ];
    final top2 = result.ranked
        .take(2)
        .map((e) => '${e.name} ${e.pct.toStringAsFixed(1)}%')
        .join('、');
    final bestNames = result.compatBest.map((e) => e.name).join('、');
    final hardNames = result.compatHard.map((e) => e.name).join('、');

    final prompt =
        '一位用户完成了十二系亲密关系（成人依恋）测评，结果如下：\n'
        '主原型：${result.typeName}${proto == null ? '' : '（${proto.en}）'}\n'
        '${proto == null ? '' : '原型描述：${proto.tagline}\n'}'
        '依恋象限：${result.attachment}\n'
        '构型模式：${result.profileMode}（主型稳定率 ${result.stabilityPct}%，轮廓集中度 ${result.sharpness}/100）\n'
        '主次原型占比：$top2\n'
        '${result.driftName != null ? '漂移倾向：有 ${result.driftPct}% 概率向${result.driftName}偏移\n' : ''}'
        '五维坐标（范围 -1 到 +1，正值偏右端，负值偏左端）：\n'
        '${dimLines.join('\n')}\n'
        '${bestNames.isNotEmpty ? '低摩擦协同原型：$bestNames\n' : ''}'
        '${hardNames.isNotEmpty ? '高张力磨合原型：$hardNames\n' : ''}'
        '\n请为他写一段 160~230 字的个性化关系解读，要求：\n'
        '1. 结合依恋象限与几个最突出的维度分值，描摹他在亲密关系里真实可见的互动画面（例如消息延迟、对方靠近或发生冷战时的本能反应）；\n'
        '2. 如果主型稳定率偏低或模长较均衡，点出他容易在不同姿态之间摇摆的特点，不要把原型当成死标签；\n'
        '3. 指出一个他在亲密关系里最容易反复踩进的循环，并给一条当下就能尝试的具体沟通动作；\n'
        '4. 语气温和、真诚、像懂他的朋友，不要堆砌心理学术语，不要 emoji，不要标题和列表，分成一到两段。';

    try {
      final text = await AiService.complete(
        prompt: prompt,
        system:
            '你是亲密关系测评解读助手，擅长把成人依恋与五维人际坐标翻译成克制、温暖、可对照日常相处的中文观察。'
            '你只做自我觉察参考，不做临床诊断或情绪煽动，不使用绝对化表述。',
        maxTokens: 900,
        temperature: 0.7,
      );
      final cleaned = text.trim();
      if (cleaned.length < 60) return null;
      return cleaned;
    } catch (_) {
      return null;
    }
  }
}
