import 'dart:ui' show Size;

import 'package:flutter/services.dart';

import '../theme/breakpoints.dart';
import 'platform.dart' as platform;

/// iPhone 默认锁竖屏；只有 Duo 内屏允许横握。
/// iPad 继续使用 Info.plist 的全方向，不做运行时限制。
class CitroOrientation {
  static const MethodChannel _channel = MethodChannel('com.chimu.crew/device');
  static String? _idiom;
  static bool? _isDuo;
  static bool? _landscape;

  static bool get isDuo => _isDuo == true;

  static List<DeviceOrientation>? preferredFor({
    required bool isPad,
    required Size size,
  }) {
    if (isPad) return null;
    return CitroForm.duoInner(size)
        ? const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const [DeviceOrientation.portraitUp];
  }

  static Future<void> sync(Size size) async {
    if (!platform.isIOS) return;
    if (_idiom == null) {
      try {
        _idiom = await _channel.invokeMethod<String>('idiom');
      } catch (_) {
        return;
      }
    }
    if (_isDuo == null) {
      try {
        _isDuo = await _channel.invokeMethod<bool>('isDuo') ?? false;
      } catch (_) {
        _isDuo = false;
      }
    }
    // Duo 的两块屏都由系统管理方向：合盖时若锁竖屏，展开后的
    // alwaysAll 窗口会拒绝程序化改向，内屏就会横着停在竖屏。
    // 因此整机不调用 setPreferredOrientations，交给系统按形态旋转。
    if (_isDuo == true) return;
    if (CitroForm.duoInner(size)) {
      _landscape = true;
      return;
    }
    final preferred = preferredFor(isPad: _idiom == 'pad', size: size);
    if (preferred == null) return;
    final landscape = preferred.length > 1;
    if (_landscape == landscape) return;
    _landscape = landscape;
    try {
      await SystemChrome.setPreferredOrientations(preferred);
    } catch (_) {}
  }
}
