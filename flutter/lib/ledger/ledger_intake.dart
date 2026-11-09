import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_keys.dart';
import '../services/platform.dart' as platform;

/// 一次来自系统分享（Android / iOS ShareExtension）的账单截图。
@immutable
class LedgerIntakeImage {
  final Uint8List bytes;

  /// androidShare / iosShare。
  final String origin;

  const LedgerIntakeImage({required this.bytes, required this.origin});
}

/// 截图一键记账的原生入口。
///
/// Android 从系统分享面板接收图片，iOS 从系统分享的 ShareExtension
/// 接收图片（通过 App Group 传递），随后自动跳到账单页的「记一笔」，
/// 由 [LedgerAddTab] 取走并走原有的识别草稿确认流程。
class LedgerIntake with WidgetsBindingObserver {
  LedgerIntake._();

  static final LedgerIntake instance = LedgerIntake._();

  static const _channel = MethodChannel('com.chimu.crew/ledger_intake');
  static const _ledgerRoute = '/ledger';

  final List<LedgerIntakeImage> _pending = [];
  final List<String> _errors = [];
  final StreamController<void> _pendingEvents =
      StreamController<void>.broadcast();

  bool _attached = false;
  bool _navigating = false;
  int _attachAttempts = 0;

  /// 有新图片入队；账单页监听后切到「记一笔」，记账页监听后开始识别。
  Stream<void> get pending => _pendingEvents.stream;

  /// App 启动后调用一次。重复调用会被忽略。
  void attach() {
    if (_attached || platform.isTest) return;
    if (!platform.isAndroid && !platform.isIOS) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onMethodCall);
    _attachNative();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS 分享扩展未能直接拉起 App 时，用户回到前台后再取一次共享图片。
    if (state == AppLifecycleState.resumed && platform.isIOS) {
      unawaited(_consumeNative());
    }
  }

  Future<void> _consumeNative() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('consume');
      _accept(raw);
    } catch (_) {
      // 没有待处理图片或原生通道暂不可用时忽略。
    }
  }

  Future<void> _attachNative() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('attach');
      _accept(raw);
    } on MissingPluginException {
      // 极少数冷启动时序下 Flutter 通道还没注册好，短暂重试。
      if (++_attachAttempts < 10) {
        Timer(const Duration(milliseconds: 300), _attachNative);
      }
    } catch (_) {
      // 原生入口不可用时静默降级，不影响手动记账。
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'ledgerImage':
        _accept(call.arguments);
      case 'ledgerIntakeError':
        _reportError('${call.arguments ?? ''}');
    }
    return null;
  }

  void _accept(dynamic raw) {
    if (raw is! Map) return;
    final error = raw['error'];
    if (error is String && error.trim().isNotEmpty) {
      _reportError(error.trim());
      return;
    }
    final value = raw['bytes'];
    Uint8List? bytes;
    if (value is Uint8List) {
      bytes = value;
    } else if (value is List<int>) {
      bytes = Uint8List.fromList(value);
    } else if (value is List) {
      bytes = Uint8List.fromList(
        value.map((item) => item is num ? item.toInt() : 0).toList(),
      );
    }
    if (bytes == null || bytes.isEmpty) return;
    final origin = raw['origin'] is String
        ? raw['origin'] as String
        : 'unknown';
    _pending.add(LedgerIntakeImage(bytes: bytes, origin: origin));
    _ensureLedgerRoute();
    _pendingEvents.add(null);
  }

  void _reportError(String message) {
    if (message.isEmpty) return;
    _errors.add(message);
    // 失败时也进入账单页，让用户能看到提示并改用相册/拍照。
    _ensureLedgerRoute();
    _pendingEvents.add(null);
  }

  /// 记账页取走下一张截图。没有时返回 null。
  LedgerIntakeImage? takePending() {
    if (_pending.isEmpty) return null;
    return _pending.removeAt(0);
  }

  /// 取走下一条原生错误。
  String? takeError() {
    if (_errors.isEmpty) return null;
    return _errors.removeAt(0);
  }

  Future<void> _ensureLedgerRoute() async {
    if (_navigating) return;
    _navigating = true;
    try {
      NavigatorState? nav;
      for (var i = 0; i < 40; i++) {
        nav = citroNavigatorKey.currentState;
        if (nav != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (nav == null) {
        // 首帧还没建好时保留队列，稍后重试，避免冷启动丢截图。
        unawaited(
          Future<void>.delayed(const Duration(seconds: 1), _ensureLedgerRoute),
        );
        return;
      }
      // 已经在账单页时由 LedgerPage 监听切换 Tab，不重复压路由。
      if (citroActiveRoute.value != _ledgerRoute) {
        unawaited(nav.pushNamed(_ledgerRoute, arguments: 1));
      }
    } finally {
      _navigating = false;
    }
  }
}