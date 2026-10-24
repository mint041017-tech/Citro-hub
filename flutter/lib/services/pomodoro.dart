import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';

class PomodoroState extends ChangeNotifier {
  static final PomodoroState instance = PomodoroState._();
  PomodoroState._();

  static const int focusSeconds = 25 * 60;
  static const int shortSeconds = 5 * 60;

  static const _longKey = 'citro_pomo_long';
  static String get _todayKey {
    final d = DateTime.now();
    return 'citro_pomo_${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

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

  void init() {
    longMinutes = Prefs.getInt(_longKey, 15).clamp(15, 30);
    todayCount = Prefs.getInt(_todayKey, 0);
    notifyListeners();
  }

  void switchMode(String next) {
    _ticker?.cancel();
    running = false;
    done = false;
    notice = null;
    mode = next;
    total = next == 'focus'
        ? focusSeconds
        : (next == 'short' ? shortSeconds : longSeconds);
    remain = total.toDouble();
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
    endAt = DateTime.now().add(Duration(milliseconds: (remain * 1000).round()));
    running = true;
    done = false;
    notice = null;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
    notifyListeners();
  }

  void pause() {
    if (!running) return;
    _syncRemain();
    running = false;
    _ticker?.cancel();
    notifyListeners();
  }

  void reset() {
    _ticker?.cancel();
    running = false;
    done = false;
    notice = null;
    remain = total.toDouble();
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
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();

    final String nextMode;
    if (mode == 'focus') {
      todayCount += 1;
      await Prefs.setInt(_todayKey, todayCount);
      nextMode = todayCount % 4 == 0 ? 'long' : 'short';
      notice = '专注完成，休息一下吧 🍅';
    } else {
      nextMode = 'focus';
      notice = '休息结束，继续专注';
    }
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 1900), () {
      if (!done) return;
      done = false;
      notice = null;
      mode = nextMode;
      total = nextMode == 'focus'
          ? focusSeconds
          : (nextMode == 'short' ? shortSeconds : longSeconds);
      remain = total.toDouble();
      notifyListeners();
    });
  }
}
