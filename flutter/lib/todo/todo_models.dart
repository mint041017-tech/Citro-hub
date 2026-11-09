import 'package:flutter/material.dart';

/// 待办模块的数据模型。
///
/// 全部字段手写 JSON，和项目里 CookIngredient / FishConfig 的做法一致：
/// 数值走 num 容错、字符串走 `'${x ?? ''}'`、缺失集合给空列表。

// ---------------------------------------------------------------------------
// 基础枚举
// ---------------------------------------------------------------------------

/// 任务类型。四类任务只在「时间」字段上不同，其余字段共用。
enum TodoKind { reminder, task, habit, quick }

extension TodoKindX on TodoKind {
  String get label => switch (this) {
    TodoKind.reminder => '提醒',
    TodoKind.task => '待办',
    TodoKind.habit => '习惯',
    TodoKind.quick => '随手做',
  };

  String get hint => switch (this) {
    TodoKind.reminder => '到点提醒你，不占完成率',
    TodoKind.task => '有截止时间，可以勾完成',
    TodoKind.habit => '按周重复，记录连续天数',
    TodoKind.quick => '不设时间，想到就做',
  };

  String get icon => switch (this) {
    TodoKind.reminder => 'bell',
    TodoKind.task => 'check',
    TodoKind.habit => 'repeat',
    TodoKind.quick => 'flash',
  };

  static TodoKind fromName(String? raw) => TodoKind.values.firstWhere(
    (k) => k.name == raw,
    orElse: () => TodoKind.task,
  );
}

/// 心情档位。
enum MoodKind { happy, calm, neutral, tired, low, anxious }

extension MoodKindX on MoodKind {
  String get label => switch (this) {
    MoodKind.happy => '开心',
    MoodKind.calm => '平静',
    MoodKind.neutral => '一般',
    MoodKind.tired => '疲惫',
    MoodKind.low => '低落',
    MoodKind.anxious => '焦虑',
  };

  /// 低饱和、能落在暖纸 palette 里的六种色。
  Color get color => switch (this) {
    MoodKind.happy => const Color(0xFFE0A03E),
    MoodKind.calm => const Color(0xFF8FA6BE),
    MoodKind.neutral => const Color(0xFFA79E8C),
    MoodKind.tired => const Color(0xFF9A8FA6),
    MoodKind.low => const Color(0xFF7C8AA0),
    MoodKind.anxious => const Color(0xFFC4855D),
  };

  static MoodKind fromName(String? raw) => MoodKind.values.firstWhere(
    (k) => k.name == raw,
    orElse: () => MoodKind.neutral,
  );
}

// ---------------------------------------------------------------------------
// 分类与清单
// ---------------------------------------------------------------------------

class TodoCategory {
  final String id;
  final String name;
  final int color;
  final String iconKey;
  final bool builtIn;

  const TodoCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.iconKey,
    this.builtIn = false,
  });

  Color get tint => Color(color);

  TodoCategory copyWith({String? name, int? color, String? iconKey}) =>
      TodoCategory(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        iconKey: iconKey ?? this.iconKey,
        builtIn: builtIn,
      );

  factory TodoCategory.fromJson(Map<String, dynamic> j) => TodoCategory(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    color: _asInt(j['color'], 0xFF8A7F6A),
    iconKey: '${j['icon'] ?? 'flag'}',
    builtIn: j['builtIn'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'icon': iconKey,
    'builtIn': builtIn,
  };
}

class TodoList {
  final String id;
  final String name;
  final int color;
  final String iconKey;

  const TodoList({
    required this.id,
    required this.name,
    required this.color,
    required this.iconKey,
  });

  Color get tint => Color(color);

  TodoList copyWith({String? name, int? color, String? iconKey}) => TodoList(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    iconKey: iconKey ?? this.iconKey,
  );

  factory TodoList.fromJson(Map<String, dynamic> j) => TodoList(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    color: _asInt(j['color'], 0xFFE8935A),
    iconKey: '${j['icon'] ?? 'list'}',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'icon': iconKey,
  };
}

// ---------------------------------------------------------------------------
// 任务
// ---------------------------------------------------------------------------

class TodoSubtask {
  String id;
  String title;
  bool done;

  TodoSubtask({required this.id, required this.title, this.done = false});

  factory TodoSubtask.fromJson(Map<String, dynamic> j) => TodoSubtask(
    id: '${j['id'] ?? ''}',
    title: '${j['title'] ?? ''}',
    done: j['done'] == true,
  );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};
}

