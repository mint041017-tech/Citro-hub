import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'notifications.dart';

class CookTick {
  final String label;
  final DateTime start;
  final DateTime end;
  final int notificationId;
  final int totalSeconds;

  const CookTick(
    this.label,
    this.start,
    this.end,
    this.notificationId,
    this.totalSeconds,
  );

  int get remainingSeconds =>
      math.max(0, end.difference(DateTime.now()).inSeconds);

  String get timeText {
    final s = remainingSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

/// 全站计时器：离开食谱页后仍继续，由全局胶囊展示和操作。
class CookTimer extends ChangeNotifier {
  static final CookTimer instance = CookTimer._();
  CookTimer._();

  CookTick? tick;
  Timer? _ticker;
  final ValueNotifier<String?> finished = ValueNotifier<String?>(null);

  void start(String label, int minutes) {
    if (minutes <= 0) return;
    finished.value = null;
    final now = DateTime.now();
    _arm(label, now.add(Duration(minutes: minutes)), minutes * 60);
  }

  void addMinutes(int minutes) {
    final current = tick;
    if (current == null) return;
    final now = DateTime.now();
    final remaining = math.max(
      1,
      current.end.difference(now).inSeconds + minutes * 60,
    );
    _arm(current.label, now.add(Duration(seconds: remaining)), remaining);
  }

  void cancel() {
    _ticker?.cancel();
    final current = tick;
    tick = null;
    if (current != null) Notifications.cancel(current.notificationId);
    notifyListeners();
  }

  void _arm(String label, DateTime end, int totalSeconds) {
    _ticker?.cancel();
    final previous = tick;
    if (previous != null) Notifications.cancel(previous.notificationId);
    final id = label.hashCode & 0x7fffffff;
    tick = CookTick(label, DateTime.now(), end, id, totalSeconds);
    // 通知提前 2 秒排程：前台由应用内收尾并取消，后台由系统推送兜底。
    unawaited(
      Notifications.schedule(
        id,
        '⏰ 时间到',
        label,
        end.add(const Duration(seconds: 2)),
      ),
    );
    unawaited(Notifications.showTimerOngoing(id, label, end));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    notifyListeners();
  }

  void _onTick() {
    final current = tick;
    if (current == null) {
      _ticker?.cancel();
      return;
    }
    if (DateTime.now().isAfter(current.end)) {
      _ticker?.cancel();
      tick = null;
      notifyListeners();
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final foreground =
          lifecycle == null || lifecycle == AppLifecycleState.resumed;
      if (foreground) {
        Notifications.cancel(current.notificationId);
        finished.value = current.label;
      }
    } else {
      notifyListeners();
    }
  }
}
