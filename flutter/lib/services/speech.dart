import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// CiCi 的语音输入：使用设备自带听写，把识别结果实时填进输入框。
class SpeechInput {
  SpeechInput._();

  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _localized = false;
  static bool _available = false;
  static String? _localeId;
  static String? _lastError;
  static DateTime? _lastFailAt;
  static Future<bool>? _initFuture;
  static Timer? _watchdog;
  static String? lastStatus;
  static bool permissionOk = false;
  static int resultCount = 0;

  static bool get listening => _speech.isListening;
  static bool get available => _available;
  static String? get lastError => _lastError;

  /// 初始化识别器。
  ///
  /// 失败不缓存：麦克风权限被拒时 initialize 返回 false，
  /// 缓存失败会让用户授权后也永远恢复不了。
  /// 同时合并并发调用：预热和按住几乎同时发生时只初始化一次。
  static Future<bool> ensureReady({bool force = false}) {
    if (_available) return Future.value(true);
    final pending = _initFuture;
    if (pending != null) return pending;
    final lastFail = _lastFailAt;
    if (!force &&
        lastFail != null &&
        DateTime.now().difference(lastFail) < const Duration(seconds: 2)) {
      return Future.value(false);
    }
    final future = _initialize();
    _initFuture = future;
    return future.whenComplete(() => _initFuture = null);
  }

  static Future<bool> _initialize() async {
    try {
      _available = await _speech.initialize(
        onError: (error) => _lastError = error.errorMsg,
        onStatus: (status) {
          lastStatus = status;
          debugPrint('speech status: $status');
        },
      );
      if (!_available) {
        _lastFailAt = DateTime.now();
        _lastError ??= '麦克风权限未开启';
        return false;
      }
      _lastFailAt = null;
      try {
        permissionOk = await _speech.hasPermission;
      } catch (_) {}
      if (!_localized) {
        _localized = true;
        if (defaultTargetPlatform != TargetPlatform.windows) {
          final locales = await _speech.locales();
          if (locales.isNotEmpty) {
            final zh = locales.where(
              (locale) => locale.localeId.toLowerCase().startsWith('zh'),
            );
// 优先普通话：列表里第一个中文包未必是 zh-CN。
            final zhCn = zh.where(
              (l) => l.localeId.toLowerCase().replaceAll('-', '_') == 'zh_cn',
            );
            // 没有中文包就用系统默认，别强行挑一个英文 locale。
            _localeId = zhCn.isNotEmpty
                ? zhCn.first.localeId
                : (zh.isEmpty ? null : zh.first.localeId);
          }
        }
      }
      return true;
    } catch (error) {
      _available = false;
      _lastFailAt = DateTime.now();
      _lastError = '$error';
      return false;
    }
  }

/// 诊断信息：同步取当前已知状态，绝不再 await 初始化/语言包，
  /// 否则平台通道卡住时面板永远弹不出来。
  static String diagnoseNow() {
    return [
      '系统语音识别：${_available ? '可用' : '不可用'}',
      '麦克风权限：${permissionOk ? '已授予' : '未授予'}',
      '正在收音：${_speech.isListening}',
      '错误信息：${_lastError ?? '无'}',
      '识别语言：${_localeId ?? '系统默认'}',
      '最近状态：${lastStatus ?? '无'}',
      '收到结果：$resultCount 次',
      '平台：${defaultTargetPlatform.name}',
    ].join('\n');
  }

  static Future<bool> start({
required void Function(String text, bool isFinal) onResult,
    void Function(String message)? onError,
    void Function()? onDone,
    void Function(double level)? onLevel,
  }) async {
// 初始化本身也可能卡在权限弹窗或平台通道上，统一加超时。
    var ready = await ensureReady().timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    // 权限刚授予（或上一次初始化失败）时，再强制重试一次。
    if (!ready) {
      ready = await ensureReady(force: true).timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    }
    if (!ready) {
      onError?.call(_lastError ?? '麦克风初始化超时或当前设备不支持语音识别');
      return false;
    }
    // 上一次没收干净就先取消，否则 listen 会被忽略。
    if (_speech.isListening) {
      try {
        await _speech.cancel();
      } catch (_) {}
    }
_lastError = null;
    // 看门狗必须抢在 listen 之前：部分 ROM 的平台通道会一直不回，
    // 若等 listen 返回再挂计时器，就永远轮不到它，界面全程静默。
    var signalled = false;
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 4), () {
      if (signalled) return;
      _lastError = (lastStatus == 'listening' || lastStatus == 'speech')
          ? '识别服务已启动，但没收到麦克风声音（权限或占用问题）'
          : '识别服务没有响应（状态：${lastStatus ?? '无'}）';
      onError?.call(_lastError!);
    });
    try {
      await _speech
          .listen(
            onResult: (SpeechRecognitionResult result) {
              resultCount++;
              signalled = true;
              onResult(result.recognizedWords, result.finalResult);
              if (result.finalResult) onDone?.call();
            },
            onSoundLevelChange: (level) {
              signalled = true;
              onLevel?.call(level.clamp(0, 10).toDouble());
            },
            listenOptions: stt.SpeechListenOptions(
              localeId: _localeId,
              partialResults: true,
              cancelOnError: false,
              listenFor: const Duration(minutes: 2),
              pauseFor: const Duration(seconds: 10),
            ),
          )
          // 通道没回也只是「还没回」，不当失败，交给看门狗判定。
          .timeout(const Duration(seconds: 6), onTimeout: () {});
      return true;
    } catch (error) {
      _watchdog?.cancel();
      _watchdog = null;
      _lastError = '$error';
      onError?.call(_lastError!);
      return false;
    }
  }

  static Future<void> stop() async {
    _watchdog?.cancel();
    _watchdog = null;
    try {
      await _speech.stop();
    } catch (_) {}
  }

  static Future<void> cancel() async {
    _watchdog?.cancel();
    _watchdog = null;
    try {
      await _speech.cancel();
    } catch (_) {}
  }
}
