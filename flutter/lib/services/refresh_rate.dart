import 'dart:async';

import 'package:flutter/services.dart';

/// 游戏等持续动画场景请求系统使用屏幕最高刷新率。
///
/// Android 的 Choreographer 本来就会跟随屏幕 vsync，但部分 LTPO / 可变刷新率
/// 机型（Android 15+ 更常见）在没有显式 rate 请求时会停留在 60Hz。这里通过
/// 原生 `Window.setFrameRate` 申请最高模式；退出游戏后恢复系统默认，避免
/// 全程 120Hz 带来的耗电。
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
    try {
      await _channel.invokeMethod<void>('setHighRefresh', {'on': high});
    } catch (_) {
      // 桌面 / 测试环境没有原生通道，静默降级。
    }
  }
}
