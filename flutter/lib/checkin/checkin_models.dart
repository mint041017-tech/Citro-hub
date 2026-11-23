/// 每日打卡升级（晚间回签 / 七日成卷 / 签类行动联动）的数据模型。
///
/// 这里只放纯数据与纯函数，便于单测；读写 Prefs、网络同步在
/// `checkin_store.dart` 与 `checkin_sync.dart` 里。
library;

import 'dart:math' as math;

import '../data/fortunes.dart';
import '../services/prefs.dart';

/// 回签正文上限，与服务端校验保持一致。
const int kCheckinReflectionMax = 120;

/// 行动文案上限。
const int kCheckinActionTextMax = 60;

/// 规则版本：本地键里带 v1，后续大改再升版本。
const String kCheckinStoreVersion = 'v1';

/// 通用行动类型。
class CheckinActionType {
  static const task = 'task';
  static const focus = 'focus';
  static const listen = 'listen';
  static const ledger = 'ledger';
  static const note = 'note';
  static const community = 'community';
  static const manual = 'manual';

  static const all = <String>[
    task,
    focus,
    listen,
    ledger,
    note,
    community,
    manual,
  ];

  static String label(String? type) => switch (type) {
    task => '计划任务',
    focus => '专注',
    listen => '听隅',
    ledger => '记账',
    note => '记录',
    community => '社区互动',
    _ => '手动确认',
  };
}

/// 回签落点。
class CheckinMood {
  static const same = 'same';
  static const different = 'different';
  static const unrated = 'unrated';

  static const all = <String>[same, different, unrated];

  static String label(String? mood) => switch (mood) {
    same => '如签所说',
    different => '走了自己的路',
    _ => '不想归类',
  };
}

/// 行动状态。
class CheckinActionStatus {
  static const pending = 'pending';
  static const done = 'done';
}

/// 功能开关。默认全开；编译时可用 `--dart-define` 关闭，也可以在
/// 本机写入 `citro_checkin_flag_*`（`'0'` 关闭）做灰度回滚。
class CheckinFlags {
  static const _envReflection = bool.fromEnvironment(
    'CITRO_CHECKIN_REFLECTION',
    defaultValue: true,
  );
  static const _envScroll = bool.fromEnvironment(
    'CITRO_CHECKIN_SCROLL',
    defaultValue: true,
  );
  static const _envLinkedAction = bool.fromEnvironment(
    'CITRO_CHECKIN_LINKED_ACTION',
    defaultValue: true,
  );

  static const keyReflection = 'citro_checkin_flag_reflection';
  static const keyScroll = 'citro_checkin_flag_scroll';
  static const keyLinkedAction = 'citro_checkin_flag_linked_action';

  static bool get reflectionEnabled =>
      _read(keyReflection, _envReflection);
  static bool get scrollEnabled => _read(keyScroll, _envScroll);
  static bool get linkedActionEnabled =>
      _read(keyLinkedAction, _envLinkedAction);

  static bool _read(String key, bool fallback) {
    try {
      final raw = Prefs.getString(key);
      if (raw == null || raw.isEmpty) return fallback;
      return raw != '0';
    } catch (_) {
      return fallback;
    }
  }
}

/// 一天的打卡记录。字段与执行方案 7.1 对齐；`pendingSync` 与
/// `actionStartedAt` 只存在本机，不上传服务端。
class CheckinDayEntry {
  final String date;
  final String signId;
  final String signTitle;
  final int levelIndex;
  final String kind;
  final String? cardId;
  final bool transferUsed;
  final String actionText;
  final String actionType;
  final String actionStatus;
  final String? linkedId;
  final String? completedActionText;
  final int? completedAt;
  final String? reflectionMood;
  final String reflectionText;
  final int? reflectionUpdatedAt;
  final int createdAt;
  final int updatedAt;
  final int rev;

  /// 本地字段：是否还有未同步的改动。
  final bool pendingSync;

  /// 本地字段：用户点下行动主按钮的时间。自动验证只统计这之后的新行为。
  final int? actionStartedAt;

