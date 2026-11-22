import 'dart:convert';

import '../data/fortunes.dart';
import '../services/ai.dart';
import '../services/prefs.dart';
import 'prompt.dart';

/// 一次「今日解签」的结果。
///
/// 只装模型写出来的那部分：签的等级、签类、骨架仍然来自本地签池，
/// 这样 AI 不可用时签面不会空。
class FortuneAiSign {
  const FortuneAiSign({
    required this.title,
    required this.poem,
    required this.read,
    required this.keywords,
    required this.doText,
    required this.dontText,
    required this.note,
  });

  final String title;
  final List<String> poem;
  final String read;
  final List<String> keywords;
  final String doText;
  final String dontText;
  final String note;

  bool get isComplete => title.isNotEmpty && read.length >= 30;

  Map<String, dynamic> toJson() => {
    'title': title,
    'poem': poem,
    'read': read,
    'keywords': keywords,
    'do': doText,
    'dont': dontText,
    'note': note,
  };

  static FortuneAiSign? fromJson(Map<String, dynamic> j) {
    final title = _clean('${j['title'] ?? ''}');
    final read = _clean('${j['read'] ?? ''}');
    if (title.isEmpty || read.length < 30) return null;
    final poem = _list(j['poem']);
    final keywords = _list(j['keywords']);
    return FortuneAiSign(
      title: title.length > 14 ? title.substring(0, 14) : title,
      poem: poem.take(3).toList(),
      read: read.length > 260 ? read.substring(0, 260) : read,
      keywords: keywords.take(5).toList(),
      doText: _clean('${j['do'] ?? ''}').replaceAll(RegExp(r'[。；;]'), ''),
      dontText: _clean('${j['dont'] ?? ''}').replaceAll(RegExp(r'[。；;]'), ''),
      note: _clean('${j['note'] ?? ''}'),
    );
  }

  static List<String> _list(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => _clean('$e')).where((e) => e.isNotEmpty).toList();
    }
    final text = _clean('${raw ?? ''}');
    if (text.isEmpty) return const [];
    return text
        .split(RegExp(r'[\n｜|/、，,]+'))
        .map(_clean)
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String _clean(String raw) {
    var text = raw.trim();
    // 模型偶尔会自己加代码围栏或加粗，签面上不该出现这些符号。
    text = text.replaceAll(RegExp(r'```[a-zA-Z]*'), '');
    text = text.replaceAll(RegExp(r'[`*#]'), '');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }
}

/// 从模型返回的原文里解析出签。允许前后有解释、代码块或多余标点；
/// 结构不成立就返回 null，由 UI 退回本地签文。
FortuneAiSign? parseAiSign(String raw) {
  var text = raw;
  final fence = RegExp(r'```[a-zA-Z]*\n?').firstMatch(text);
  if (fence != null) text = text.replaceAll(RegExp(r'```[a-zA-Z]*'), '');
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final json = jsonDecode(text.substring(start, end + 1));
    if (json is! Map) return null;
    return FortuneAiSign.fromJson(json.cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

/// 生成 / 读取当天的「今日解」。
///
/// 同一天同一支签只请求一次，落在本地缓存里；换签（转运）时等级变了，
/// 缓存键跟着变，会重新写一份。任何失败都返回 null，不抛异常。
class FortuneAi {
  static const String _prefix = 'citro_fortune_ai_';

  static String cacheKey(Fortune fortune, DateTime day) {
    final d =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return '$_prefix${d}_${fortune.idx ?? 0}';
  }

  static Future<FortuneAiSign?> loadOrGenerate({
    required Fortune fortune,
    required DateTime day,
    required int streak,
    required String weekday,
    String? lunar,
    String? festival,
    String? term,
    String? cardLabel,
    bool force = false,
  }) async {
    final key = cacheKey(fortune, day);
    if (!force) {
      final cached = Prefs.getString(key);
      if (cached != null) {
        try {
          final j = jsonDecode(cached);
          if (j is Map) {
            final sign = FortuneAiSign.fromJson(j.cast<String, dynamic>());
            if (sign != null) return sign;
          }
        } catch (_) {}
      }
    }
    final prompt = buildFortunePrompt(
      day: day,
      weekday: weekday,
      streak: streak,
      level: fortune.lv,
      kindLabel: fortuneKindLabel(fortune.kind),
      baseName: fortune.name,
      baseDesc: fortune.desc,
      baseYi: fortune.yi,
      baseJi: fortune.ji,
      lunar: lunar,
      festival: festival,
      term: term,
      cardLabel: cardLabel,
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final raw = await AiService.complete(
          prompt: prompt,
          system: kFortuneSystemPrompt,
          maxTokens: 760,
          temperature: .8,
        );
        final sign = parseAiSign(raw);
        if (sign != null) {
          await Prefs.setString(key, jsonEncode(sign.toJson()));
          return sign;
        }
      } catch (_) {
        // 网络/AI 不可用：不重试到超时，直接退回本地签文。
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          continue;
        }
        return null;
      }
    }
    return null;
  }
}
