import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _timerChannel = MethodChannel(
    'com.chimu.crew/timer',
  );
  static bool ready = false;
  static bool enabled = true;
  static Future<void>? _initFuture;

  static Future<void> ensureInit() {
    if (ready) return Future.value();
    return _initFuture ??= _init();
  }

  static Future<void> _init() async {
    try {
      tz_data.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
      } catch (_) {}
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_chimu'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings);
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      try {
        await android?.requestNotificationsPermission();
      } catch (_) {}
      try {
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            'citro_reminders',
            'Citro 提醒',
            description: '烹饪计时与社区消息',
            importance: Importance.high,
          ),
        );
      } catch (_) {}
      ready = true;
    } catch (_) {
      ready = false;
      _initFuture = null;
    }
  }

  static Future<bool> areEnabled() async {
    await ensureInit();
    try {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        final options = await ios.checkPermissions();
        return options?.isEnabled ?? false;
      }
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    await ensureInit();
    try {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> show(String title, String body) async {
    if (!enabled) return;
    await ensureInit();
    if (!ready) return;
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'citro_reminders',
            'Citro 提醒',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_chimu',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            presentBanner: true,
            presentList: true,
          ),
        ),
      );
    } catch (_) {}
  }

  static Future<void> showTimerOngoing(
    int id,
    String label,
    DateTime end,
  ) async {
    if (!enabled) return;
    await ensureInit();
    if (!ready) return;
    try {
      final native = await _timerChannel.invokeMethod<bool>('show', {
        'id': id,
        'label': label,
        'end': end.millisecondsSinceEpoch,
      });
      if (native == true) return;
    } catch (_) {}
    try {
      final endText =
          '${end.hour.toString().padLeft(2, '0')}:'
          '${end.minute.toString().padLeft(2, '0')}';
      await _plugin.show(
        id,
        '⏳ 计时中',
        '$label · $endText 结束',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'citro_reminders',
            'Citro 提醒',
            channelDescription: '烹饪计时与社区消息',
            importance: Importance.high,
            priority: Priority.high,
            silent: true,
            playSound: false,
            enableVibration: false,
            showWhen: true,
            when: end.millisecondsSinceEpoch,
            usesChronometer: true,
            chronometerCountDown: true,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            icon: 'ic_stat_chimu',
          ),
          // iOS 无法在通知里放实时倒计时；显示固定文案，到点由 schedule 提醒。
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
            presentBanner: true,
            presentList: true,
            threadIdentifier: 'citro_timer',
          ),
        ),
      );
    } catch (_) {}
  }

  static Future<void> schedule(
    int id,
    String title,
    String body,
    DateTime when,
  ) async {
    if (!enabled) return;
    await ensureInit();
    if (!ready) return;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final exact = await android?.canScheduleExactNotifications() ?? false;
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'citro_reminders',
            'Citro 提醒',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'ic_stat_chimu',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            presentBanner: true,
            presentList: true,
          ),
        ),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  static Future<void> cancel(int id) async {
    try {
      await _timerChannel.invokeMethod('cancel', {'id': id});
    } catch (_) {}
    if (!ready) return;
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      await _timerChannel.invokeMethod('cancelAll');
    } catch (_) {}
    if (!ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