/// 任务在今日面板里的三种状态。
enum TodoTaskState {
  todo,
  doing,
  done;

  String get label => switch (this) {
    TodoTaskState.todo => '待办',
    TodoTaskState.doing => '进行中',
    TodoTaskState.done => '已完成',
  };
}

class TodoTask {
  final String id;
  String title;
  String note;
  TodoKind kind;
  String categoryId;
  String listId;

  /// 提醒：提醒时间；待办：截止时间；习惯/随手做为 null。
  DateTime? remindAt;
  DateTime? dueAt;

  /// 待办在截止前多久提醒（分钟，0 表示截止那一刻），可以选多个。
  List<int> leadMinutes;

  /// 习惯：周几执行（1=周一 … 7=周日）与执行时间。
  Set<int> habitDays;
  String habitTime;

  bool done;

  /// 进行中：done 为 false 时的第二条状态，面板里单独一列。
  bool doing;
  DateTime? doneAt;
  final DateTime createdAt;
  List<TodoSubtask> subtasks;
  int priority;

  /// manual / ai / cici，用于在列表里标出来源。
  String source;

  TodoTask({
    required this.id,
    required this.title,
    this.note = '',
    this.kind = TodoKind.task,
    required this.categoryId,
    required this.listId,
    this.remindAt,
    this.dueAt,
    List<int>? leadMinutes,
    Set<int>? habitDays,
    this.habitTime = '20:00',
    this.done = false,
    this.doing = false,
    this.doneAt,
    DateTime? createdAt,
    List<TodoSubtask>? subtasks,
    this.priority = 0,
    this.source = 'manual',
  }) : leadMinutes = leadMinutes ?? const [15],
       habitDays = habitDays ?? <int>{},
       createdAt = createdAt ?? DateTime.now(),
       subtasks = subtasks ?? [];

  /// 任务实际需要出现的日期（用于「今日」与日程）。
  ///
  /// 提醒/待办按设置的日期；习惯按周几展开；随手做只在创建当天出现。
  bool occursOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (kind == TodoKind.habit) {
      return habitDays.contains(d.weekday) && !d.isBefore(_createdDay);
    }
    if (kind == TodoKind.quick) return d == _createdDay;
    final at = kind == TodoKind.reminder ? remindAt : dueAt;
    if (at == null)
      return d == _createdDay ||
          (d.isAfter(_createdDay) &&
              d.isBefore(_createdDay.add(const Duration(days: 7))));
    return DateTime(at.year, at.month, at.day) == d;
  }

  DateTime get _createdDay =>
      DateTime(createdAt.year, createdAt.month, createdAt.day);

  /// 「今日」列表里实际用的时间：习惯用今天的执行时间，其余用设置的时间。
  DateTime? scheduledAt(DateTime day) {
    if (kind == TodoKind.habit) {
      final parts = habitTime.split(':');
      final h = int.tryParse(parts.first) ?? 20;
      final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return DateTime(day.year, day.month, day.day, h, m);
    }
    if (kind == TodoKind.reminder) return remindAt;
    if (kind == TodoKind.task) return dueAt;
    return null;
  }

  bool get overdue {
    if (done) return false;
    final at = kind == TodoKind.task
        ? dueAt
        : (kind == TodoKind.reminder ? remindAt : null);
    return at != null && at.isBefore(DateTime.now());
  }

  int get doneSubtasks => subtasks.where((s) => s.done).length;

  /// 三态：待办 / 进行中 / 已完成。
  TodoTaskState get state => done
      ? TodoTaskState.done
      : (doing ? TodoTaskState.doing : TodoTaskState.todo);

  TodoTask copyWith({
    String? title,
    String? note,
    TodoKind? kind,
    String? categoryId,
    String? listId,
    DateTime? remindAt,
    DateTime? dueAt,
    List<int>? leadMinutes,
    Set<int>? habitDays,
    String? habitTime,
    bool? done,
    bool? doing,
    DateTime? doneAt,
    List<TodoSubtask>? subtasks,
    int? priority,
    String? source,
  }) => TodoTask(
    id: id,
    title: title ?? this.title,
    note: note ?? this.note,
    kind: kind ?? this.kind,
    categoryId: categoryId ?? this.categoryId,
    listId: listId ?? this.listId,
    remindAt: remindAt ?? this.remindAt,
    dueAt: dueAt ?? this.dueAt,
    leadMinutes: leadMinutes ?? this.leadMinutes,
    habitDays: habitDays ?? this.habitDays,
    habitTime: habitTime ?? this.habitTime,
    done: done ?? this.done,
    doing: doing ?? this.doing,
    doneAt: doneAt ?? this.doneAt,
    createdAt: createdAt,
    subtasks: subtasks ?? this.subtasks,
    priority: priority ?? this.priority,
    source: source ?? this.source,
  );

  factory TodoTask.fromJson(Map<String, dynamic> j) => TodoTask(
    id: '${j['id'] ?? ''}',
    title: '${j['title'] ?? ''}',
    note: '${j['note'] ?? ''}',
    kind: TodoKindX.fromName(j['kind'] as String?),
    categoryId: '${j['categoryId'] ?? 'study'}',
    listId: '${j['listId'] ?? 'default'}',
    remindAt: _asDate(j['remindAt']),
    dueAt: _asDate(j['dueAt']),
    leadMinutes:
        (j['leadMinutes'] as List?)
            ?.map((e) => _asInt(e, 15))
            .where((e) => e >= 0 && e <= 10080)
            .toSet()
            .toList() ??
        const [15],
    habitDays:
        (j['habitDays'] as List?)
            ?.map((e) => _asInt(e, 1))
            .where((e) => e >= 1 && e <= 7)
            .toSet() ??
        <int>{},
    habitTime: '${j['habitTime'] ?? '20:00'}',
    done: j['done'] == true,
    doing: j['doing'] == true,
    doneAt: _asDate(j['doneAt']),
    createdAt: _asDate(j['createdAt']) ?? DateTime.now(),
    subtasks:
        (j['subtasks'] as List?)
            ?.whereType<Map>()
            .map((e) => TodoSubtask.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [],
    priority: _asInt(j['priority'], 0),
    source: '${j['source'] ?? 'manual'}',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'kind': kind.name,
    'categoryId': categoryId,
    'listId': listId,
    'remindAt': remindAt?.millisecondsSinceEpoch,
    'dueAt': dueAt?.millisecondsSinceEpoch,
    'leadMinutes': leadMinutes,
    'habitDays': habitDays.toList()..sort(),
    'habitTime': habitTime,
    'done': done,
    'doing': doing,
    'doneAt': doneAt?.millisecondsSinceEpoch,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'subtasks': subtasks.map((s) => s.toJson()).toList(),
    'priority': priority,
    'source': source,
  };
}

