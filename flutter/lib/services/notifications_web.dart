import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as html;

class Notifications {
  static bool ready = false;
  static bool enabled = true;
  static final Map<int, Timer> _timers = {};
  static final Map<int, html.Notification> _shown = {};

  static Future<void> ensureInit() async {
    try {
      ready = html.Notification.permission.isNotEmpty;
    } catch (_) {
      ready = false;
    }
  }

  /// 浏览器权限不反向改写 App 通知偏好；无权限时各发送入口安静跳过。
  static Future<bool> areEnabled() async {
    await ensureInit();
    return ready;
  }

  /// 应由用户点击等明确手势调用；浏览器拒绝时只返回 false。
  static Future<bool> requestPermission() async {
    await ensureInit();
    if (!ready) return false;
    try {
      if (html.Notification.permission == 'granted') return true;
      if (html.Notification.permission == 'denied') return false;
      final permission = await html.Notification.requestPermission().toDart;
      return permission.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  static bool get _granted {
    if (!ready) return false;
    try {
      return html.Notification.permission == 'granted';
    } catch (_) {
      return false;
    }
  }

  static void _display(int id, String title, String body, {String? tag}) {
    if (!enabled || !_granted) return;
    try {
      _shown[id]?.close();
      _shown[id] = html.Notification(
        title,
        html.NotificationOptions(body: body, tag: tag ?? ''),
      );
    } catch (_) {}
  }

  static Future<void> show(String title, String body) async {
    if (!enabled) return;
    await ensureInit();
    _display(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body);
  }

  static Future<void> showTimerOngoing(
    int id,
    String label,
    DateTime end,
  ) async {
    if (!enabled) return;
    await ensureInit();
    final endText =
        '${end.hour.toString().padLeft(2, '0')}:'
        '${end.minute.toString().padLeft(2, '0')}';
    _display(id, '⏳ 计时中', '$label · $endText 结束', tag: 'citro_timer_$id');
  }

  static Future<void> schedule(
    int id,
    String title,
    String body,
    DateTime when, {
    String channelId = 'citro_reminders',
    String channelName = 'Citro 提醒',
  }) async {
    if (!enabled) return;
    await ensureInit();
    if (!ready) return;
    // 计时通常由按钮启动，可在这里沿用该用户手势申请权限。
    if (html.Notification.permission == 'default') {
      await requestPermission();
    }
    if (!_granted) return;
    _timers.remove(id)?.cancel();
    final delay = when.difference(DateTime.now());
    _timers[id] = Timer(delay.isNegative ? Duration.zero : delay, () {
      _timers.remove(id);
      _display(id, title, body, tag: 'citro_reminder_$id');
    });
  }

  static Future<void> cancel(int id) async {
    _timers.remove(id)?.cancel();
    try {
      _shown.remove(id)?.close();
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final notification in _shown.values) {
      try {
        notification.close();
      } catch (_) {}
    }
    _shown.clear();
  }
}
