import '../services/ai.dart';
import 'models.dart';
import 'scoring.dart';

/// 用项目现有 GLM 代理生成个性化解读。
///
/// 只作为模板报告的增量：任何失败都返回 null，UI 直接隐藏，
/// 不影响离线可用的基础报告。
class MbtiAi {
  static Future<String?> insight({
    required MbtiResult result,
    required TypeContent content,
    required MbtiBank bank,
    String? typeConfirmed,
  }) async {
    final dimLines = <String>[];
    for (final dim in ['EI', 'SN', 'TF', 'JP', 'AT']) {
      final s = result.scores[dim];
      if (s == null) continue;
      final meta = bank.dimensions[dim]!;
      dimLines.add(
        '$dim：${meta.leftName}${s.pctLeft}% / ${meta.rightName}${s.pctRight}%'
        '（${s.band == DimBand.center ? '贴线，倾向不明显' : s.band == DimBand.mild ? '倾向温和' : '倾向明确'}）',
      );
    }
    final prompt =
        '一位用户完成了 16 型人格测试，结果如下：\n'
        '类型：${result.displayType}（${content.name}）\n'
        '${typeConfirmed != null && typeConfirmed != result.typeRaw ? '用户作答类型为 ${result.typeRaw}，但自评确认更接近 $typeConfirmed。\n' : ''}'
        '${dimLines.join('\n')}\n\n'
        '该类型的通用画像：${content.tagline}\n\n'
        '请为他写一段 150~220 字的个性化解读，要求：\n'
        '1. 结合每个维度的具体百分比说话，贴线维度要指出"这一项两边都沾一点"，不要当成铁律；\n'
        '2. 写具体行为画面（工作/社交/独处时的样子），不要空泛的夸奖，不要"你是一个……的人"式标签堆砌；\n'
        '3. 指出一个他最容易踩的坑，并给一条可执行的小建议；\n'
        '4. 语气温和、直接，像懂他的朋友，不要心理学术语，不要emoji，不要标题和列表，一整段或两段。';
    try {
      final text = await AiService.complete(
        prompt: prompt,
        system:
            '你是人格测试报告撰写助手，擅长把心理测量结果翻译成具体、克制、可对照的中文描述。'
            '你只做自我探索参考，不做心理诊断，不夸大结论，不使用绝对化表述。',
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
