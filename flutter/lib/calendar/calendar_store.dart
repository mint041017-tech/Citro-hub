import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/api.dart';
import '../services/platform.dart' as platform;
import '../services/prefs.dart';
import '../state/app_state.dart';
import 'calendar_models.dart';

/// 日历「倒数日 / 纪念日」的本地缓存 + 账号云端同步。
///
/// 同步策略与待办、记账一致：本地先写 SharedPreferences，登录后把整包
/// 推到 `/api/calendar`；拉取时比较服务端 `at` 和本地 `updatedAt`，
/// 远端更新则覆盖本地，否则把本地推上去。离线时完全不影响使用。
class CalendarStore extends ChangeNotifier {
  CalendarStore._();

  static final CalendarStore instance = CalendarStore._();

  List<CalendarMark> _marks = const [];
  int _updatedAt = 0;
  bool _ready = false;
  bool _accountSynced = false;
  Timer? _pushTimer;

  List<CalendarMark> get marks => List.unmodifiable(_marks);

  int get count => _marks.length;

  bool get isEmpty => _marks.isEmpty;

  bool get signedIn => AppState.instance.loggedIn;

  Future<void> ensureInit() async {
    if (_ready) return;
    _ready = true;
    await _load();
    unawaited(syncFromAccount());
  }

  /// 测试用：清空内存状态，让下一次 [ensureInit] 重新读本地缓存。
  void resetForTest() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _ready = false;
    _accountSynced = false;
    _updatedAt = 0;
    _marks = const [];
  }

  Future<void> _load() async {
    try {
      final raw = Prefs.getString(PrefKeys.calendarMarks);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw);
      if (json is! Map) return;
      final list = json['marks'];
      if (list is List) {
        _marks = list
            .map(CalendarMark.fromJson)
            .whereType<CalendarMark>()
            .toList(growable: false);
      }
      final at = json['updatedAt'];
      _updatedAt = at is int ? at : (at is num ? at.toInt() : 0);
    } catch (_) {
      // 坏数据不阻塞卡片：回到空列表，用户重新添加即可。
    }
  }

  /// 按今天排序：先倒数日（最近发生的在前），再纪念日。
  List<CalendarMark> sorted(DateTime today) {
    final list = [..._marks];
    list.sort((a, b) {
      final byKind = a.kind.index.compareTo(b.kind.index);
      if (byKind != 0) return byKind;
      final da = CalendarDates.daysFor(a, today).abs();
      final db = CalendarDates.daysFor(b, today).abs();
      if (da != db) return da.compareTo(db);
      return a.title.compareTo(b.title);
    });
    return list;
  }

  /// 今日命中的标记，供首页小卡展示「今天是什么日子」。
  List<CalendarMark> todayMarks(DateTime today) =>
      _marks.where((mark) => CalendarDates.hits(mark, today)).toList();

  Future<void> saveMark(CalendarMark mark) async {
    final next = [..._marks];
    final index = next.indexWhere((item) => item.id == mark.id);
    if (index >= 0) {
      next[index] = mark;
    } else {
      next.add(mark);
    }
    _marks = next;
    await _save();
  }

  Future<void> removeMark(String id) async {
    final next = _marks.where((mark) => mark.id != id).toList();
    if (next.length == _marks.length) return;
    _marks = next;
    await _save();
  }

  Future<void> _save() async {
    _updatedAt = DateTime.now().millisecondsSinceEpoch;
    await Prefs.setString(PrefKeys.calendarMarks, jsonEncode(_payload()));
    notifyListeners();
    _schedulePush();
  }

  Map<String, Object?> _payload() => {
    'marks': _marks.map((mark) => mark.toJson()).toList(),
    'updatedAt': _updatedAt,
  };

  /// 登录后拉取云端标记；远端更新时覆盖本地，否则把本地推上去。
  Future<void> syncFromAccount({bool force = false}) async {
    if (platform.isTest) return;
    if (!force && _accountSynced) return;
    if (!AppState.instance.loggedIn) return;
    _accountSynced = true;
    try {
      final json = await Api.calendarGet();
      final remote = json['calendar'];
      final at = json['at'] is num ? (json['at'] as num).toInt() : 0;
      if (remote is Map && at > _updatedAt) {
        await _applyRemote(Map<String, dynamic>.from(remote), at);
        return;
      }
      if (_marks.isNotEmpty) _schedulePush(immediate: true);
    } catch (_) {
      // 离线或服务端未部署：继续使用本地数据。
    }
  }

  Future<void> _applyRemote(Map<String, dynamic> remote, int at) async {
    final list = remote['marks'];
    final marks = list is List
        ? list
              .map(CalendarMark.fromJson)
              .whereType<CalendarMark>()
              .toList(growable: false)
        : <CalendarMark>[];
    _marks = marks;
    _updatedAt = at;
    await Prefs.setString(
      PrefKeys.calendarMarks,
      jsonEncode({...remote, 'updatedAt': at}),
    );
    notifyListeners();
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
      await Api.calendarSave(_payload());
    } catch (_) {
      // 网络恢复后下一次修改会再次推送。
    }
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    super.dispose();
  }
}
