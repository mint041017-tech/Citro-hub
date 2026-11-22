import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ledger/ledger_store.dart';
import '../services/api.dart';
import '../services/pomodoro.dart';
import '../services/prefs.dart';
import '../tingyu/tingyu_controller.dart';
import '../todo/todo_store.dart';
import 'checkin_models.dart';
import 'checkin_sync.dart';
import 'daily_actions.dart';

/// 每日打卡本机 Store。
///
/// 页面只读它、不直接碰 Prefs/Api：
/// - 当天打开打卡就创建 [CheckinDayEntry]；
/// - 所有改动先落本机，再排队同步（游客只存本机）；
/// - 行动完成由各模块的通知自动验证，验证不到时保留手动按钮。
class CheckinStore extends ChangeNotifier {
  static final CheckinStore instance = CheckinStore._();
  CheckinStore._();

  String? _accountName;
  String _accountKey = 'guest';
  bool _ready = false;

  Map<String, CheckinDayEntry> _days = {};
  Set<String> _pendingDates = {};
  String? _serverDate;

  bool syncing = false;
  bool syncFailed = false;
  String? syncNote;
  String? conflictDate;

  int? _justCompletedVolume;
  Timer? _dayTimer;
  Timer? _syncTimer;
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _busySync = false;
  bool _syncQueued = false;

  bool _listenersAttached = false;
  bool _listenWasPlaying = false;
  DateTime? _listenStartedAt;
  int _listenSeconds = 0;
  Timer? _listenTimer;

  bool get ready => _ready;
  bool get isGuest => _accountName == null;
  String? get accountName => _accountName;

  String get _daysKey => 'citro_checkin_days_v1_$_accountKey';

  String get todayKey {
    final server = _serverDate;
    if (!isGuest && server != null && isCheckinDate(server)) return server;
    return checkinDateKey(DateTime.now());
  }

  CheckinDayEntry? get today => _days[todayKey];

  List<CheckinDayEntry> get days {
    final list = _days.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return List.unmodifiable(list);
  }

  bool get hasToday => today != null;

  int get totalDays => _days.length;

  CheckinDayEntry? entryFor(String date) => _days[date];

  List<CheckinVolume> get volumes => buildCheckinVolumes(_days.values.toList());

  CheckinVolume get currentVolume => volumes.isEmpty
      ? const CheckinVolume(index: 1, entries: [])
      : volumes.last;

  /// 上一卷集满后，下一卷的预览（还没有任何记录）。
  CheckinVolume get nextVolume =>
      CheckinVolume(index: volumes.length + 1, entries: const []);

