import 'dart:convert';

import 'calendar_models.dart';

/// AI 返回的一条「倒数日 / 纪念日」草稿。字段都做过容错，允许模型少给。
class CalendarMarkDraft {
  final String title;
  final DateTime date;
  final CalendarMarkKind kind;
  final bool yearly;
  final String note;

  const CalendarMarkDraft({
    required this.title,
    required this.date,
    this.kind = CalendarMarkKind.countdown,
    this.yearly = false,
    this.note = '',
  });
}

/// 日历模块的 AI 能力：把「记一个倒数日 / 纪念日」解析成结构化的日历标记。
///
/// 和 TodoAi 一样，动作指令是一行 marker + JSON；解析是纯函数，
/// 测试时不用联网。落库、回执与界面刷新由调用方负责。
class CalendarAi {
  CalendarAi._();

  /// 创建日历标记的指令标记。
  static const markMarker = '[[CAL]]';

  /// 首页 CiCi 的日历约定，与待办、记账的指令并列使用。
  static const assistantSystem =
      '日历助手规则：\n'
      '1. 用户要记倒数日或纪念日时，先用一句话回应，再在末尾单独一行追加创建指令：\n'
      '$markMarker{"title":"纪念日名称","date":"2026-12-05","kind":"countdown","yearly":false,"note":""}\n'
      '2. kind 只能是 countdown 或 anniversary：\n'
      '   - countdown（倒数日）：还没到的日子，用户关心「还有多少天」，如生日、考试、旅行、发布日；\n'
      '   - anniversary（纪念日）：已经发生的起点，用户关心「已经多少天 / 第几年」，'
      '如在一起、结婚、入职纪念。\n'
      '3. date 用 yyyy-MM-dd：倒数日填目标日，纪念日填起始日（必须是过去的日期）。\n'
      '4. 生日、周年这类每年都会再来的加 "yearly":true；一次性目标加 "yearly":false。\n'
      '5. 用户没给年份时不要编造：倒数日按【当前日历标记】里的今天推算下一次日期；'
      '纪念日缺起始年份就先用一句话问清楚，不要输出指令。\n'
      '6. 创建指令必须单独一行，不要放进代码块，一次最多创建 5 个；'
      '用户只是查询有哪些日子时不要输出指令。\n';

  /// 从模型回复里拆出日历指令，并返回去掉指令后的正文。
  static (String, List<CalendarMarkDraft>) parseReply(String raw) {
    final drafts = <CalendarMarkDraft>[];
    final keep = <String>[];
    for (final line in raw.split('\n')) {
      final i = line.indexOf(markMarker);
      if (i < 0) {
        keep.add(line);
        continue;
      }
      final jsonText = line.substring(i + markMarker.length).trim();
      final draft = _draftFromJson(_decodeObject(jsonText));
      if (draft != null) drafts.add(draft);
    }
    return (keep.join('\n').trim(), drafts.take(5).toList(growable: false));
  }

  /// 给助手用的日历上下文：今天是什么日子、已经记了哪些标记。
  static String contextFor({
    required List<CalendarMark> marks,
    required DateTime now,
  }) {
    final buffer = StringBuffer()
      ..writeln('当前日期：${CalendarDates.ymd(now)} ${CalendarDates.weekday(now)}');
    if (marks.isEmpty) {
      buffer.writeln('还没有记录任何倒数日或纪念日。');
      return buffer.toString();
    }
    final sorted = [...marks]
      ..sort(
        (a, b) => CalendarDates.daysFor(
          a,
          now,
        ).abs().compareTo(CalendarDates.daysFor(b, now).abs()),
      );
    buffer.writeln('已有 ${marks.length} 个倒数日 / 纪念日：');
    for (final mark in sorted.take(10)) {
      buffer.writeln(
        '- ${mark.title}（${mark.kind.label}${mark.yearly ? '，每年重复' : ''}，'
        '${CalendarDates.ymd(mark.date)}，${CalendarDates.labelFor(mark, now)}）',
      );
    }
    return buffer.toString();
  }

  // -------------------------------------------------------------------------
  // 解析
  // -------------------------------------------------------------------------

  static CalendarMarkDraft? _draftFromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final title = '${j['title'] ?? j['name'] ?? ''}'.trim();
    if (title.isEmpty) return null;
    final date = _parseDate('${j['date'] ?? j['at'] ?? ''}');
    if (date == null) return null;
    final repeat = '${j['repeat'] ?? ''}'.toLowerCase();
    return CalendarMarkDraft(
      title: title,
      date: date,
      kind: CalendarMarkKind.fromName(j['kind']),
      yearly: _asBool(j['yearly']) || repeat == 'yearly' || repeat == 'year',
      note: '${j['note'] ?? ''}'.trim(),
    );
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    final text = '${value ?? ''}'.toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  static DateTime? _parseDate(String text) {
    final normalized = text.trim().replaceAll('/', '-');
    if (normalized.isEmpty) return null;
    final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})')
        .firstMatch(normalized);
    if (match == null) return null;
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    // DateTime 会把 2 月 30 日规范化成 3 月 2 日，这里挡掉这类脏日期。
    if (date.month != month || date.day != day) return null;
    return date;
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
}
