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

  /// 测试 / 诊断：当前租约层数。
  static int get debugLeases => _leases;

  /// 测试专用：租约是静态计数，用例之间要归零。
  @visibleForTesting
  static void resetForTest() {
    _leases = 0;
  }


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
      if (high) unawaited(_verifyAfterDelay());
    } catch (_) {
      // 桌面 / 测试环境没有原生通道，静默降级。
    }
  }

  /// 申请后等系统应用再读回实际刷新率。HyperOS 等系统会静默拒绝或在
  /// 生命周期里重置，只看 setHighRefresh 的返回值无法发现问题；这里把
  /// 申请值 / 实际值 / 支持的模式都捞出来打到日志，用户反馈「没到 120」
  /// 时 adb logcat 一眼可查。
  static Future<void> _verifyAfterDelay() async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < const Duration(milliseconds: 900)) {
      await Future<void>.delayed(
        sw.elapsedMilliseconds < 300
            ? const Duration(milliseconds: 150)
            : const Duration(milliseconds: 300),
      );
      try {
        final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
          'currentRefreshRate',
        );
        if (raw == null) return;
        final m = raw.map((k, v) => MapEntry(k.toString(), v));
        final refresh = (m['refresh'] as num?)?.toDouble() ?? 0;
        final requested = (m['requested'] as num?)?.toDouble() ?? 0;
        final powerSave = m['powerSave'] == true;
        debugPrint('[refresh] actual=${refresh.toStringAsFixed(1)}Hz '
            'requested=${requested.toStringAsFixed(1)}Hz '
            'powerSave=$powerSave modes=${m['supported']}');
        // 已经稳定落在申请值附近，不用继续轮询。
        if (requested > 0 && (refresh - requested).abs() < 3) return;
      } catch (_) {
        return;
      }
    }
  }
}