  const CheckinDayEntry({
    required this.date,
    required this.signId,
    required this.signTitle,
    required this.levelIndex,
    required this.kind,
    this.cardId,
    this.transferUsed = false,
    required this.actionText,
    required this.actionType,
    this.actionStatus = CheckinActionStatus.pending,
    this.linkedId,
    this.completedActionText,
    this.completedAt,
    this.reflectionMood,
    this.reflectionText = '',
    this.reflectionUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.rev = 0,
    this.pendingSync = false,
    this.actionStartedAt,
  });

  bool get actionDone => actionStatus == CheckinActionStatus.done;

  bool get hasReflection => reflectionUpdatedAt != null;
  bool get hasText => reflectionText.trim().isNotEmpty;
  String get kindLabel => fortuneKindLabel(kind);

  CheckinDayEntry copyWith({
    String? signId,
    String? signTitle,
    int? levelIndex,
    String? kind,
    String? cardId,
    bool? clearCardId,
    bool? transferUsed,
    String? actionText,
    String? actionType,
    String? actionStatus,
    String? linkedId,
    bool? clearLinkedId,
    String? completedActionText,
    bool? clearCompletedActionText,
    int? completedAt,
    bool? clearCompletedAt,
    String? reflectionMood,
    bool? clearReflectionMood,
    String? reflectionText,
    int? reflectionUpdatedAt,
    int? updatedAt,
    int? rev,
    bool? pendingSync,
    int? actionStartedAt,
    bool? clearActionStartedAt,
  }) => CheckinDayEntry(
    date: date,
    signId: signId ?? this.signId,
    signTitle: signTitle ?? this.signTitle,
    levelIndex: levelIndex ?? this.levelIndex,
    kind: kind ?? this.kind,
    cardId: clearCardId == true ? null : (cardId ?? this.cardId),
    transferUsed: transferUsed ?? this.transferUsed,
    actionText: actionText ?? this.actionText,
    actionType: actionType ?? this.actionType,
    actionStatus: actionStatus ?? this.actionStatus,
    linkedId: clearLinkedId == true ? null : (linkedId ?? this.linkedId),
    completedActionText: clearCompletedActionText == true
        ? null
        : (completedActionText ?? this.completedActionText),
    completedAt: clearCompletedAt == true
        ? null
        : (completedAt ?? this.completedAt),
    reflectionMood: clearReflectionMood == true
        ? null
        : (reflectionMood ?? this.reflectionMood),
    reflectionText: reflectionText ?? this.reflectionText,
    reflectionUpdatedAt: reflectionUpdatedAt ?? this.reflectionUpdatedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    rev: rev ?? this.rev,
    pendingSync: pendingSync ?? this.pendingSync,
    actionStartedAt: clearActionStartedAt == true
        ? null
        : (actionStartedAt ?? this.actionStartedAt),
  );

  /// 完整 JSON（本机缓存用，含本地字段）。
  Map<String, Object?> toJson({bool includeLocal = true}) {
    final map = <String, Object?>{
      'date': date,
      'signId': signId,
      'signTitle': signTitle,
      'levelIndex': levelIndex,
      'kind': kind,
      'cardId': cardId,
      'transferUsed': transferUsed,
      'actionText': actionText,
      'actionType': actionType,
      'actionStatus': actionStatus,
      'linkedId': linkedId,
      'completedActionText': completedActionText,
      'completedAt': completedAt,
      'reflectionMood': reflectionMood,
      'reflectionText': reflectionText,
      'reflectionUpdatedAt': reflectionUpdatedAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'rev': rev,
    };
    if (includeLocal) {
      map['pendingSync'] = pendingSync;
      map['actionStartedAt'] = actionStartedAt;
    }
    return map;
  }

  /// 创建记录时提交的字段子集。
  Map<String, Object?> creationPayload() => {
    'date': date,
    'signId': signId,
    'signTitle': signTitle,
    'levelIndex': levelIndex,
    'kind': kind,
    'cardId': cardId,
    'transferUsed': transferUsed,
    'actionText': actionText,
    'actionType': actionType,
  };

  Map<String, Object?> actionPayload({required bool done, int? revOverride}) => {
    'date': date,
    'done': done,
    'actionText': actionText,
    'actionType': actionType,
    'linkedId': linkedId,
    'rev': revOverride ?? rev,
  };

