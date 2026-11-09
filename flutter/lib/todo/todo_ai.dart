import 'dart:convert';

import '../services/ai.dart';
import 'todo_models.dart';

/// AI 返回的一条任务草稿。字段都做过容错，允许模型少给。
class TodoDraft {
  final String title;
  final TodoKind kind;
  final String categoryName;
  final String note;
  final DateTime? at;
  final Set<int> days;
  final String time;
  final List<String> subtasks;
  final int priority;

  /// true 表示不是新建，而是给已有任务补备注/改时间。
  final bool update;

  const TodoDraft({
    required this.title,
    this.kind = TodoKind.task,
    this.categoryName = '',
    this.note = '',
    this.at,
    this.days = const {},
    this.time = '20:00',
    this.subtasks = const [],
    this.priority = 0,
    this.update = false,
  });
}

/// 待办模块的 AI 能力：整理、拆解、总结、建议。
class TodoAi {
  TodoAi._();

  /// 测试钩子：替换真实请求。
  static Future<String> Function(String prompt, String system)? completer;

  static Future<String> _complete(
    String prompt,
    String system, {
    int maxTokens = 1200,
    double temperature = .35,
  }) {
    final hook = completer;
    if (hook != null) return hook(prompt, system);
    return AiService.complete(
      prompt: prompt,
      system: system,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  // -------------------------------------------------------------------------
  // 整理：一段自然语言 → 多条任务
  // -------------------------------------------------------------------------

  static const _organizeSystem =
      '你是待办整理器。只输出严格 JSON，不要代码块，不要解释。'
      '所有时间使用 24 小时制，日期格式 yyyy-MM-dd HH:mm。';

  static Future<List<TodoDraft>> organize(
    String text, {
    List<String> categoryNames = const ['学习', '工作', '运动', '健康'],
  }) async {
    final prompt =
        '''
把下面这段待办描述整理成任务列表。规则：
1. 只整理用户明确提到的事，不要新增、不要编造时间。
2. kind 只能是 reminder（到点提醒）、task（有截止时间）、habit（每周重复）、quick（随手做，无时间）。
3. 用户没说时间时 kind 用 quick，at 为 null；说"提醒我"用 reminder；说"每天/每周"用 habit，days 写 1-7。
4. category 只能从这些里选：${categoryNames.join('、')}；都不合适就填空字符串。
5. subtasks 只在原文已经包含步骤时填写，否则给空数组。
6. 输出格式：
{"tasks":[{"title":"","kind":"task","category":"","at":"2026-11-08 18:00","days":[1,3],"time":"20:00","note":"","subtasks":[""]}]}

待办描述：
$text
''';
    final raw = await _complete(prompt, _organizeSystem);
    return parseDrafts(raw);
  }

  // -------------------------------------------------------------------------
  // 拆解：一条任务 → 子步骤
  // -------------------------------------------------------------------------

  static Future<List<String>> breakdown(TodoTask task) async {
    const system = '你是任务拆解器。只输出严格 JSON，不要代码块，不要解释。';
    final prompt =
        '''
把这条任务拆成 3 到 6 个可以独立勾选的小步骤。
要求：动词开头、每条不超过 20 字、按执行顺序排列、能在 25 分钟内完成。
任务：${task.title}
${task.note.isEmpty ? '' : '补充：${task.note}'}
输出：{"subtasks":[""]}
''';
    final raw = await _complete(prompt, system, maxTokens: 500);
    final j = _decodeObject(raw);
    if (j == null) return [];
    final list = j['subtasks'];
    if (list is! List) return [];
    return list
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .take(8)
        .toList();
  }

  // -------------------------------------------------------------------------
  // 总结：必须客观，不讨好
  // -------------------------------------------------------------------------

  static const _summarySystem =
      '你是一个客观的工作复盘记录员。只陈述事实与数据，不评价人格，不使用鼓励或奉承话术，'
      '不写"你真棒""太厉害了""继续保持"这类句子。指出未完成时只描述事实与可能原因，'
      '原因只能来自用户自己写的内容，不要臆测。输出 3 到 5 句纯文本。';

  static Future<String> summary({
    required DateTime day,
    required List<TodoTask> tasks,
    required List<MoodEntry> moods,
    required int focusMinutes,
    required int streak,
    int gameMinutes = 0,
    String extraContext = '',
  }) async {
    final done = tasks.where((t) => t.done).toList();
    final open = tasks.where((t) => !t.done).toList();
    final buffer = StringBuffer()
      ..writeln('日期：${dayKey(day)}')
      ..writeln('任务总数：${tasks.length}，已完成：${done.length}，未完成：${open.length}');
    if (done.isNotEmpty) {
      buffer.writeln('已完成：${done.map((t) => t.title).join('、')}');
    }
    if (open.isNotEmpty) {
      buffer.writeln('未完成：${open.map((t) => t.title).join('、')}');
    }
    final notes = tasks.where((t) => t.note.trim().isNotEmpty);
    if (notes.isNotEmpty) {
      buffer.writeln('任务备注：');
      for (final t in notes) {
        buffer.writeln('- ${t.title}：${t.note}');
      }
    }
    buffer.writeln('专注时长：$focusMinutes 分钟');
    buffer.writeln('连续完成天数：$streak');
    if (gameMinutes > 0) {
      buffer.writeln('小游戏时长：$gameMinutes 分钟');
    }
    if (extraContext.trim().isNotEmpty) {
      buffer.writeln(extraContext.trim());
    }
    if (moods.isNotEmpty) {
      buffer.writeln(
        '心情记录：${moods.map((m) => '${_hm(m.ts)} ${m.kind.label}${m.note.isEmpty ? '' : '（${m.note}）'}').join('；')}',
      );
    } else {
      buffer.writeln('心情记录：无');
    }
    final raw = await _complete(
      '根据以下数据写今日复盘。先给一句结论，再说依据，最后指出一个具体的改进点。\n\n$buffer',
      _summarySystem,
      maxTokens: 520,
      temperature: .3,
    );
    return raw.trim();
  }

  // -------------------------------------------------------------------------
  // 建议
  // -------------------------------------------------------------------------

  static Future<String> suggest({
    required List<TodoTask> recent,
    required Map<DateTime, int> doneByDay,
    required int focusMinutes,
  }) async {
    const system =
        '你是客观的待办分析员。只输出 1 到 2 条具体、可执行的建议，每条一句话，'
        '必须引用数据作为依据，不写鼓励或空泛的话。';
    final open = recent.where((t) => !t.done).toList();
    final overdue = open.where((t) => t.overdue).toList();
    final buffer = StringBuffer()
      ..writeln(
        '近 7 天完成数：${doneByDay.entries.map((e) => '${dayKey(e.key)}=${e.value}').join('，')}',
      )
      ..writeln('未完成任务：${open.length} 条，其中已逾期 ${overdue.length} 条')
      ..writeln('本周专注：$focusMinutes 分钟');
    if (overdue.isNotEmpty) {
      buffer.writeln('逾期任务：${overdue.take(5).map((t) => t.title).join('、')}');
    }
    final raw = await _complete(
      '$buffer\n请给出建议。',
      system,
      maxTokens: 320,
      temperature: .4,
    );
    return raw.trim();
  }

  // -------------------------------------------------------------------------
  // 小c助手：解析回复里的创建指令
  // -------------------------------------------------------------------------

  static const actionMarker = '[[TODO]]';

  /// 更新已有任务（补备注 / 改时间）的指令标记。
  static const updateMarker = '[[TODO-UPDATE]]';

  static const assistantSystem =
      '''
你是 CiCi，待办助手。你的名字固定是 CiCi，不要自称其他名字。
你可以帮用户创建任务、拆解任务、总结今天、查询待办、给建议。
回答要求：
1. 客观、简短，先给结论。不奉承、不夸张、不使用"太棒了""你真厉害"这类话术。
2. 总结今天时只依据提供的待办数据，不推测用户没写的内容；数据不足就直说。
3. 当用户要求创建任务时，在正文末尾追加一行创建指令，格式严格如下：
${actionMarker}{"title":"任务名","kind":"task","at":"2026-11-08 18:00","category":"学习","days":[],"time":"20:00","note":"","subtasks":[]}
kind 只能是 reminder / task / habit / quick。用户没给时间就用 quick 且 at 为 null。
创建指令必须单独一行，不要放进代码块。一次最多创建 5 条。
4. 用户只是查询或聊天时，不要输出创建指令。
5. 当用户要给已有任务补备注或改时间时，在正文末尾追加一行更新指令，格式严格如下：
${updateMarker}{"title":"已有任务的标题（必须与待办数据里的标题完全一致）","note":"要补充的备注","at":"2026-11-08 18:00"}
只需给出要改的字段；只是补备注时不要带 at。更新指令同样单独一行、不要放进代码块。
6. 用户说「给 XX 加备注」「把 XX 改到几点」时，用更新指令，不要再创建一条同名任务。
''';

  /// 从模型回复中拆出创建/更新指令。
  static (String, List<TodoDraft>) parseReply(String raw) {
    final drafts = <TodoDraft>[];
    final keep = <String>[];
    for (final line in raw.split('\n')) {
      final up = line.indexOf(updateMarker);
      if (up >= 0) {
        final jsonText = line.substring(up + updateMarker.length).trim();
        final draft = _draftFromJson(_decodeObject(jsonText), update: true);
        if (draft != null) drafts.add(draft);
        continue;
      }
      final i = line.indexOf(actionMarker);
      if (i < 0) {
        keep.add(line);
        continue;
      }
      final jsonText = line.substring(i + actionMarker.length).trim();
      final draft = _draftFromJson(_decodeObject(jsonText));
      if (draft != null) drafts.add(draft);
    }
    var text = keep.join('\n').trim();
    if (text.isEmpty && drafts.isNotEmpty) {
      final created = drafts.where((d) => !d.update).length;
      final updated = drafts.where((d) => d.update).length;
      text = [
        if (created > 0) '已为你创建 $created 条任务。',
        if (updated > 0) '已更新 $updated 条任务。',
      ].join(' ');
    }
    return (text, drafts);
  }

  /// 给助手用的待办上下文。
  static String contextFor({
    required List<TodoTask> tasks,
    required List<MoodEntry> moods,
    required int focusMinutes,
    required int streak,
    required DateTime now,
  }) {
    final today = tasks.where((t) => t.occursOn(now)).toList();
    final done = today.where((t) => t.done).length;
    final open = today.where((t) => !t.done).toList();
    final buffer = StringBuffer()
      ..writeln('当前时间：${dayKey(now)} ${_hm(now)}')
      ..writeln('今日任务 ${today.length} 条，已完成 $done 条，未完成 ${open.length} 条。');
    if (open.isNotEmpty) {
      buffer.writeln('未完成：');
      for (final t in open.take(12)) {
        buffer.writeln(
          '- ${t.title}（${t.kind.label}，${taskTimeText(t).isEmpty ? '无时间' : taskTimeText(t)}，${t.note.isEmpty ? '无备注' : t.note}）',
        );
      }
    }
    final later = TodoStoreRefHelper.upcoming(tasks, now);
    if (later.isNotEmpty) {
      buffer.writeln(
        '未来 7 天还有：${later.take(10).map((t) => t.title).join('、')}',
      );
    }
    buffer.writeln('今日专注：$focusMinutes 分钟；连续完成：$streak 天。');
    final todayMoods = moods.where((m) => dayKey(m.ts) == dayKey(now)).toList();
    if (todayMoods.isNotEmpty) {
      buffer.writeln(
        '今日心情：${todayMoods.map((m) => '${_hm(m.ts)} ${m.kind.label}').join('，')}',
      );
    }
    return buffer.toString();
  }

  // -------------------------------------------------------------------------
  // 解析
  // -------------------------------------------------------------------------

  static List<TodoDraft> parseDrafts(String raw) {
    final j = _decodeObject(raw);
    if (j == null) return [];
    return _draftsFromJson(j);
  }

  static List<TodoDraft> _draftsFromJson(Map<String, dynamic> j) {
    final list = j['tasks'];
    if (list is! List) return [];
    final out = <TodoDraft>[];
    for (final item in list) {
      if (item is! Map) continue;
      final d = _draftFromJson(Map<String, dynamic>.from(item));
      if (d != null) out.add(d);
      if (out.length >= 8) break;
    }
    return out;
  }

  static TodoDraft? _draftFromJson(
    Map<String, dynamic>? j, {
    bool update = false,
  }) {
    if (j == null) return null;
    final title = '${j['title'] ?? ''}'.trim();
    if (title.isEmpty) return null;
    final kind = TodoKindX.fromName('${j['kind'] ?? 'task'}');
    final at = _parseDateTime(j['at']);
    final days = <int>{};
    final rawDays = j['days'];
    if (rawDays is List) {
      for (final d in rawDays) {
        final n = int.tryParse('$d');
        if (n != null && n >= 1 && n <= 7) days.add(n);
      }
    }
    final subs = <String>[];
    final rawSubs = j['subtasks'];
    if (rawSubs is List) {
      for (final s in rawSubs) {
        final v = '$s'.trim();
        if (v.isNotEmpty) subs.add(v);
        if (subs.length >= 8) break;
      }
    }
    final time = '${j['time'] ?? ''}'.trim();
    return TodoDraft(
      title: title,
      kind: kind,
      categoryName: '${j['category'] ?? ''}'.trim(),
      note: '${j['note'] ?? ''}'.trim(),
      at: at,
      days: days,
      time: RegExp(r'^\d{1,2}:\d{2}$').hasMatch(time) ? time : '20:00',
      subtasks: subs,
      priority: int.tryParse('${j['priority'] ?? 0}') ?? 0,
      update: update,
    );
  }

  static Map<String, dynamic>? _decodeObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    final s = '$raw'.trim();
    if (s.isEmpty || s == 'null') return null;
    final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?')
        .firstMatch(s);
    if (m == null) {
      return DateTime.tryParse(s);
    }
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final h = int.tryParse(m.group(4) ?? '') ?? 9;
    final mi = int.tryParse(m.group(5) ?? '') ?? 0;
    return DateTime(
      y,
      mo.clamp(1, 12),
      d.clamp(1, 31),
      h.clamp(0, 23),
      mi.clamp(0, 59),
    );
  }

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 避免 TodoAi 反向依赖 TodoStore，只保留一个纯函数入口。
class TodoStoreRefHelper {
  TodoStoreRefHelper._();

  static List<TodoTask> upcoming(List<TodoTask> tasks, DateTime now) {
    final today = dayOf(now);
    final out = <TodoTask>[];
    for (final t in tasks) {
      if (t.done) continue;
      for (var i = 1; i <= 7; i++) {
        final d = today.add(Duration(days: i));
        if (t.occursOn(d)) {
          out.add(t);
          break;
        }
      }
    }
    return out;
  }
}
