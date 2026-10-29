import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform.dart' as platform;

/// 震动反馈：优先走原生通道（Android 可给到完整波形，iOS 走系统触感），
/// 平台没有实现时退回 Flutter HapticFeedback。
class Haptics {
  Haptics._();

  static const MethodChannel _channel = MethodChannel('com.chimu.crew/timer');
  static bool _channelMissing = false;

  static Future<void> breath() =>
      _trigger('breath', HapticFeedback.lightImpact);

  static Future<void> done() => _trigger('done', HapticFeedback.vibrate);

  static Future<void> _trigger(
    String kind,
    Future<void> Function() fallback,
  ) async {
    if (platform.isTest) return;
    if (!kIsWeb && !_channelMissing) {
      try {
        final ok = await _channel.invokeMethod<bool>('vibrate', {'kind': kind});
        if (ok == true) return;
      } catch (_) {
        _channelMissing = true;
      }
    }
    try {
      await fallback();
    } catch (_) {}
  }
}
