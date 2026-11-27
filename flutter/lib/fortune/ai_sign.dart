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
    this.finished = false,
  });

  final String title;
  final List<String> poem;
  final String read;
  final List<String> keywords;
  final String doText;
  final String dontText;
  final String note;

  /// 这一帧是不是流的最后一帧。UI 用它区分「只回来一半」和「真的写完了」。
  final bool finished;

  bool get isComplete => title.isNotEmpty && read.length >= 30;

  FortuneAiSign withDo(String step) => FortuneAiSign(
    title: title,
    poem: poem,
    read: read,
    keywords: keywords,
    doText: step,
    dontText: dontText,
    note: note,
    finished: finished,
  );

  FortuneAiSign withFinished() => FortuneAiSign(
    title: title,
    poem: poem,
    read: read,
    keywords: keywords,
    doText: doText,
    dontText: dontText,
    note: note,
    finished: true,
  );

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

/// 签文的分段文本协议。固定顺序：
/// 签题 → 诗 → 读签 → 关键词 → 今日一小步 → 忌 → 便签。
///
/// 每段以 `@@段名` 单独起行；这样浏览器和 SSE 都能一段一段地解析，
/// 不必等完整 JSON，也不用在客户端猜 JSON 有没有闭合。
/// [partial] 为 true 时允许读签、诗、签题写到一半；「今日一小步」要等
/// 下一段标记出现后才放进结果，避免把半截动作先显示出来。
FortuneAiSign? parseSegmentedSign(String raw, {bool partial = false}) {
  final text = raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'```[a-zA-Z]*'), '');
  final sections = <String, List<String>>{};
  final closed = <String>{};
  String? current;
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    final marker = _markerPattern.firstMatch(trimmed);
    if (marker != null) {
      if (current != null) closed.add(current);
      current = marker.group(1);
      final inline = (marker.group(2) ?? '').trim();
      final body = sections.putIfAbsent(current!, () => <String>[]);
      if (inline.isNotEmpty) body.add(inline);
      continue;
    }
    if (current != null) sections[current]!.add(line);
  }

  final titleRaw = _section(sections, '签题');
  final readRaw = _section(sections, '读签');
  final poem = _lines(sections['诗'] ?? const <String>[]);
  final title = _title(titleRaw);
  final read = _inline(readRaw);

  // 还没出现任何一段：等下一块 SSE。已经出现签题但读签没写完时可以
  // 先给签面，让「签房先生」真的像在落笔。
  if (title.isEmpty && read.isEmpty && poem.isEmpty) return null;
  if (!partial && (title.isEmpty || read.length < 30)) return null;

  final keywordsClosed = !partial || closed.contains('关键词');
  final doClosed = !partial || closed.contains('今日一小步');
  final dontClosed = !partial || closed.contains('忌');
  final noteClosed = !partial || closed.contains('便签');

  return FortuneAiSign(
    title: title.length > 14 ? title.substring(0, 14) : title,
    poem: poem.take(2).toList(),
    read: read.length > 260 ? read.substring(0, 260) : read,
    keywords: keywordsClosed
        ? _splitList(_section(sections, '关键词')).take(5).toList()
        : const [],
    doText: doClosed ? _action(_section(sections, '今日一小步')) : '',
    dontText: dontClosed
        ? _inline(_section(sections, '忌')).replaceAll(RegExp(r'[。；;]'), '')
        : '',
    note: noteClosed ? _inline(_section(sections, '便签')) : '',
  );
}

final RegExp _markerPattern = RegExp(
  r'^(?:@@\s*|【)(签题|诗|读签|关键词|今日一小步|忌|便签)(?:】|\s*[:：]?)\s*(.*)$',
);

String _section(Map<String, List<String>> sections, String name) =>
    (sections[name] ?? const <String>[]).join('\n').trim();

List<String> _lines(List<String> raw) => raw
    .map((line) => _cleanLine(line))
    .where((line) => line.isNotEmpty)
    .toList();

String _cleanLine(String raw) {
  var line = raw.trim();
  line = line.replaceFirst(RegExp(r'^[-•·*\d]+[.、)）]?\s*'), '');
  line = line.replaceAll(RegExp(r'[`*#]'), '');
  return line.trim();
}

String _title(String raw) {
  final first = _cleanLine(raw.split('\n').first);
  return first
      .replaceAll(RegExp(r'^[「『“"]|[」』”"]$'), '')
      .replaceAll(RegExp(r'[。；;：:]$'), '')
      .trim();
}

