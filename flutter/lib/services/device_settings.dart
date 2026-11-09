import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform.dart' as platform;

/// 厂商系统设置入口。
///
/// HyperOS / MIUI 的省电策略会把后台计时、定位和音频一并限制，
/// 这里只负责把用户送到系统的「应用信息」页，由用户自行选择「无限制」。
class DeviceSettings {
  DeviceSettings._();

  static const MethodChannel _channel = MethodChannel('com.chimu.crew/device');

  static bool get canOpenAppSettings => !kIsWeb && platform.isAndroid;

  static Future<bool> openAppSettings() async {
    if (!canOpenAppSettings) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}
