import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'chime.dart';
import 'haptics.dart';
import 'notifications.dart';
import 'platform.dart' as platform;
import 'prefs.dart';

class PomodoroState extends ChangeNotifier {
  static final PomodoroState instance = PomodoroState._();
  PomodoroState._();

  static const int focusSeconds = 25 * 60;
  static const int shortSeconds = 5 * 60;
  static const int _ongoingId = 7800;
  static const int _finishId = 7801;

  static const _longKey = 'citro_pomo_long';
  static String get _todayKey {
    final d = DateTime.now();
    return 'citro_pomo_${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// 到点事件：值为下一轮模式（focus / short / long），由全局监听器弹窗。
  final ValueNotifier<String?> finished = ValueNotifier<String?>(null);

  String mode = 'focus';
  int total = focusSeconds;
  double remain = focusSeconds.toDouble();
  bool running = false;
  bool done = false;
  DateTime? endAt;
  Timer? _ticker;
  int longMinutes = 15;
  int todayCount = 0;
  String? notice;
  String? pendingNextMode;
  bool nookUi = false;
  bool _inited = false;

  bool get active => running || (remain < total && remain > 0);
  int get longSeconds => longMinutes * 60;
  double get progress => total == 0 ? 0 : (1 - remain / total).clamp(0.0, 1.0);

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

  String get _ongoingLabel => switch (mode) {
    'short' => '☕ 短休中',
    'long' => '🌿 长休中',
    _ => '🍅 专注中',
  };

  String get _finishTitle => mode == 'focus' ? '🍅 专注完成' : '休息结束';

  String get _finishBody =>
      mode == 'focus' ? '起来走走，喝口水休息一下吧。' : '把心收回来，继续下一轮专注。';

  void ensureInit() {
    if (_inited) return;
    _inited = true;
    init();
  }

  void init() {
    longMinutes = Prefs.getInt(_longKey, 15).clamp(15, 30);
    todayCount = Prefs.getInt(_todayKey, 0);
    _inited = true;
    notifyListeners();
  }

  void switchMode(String next) {
    _ticker?.cancel();
    running = false;
    done = false;
    notice = null;
    pendingNextMode = null;
    mode = next;
    total = next == 'focus'
        ? focusSeconds
        : (next == 'short' ? shortSeconds : longSeconds);
    remain = total.toDouble();
    _clearNotifications();
    notifyListeners();
  }

  void setLongMinutes(int minutes) {
    final wasFresh = remain == total;
    longMinutes = minutes.clamp(15, 30);
    unawaited(Prefs.setInt(_longKey, longMinutes));
    if (mode == 'long' && !running) {
      total = longSeconds;
      if (wasFresh || remain == 0) remain = total.toDouble();
    }
    notifyListeners();
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
    if (!platform.isTest) unawaited(_armNotifications(end));
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
      todayCount += 1;
      await Prefs.setInt(_todayKey, todayCount);
      nextMode = todayCount % 4 == 0 ? 'long' : 'short';
      notice = '专注完成，休息一下吧 🍅';
    } else {
      nextMode = 'focus';
      notice = '休息结束，继续专注';
    }
    pendingNextMode = nextMode;
    _clearOngoing();
    unawaited(Chime.done());
    unawaited(Haptics.done());
    notifyListeners();
    _publishFinished(nextMode);
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
    if (startNow) start();
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