  int get streak {
    final parsed = checkinParseDate(todayKey);
    if (parsed == null) return 0;
    var cursor = parsed;
    if (!_days.containsKey(todayKey)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var n = 0;
    while (n < 3650 && _days.containsKey(checkinDateKey(cursor))) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  CheckinHomeView homeViewFor(int fallbackStreak) {
    if (!CheckinFlags.reflectionEnabled) {
      final entry = today;
      if (entry == null) {
        return const CheckinHomeView(
          phase: CheckinHomePhase.notChecked,
          pill: '待打卡',
          subtitle: '翻开今天的签',
        );
      }
      return CheckinHomeView(
        phase: CheckinHomePhase.actionDone,
        pill: '已完成',
        subtitle: '今天已完成，明天继续',
        syncing: syncing,
        syncFailed: syncFailed,
      );
    }
    return checkinHomeView(
      today: today,
      now: DateTime.now(),
      // 旧版 Prefs / 服务端连续天数仍是展示口径；新记录只补 0 的情况。
      streak: fallbackStreak > 0 ? fallbackStreak : streak,
      syncing: syncing,
      syncFailed: syncFailed,
    );
  }

  /// 进入账号后第一次初始化。AppState 在 Prefs.init 之后调用。
  Future<void> ensureInit({String? account}) async {
    final next = (account == null || account.trim().isEmpty)
        ? null
        : account.trim();
    if (_ready && next == _accountName) {
      _attachListeners();
      _scheduleDayBoundary();
      return;
    }
    _accountName = next;
    _accountKey = next ?? 'guest';
    _serverDate = null;
    _loadLocal();
    _ready = true;
    _attachListeners();
    _scheduleDayBoundary();
    notifyListeners();
    if (next != null) {
      unawaited(syncFromServer());
    }
  }

  /// 切账号：清掉当前内存，读回账号自己的本地记录。
  Future<void> onAccountChanged(String? account) =>
      ensureInit(account: account);

  void _loadLocal() {
    _days = {};
    _pendingDates = {};
    _listenSeconds = 0;
    _listenStartedAt = null;
    final raw = Prefs.getString(_daysKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        final list = decoded is Map ? decoded['days'] : decoded;
        if (list is List) {
          for (final item in list) {
            if (item is! Map) continue;
            final entry = CheckinDayEntry.fromJson(item);
            if (entry != null) _days[entry.date] = entry;
          }
        }
      } catch (_) {}
    }
    _pendingDates = CheckinSync.load(_accountKey)
        .map((e) => e.date)
        .toSet();
    for (final date in _pendingDates) {
      final entry = _days[date];
      if (entry != null) {
        _days[date] = entry.copyWith(pendingSync: true);
      }
    }
    try {
      _listenSeconds = Prefs.getInt(
        'citro_checkin_listen_v1_${_accountKey}_$todayKey',
      );
    } catch (_) {
      _listenSeconds = 0;
    }
  }

  Future<void> _persist() async {
    try {
      final list = _days.values
          .map(
            (e) => e.copyWith(
              pendingSync: _pendingDates.contains(e.date),
            ).toJson(),
          )
          .toList()
        ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
      await Prefs.setString(
        _daysKey,
        jsonEncode({'days': list, 'updatedAt': DateTime.now().toUtc().toIso8601String()}),
      );
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 创建 / 快照
  // ---------------------------------------------------------------------------

  /// 打卡页抽到签后调用。同一天重复调用只更新快照，不重开一条记录。
  ///
  /// [actionText] 是签面 / AI 给的那句小步；[cardId] 是卡面 id。
  /// 转运后再次调用会换签，但已开始的行动与回签不会被清掉。
  Future<CheckinDayEntry?> syncTodaySnapshot({
    required String signId,
    required String signTitle,
    required int levelIndex,
    required String kind,
    String? cardId,
    bool transferUsed = false,
    String? actionText,
  }) async {
    if (!_ready) await ensureInit();
    final date = todayKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final plan = checkinPlanForKind(kind);
    final text = checkinClampText(
      checkinActionTextFor(kind, stepText: actionText),
      kCheckinActionTextMax,
    );

    var entry = _days[date];
    if (entry == null) {
      entry = CheckinDayEntry(
        date: date,
        signId: signId,
        signTitle: signTitle,
        levelIndex: levelIndex.clamp(0, 7),
        kind: kind,
        cardId: cardId,
        transferUsed: transferUsed,
        actionText: text,
        actionType: plan.type,
        createdAt: now,
        updatedAt: now,
        rev: 0,
      );
      // 兼容旧版本写下的 `citro_fortune_step_<date>`，只读一次。
      final legacy = Prefs.getString('citro_fortune_step_$date');
      if (legacy == '1') {
        entry = entry.copyWith(
          actionStatus: CheckinActionStatus.done,
          completedAt: now,
          completedActionText: text,
          actionStartedAt: now,
        );
      }
      _days[date] = entry;
      _pendingDates.add(date);
      await _enqueueCreate(entry);
      if (_days.length % 7 == 0) {
        _justCompletedVolume = _days.length ~/ 7;
      }
      await _persist();
      notifyListeners();
      _scheduleSync();
      return entry;
    }

    var next = entry;
    var changed = false;
    if (entry.signId != signId ||
        entry.signTitle != signTitle ||
        entry.levelIndex != levelIndex ||
        entry.kind != kind ||
        (cardId != null && cardId.isNotEmpty && entry.cardId != cardId) ||
        (transferUsed && !entry.transferUsed)) {
      next = next.copyWith(
        signId: signId,
        signTitle: signTitle,
        levelIndex: levelIndex.clamp(0, 7),
        kind: kind,
        cardId: cardId,
        transferUsed: transferUsed || entry.transferUsed,
        updatedAt: now,
      );
      changed = true;
    }
    if (checkinActionTextEditable(entry)) {
      if (next.actionText != text) {
        next = next.copyWith(
          actionText: text,
          actionType: plan.type,
          clearLinkedId: true,
          clearActionStartedAt: true,
          updatedAt: now,
        );
        changed = true;
      } else if (next.actionType != plan.type) {
        next = next.copyWith(actionType: plan.type, updatedAt: now);
        changed = true;
      }
    }
    if (!changed) return next;
    _days[date] = next;
    _pendingDates.add(date);
    await _enqueueCreate(next);
    await _persist();
    notifyListeners();
    _scheduleSync();
    return next;
  }

  Future<void> _enqueueCreate(CheckinDayEntry entry) async {
    if (isGuest) return;
    await CheckinSync.enqueue(
      _accountKey,
      kind: 'create',
      date: entry.date,
      payload: entry.creationPayload(),
    );
  }

  /// 用户点了行动主按钮 / 次按钮，或通过外部入口进入行动。
  ///
  /// 自动验证只统计这个时间之后的新行为，避免「打卡前刚完成的任务」误触发。
  Future<void> markActionStarted({String? linkedId}) async {
    if (!_ready) await ensureInit();
    final entry = _days[todayKey];
    if (entry == null || entry.actionDone) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = entry.copyWith(
      actionStartedAt: entry.actionStartedAt ?? now,
      linkedId: linkedId ?? entry.linkedId,
      updatedAt: now,
    );
    _days[next.date] = next;
    _listenSeconds = 0;
    _listenStartedAt = NookController.instance.playing ? DateTime.now() : null;
    if (_listenStartedAt != null) _ensureListenTicker();
    await _persist();
    notifyListeners();
  }

  /// 手动 / 自动盖章。重复调用幂等。
  Future<void> completeAction({String? linkedId, String? snapshot}) async {
    if (!_ready) await ensureInit();
    final date = todayKey;
    final entry = _days[date];
    if (entry == null) return;
    if (entry.actionDone) {
      if (linkedId != null && entry.linkedId != linkedId) {
        _days[date] = entry.copyWith(linkedId: linkedId);
        await _persist();
        notifyListeners();
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = entry.copyWith(
      actionStatus: CheckinActionStatus.done,
      linkedId: linkedId ?? entry.linkedId,
      actionStartedAt: entry.actionStartedAt ?? now,
      completedAt: now,
      completedActionText: checkinClampText(
        snapshot ?? entry.actionText,
        kCheckinActionTextMax,
      ),
      updatedAt: now,
    );
    _days[date] = next;
    _pendingDates.add(date);
    if (!isGuest) {
      await CheckinSync.enqueue(
        _accountKey,
        kind: 'action',
        date: date,
        payload: next.actionPayload(done: true),
      );
    }
    await _persist();
    notifyListeners();
    _scheduleSync();
  }

  // ---------------------------------------------------------------------------
  // 晚间回签
  // ---------------------------------------------------------------------------

  /// 保存回签。返回更新后的记录；没有当天记录时返回 null。
  Future<CheckinDayEntry?> saveReflection({
    String? date,
    String? mood,
    required String text,
  }) async {
    if (!_ready) await ensureInit();
    final key = date ?? todayKey;
    final entry = _days[key];
    if (entry == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final moodValue = mood == null || mood.isEmpty
        ? (entry.reflectionMood ?? CheckinMood.unrated)
        : (CheckinMood.all.contains(mood) ? mood : CheckinMood.unrated);
    var next = entry.copyWith(
      reflectionMood: moodValue,
      reflectionText: checkinClampText(text, kCheckinReflectionMax),
      reflectionUpdatedAt: now,
      updatedAt: now,
    );

    // 心事签 / 灵感签的自动验证就是「保存一句心情或回签」。
    var completeActionToo = false;
    if (next.actionStatus == CheckinActionStatus.pending &&
        (next.kind == 'heart' || next.kind == 'idea')) {
      next = next.copyWith(
        actionStatus: CheckinActionStatus.done,
        completedAt: now,
        completedActionText: next.actionText,
        actionStartedAt: next.actionStartedAt ?? now,
      );
      completeActionToo = true;
    }

    _days[key] = next;
    _pendingDates.add(key);
    if (!isGuest) {
      if (completeActionToo) {
        await CheckinSync.enqueue(
          _accountKey,
          kind: 'action',
          date: key,
          payload: next.actionPayload(done: true),
        );
      }
      await CheckinSync.enqueue(
        _accountKey,
        kind: 'reflection',
        date: key,
        payload: next.reflectionPayload(),
      );
    }
    conflictDate = null;
    syncNote = null;
    await _persist();
    notifyListeners();
    _scheduleSync();
    return next;
  }

  // ---------------------------------------------------------------------------
  // 自动验证
  // ---------------------------------------------------------------------------

  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    TodoStore.instance.addListener(_onTodoChanged);
    PomodoroState.instance.addListener(_onPomodoroChanged);
    LedgerStore.instance.addListener(_onLedgerChanged);
    NookController.instance.addListener(_onNookChanged);
  }

  bool _eligible(String type) {
    final entry = _days[todayKey];
    if (entry == null) return false;
    if (entry.actionDone) return false;
    if (entry.actionType != type) return false;
    if (entry.actionStartedAt == null) return false;
    return true;
  }

  int _threshold(String type, String kind) {
    final plan = checkinPlanForKind(kind);
    if (plan.thresholdMinutes > 0) return plan.thresholdMinutes;
    return type == CheckinActionType.focus ? 5 : 10;
  }

  void _onTodoChanged() {
    if (!_eligible(CheckinActionType.task)) return;
    final entry = _days[todayKey]!;
    final start = DateTime.fromMillisecondsSinceEpoch(
      entry.actionStartedAt!,
    );
    final candidate = TodoStore.instance.allTasks.where((t) {
      if (!t.done || t.doneAt == null) return false;
      if (t.doneAt!.isBefore(start)) return false;
      if (entry.linkedId != null) return t.id == entry.linkedId;
      return true;
    }).toList()..sort((a, b) => a.doneAt!.compareTo(b.doneAt!));
    if (candidate.isEmpty) return;
    unawaited(completeAction(linkedId: candidate.first.id));
  }

  void _onPomodoroChanged() {
    if (!_eligible(CheckinActionType.focus)) return;
    final entry = _days[todayKey]!;
    final start = DateTime.fromMillisecondsSinceEpoch(
      entry.actionStartedAt!,
    );
    final need = _threshold(CheckinActionType.focus, entry.kind);
    final hit = PomodoroState.instance.sessions.any(
      (s) => !s.at.isBefore(start) && s.minutes >= need,
    );
    if (hit) unawaited(completeAction());
  }

  void _onLedgerChanged() {
    if (!_eligible(CheckinActionType.ledger)) return;
    final entry = _days[todayKey]!;
    final start = DateTime.fromMillisecondsSinceEpoch(
      entry.actionStartedAt!,
    );
    final hit = LedgerStore.instance.entries.where((e) {
      if (e.createdAt.isBefore(start)) return false;
      if (entry.linkedId != null) return e.id == entry.linkedId;
      return true;
    }).toList();
    if (hit.isEmpty) return;
    unawaited(completeAction(linkedId: hit.last.id));
  }

  void _onNookChanged() {
    final playing = NookController.instance.playing;
    if (playing == _listenWasPlaying) return;
    if (playing) {
      _listenStartedAt = DateTime.now();
      _ensureListenTicker();
    } else {
      _accrueListen();
      _listenStartedAt = null;
      _listenTimer?.cancel();
      _listenTimer = null;
    }
    _listenWasPlaying = playing;
  }

  void _ensureListenTicker() {
    _listenTimer?.cancel();
    _listenTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _tickListen();
    });
  }

  void _tickListen() {
    if (!_eligible(CheckinActionType.listen)) return;
    _accrueListen();
    _persistListenSeconds();
    final entry = _days[todayKey]!;
    final need = _threshold(CheckinActionType.listen, entry.kind) * 60;
    if (_listenSeconds >= need) {
      unawaited(completeAction());
      _listenTimer?.cancel();
      _listenTimer = null;
    }
  }

  void _accrueListen() {
    final from = _listenStartedAt;
    if (from == null) return;
    final now = DateTime.now();
    final entry = _days[todayKey];
    final actionStart = entry?.actionStartedAt;
    var cursor = from;
    if (actionStart != null) {
      final start = DateTime.fromMillisecondsSinceEpoch(actionStart);
      if (cursor.isBefore(start)) cursor = start;
      if (now.isAfter(cursor)) {
        _listenSeconds += now.difference(cursor).inSeconds;
      }
    }
    // 行动开始前的播放不计入；这里只推进游标。
    _listenStartedAt = now;
  }

  void _persistListenSeconds() {
    try {
      Prefs.setInt(
        'citro_checkin_listen_v1_${_accountKey}_$todayKey',
        _listenSeconds,
      );
    } catch (_) {}
  }

  /// 笔记保存后由笔记弹层调用。
  void noteSaved([String? id]) {
    if (!_eligible(CheckinActionType.note)) return;
    unawaited(completeAction(linkedId: id));
  }

  /// 评论发出后由社区页调用。
  void commentCreated([String? id]) {
    if (!_eligible(CheckinActionType.community)) return;
    unawaited(completeAction(linkedId: id));
  }

  // ---------------------------------------------------------------------------
  // 同步
  // ---------------------------------------------------------------------------

  void _scheduleSync() {
    if (isGuest) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(flushNow());
    });
  }

  Future<void> syncFromServer() async {
    if (isGuest) return;
    try {
      final res = await CheckinSync.bootstrap(days: 42);
      if (res.isEmpty) {
        if (_pendingDates.isNotEmpty) {
          syncFailed = true;
          syncNote = '已存本机，联网后再同步';
          notifyListeners();
        }
        return;
      }
      final date = '${res['date'] ?? ''}';
      if (isCheckinDate(date)) _serverDate = date;
      final rawDays = res['days'];
      if (rawDays is List) {
        for (final raw in rawDays) {
          if (raw is! Map) continue;
          final remote = CheckinDayEntry.fromJson(raw);
          if (remote != null) _mergeRemote(remote);
        }
      }
      _pendingDates = CheckinSync.load(_accountKey)
          .map((e) => e.date)
          .toSet();
      syncFailed = false;
      syncNote = null;
      await _persist();
      notifyListeners();
      if (_pendingDates.isNotEmpty) await flushNow();
    } catch (_) {
      if (_pendingDates.isNotEmpty) {
        syncFailed = true;
        notifyListeners();
      }
    }
  }

  /// 立即推送离线队列。页面在打开长卷 / 回到前台时也可以主动调。
  Future<void> flushNow() async {
    if (isGuest) return;
    if (_busySync) {
      _syncQueued = true;
      return;
    }
    _busySync = true;
    syncing = true;
    syncFailed = false;
    notifyListeners();
    late CheckinSyncRun run;
    try {
      run = await CheckinSync.flush(
        account: _accountKey,
        entryOf: (date) => _days[date],
        onRemote: _mergeRemote,
        onConflict: (latest) {
          conflictDate = latest.date;
          final local = _days[latest.date];
          if (local != null) {
            // 保留本机文字 / 完成状态，只把 rev 对齐，下一次保存再重试。
            _days[latest.date] = local.copyWith(rev: latest.rev);
          }
        },
      );
    } catch (_) {
      run = const CheckinSyncRun(
        message: '已存本机，联网后再同步',
        remaining: 1,
      );
    }
    _pendingDates = CheckinSync.load(_accountKey)
        .map((e) => e.date)
        .toSet();
    await _persist();
    _busySync = false;
    syncing = false;
    syncFailed = run.remaining > 0 && !run.conflict;
    syncNote = run.message ?? (run.conflict ? '有一天的回签在另一台设备上改过' : null);
    notifyListeners();
    if (run.remaining > 0 && !run.conflict && _retryCount < 3) {
      _retryCount++;
      _retryTimer?.cancel();
      final wait = Duration(seconds: math.min(60, 5 * _retryCount));
      _retryTimer = Timer(wait, () => unawaited(flushNow()));
    } else if (run.remaining == 0) {
      _retryCount = 0;
    }
    if (_syncQueued) {
      _syncQueued = false;
      unawaited(flushNow());
    }
  }

  /// 把服务端记录合并回来：服务端管事实，本机草稿管尚未同步的文字。
  void _mergeRemote(CheckinDayEntry remote) {
    final local = _days[remote.date];
    if (local == null) {
      _days[remote.date] = remote;
      return;
    }
    var merged = remote.copyWith(actionStartedAt: local.actionStartedAt);
    if (local.reflectionUpdatedAt != null &&
        (remote.reflectionUpdatedAt == null ||
            local.reflectionUpdatedAt! > remote.reflectionUpdatedAt!)) {
      merged = merged.copyWith(
        reflectionMood: local.reflectionMood,
        reflectionText: local.reflectionText,
        reflectionUpdatedAt: local.reflectionUpdatedAt,
      );
    }
    if (local.actionDone && !remote.actionDone) {
      merged = merged.copyWith(
        actionStatus: CheckinActionStatus.done,
        completedAt: local.completedAt,
        completedActionText: local.completedActionText,
        linkedId: local.linkedId,
      );
    }
    _days[remote.date] = merged;
  }

  int? takeJustCompletedVolume() {
    final value = _justCompletedVolume;
    _justCompletedVolume = null;
    return value;
  }

  // ---------------------------------------------------------------------------
  // 游客记录带入账号
  // ---------------------------------------------------------------------------

  Future<bool> get guestMergeAvailable async {
    if (isGuest || !_ready) return false;
    if (Prefs.getString('citro_checkin_guest_merge_v1_$_accountKey') != null) {
      return false;
    }
    final guest = _readDaysFor('guest');
    final today = todayKey;
    return guest.values.any(
      (e) => !_days.containsKey(e.date) && e.date.compareTo(today) <= 0,
    );
  }

  Future<int> mergeGuestRecords() async {
    if (isGuest) return 0;
    final guest = _readDaysFor('guest');
    final today = todayKey;
    var added = 0;
    for (final entry in guest.values) {
      if (entry.date.compareTo(today) > 0) continue;
      if (_days.containsKey(entry.date)) continue;
      // 游客历史只做本机带入；服务端不允许给过去日期补卡。
      _days[entry.date] = entry.copyWith(pendingSync: false);
      added++;
    }
    await Prefs.setString('citro_checkin_guest_merge_v1_$_accountKey', '1');
    await _persist();
    notifyListeners();
    return added;
  }

  Future<void> dismissGuestMerge() async {
    if (isGuest) return;
    await Prefs.setString('citro_checkin_guest_merge_v1_$_accountKey', '0');
  }

  Map<String, CheckinDayEntry> _readDaysFor(String account) {
    final raw = Prefs.getString('citro_checkin_days_v1_$account');
    final out = <String, CheckinDayEntry>{};
    if (raw == null || raw.isEmpty) return out;
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is Map ? decoded['days'] : decoded;
      if (list is List) {
        for (final item in list) {
          if (item is! Map) continue;
          final entry = CheckinDayEntry.fromJson(item);
          if (entry != null) out[entry.date] = entry;
        }
      }
    } catch (_) {}
    return out;
  }

