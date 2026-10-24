import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceResult {
  final String dataUrl;
  final int seconds;
  const VoiceResult(this.dataUrl, this.seconds);
}

class VoiceRecorder {
  static final AudioRecorder _rec = AudioRecorder();
  static String? _path;
  static DateTime? _started;
  static Timer? _autoStop;

  static Future<bool> start({VoidCallback? onAutoStop}) async {
    try {
      if (!await _rec.hasPermission()) return false;
      final dir = await getTemporaryDirectory();
      _path =
          '${dir.path}/citro_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: _path!,
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
      final path = await _rec.stop() ?? _path;
      final seconds = _started == null
          ? 0
          : DateTime.now().difference(_started!).inSeconds.clamp(1, 60);
      _started = null;
      if (path == null) return null;
      final f = File(path);
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      if (bytes.length < 64) return null;
      try {
        await f.delete();
      } catch (_) {}
      return VoiceResult(
        'data:audio/mp4;base64,${base64Encode(bytes)}',
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
