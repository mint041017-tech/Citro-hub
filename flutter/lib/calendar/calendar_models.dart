/// 日历卡片里的「倒数日 / 纪念日」数据模型。
///
/// 两类标记共用一只 [CalendarMark]，区别只在计数方向：
/// - [CalendarMarkKind.countdown]：距离目标日还有多少天；
/// - [CalendarMarkKind.anniversary]：从起始日到现在已经多少天。
///
/// [yearly] 为 true 时按月日每年重复（生日、周年纪念等），
/// 为 false 时只认 [date] 那一天（考试、旅行、项目截止等）。
enum CalendarMarkKind {
  countdown('倒数日'),
  anniversary('纪念日');

  const CalendarMarkKind(this.label);

  final String label;

  String get storageKey => name;

  static CalendarMarkKind fromName(Object? value) =>
      value == CalendarMarkKind.anniversary.name
      ? CalendarMarkKind.anniversary
      : CalendarMarkKind.countdown;
}

class CalendarMark {
  final String id;
  final String title;
  final DateTime date;
  final CalendarMarkKind kind;
  final bool yearly;
  final String note;
  final int createdAt;

  const CalendarMark({
    required this.id,
    required this.title,
    required this.date,
    required this.kind,
    this.yearly = false,
    this.note = '',
    this.createdAt = 0,
  });

  CalendarMark copyWith({
    String? title,
    DateTime? date,
    CalendarMarkKind? kind,
    bool? yearly,
    String? note,
  }) => CalendarMark(
    id: id,
    title: title ?? this.title,
    date: date ?? this.date,
    kind: kind ?? this.kind,
    yearly: yearly ?? this.yearly,
    note: note ?? this.note,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'date': CalendarDates.ymd(date),
    'kind': kind.storageKey,
    'yearly': yearly,
    'note': note,
    'createdAt': createdAt,
  };

  static CalendarMark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final dateRaw = raw['date'];
    if (id is! String || id.isEmpty) return null;
    if (title is! String || title.trim().isEmpty) return null;
    final date = dateRaw is String ? DateTime.tryParse(dateRaw) : null;
    if (date == null) return null;
    final createdAt = raw['createdAt'];
    return CalendarMark(
      id: id,
      title: title.trim(),
      date: CalendarDates.dayOnly(date),
      kind: CalendarMarkKind.fromName(raw['kind']),
      yearly: raw['yearly'] == true,
      note: raw['note'] is String ? raw['note'] as String : '',
      createdAt: createdAt is int
          ? createdAt
          : (createdAt is num ? createdAt.toInt() : 0),
    );
  }
}

/// 日期计算与展示文案：首页小卡和详情页共用同一套口径。
class CalendarDates {
  const CalendarDates._();

  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 用 UTC 日期做差，避开夏令时造成的 23/25 小时误差。
  static int diffDays(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String fullDate(DateTime d) => '${d.year}年${d.month}月${d.day}日';

  static String monthLabel(DateTime d) => '${d.year}年${d.month}月';

  static String weekday(DateTime d) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[d.weekday - 1];
  }

  /// 某个标记在当前时间点对应的「下一次发生日」。
  ///
  /// 倒数日：单次就是目标日，每年重复则取今年或明年的同月日；
  /// 纪念日：单次/每年重复都以起始日为准，用于排序和展示。
  static DateTime occurrence(CalendarMark mark, DateTime today) {
    final base = dayOnly(mark.date);
    if (mark.kind == CalendarMarkKind.anniversary) return base;
    if (!mark.yearly) return base;
    final todayOnly = dayOnly(today);
    var next = DateTime(todayOnly.year, base.month, base.day);
    if (diffDays(todayOnly, next) < 0) {
      next = DateTime(todayOnly.year + 1, base.month, base.day);
    }
    return next;
  }

  /// 标记相对今天的天数：倒数日为正数代表「还有几天」，可为负；
  /// 纪念日为正数代表「已经几天」。
  static int daysFor(CalendarMark mark, DateTime today) {
    final todayOnly = dayOnly(today);
    if (mark.kind == CalendarMarkKind.anniversary) {
      return diffDays(dayOnly(mark.date), todayOnly);
    }
    return diffDays(todayOnly, occurrence(mark, today));
  }

  /// 大数字旁的说明：还有 / 已经 / 已过。
  static String unitFor(CalendarMark mark, DateTime today) {
    final days = daysFor(mark, today);
    if (days == 0) return '今天';
    if (mark.kind == CalendarMarkKind.anniversary) {
      return days > 0 ? '已经' : '还有';
    }
    return days > 0 ? '还有' : '已过';
  }

  /// 完整文案：「还有 12 天」「已经 365 天」「就是今天」。
  static String labelFor(CalendarMark mark, DateTime today) {
    final days = daysFor(mark, today);
    if (days == 0) return '就是今天';
    return '${unitFor(mark, today)} ${days.abs()} 天';
  }

  /// 日期是否命中该标记：每年重复按月日匹配，否则要求年月日完全一致。
  static bool hits(CalendarMark mark, DateTime date) {
    if (mark.yearly) {
      return mark.date.month == date.month && mark.date.day == date.day;
    }
    return mark.date.year == date.year &&
        mark.date.month == date.month &&
        mark.date.day == date.day;
  }

  /// 年度纪念日的「第 N 年」；非纪念日、非年度或尚未到周年时返回 null。
  static int? yearCount(CalendarMark mark, DateTime today) {
    if (mark.kind != CalendarMarkKind.anniversary || !mark.yearly) return null;
    final years = today.year - mark.date.year;
    return years > 0 ? years + 1 : null;
  }
}