String _inline(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

String _action(String raw) {
  final text = _inline(raw);
  return text
      .replaceAll(RegExp(r'^[「『“"]|[」』”"]$'), '')
      .replaceAll(RegExp(r'[。；;，,]$'), '')
      .trim();
}

List<String> _splitList(String raw) => raw
    .split(RegExp(r'[\n、，,｜|/;；]+'))
    .map(_cleanLine)
    .map((item) => item.replaceAll(RegExp(r'^[「『“"]|[」』”"]$'), ''))
    .where((item) => item.isNotEmpty)
    .toList();

/// 「今日一小步」必须是不依赖别人、不依赖特定地点/购买/预约的动作。
/// 模型有时会写「给妈妈发一句」「把事交给同事」这类看似具体、实际做不了
/// 的任务；这里做一道生成后的硬校验，不合格就换成手边能做的动作。
const List<String> kFortuneFallbackSteps = [
  '把桌面上三样东西放回原位',
  '把手机里今天拍的三张截图删掉',
  '把杯子洗了倒扣在架子上',
  '把明天第一件事写在纸上折好',
  '给手机充上电放在桌角',
  '把衣柜最外面的两件衣服挂好',
  '把桌面上的充电线收进抽屉',
  '把垃圾袋系好放到门口',
  '把键盘表面的灰擦一遍',
  '把包里不用的票据丢掉',
  '把镜子上的水渍擦干净',
  '把明天要穿的衣服摆到椅背',
  '把冰箱里过期的一盒东西扔掉',
  '把书架上歪着的三本书扶正',
  '把鞋子摆齐鞋头朝外',
  '把水杯加满放到手边',
  '把窗户推开一条缝站一会儿',
  '把手机通知清空只留三条',
  '把桌角的纸张按大小叠好',
  '把充电线理顺用夹子固定',
  '把外套挂起来口袋掏空',
  '把桌面上的空瓶扔进回收袋',
  '把明天要带的钥匙放到门口',
  '把电脑桌面三个图标归档',
  '把耳机线擦一遍放回盒子',
  '把日历上今天的事划掉',
  '把一张纸对折写下三件待办',
  '把床边的东西归到一处',
  '把冰箱门上过期的贴纸撕掉',
  '把鞋柜里最外面的两双鞋摆正',
];

/// 校验模型写的「今日一小步」：动词开头、有手边落点、能核对。
bool isReasonableStep(String raw) {
  final text = raw
      .trim()
      .replaceFirst(RegExp(r'^[-•·*\d]+[.、)）]?\s*'), '')
      .replaceAll(RegExp(r'[「『“"]|[」』”"]'), '')
      .trim();
  if (text.length < 8 || text.length > 30) return false;

  // 需要别人、通讯、外出、购买或预约的任务，默认这个人此刻做不了。
  if (RegExp(
    r'妈妈|爸爸|父母|家人|同事|老板|领导|客户|朋友|对象|男朋友|女朋友|老公|老婆|孩子|宝宝|老师|同学|邻居|快递|外卖|客服|商家|医生|护士|那个人',
  ).hasMatch(text)) {
    return false;
  }
  if (RegExp(
    r'打电话|发消息|发微信|回.*(话|消息|信)|联系|约.*(人|会)|邀请|告诉|交给|递给|帮.*(做|拿|带|买)|替.*(做|决定|拿)',
  ).hasMatch(text)) {
    return false;
  }
  if (RegExp(
    r'出门|下楼|散步|跑步|走路|遛|逛街|买菜|上班|上学|去趟|前往|到店|超市|商场|便利店|药店|医院|银行|餐厅|咖啡馆|健身房|公园|地铁|公交|打车|骑车',
  ).hasMatch(text)) {
    return false;
  }
  if (RegExp(r'下单|购买|预约|挂号|缴费|转账|付款|充值|点外卖|取快递|寄快递|买一|买个').hasMatch(text)) {
    return false;
  }
  // 没有落点的「整理一下 / 调整心态 / 早点休息」不算动作。
  if (RegExp(
    r'整理一下|收拾一下|调整|放松|休息|早点睡|多陪|想一想|思考|反思|感受|允许自己|照顾好自己|爱自己|断舍离|提升|成长|复盘|总结|计划|规划|保持|坚持|注意|留意|关注|享受|放空|发呆',
  ).hasMatch(text)) {
    return false;
  }

  // 动词开头，且必须落到手边物件或身体动作上。
  final startsWithVerb = RegExp(
    r'^[把给写列删洗擦收放关开倒换叠扔清数读抄贴设调截拍整挑拣选记查录打晾挂装拆扫拖浇喂称量剪撕折按点存传看听喝吃起站坐伸泡冲煮热切刷晒丢充拔插连断更确核对于翻锁摆归分标勾登备退取戴脱穿铺盖卷套抹捡拎提搬推拉挪移蹬踩踏踢弯腰抬头转身蹲跳深呼吸闭远眺]',
  ).hasMatch(text);
  if (!startsWithVerb) return false;

  final hasObject = RegExp(
    r'桌|杯|水|手机|纸|笔|稿|文档|笔记|衣柜|衣|鞋|包|床|枕|被|书|电脑|键盘|充电|线|垃圾|地面|窗|门|冰箱|碗|盘|筷|勺|毛巾|牙刷|镜|钥匙|耳机|桌面|抽屉|柜|沙发|椅|墙|灯|开关|遥控|瓶|罐|袋|盒|箱|伞|眼镜|表|钱包|证|票|账本|日历|清单|截图|照片|文件|邮件|通知|缓存|相册|指甲|头发|脸|牙|手|脚|肩|腰|背|眼',
  ).hasMatch(text);
  final bodyAction = RegExp(
    r'深呼吸|站起来|坐下|伸个懒腰|喝一口水|眨眨眼|洗把脸|刷牙|洗脸|洗手|闭眼|远眺|转肩|拉伸',
  ).hasMatch(text);
  return hasObject || bodyAction;
}

/// 给这支签配一条安全的「今日一小步」：优先用本地签池，其次用通用动作池。
String fallbackStepFor(Fortune fortune, DateTime day) {
  final local = (fortune.step ?? '').trim();
  if (local.isNotEmpty && isReasonableStep(local)) return local;
  final idx = fortune.idx ?? 0;
  final seed = idx * 7 + day.year + day.month * 31 + day.day;
  return kFortuneFallbackSteps[seed % kFortuneFallbackSteps.length];
}

FortuneAiSign _withSafeStep(FortuneAiSign sign, Fortune fortune, DateTime day) {
  if (isReasonableStep(sign.doText)) return sign;
  return sign.withDo(fallbackStepFor(fortune, day));
}

/// 生成 / 读取当天的「今日解」。
///
/// 同一天同一支签只请求一次，落在本地缓存里；换签（转运）时等级变了，
/// 缓存键跟着变，会重新写一份。任何失败都返回 null，不抛异常。
class FortuneAi {
  static const String _prefix = 'citro_fortune_ai_';

  /// 缓存键：日期 + 等级（+ 账号）。
  /// 不带账号时，同一台设备换个人登录会直接读到上一个人的解签。
  static String cacheKey(Fortune fortune, DateTime day, [String owner = '']) {
    final d =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final tail = owner.trim().isEmpty ? '' : '_${owner.trim()}';
    return '$_prefix${d}_${fortune.idx ?? 0}$tail';
  }

  /// 流式生成：每解析出一段就交给签面，最后再落缓存。
  ///
  /// 旧缓存仍是完整 JSON，直接读出来当第一帧；新缓存也继续写 JSON，
  /// 保证回退格式与旧版本兼容。
  static Stream<FortuneAiSign> streamOrGenerate({
    required Fortune fortune,
    required DateTime day,
    required int streak,
    required String weekday,
    String? lunar,
    String? festival,
    String? term,
    String? cardLabel,
    String owner = '',
    bool force = false,
  }) async* {
    final key = cacheKey(fortune, day, owner);
    if (!force) {
      final cached = Prefs.getString(key);
      if (cached != null) {
        try {
          final j = jsonDecode(cached);
          if (j is Map) {
            final sign = FortuneAiSign.fromJson(j.cast<String, dynamic>());
            if (sign != null) {
              yield _withSafeStep(sign, fortune, day).withFinished();
              return;
            }
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
      angle: fortuneAngleFor(owner: owner, day: day, idx: fortune.idx ?? 0),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      final buffer = StringBuffer();
      DateTime? lastEmit;
      try {
        await for (final chunk in AiService.stream(
          [
            {'role': 'user', 'content': prompt},
          ],
          system: kFortuneSystemPrompt,
          maxTokens: 820,
          temperature: .8,
        )) {
          buffer.write(chunk);
          final partial = parseSegmentedSign(buffer.toString(), partial: true);
          if (partial == null) continue;
          final now = DateTime.now();
          if (lastEmit == null ||
              now.difference(lastEmit) >= const Duration(milliseconds: 90)) {
            lastEmit = now;
            yield partial;
          }
        }
        final raw = buffer.toString();
        final sign =
            parseSegmentedSign(raw) ??
            // 模型偶尔不守协议、仍回完整 JSON：老解析器兜住。
            parseAiSign(raw);
        if (sign != null) {
          final safe = _withSafeStep(sign, fortune, day);
          await Prefs.setString(key, jsonEncode(safe.toJson()));
          yield safe.withFinished();
          return;
        }
      } catch (_) {
        // 网络/AI 不可用：不重试到超时，直接退回本地签文。
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          continue;
        }
        return;
      }
    }
  }
}
