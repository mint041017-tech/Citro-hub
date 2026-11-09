import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/api.dart';
import '../services/notifications.dart';
import '../services/platform.dart' as platform;
import '../services/prefs.dart';
import '../state/app_state.dart';
import 'todo_models.dart';

/// 待办模块的唯一数据源。
///
/// 和 PomodoroState 一样是独立单例 ChangeNotifier，不挂在 AppState 里，
/// 避免首页/社区这些长页面跟着任务勾选一起重建。
class TodoStore extends ChangeNotifier {
  TodoStore._();

  static final TodoStore instance = TodoStore._();

  bool _inited = false;
  bool get inited => _inited;

  int _updatedAt = 0;
  bool _accountSynced = false;
  Timer? _pushTimer;

  List<TodoTask> _tasks = [];
  List<TodoList> _lists = [];
  List<TodoCategory> _categories = [];
  Map<String, DailyReview> _reviews = {};
  List<MoodEntry> _moods = [];

  /// 同一微秒内连续创建任务时，靠这个序号避免 id 撞车。
  int _idSeq = 0;

  bool autoReviewEnabled = true;
  String autoReviewTime = '21:30';

  List<TodoTask> get tasks => List.unmodifiable(_tasks);
  List<TodoList> get lists => List.unmodifiable(_lists);
  List<TodoCategory> get categories => List.unmodifiable(_categories);
  List<MoodEntry> get moods => List.unmodifiable(_moods);

  final Set<int> _scheduledIds = {};

  // -------------------------------------------------------------------------
  // 初始化
  // -------------------------------------------------------------------------

  Future<void> ensureInit() async {
    if (_inited) return;
    _inited = true;
    await _load();
    unawaited(reschedule());
    unawaited(syncFromAccount());
    notifyListeners();
  }

