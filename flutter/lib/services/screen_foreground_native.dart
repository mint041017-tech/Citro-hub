import 'package:flutter/services.dart';

/// 共享期间的常驻前台服务。
///
/// Android 14+ 要求：开始 MediaProjection 之前必须先起一个
/// `mediaProjection` 类型的前台服务。调用失败不影响采集 —— 老系统上
/// 没有这条要求，新系统上失败会由 flutter_webrtc 给出更具体的报错。
Future<void> startScreenForeground() async {
  try {
    await const MethodChannel('com.chimu.crew/screen_capture').invokeMethod<bool>('start');
  } catch (_) {
    // 平台通道不存在（测试 / 非 Android）时静默跳过。
  }
}

Future<void> stopScreenForeground() async {
  try {
    await const MethodChannel('com.chimu.crew/screen_capture').invokeMethod<bool>('stop');
  } catch (_) {}
}
