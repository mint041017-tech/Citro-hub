import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'chime.dart';
import 'haptics.dart';
import 'notifications.dart';
import 'platform.dart' as platform;
import 'prefs.dart';

/// 一次已完成的专注记录。
class PomoSession {
  const PomoSession(this.at, this.minutes);

  final DateTime at;
  final int minutes;

  String encode() => '${at.millisecondsSinceEpoch}:$minutes';

  static PomoSession? decode(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final t = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (t == null || m == null || m <= 0) return null;
    return PomoSession(DateTime.fromMillisecondsSinceEpoch(t), m);
  }
}

class PomodoroState extends ChangeNotifier {
  static final PomodoroState instance = PomodoroState._();
  PomodoroState._();

  static const int defaultFocusMinutes = 25;
  static const int defaultShortMinutes = 5;
  static const int defaultLongMinutes = 15;
  static const int _ongoingId = 7800;
  static const int _finishId = 7801;

  static const _focusKey = 'citro_pomo_focus';
  static const _shortKey = 'citro_pomo_short';
  static const _longKey = 'citro_pomo_long';
  static const _everyKey = 'citro_pomo_every';
  static const _autoKey = 'citro_pomo_auto';
  static const _playKey = 'citro_pomo_play_v2';
  static const _pauseKey = 'citro_pomo_pause_v2';
  static const _chimeKey = 'citro_pomo_chime';
  static const _chimeVolumeKey = 'citro_pomo_chime_volume';
  static const _chimeKindKey = 'citro_pomo_chime_kind';
  static const _notifyKey = 'citro_pomo_notify';
  static const _sessionsKey = 'citro_pomo_sessions';

  /// 到点事件：值为下一轮模式（focus / short / long），由全局监听器弹窗。
  final ValueNotifier<String?> finished = ValueNotifier<String?>(null);

  String mode = 'focus';
  int total = defaultFocusMinutes * 60;
  double remain = (defaultFocusMinutes * 60).toDouble();
  bool running = false;
  bool done = false;
  DateTime? endAt;
  Timer? _ticker;
  String? notice;
  String? pendingNextMode;
  bool nookUi = false;
  bool _inited = false;

  // 设置
  int focusMinutes = defaultFocusMinutes;
  int shortMinutes = defaultShortMinutes;
  int longMinutes = defaultLongMinutes;
  int longEvery = 4;
  bool autoStart = false;
  bool playWithFocus = false;
  bool pauseOnBreak = false;
  bool chime = true;
  bool chimeKindWood = false;
  int chimeVolume = 55;
  bool notify = true;
  String notificationPermission = 'default';

  List<PomoSession> sessions = [];

  /// 由听隅注入：开始/暂停背景混音。
  Future<void> Function(bool play)? audioHook;

  bool get active => running || (remain < total && remain > 0);
  int get longSeconds => longMinutes * 60;
  double get progress => total == 0 ? 0 : (1 - remain / total).clamp(0.0, 1.0);

  int _secondsFor(String next) => switch (next) {
    'short' => shortMinutes * 60,
    'long' => longSeconds,
    _ => focusMinutes * 60,
  };

  String get modeLabel => switch (mode) {
    'short' => '短休息',
    'long' => '长休息',
    _ => '专注时间',
  };

  String get startLabel => switch (mode) {
    'focus' => '开始专注',
    _ => '开始休息',
  };

