import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform.dart' as platform;

/// 向系统请求屏幕最高刷新率（通常 120Hz）。
///
/// App 启动时常驻一个 lease，保证首页、滚动、弹层都能用上高刷；
/// 游戏页进入时再叠加一层，退出游戏只释放自己那一层，不会把全局请求关掉。
/// Android 侧同时写 preferredRefreshRate 与 preferredDisplayModeId，
/// 并在 onResume / onPostResume / onWindowFocusChanged 重新申请，
/// 因为 HyperOS / MIUI 会在切前台时把刷新率重置回 60Hz。
class RefreshRate {
  static const MethodChannel _channel = MethodChannel('com.chimu.crew/display');
  static int _leases = 0;

  static void acquire() {
    _leases++;
    if (_leases != 1) return;
    unawaited(_set(true));
  }

  static void release() {
    if (_leases == 0) return;
    _leases--;
    if (_leases != 0) return;
    unawaited(_set(false));
  }

  static Future<void> _set(bool high) async {
    // 只有 Android 原生端有对应通道；Windows / Web 直接跳过，避免无谓异常。
    if (kIsWeb || !platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setHighRefresh', {'on': high});
    } catch (_) {
      // 桌面 / 测试环境没有原生通道，静默降级。
    }
  }
}
