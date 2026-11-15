import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一起看弹幕悬浮窗桥。
///
/// 观众的文字聊天要以弹幕形式滚动在主持人的屏幕画面上（即使 Citro 应用
/// 被最小化）。App 内 Widget 在应用最小化后消失、也进不了屏幕采集流，所以
/// 弹幕画在系统悬浮窗里（Android TYPE_APPLICATION_OVERLAY / Windows
/// WS_EX_TOPMOST 独立窗口），MediaProjection 采整屏时自然把它采进视频流。
///
/// 平台差异：
///  - Android：悬浮窗是特殊权限，首次 [show] 前需 [canShow] 检查 +
///    [openPermissionSettings] 引导授权。
///  - Windows / 其他桌面：无权限门槛，canShow 恒 true。
///  - Web / iOS：iOS 系统不允许悬浮窗悬浮于其他应用之上，不支持；
///    Web 端走页面内弹幕层。
class DanmakuBridge {
  DanmakuBridge._();

  static const MethodChannel _channel = MethodChannel('com.chimu.crew/danmaku');

  /// 弹幕总开关（主持人在房间页切换）。controller 只在 enabled 时把
  /// 新聊天消息转发给悬浮窗；房间页负责 show/hide 生命周期。
  static bool enabled = true;

  /// 当前平台是否有原生弹幕悬浮窗实现（Android / Windows）。
  static bool get isSupported {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.windows:
        return true;
      default:
        return false;
    }
  }

  /// 悬浮窗当前是否可显示（Android 上即 SYSTEM_ALERT_WINDOW 已授权）。
  static Future<bool> canShow() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('canShow') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 显示悬浮窗。Android 无权限时返回 false（应先走设置引导）。
  /// [top] 为距屏幕（工作区）顶部的像素偏移，默认避开状态栏与挖孔。
  static Future<bool> show({int top = 72}) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('show', {'top': top}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 隐藏悬浮窗（停止共享 / 关弹幕开关时调用；未显示时无害）。
  static Future<void> hide() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } on PlatformException {
      // 忽略：悬浮窗可能已被系统回收。
    } on MissingPluginException {
      // 非 Android/Windows 平台没有实现。
    }
  }

  /// 推一条弹幕（未显示时静默丢弃）。[name] 为空则只显示正文。
  static Future<void> push(String name, String text) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('push', {'name': name, 'text': text});
    } on PlatformException {
      // 弹幕是锦上添花，任何失败都不打扰主流程。
    } on MissingPluginException {
      // 同上。
    }
  }

  /// 清空正在滚动的弹幕（重进房间时调用）。
  static Future<void> clear() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on PlatformException {
      // 忽略。
    } on MissingPluginException {
      // 同上。
    }
  }

  /// Android 打开系统「显示在其他应用上层」设置页；其余平台返回 true。
  static Future<bool> openPermissionSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openPermissionSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