// ---------------------------------------------------------------------------
// 复盘与心情
// ---------------------------------------------------------------------------

class DailyReview {
  String text;
  bool ai;
  bool auto;
  DateTime updatedAt;

  DailyReview({
    required this.text,
    this.ai = false,
    this.auto = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory DailyReview.fromJson(Map<String, dynamic> j) => DailyReview(
    text: '${j['text'] ?? ''}',
    ai: j['ai'] == true,
    auto: j['auto'] == true,
    updatedAt: _asDate(j['updatedAt']) ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'ai': ai,
    'auto': auto,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}

class MoodEntry {
  final String id;
  final String dateKey;
  final MoodKind kind;
  final String note;
  final DateTime ts;

  const MoodEntry({
    required this.id,
    required this.dateKey,
    required this.kind,
    this.note = '',
    required this.ts,
  });

  factory MoodEntry.fromJson(Map<String, dynamic> j) => MoodEntry(
    id: '${j['id'] ?? ''}',
    dateKey: '${j['date'] ?? ''}',
    kind: MoodKindX.fromName(j['kind'] as String?),
    note: '${j['note'] ?? ''}',
    ts: _asDate(j['ts']) ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': dateKey,
    'kind': kind.name,
    'note': note,
    'ts': ts.millisecondsSinceEpoch,
  };
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

String taskTimeText(TodoTask t) {
  if (t.kind == TodoKind.habit) {
    final names = <String>['一', '二', '三', '四', '五', '六', '日'];
    final days = t.habitDays.toList()..sort();
    final label = days.isEmpty
        ? '每天'
        : '周${days.map((d) => names[d - 1]).join('、')}';
    return '$label ${t.habitTime}';
  }
  final at = t.kind == TodoKind.reminder ? t.remindAt : t.dueAt;
  if (at == null) return '';
  final sameDay = dayOf(at) == dayOf(DateTime.now());
  final hm =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  return sameDay ? hm : '${at.month}/${at.day} $hm';
}

int _asInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

DateTime? _asDate(dynamic v) {
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String && v.isNotEmpty) {
    final n = int.tryParse(v);
    if (n != null) return DateTime.fromMillisecondsSinceEpoch(n);
    return DateTime.tryParse(v);
  }
  return null;
}
