import 'dart:async';

import 'package:flutter/services.dart';

import 'api.dart';
import 'platform.dart' as platform;
import 'push_binding.dart';

final class PushNotifications {
  static const _channel = MethodChannel('com.chimu.crew/push');
  static Completer<PushToken?>? _tokenWaiter;
  static bool _handlerReady = false;
  static void Function(PushToken token)? onToken;
  static final PushBindingCoordinator _binding = PushBindingCoordinator(
    tokenProvider: currentToken,
    bind: (call) => Api.post('/api/push/devices', {
      'token': call['token'],
      'environment': call['environment'],
    }),
    unbind: (call) => Api.del('/api/push/devices', {'token': call['token']}),
  );

  static Future<void> setActive({
    required String? account,
    required bool enabled,
  }) => _binding.setActive(account: account, enabled: enabled);

  static Future<PushToken?> currentToken() async {
    if (!platform.isIOS) return null;
    _installHandler();
    final current = await _invokeCurrentToken();
    if (current != null) return current;
    _tokenWaiter ??= Completer<PushToken?>();
    final waiter = _tokenWaiter!;
    unawaited(_channel.invokeMethod<void>('register'));
    try {
      return await waiter.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      if (identical(_tokenWaiter, waiter)) _tokenWaiter = null;
      return null;
    }
  }

  static void _installHandler() {
    if (_handlerReady) return;
    _handlerReady = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'token') return null;
      final value = _parseToken(call.arguments);
      if (value != null) {
        final waiter = _tokenWaiter;
        _tokenWaiter = null;
        if (waiter != null && !waiter.isCompleted) waiter.complete(value);
        onToken?.call(value);
      }
      return null;
    });
  }

  static Future<PushToken?> _invokeCurrentToken() async {
    try {
      return _parseToken(await _channel.invokeMethod<dynamic>('getToken'));
    } catch (_) {
      return null;
    }
  }

  static PushToken? _parseToken(Object? value) {
    if (value is! Map) return null;
    final token = value['token'].toString().trim();
    if (token.length != 64) return null;
    return (token: token, environment: value['environment'].toString());
  }
}