  /// 测试用：清空内存状态，让下一次 [ensureInit] 重新读本地缓存。
  void resetForTest() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _inited = false;
    _accountSynced = false;
    _updatedAt = 0;
    _tasks = [];
    _lists = [];
    _categories = [];
    _reviews = {};
    _moods = [];
    _scheduledIds.clear();
    autoReviewEnabled = true;
    autoReviewTime = '21:30';
    _idSeq = 0;
  }

  Future<void> _load() async {
    _categories = _defaultCategories();
    _lists = _defaultLists();
    final raw = Prefs.getString(PrefKeys.todo);
    if (raw == null || raw.isEmpty) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final cats = (j['categories'] as List?)
          ?.whereType<Map>()
          .map((e) => TodoCategory.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.id.isNotEmpty)
          .toList();
      if (cats != null && cats.isNotEmpty) _categories = cats;

      final lists = (j['lists'] as List?)
          ?.whereType<Map>()
          .map((e) => TodoList.fromJson(Map<String, dynamic>.from(e)))
          .where((l) => l.id.isNotEmpty)
          .toList();
      if (lists != null && lists.isNotEmpty) _lists = lists;

      _tasks =
          (j['tasks'] as List?)
              ?.whereType<Map>()
              .map((e) => TodoTask.fromJson(Map<String, dynamic>.from(e)))
              .where((t) => t.id.isNotEmpty && t.title.isNotEmpty)
              .toList() ??
          [];
      final reviews = j['reviews'];
      if (reviews is Map) {
        _reviews = reviews.map(
          (k, v) => MapEntry(
            k.toString(),
            DailyReview.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        );
      }
      _moods =
          (j['moods'] as List?)
              ?.whereType<Map>()
              .map((e) => MoodEntry.fromJson(Map<String, dynamic>.from(e)))
              .where((m) => m.dateKey.isNotEmpty)
              .toList() ??
          [];
      autoReviewEnabled = j['autoReviewEnabled'] != false;
      autoReviewTime = '${j['autoReviewTime'] ?? '21:30'}';
      final at = j['updatedAt'];
      _updatedAt = at is int ? at : (at is num ? at.toInt() : 0);
    } catch (_) {
      // 坏数据不阻塞模块启动，回到默认分类与清单。
    }
  }

  Future<void> _save() async {
    _updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _persistLocal();
    notifyListeners();
    unawaited(reschedule());
    _schedulePush();
  }

  Map<String, Object?> _payload() => {
    'tasks': _tasks.map((t) => t.toJson()).toList(),
    'lists': _lists.map((l) => l.toJson()).toList(),
    'categories': _categories.map((c) => c.toJson()).toList(),
    'reviews': _reviews.map((k, v) => MapEntry(k, v.toJson())),
    'moods': _moods.map((m) => m.toJson()).toList(),
    'autoReviewEnabled': autoReviewEnabled,
    'autoReviewTime': autoReviewTime,
    'updatedAt': _updatedAt,
  };

  Future<void> _persistLocal() async {
    await Prefs.setString(PrefKeys.todo, jsonEncode(_payload()));
  }

  /// 登录后拉取云端待办；远端更新时覆盖本地，否则把本地推上去。
  Future<void> syncFromAccount({bool force = false}) async {
    if (platform.isTest) return;
    if (!force && _accountSynced) return;
    if (!AppState.instance.loggedIn) return;
    _accountSynced = true;
    try {
      final json = await Api.todoGet();
      final remote = json['todo'];
      final at = json['at'] is num ? (json['at'] as num).toInt() : 0;
      if (remote is Map && at > _updatedAt) {
        await _applyRemote(Map<String, dynamic>.from(remote), at);
        return;
      }
      _schedulePush(immediate: true);
    } catch (_) {
      // 离线或服务端未部署：继续使用本地数据。
    }
  }

  Future<void> _applyRemote(Map<String, dynamic> remote, int at) async {
    await Prefs.setString(
      PrefKeys.todo,
      jsonEncode({...remote, 'updatedAt': at}),
    );
    await _load();
    _updatedAt = at;
    notifyListeners();
    unawaited(reschedule());
  }

  void _schedulePush({bool immediate = false}) {
    if (platform.isTest) return;
    if (!AppState.instance.loggedIn) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 900),
      _pushRemote,
    );
  }

  Future<void> _pushRemote() async {
    if (!AppState.instance.loggedIn) return;
    try {
      await Api.todoSave(_payload());
    } catch (_) {
      // 网络恢复后下一次修改会再次推送。
    }
  }

  // -------------------------------------------------------------------------
  // 默认数据
  // -------------------------------------------------------------------------

  static List<TodoCategory> _defaultCategories() => const [
    TodoCategory(
      id: 'study',
      name: '学习',
      color: 0xFFC08A4A,
      iconKey: 'book',
      builtIn: true,
    ),
    TodoCategory(
      id: 'work',
      name: '工作',
      color: 0xFF6F8CA8,
      iconKey: 'note',
      builtIn: true,
    ),
    TodoCategory(
      id: 'sport',
      name: '运动',
      color: 0xFF6E9A78,
      iconKey: 'target',
      builtIn: true,
    ),
    TodoCategory(
      id: 'health',
      name: '健康',
      color: 0xFFB5717A,
      iconKey: 'heart',
      builtIn: true,
    ),
  ];

  static List<TodoList> _defaultLists() => const [
    TodoList(id: 'default', name: '我的清单', color: 0xFFE8935A, iconKey: 'list'),
  ];

  TodoCategory categoryOf(String id) => _categories.firstWhere(
    (c) => c.id == id,
    orElse: () => _categories.isEmpty
        ? const TodoCategory(
            id: 'study',
            name: '学习',
            color: 0xFFC08A4A,
            iconKey: 'flag',
          )
        : _categories.first,
  );

  TodoList listOf(String id) =>
      _lists.firstWhere((l) => l.id == id, orElse: () => _lists.first);

  // -------------------------------------------------------------------------
  // 任务
  // -------------------------------------------------------------------------

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  TodoTask createTask({
    required String title,
    String note = '',
    TodoKind kind = TodoKind.task,
    required String categoryId,
    required String listId,
    DateTime? remindAt,
    DateTime? dueAt,
    List<int> leadMinutes = const [15],
    Set<int>? habitDays,
    String habitTime = '20:00',
    List<String> subtasks = const [],
    int priority = 0,
    String source = 'manual',
  }) {
    final task = TodoTask(
      id: _newId('t'),
      title: title.trim(),
      note: note.trim(),
      kind: kind,
      categoryId: categoryId,
      listId: listId,
      remindAt: kind == TodoKind.reminder ? remindAt : null,
      dueAt: kind == TodoKind.task ? dueAt : null,
      leadMinutes: kind == TodoKind.task ? leadMinutes : const [],
      habitDays: kind == TodoKind.habit
          ? (habitDays?.isEmpty == false ? habitDays : {1, 2, 3, 4, 5, 6, 7})
          : <int>{},
      habitTime: habitTime,
      subtasks: [
        for (final s in subtasks)
          if (s.trim().isNotEmpty)
            TodoSubtask(id: _newId('s'), title: s.trim()),
      ],
      priority: priority,
      source: source,
    );
    _tasks.add(task);
    unawaited(_save());
    return task;
  }

  TodoTask? taskById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void updateTask(TodoTask task) {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i < 0) return;
    _tasks[i] = task;
    unawaited(_save());
  }

  void deleteTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    unawaited(_save());
  }

  void toggleTask(TodoTask task) {
    setTaskState(task, task.done ? TodoTaskState.todo : TodoTaskState.done);
  }

  /// 直接设定三态，面板里点击状态按钮时用。
  void setTaskState(TodoTask task, TodoTaskState state) {
    task.done = state == TodoTaskState.done;
    task.doing = state == TodoTaskState.doing;
    task.doneAt = task.done ? DateTime.now() : null;
    unawaited(_save());
  }

  /// 待办 → 进行中 → 已完成 → 待办。
  void cycleTaskState(TodoTask task) {
    final next = switch (task.state) {
      TodoTaskState.todo => TodoTaskState.doing,
      TodoTaskState.doing => TodoTaskState.done,
      TodoTaskState.done => TodoTaskState.todo,
    };
    setTaskState(task, next);
  }

  /// 标记重点：优先级在 0（普通）与 1（重要）之间切换。
  void toggleFocus(TodoTask task) {
    task.priority = task.priority > 0 ? 0 : 1;
    unawaited(_save());
  }

  void toggleSubtask(TodoTask task, TodoSubtask sub) {
    sub.done = !sub.done;
    unawaited(_save());
  }

  void addSubtasks(TodoTask task, List<String> titles) {
    for (final title in titles) {
      final t = title.trim();
      if (t.isEmpty) continue;
      task.subtasks.add(TodoSubtask(id: _newId('s'), title: t));
    }
    unawaited(_save());
  }

  /// 把任务挪到另一天（日程视图拖拽/改期用）。
  void moveTaskToDay(TodoTask task, DateTime day) {
    final at = task.scheduledAt(task.dueAt ?? task.remindAt ?? DateTime.now());
    final h = at?.hour ?? 9;
    final m = at?.minute ?? 0;
    final target = DateTime(day.year, day.month, day.day, h, m);
    if (task.kind == TodoKind.reminder) {
      task.remindAt = target;
    } else if (task.kind == TodoKind.task) {
      task.dueAt = target;
    }
    unawaited(_save());
  }

  // -------------------------------------------------------------------------
  // 清单与分类
  // -------------------------------------------------------------------------

  TodoList addList({
    required String name,
    required int color,
    required String iconKey,
  }) {
    final list = TodoList(
      id: _newId('l'),
      name: name.trim(),
      color: color,
      iconKey: iconKey,
    );
    _lists.add(list);
    unawaited(_save());
    return list;
  }

  void updateList(TodoList list) {
    final i = _lists.indexWhere((l) => l.id == list.id);
    if (i < 0) return;
    _lists[i] = list;
    unawaited(_save());
  }

  void deleteList(String id) {
    if (_lists.length <= 1) return;
    _lists.removeWhere((l) => l.id == id);
    final fallback = _lists.first.id;
    for (final t in _tasks) {
      if (t.listId == id) t.listId = fallback;
    }
    unawaited(_save());
  }

  TodoCategory addCategory({
    required String name,
    required int color,
    required String iconKey,
  }) {
    final cat = TodoCategory(
      id: _newId('c'),
      name: name.trim(),
      color: color,
      iconKey: iconKey,
    );
    _categories.add(cat);
    unawaited(_save());
    return cat;
  }

  void updateCategory(TodoCategory cat) {
    final i = _categories.indexWhere((c) => c.id == cat.id);
    if (i < 0) return;
    _categories[i] = cat;
    unawaited(_save());
  }

  void deleteCategory(String id) {
    final cat = categoryOf(id);
    if (cat.builtIn) return;
    _categories.removeWhere((c) => c.id == id);
    final fallback = _categories.first.id;
    for (final t in _tasks) {
      if (t.categoryId == id) t.categoryId = fallback;
    }
    unawaited(_save());
  }

  // -------------------------------------------------------------------------
  // 查询
  // -------------------------------------------------------------------------

  List<TodoTask> tasksOn(DateTime day) {
    final d = dayOf(day);
    final list = _tasks.where((t) => t.occursOn(d)).toList();
    list.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      final at = a.scheduledAt(d);
      final bt = b.scheduledAt(d);
      if (at != null && bt != null) return at.compareTo(bt);
      if (at != null) return -1;
      if (bt != null) return 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  List<TodoTask> get todayTasks => tasksOn(DateTime.now());

  List<TodoTask> get openTasks => _tasks.where((t) => !t.done).toList();

  /// 从 [day] 往后 14 天里每天的任务数，用于日程日历。
  Map<DateTime, List<TodoTask>> monthMap(DateTime month) {
    final out = <DateTime, List<TodoTask>>{};
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    for (var i = 0; i < days; i++) {
      final d = DateTime(first.year, first.month, first.day + i);
      final list = tasksOn(d);
      if (list.isNotEmpty) out[d] = list;
    }
    return out;
  }

  int doneOn(DateTime day) {
    final d = dayOf(day);
    final done = _tasks
        .where((t) => t.done && t.doneAt != null && dayOf(t.doneAt!) == d)
        .length;
    return done;
  }

  int totalOn(DateTime day) {
    final d = dayOf(day);
    final planned = _tasks.where((t) => t.occursOn(d)).length;
    final extra = _tasks
        .where(
          (t) =>
              t.done &&
              t.doneAt != null &&
              dayOf(t.doneAt!) == d &&
              !t.occursOn(d),
        )
        .length;
    return planned + extra;
  }

  int get todayDone => doneOn(DateTime.now());
  int get todayTotal => totalOn(DateTime.now());
  double get todayRate =>
      todayTotal == 0 ? 0 : (todayDone / todayTotal).clamp(0, 1);

  /// 连续完成天数：今天有完成就从今天算，否则从昨天往前算。
  int get streak {
    var cursor = dayOf(DateTime.now());
    if (doneOn(cursor) == 0) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var n = 0;
    while (doneOn(cursor) > 0 && n < 3650) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// 最近 7 天（含今天）的完成数。
  List<(DateTime, int)> get weekDone {
    final today = dayOf(DateTime.now());
    return [
      for (var i = 6; i >= 0; i--)
        (
          today.subtract(Duration(days: i)),
          doneOn(today.subtract(Duration(days: i))),
        ),
    ];
  }

  Map<String, int> listCounts(DateTime day) {
    final out = <String, int>{};
    for (final t in tasksOn(day)) {
      out[t.listId] = (out[t.listId] ?? 0) + (t.done ? 1 : 0);
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // 复盘
  // -------------------------------------------------------------------------

  DailyReview? reviewFor(DateTime day) => _reviews[dayKey(day)];

  Future<void> saveReview(
    DateTime day,
    String text, {
    bool ai = false,
    bool auto = false,
  }) async {
    final key = dayKey(day);
    if (text.trim().isEmpty) {
      _reviews.remove(key);
    } else {
      _reviews[key] = DailyReview(
        text: text.trim(),
        ai: ai,
        auto: auto,
        updatedAt: DateTime.now(),
      );
    }
    await _save();
  }

  void setAutoReview({bool? enabled, String? time}) {
    if (enabled != null) autoReviewEnabled = enabled;
    if (time != null) autoReviewTime = time;
    unawaited(_save());
  }

  // -------------------------------------------------------------------------
  // 心情
  // -------------------------------------------------------------------------

  List<MoodEntry> moodsOn(DateTime day) {
    final key = dayKey(day);
    final list = _moods.where((m) => m.dateKey == key).toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));
    return list;
  }

  MoodEntry? latestMoodOn(DateTime day) {
    final list = moodsOn(day);
    return list.isEmpty ? null : list.last;
  }

  MoodEntry addMood(MoodKind kind, {String note = '', DateTime? at}) {
    final ts = at ?? DateTime.now();
    final entry = MoodEntry(
      id: _newId('m'),
      dateKey: dayKey(ts),
      kind: kind,
      note: note.trim(),
      ts: ts,
    );
    _moods.add(entry);
    _moods.sort((a, b) => a.ts.compareTo(b.ts));
    unawaited(_save());
    return entry;
  }

  void updateMood(MoodEntry entry) {
    final i = _moods.indexWhere((m) => m.id == entry.id);
    if (i < 0) return;
    _moods[i] = entry;
    unawaited(_save());
  }

  void deleteMood(String id) {
    _moods.removeWhere((m) => m.id == id);
    unawaited(_save());
  }

  /// 最近 N 天每天最后一条心情记录，用于趋势。
  List<(DateTime, MoodEntry?)> moodTrend(int days) {
    final today = dayOf(DateTime.now());
    return [
      for (var i = days - 1; i >= 0; i--)
        (
          today.subtract(Duration(days: i)),
          latestMoodOn(today.subtract(Duration(days: i))),
        ),
    ];
  }

  // -------------------------------------------------------------------------
  // 提醒
  // -------------------------------------------------------------------------

  /// 重排本地提醒。通知 id 落在 9000–9508：每个任务最多 4 个槽，对应多条提前提醒。
  Future<void> reschedule() async {
    if (!_inited) return;
    // 测试环境不排真提醒，避免留下 pending timer 影响用例收尾。
    if (platform.isTest) return;
    if (!Notifications.enabled) return;
    final now = DateTime.now();
    final wanted = <int>{};
    // 只取哈希低位时两个任务极易撞车，撞了就会被 _scheduledIds 跳过、提醒直接丢。
    final used = <int>{};
    for (final t in _tasks) {
      if (t.done) continue;
      final times = _reminderTimes(t, now);
      if (times.isEmpty) continue;
      final base = 9000 + (t.id.hashCode.abs() % 20000) * 4;
      for (var i = 0; i < times.length; i++) {
        var id = base + i;
        var guard = 0;
        while (used.contains(id) && guard < 8) {
          id++;
          guard++;
        }
        used.add(id);
        wanted.add(id);
        if (_scheduledIds.contains(id)) continue;
        // 每条通知自己的提前量，决定文案。
        final lead = t.kind == TodoKind.task && t.dueAt != null
            ? t.dueAt!.difference(times[i]).inMinutes
            : 0;
        String title;
        String body;
        switch (t.kind) {
          case TodoKind.reminder:
            title = '提醒 · ${t.title}';
            body = t.note.isEmpty ? '到点了，记得处理' : t.note;
          case TodoKind.task:
            title = '待办 · ${t.title}';
            body = _leadText(lead, t.dueAt);
          case TodoKind.habit:
            title = '习惯 · ${t.title}';
            body = '今天这一小步，别忘了';
          case TodoKind.quick:
            continue;
        }
        unawaited(
          Notifications.schedule(
            id,
            title,
            body,
            times[i],
            channelId: 'citro_reminders',
            channelName: 'Citro 提醒',
          ),
        );
      }
    }
    for (final id in _scheduledIds.toList()) {
      if (!wanted.contains(id)) {
        unawaited(Notifications.cancel(id));
      }
    }
    _scheduledIds
      ..clear()
      ..addAll(wanted);
  }

  /// 提前提醒的正文：到点就问完成没，提前则说明还剩多久。
  String _leadText(int lead, DateTime? due) {
    if (lead <= 0) {
      final hm = due == null
          ? ''
          : '（${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}）';
      return '到截止时间了$hm，完成了吗？';
    }
    final label = lead < 60
        ? '$lead 分钟'
        : lead < 1440
        ? '${lead ~/ 60} 小时'
        : '${lead ~/ 1440} 天';
    return '距离截止还有 $label';
  }

  /// 一个任务在未来的所有提醒时间：提醒一条，待办按每个提前量各一条。
  List<DateTime> _reminderTimes(TodoTask task, DateTime now) {
    switch (task.kind) {
      case TodoKind.reminder:
        final at = task.remindAt;
        return at != null && at.isAfter(now) ? [at] : const [];
      case TodoKind.task:
        final at = task.dueAt;
        if (at == null) return const [];
        final leads = task.leadMinutes.isEmpty ? const [15] : task.leadMinutes;
        final out = <DateTime>[
          for (final m in leads)
            if (at.subtract(Duration(minutes: m)).isAfter(now))
              at.subtract(Duration(minutes: m)),
        ];
        // 提前量都过了，也至少在截止那一刻提醒一次。
        if (out.isEmpty && at.isAfter(now)) out.add(at);
        out.sort();
        return out.take(4).toList();
      case TodoKind.habit:
        // 一次排未来几天的，App 不打开也不会漏掉第二天的习惯。
        return _habitTimes(task, now);
      case TodoKind.quick:
        return const [];
    }
  }

  List<DateTime> _habitTimes(TodoTask task, DateTime now) {
    final parts = task.habitTime.split(':');
    final h = int.tryParse(parts.first) ?? 20;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final days = task.habitDays.isEmpty
        ? {1, 2, 3, 4, 5, 6, 7}
        : task.habitDays;
    final out = <DateTime>[];
    for (var i = 0; i <= 7 && out.length < 4; i++) {
      final d = dayOf(now).add(Duration(days: i));
      if (!days.contains(d.weekday)) continue;
      final at = DateTime(d.year, d.month, d.day, h, m);
      if (at.isAfter(now)) out.add(at);
    }
    return out;
  }
}
