import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// CiCi 的语音输入：使用设备自带听写，把识别结果实时填进输入框。
class SpeechInput {
  SpeechInput._();

  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _initialized = false;
  static bool _available = false;
  static String? _localeId;
  static String? _lastError;

  static bool get listening => _speech.isListening;
  static bool get available => _available;
  static String? get lastError => _lastError;

  static Future<bool> ensureReady() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _speech.initialize(
        onError: (error) => _lastError = error.errorMsg,
        onStatus: (_) {},
      );
      if (_available) {
        // Windows 走 SAPI，让系统按自己的语言包识别；其它平台优先中文。
        if (defaultTargetPlatform == TargetPlatform.windows) {
          _localeId = null;
        } else {
          final locales = await _speech.locales();
          if (locales.isNotEmpty) {
            final zh = locales.where(
              (locale) => locale.localeId.toLowerCase().startsWith('zh'),
            );
            _localeId = (zh.isNotEmpty ? zh.first : locales.first).localeId;
          }
        }
      }
    } catch (error) {
      _available = false;
      _lastError = '$error';
    }
    return _available;
  }

  static Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    void Function(String message)? onError,
    void Function()? onDone,
  }) async {
    if (!await ensureReady()) {
      onError?.call(_lastError ?? '当前设备不支持语音识别');
      return false;
    }
    _lastError = null;
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          onResult(result.recognizedWords, result.finalResult);
          if (result.finalResult) onDone?.call();
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: _localeId,
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 5),
        ),
      );
      return true;
    } catch (error) {
      _lastError = '$error';
      onError?.call(_lastError!);
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  static Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {}
  }
}