  Map<String, Object?> reflectionPayload({int? revOverride}) => {
    'date': date,
    'mood': reflectionMood ?? CheckinMood.unrated,
    'text': reflectionText,
    'rev': revOverride ?? rev,
  };

  static CheckinDayEntry? fromJson(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    final date = _str(raw['date']);
    if (!isCheckinDate(date)) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final level = _int(raw['levelIndex']).clamp(0, 7);
    return CheckinDayEntry(
      date: date,
      signId: _trim(_str(raw['signId']), 40),
      signTitle: _trim(_str(raw['signTitle']), 40),
      levelIndex: level,
      kind: _kind(raw['kind']),
      cardId: _nullableTrim(raw['cardId'], 40),
      transferUsed: raw['transferUsed'] == true,
      actionText: _trim(_str(raw['actionText']), kCheckinActionTextMax),
      actionType: _actionType(raw['actionType']),
      actionStatus: raw['actionStatus'] == CheckinActionStatus.done
          ? CheckinActionStatus.done
          : CheckinActionStatus.pending,
      linkedId: _nullableTrim(raw['linkedId'], 64),
      completedActionText: _nullableTrim(
        raw['completedActionText'],
        kCheckinActionTextMax,
      ),
      completedAt: _nullableInt(raw['completedAt']),
      reflectionMood: _mood(raw['reflectionMood']),
      reflectionText: _trim(_str(raw['reflectionText']), kCheckinReflectionMax),
      reflectionUpdatedAt: _nullableInt(raw['reflectionUpdatedAt']),
      createdAt: _nullableInt(raw['createdAt']) ?? now,
      updatedAt: _nullableInt(raw['updatedAt']) ?? now,
      rev: math.max(0, _int(raw['rev'])),
      pendingSync: raw['pendingSync'] == true,
      actionStartedAt: _nullableInt(raw['actionStartedAt']),
    );
  }

  static String _str(Object? v) => v == null ? '' : '$v'.trim();
  static String? _nullableTrim(Object? v, int max) {
    final s = _trim(_str(v), max);
    return s.isEmpty ? null : s;
  }

  static String _trim(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse('$v') ?? 0;
  }

  static int? _nullableInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    final parsed = int.tryParse('$v');
    return parsed;
  }

  static String _kind(Object? v) {
    final s = _str(v);
    return kFortuneKinds.containsKey(s) ? s : 'tiny';
  }

  static String _actionType(Object? v) {
    final s = _str(v);
    return CheckinActionType.all.contains(s) ? s : CheckinActionType.manual;
  }

  static String? _mood(Object? v) {
    final s = _str(v);
    return CheckinMood.all.contains(s) ? s : null;
  }
}

/// 一卷：七个打卡日期为一卷（不要求连续）。
class CheckinVolume {
  final int index;

  /// 已收进本卷的记录，最多七条，按日期升序。
  final List<CheckinDayEntry> entries;

  const CheckinVolume({required this.index, required this.entries});

  int get filled => entries.length;
  bool get full => entries.length >= 7;
  bool get isEmpty => entries.isEmpty;
  String get title => '第 $index 卷';

  String? get startDate => entries.isEmpty ? null : entries.first.date;
  String? get endDate => entries.isEmpty ? null : entries.last.date;

  String get rangeLabel {
    if (entries.isEmpty) return '这一卷还没有开始';
    final start = _shortDate(entries.first.date);
    final end = _shortDate(entries.last.date);
    return start == end ? start : '$start — $end';
  }

  /// 七个格子，未到来的为空。
  List<CheckinDayEntry?> get slots => List<CheckinDayEntry?>.generate(
    7,
    (i) => i < entries.length ? entries[i] : null,
    growable: false,
  );

  static String _shortDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${int.tryParse(parts[1]) ?? parts[1]} 月 '
        '${int.tryParse(parts[2]) ?? parts[2]} 日';
  }
}