  /// 注销 / 删除账号后清掉本机当天之后的所有打卡副本。
  Future<void> clearLocalForDeletedAccount() async {
    _days = {};
    _pendingDates = {};
    await CheckinSync.save(_accountKey, const []);
    await Prefs.setString(_daysKey, null);
    await Prefs.setString('citro_checkin_guest_merge_v1_$_accountKey', null);
    await Prefs.setString(
      'citro_checkin_listen_v1_${_accountKey}_$todayKey',
      null,
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 时间边界
  // ---------------------------------------------------------------------------

  void _scheduleDayBoundary() {
    _dayTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _dayTimer = Timer(next.difference(now), () async {
      _listenSeconds = 0;
      _listenStartedAt = null;
      // 先回到本机日期，避免离线跨天时一直停在昨天的服务端日期上。
      _serverDate = null;
      if (!isGuest) {
        try {
          final res = await Api.checkinStats(null);
          final date = '${res['date'] ?? ''}';
          if (isCheckinDate(date)) _serverDate = date;
        } catch (_) {}
      }
      notifyListeners();
      _scheduleDayBoundary();
    });
  }

  @visibleForTesting
  void resetForTest() {
    _ready = false;
    _accountName = null;
    _accountKey = 'guest';
    _serverDate = null;
    _days = {};
    _pendingDates = {};
    syncing = false;
    syncFailed = false;
    syncNote = null;
    conflictDate = null;
    _justCompletedVolume = null;
    _busySync = false;
    _syncQueued = false;
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    _dayTimer?.cancel();
    _listenTimer?.cancel();
    _listenSeconds = 0;
    _listenStartedAt = null;
    _listenWasPlaying = false;
  }
}
