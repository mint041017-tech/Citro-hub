import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

class VoiceResult {
  final String dataUrl;
  final int seconds;
  const VoiceResult(this.dataUrl, this.seconds);
}

class VoiceRecorder {
  static final AudioRecorder _rec = AudioRecorder();
  static DateTime? _started;
  static Timer? _autoStop;

  static Future<bool> start({VoidCallback? onAutoStop}) async {
    try {
      if (!await _rec.hasPermission()) return false;
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: 'citro_voice_${DateTime.now().millisecondsSinceEpoch}.webm',
      );
      _started = DateTime.now();
      _autoStop?.cancel();
      _autoStop = Timer(const Duration(seconds: 60), () {
        onAutoStop?.call();
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<VoiceResult?> stop() async {
    _autoStop?.cancel();
    try {
      final path = await _rec.stop();
      final seconds = _started == null
          ? 0
          : DateTime.now().difference(_started!).inSeconds.clamp(1, 60);
      _started = null;
      if (path == null) return null;
      final response = await http.get(Uri.parse(path));
      if (response.statusCode != 200 || response.bodyBytes.length < 64) {
        return null;
      }
      final mime =
          response.headers['content-type']?.split(';').first.trim() ??
          'audio/webm';
      return VoiceResult(
        'data:$mime;base64,${base64Encode(response.bodyBytes)}',
        seconds,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> cancel() async {
    _autoStop?.cancel();
    try {
      await _rec.cancel();
    } catch (_) {}
    _started = null;
  }
}