/// 成卷算法：所有有效打卡日期排序，每七条一卷。
///
/// - 同一天只算一次（由 Map 保证）；
/// - 转运、行动、回签都不增加格子；
/// - 漏签不清空；
/// - 第七次集满后，下一次打卡开启下一卷。
List<CheckinVolume> buildCheckinVolumes(List<CheckinDayEntry> days) {
  final sorted = List<CheckinDayEntry>.from(days)
    ..sort((a, b) => a.date.compareTo(b.date));
  final volumes = <CheckinVolume>[];
  for (var i = 0; i < sorted.length; i += 7) {
    volumes.add(
      CheckinVolume(
        index: volumes.length + 1,
        entries: sorted.sublist(i, math.min(i + 7, sorted.length)),
      ),
    );
  }
  return volumes;
}

/// 首页状态机（执行方案 4.2）。
enum CheckinHomePhase {
  notChecked,
  actionPending,
  actionDone,
  pendingReflection,
  reflected,
}

class CheckinHomeView {
  final CheckinHomePhase phase;
  final String pill;
  final String subtitle;
  final bool syncing;
  final bool syncFailed;

  const CheckinHomeView({
    required this.phase,
    required this.pill,
    required this.subtitle,
    this.syncing = false,
    this.syncFailed = false,
  });

  bool get done => phase == CheckinHomePhase.reflected;
}

/// 根据当天记录、当前时间与同步状态生成首页文案。
///
/// 18:00 之后的「待回签」只是视觉状态：不弹窗、不加红点、不催办。
CheckinHomeView checkinHomeView({
  required CheckinDayEntry? today,
  required DateTime now,
  required int streak,
  bool syncing = false,
  bool syncFailed = false,
}) {
  if (today == null) {
    return const CheckinHomeView(
      phase: CheckinHomePhase.notChecked,
      pill: '待打卡',
      subtitle: '翻开今天的签',
    );
  }
  if (today.hasReflection) {
    return CheckinHomeView(
      phase: CheckinHomePhase.reflected,
      pill: '已收好',
      subtitle: streak > 0 ? '今天收好了 · 连续 $streak 天' : '今天收好了',
      syncing: syncing,
      syncFailed: syncFailed,
    );
  }
  if (CheckinFlags.reflectionEnabled && now.hour >= 18) {
    return CheckinHomeView(
      phase: CheckinHomePhase.pendingReflection,
      pill: '待回签',
      subtitle: '给今天收个尾',
      syncing: syncing,
      syncFailed: syncFailed,
    );
  }
  if (!today.actionDone) {
    return CheckinHomeView(
      phase: CheckinHomePhase.actionPending,
      pill: '已打卡',
      subtitle: '今日一小步还等着你',
      syncing: syncing,
      syncFailed: syncFailed,
    );
  }
  return CheckinHomeView(
    phase: CheckinHomePhase.actionDone,
    pill: '已打卡',
    subtitle: '今天已经留下了脚印',
    syncing: syncing,
    syncFailed: syncFailed,
  );
}

/// `YYYY-MM-DD`（本机时区）。
String checkinDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 严格校验日期字符串，且必须是真实存在的日期。
bool isCheckinDate(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  final d = checkinParseDate(s);
  if (d == null) return false;
  return checkinDateKey(d) == s;
}

DateTime? checkinParseDate(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  final parsed = DateTime(y, m, d);
  if (parsed.month != m || parsed.day != d) return null;
  return parsed;
}

/// 日期短标签：`11 月 21 日 · 周六`。
String checkinDateLabel(String date, {bool withWeekday = true}) {
  final d = checkinParseDate(date);
  if (d == null) return date;
  const weekday = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final base = '${d.month} 月 ${d.day} 日';
  return withWeekday ? '$base · ${weekday[d.weekday - 1]}' : base;
}

/// 按 Unicode 码点截断，避免把 emoji 或组合字切成半个。
String checkinClampText(String text, int max) {
  final trimmed = text.trim();
  final runes = trimmed.runes.toList();
  if (runes.length <= max) return trimmed;
  return String.fromCharCodes(runes.take(max));
}

/// 签等级 → 索引（节日签没有 idx，用等级名兜底）。
int checkinLevelIndex(Fortune f) {
  if (f.idx != null) return f.idx!.clamp(0, 7);
  for (var i = 0; i < kFortunes.length; i++) {
    if (kFortunes[i].lv == f.lv) return i;
  }
  return 0;
}