  String get timeText {
    final sec = math.max(0, remain.ceil());
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  List<PomoSession> get _todaySessions {
    final now = DateTime.now();
    return sessions
        .where(
          (s) =>
              s.at.year == now.year &&
              s.at.month == now.month &&
              s.at.day == now.day,
        )
        .toList();
  }

  int get todayCount => _todaySessions.length;
  int get todayMinutes =>
      _todaySessions.fold<int>(0, (sum, s) => sum + s.minutes);

  List<int> get weekMinutes {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List<int>.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      return sessions
          .where(
            (s) =>
                s.at.year == day.year &&
                s.at.month == day.month &&
                s.at.day == day.day,
          )
          .fold<int>(0, (sum, s) => sum + s.minutes);
    });
  }

  int get streakDays {
    if (sessions.isEmpty) return 0;
    final days = sessions
        .map((s) => DateTime(s.at.year, s.at.month, s.at.day))
        .toSet();
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    if (!days.contains(day)) {
      day = day.subtract(const Duration(days: 1));
      if (!days.contains(day)) return 0;
    }
    var count = 0;
    while (days.contains(day)) {
      count += 1;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  String get _ongoingLabel => switch (mode) {
    'short' => '短休中',
    'long' => '长休中',
    _ => '专注中',
  };

  String get _finishTitle => mode == 'focus' ? '专注完成' : '休息结束';

  String get _finishBody =>
      mode == 'focus' ? '起来走走，喝口水休息一下吧。' : '把心收回来，继续下一轮专注。';

  void ensureInit() {
    if (_inited) return;
    _inited = true;
    init();
  }

  void init() {
    focusMinutes = Prefs.getInt(_focusKey, defaultFocusMinutes).clamp(5, 180);
    shortMinutes = Prefs.getInt(_shortKey, defaultShortMinutes).clamp(1, 60);
    longMinutes = Prefs.getInt(_longKey, defaultLongMinutes).clamp(5, 120);
    longEvery = Prefs.getInt(_everyKey, 4).clamp(2, 8);
    autoStart = Prefs.getBool(_autoKey, false);
    playWithFocus = Prefs.getBool(_playKey, false);
    pauseOnBreak = Prefs.getBool(_pauseKey, false);
    chime = Prefs.getBool(_chimeKey, true);
    chimeVolume = Prefs.getInt(_chimeVolumeKey, 55).clamp(0, 100);
    chimeKindWood = Prefs.getString(_chimeKindKey) == 'wood';
    notify = Prefs.getBool(_notifyKey, true);
    sessions = Prefs.getStringList(_sessionsKey)
        .map(PomoSession.decode)
        .whereType<PomoSession>()
        .toList();
    if (mode == 'focus' && !running) {
      total = focusMinutes * 60;
      if (remain >= total || remain == 0) remain = total.toDouble();
    }
    if (mode == 'long' && !running) {
      total = longMinutes * 60;
      if (remain >= total || remain == 0) remain = total.toDouble();
    }
    if (mode == 'short' && !running) {
      total = shortMinutes * 60;
      if (remain >= total || remain == 0) remain = total.toDouble();
    }
    _inited = true;
    notifyListeners();
    unawaited(_refreshPermission());
  }

  Future<void> _refreshPermission() async {
    try {
      final enabled = await Notifications.areEnabled();
      notificationPermission = enabled ? 'granted' : 'default';
      if (enabled) notifyListeners();
    } catch (_) {}
  }

  void switchMode(String next) {
    _ticker?.cancel();
    running = false;
    done = false;
    notice = null;
    pendingNextMode = null;
    mode = next;
    total = _secondsFor(next);
    remain = total.toDouble();
    _clearNotifications();
    notifyListeners();
  }

  void setLongMinutes(int minutes) {
    final wasFresh = remain == total;
    longMinutes = minutes.clamp(5, 120);
    unawaited(Prefs.setInt(_longKey, longMinutes));
    if (mode == 'long' && !running) {
      total = longSeconds;
      if (wasFresh || remain == 0) remain = total.toDouble();
    }
    notifyListeners();
  }

  void setDuration(String next, int minutes) {
    switch (next) {
      case 'short':
        shortMinutes = minutes.clamp(1, 60);
        unawaited(Prefs.setInt(_shortKey, shortMinutes));
      case 'long':
        longMinutes = minutes.clamp(5, 120);
        unawaited(Prefs.setInt(_longKey, longMinutes));
      default:
        focusMinutes = minutes.clamp(5, 180);
        unawaited(Prefs.setInt(_focusKey, focusMinutes));
    }
    if (mode == next && !running) {
      total = _secondsFor(next);
      remain = total.toDouble();
      done = false;
    }
    notifyListeners();
  }

  void setLongEvery(int value) {
    longEvery = value.clamp(2, 8);
    unawaited(Prefs.setInt(_everyKey, longEvery));
    notifyListeners();
  }

  void setAutoStart(bool value) {
    autoStart = value;
    unawaited(Prefs.setBool(_autoKey, value));
    notifyListeners();
  }

  void setPlayWithFocus(bool value) {
    playWithFocus = value;
    unawaited(Prefs.setBool(_playKey, value));
    notifyListeners();
  }

  void setPauseOnBreak(bool value) {
    pauseOnBreak = value;
    unawaited(Prefs.setBool(_pauseKey, value));
    notifyListeners();
  }

  void setChime(bool value) {
    chime = value;
    unawaited(Prefs.setBool(_chimeKey, value));
    notifyListeners();
  }

  void setChimeKind(String kind) {
    chimeKindWood = kind == 'wood';
    unawaited(Prefs.setString(_chimeKindKey, chimeKindWood ? 'wood' : 'bell'));
    notifyListeners();
  }

  void setChimeVolume(int value) {
    chimeVolume = value.clamp(0, 100);
    unawaited(Prefs.setInt(_chimeVolumeKey, chimeVolume));
    notifyListeners();
  }

  void setNotify(bool value) {
    notify = value;
    unawaited(Prefs.setBool(_notifyKey, value));
    notifyListeners();
  }

  Future<void> chimePreview() async {
    if (!chime) return;
    await Chime.done(wood: chimeKindWood, volume: chimeVolume);
  }

  void toggle() => running ? pause() : start();

  void start() {
    if (remain <= 0) {
      remain = total.toDouble();
      done = false;
    }
    final end = DateTime.now().add(
      Duration(milliseconds: (remain * 1000).round()),
    );
    endAt = end;
    running = true;
    done = false;
    pendingNextMode = null;
    notice = null;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
    notifyListeners();
    _syncAudio(playing: mode == 'focus' ? playWithFocus : !pauseOnBreak);
    if (!platform.isTest && notify) unawaited(_armNotifications(end));
  }

  void pause() {
    if (!running) return;
    _syncRemain();
    running = false;
    _ticker?.cancel();
    _clearNotifications();
    notifyListeners();
  }

  void reset() {
    _ticker?.cancel();
    running = false;
    done = false;
    pendingNextMode = null;
    notice = null;
    remain = total.toDouble();
    _clearNotifications();
    notifyListeners();
  }

  void tick() {
    if (!running) return;
    _syncRemain();
    if (remain <= 0) {
      _complete();
    } else {
      notifyListeners();
    }
  }

  void _syncRemain() {
    final end = endAt;
    if (end == null) return;
    remain = math.max(0, end.difference(DateTime.now()).inMilliseconds / 1000);
  }

  Future<void> _complete() async {
    _ticker?.cancel();
    running = false;
    done = true;
    remain = 0;
    final completedMode = mode;
    final String nextMode;
    if (completedMode == 'focus') {
      sessions.add(PomoSession(DateTime.now(), focusMinutes));
      if (sessions.length > 400) {
        sessions = sessions.sublist(sessions.length - 400);
      }
      await _saveSessions();
      final cycle = sessions.where((s) => _isToday(s.at)).length;
      nextMode = cycle % longEvery == 0 ? 'long' : 'short';
      notice = '专注完成，休息一下吧';
      if (pauseOnBreak) _syncAudio(playing: false);
    } else {
      nextMode = 'focus';
      notice = '休息结束，继续专注';
    }
    pendingNextMode = nextMode;
    _clearOngoing();
    if (chime) {
      unawaited(Chime.done(wood: chimeKindWood, volume: chimeVolume));
    }
    unawaited(Haptics.done());
    notifyListeners();
    _publishFinished(nextMode);
  }

  bool _isToday(DateTime at) {
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day;
  }

  Future<void> _saveSessions() async {
    await Prefs.setStringList(
      _sessionsKey,
      sessions.map((s) => s.encode()).toList(),
    );
  }

  Future<void> clearHistory() async {
    sessions = [];
    await _saveSessions();
    notifyListeners();
  }

  void _syncAudio({required bool playing}) {
    final hook = audioHook;
    if (hook == null) return;
    unawaited(hook(playing));
  }

  void _publishFinished(String nextMode) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        finished.value = nextMode;
      });
      SchedulerBinding.instance.scheduleFrame();
    } else {
      finished.value = nextMode;
    }
  }

  /// 对话框按钮：切到下一轮；startNow 时立即开始。
  void beginNext({bool startNow = false}) {
    final next = pendingNextMode ?? (mode == 'focus' ? 'short' : 'focus');
    pendingNextMode = null;
    switchMode(next);
    if (startNow || autoStart) start();
  }

  /// 对话框被点外部/返回关闭：切到下一轮但保持未开始。
  void settleFinished() {
    if (!done) return;
    beginNext();
  }

  Future<void> _armNotifications(DateTime end) async {
    try {
      await Notifications.requestPermission();
      if (!running || endAt != end) return;
      await Notifications.showTimerOngoing(_ongoingId, _ongoingLabel, end);
      await Notifications.schedule(
        _finishId,
        _finishTitle,
        _finishBody,
        end,
        channelId: 'citro_pomodoro',
        channelName: '番茄钟',
      );
    } catch (_) {}
  }

  void _clearOngoing() {
    if (platform.isTest) return;
    unawaited(Notifications.cancel(_ongoingId));
  }

  void _clearNotifications() {
    if (platform.isTest) return;
    unawaited(Notifications.cancel(_ongoingId));
    unawaited(Notifications.cancel(_finishId));
  }
}
