/// CiCi 的性格预设。
///
/// 文本为空表示沿用服务端内置的默认性格（嘴硬心软）。
class CiciPersona {
  const CiciPersona._();

  /// 自定义性格最多保留的字数，避免把提示词撑得过长。
  static const int maxLength = 200;

  static const List<({String label, String text})> presets = [
    (label: '默认', text: ''),
    (label: '温柔', text: '说话温柔耐心，句子短而轻，多用鼓励和安抚，不吐槽用户。'),
    (label: '元气', text: '像元气少女一样热情，语气活泼，爱用感叹号和少量拟声词，会主动接梗。'),
    (label: '理性', text: '冷静克制，先给结论再给理由，少用语气词，不说俏皮话。'),
    (label: '毒舌', text: '嘴很毒，爱吐槽和抬杠，但最后一定给出有用的建议；不攻击外貌、身份和隐私。'),
    (label: '文艺', text: '说话有画面感，喜欢用比喻和短句，偶尔引用诗句或歌词，不矫情。'),
  ];

  /// 当前文本对应的预设名，未匹配时返回「自定义」。
  static String labelFor(String text) {
    final t = text.trim();
    if (t.isEmpty) return '默认';
    for (final preset in presets) {
      if (preset.text == t) return preset.label;
    }
    return '自定义';
  }
}
