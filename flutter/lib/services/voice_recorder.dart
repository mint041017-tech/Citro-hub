import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'api.dart';
import 'glm_asr.dart';

/// 语音输入：边录边转写。
///
/// 系统听写在部分机型上 `startListening` 后立刻 `done`，所以这里改成
/// 自己录 PCM 流，每 2 秒切一片丢给服务端 GLM-ASR，拼出实时预览文本。
/// 切片之间不重叠，成本与一次性上传整段持平。
class VoiceRecorder {
  VoiceRecorder._();

  static final AudioRecorder _rec = AudioRecorder();
  static StreamSubscription<Uint8List>? _pcm;
  static StreamSubscription<Amplitude>? _amp;

  static final BytesBuilder _pendingPcm = BytesBuilder(copy: false);
  static Timer? _chunkTimer;
  static Future<void> _uploadChain = Future<void>.value();

  static DateTime? _startedAt;
  static String _text = '';
  static String? _lastError;
  static bool _permissionOk = false;
  static double _lastLevel = 0;

  /// 每片音频的时长。太短识别不准，太长预览就慢。
  static const Duration chunk = Duration(milliseconds: 2000);

  /// 服务端单次上限 30 秒，按住超过这个时长自动收尾。
  static const Duration maxLength = Duration(seconds: 25);

  static const int _sampleRate = 16000;

  /// 已转好的文本（松手前可用于预览）。
  static String get text => _text;
  static bool get isRecording => _startedAt != null;
  static double get level => _lastLevel;
  static String? get lastError => _lastError;

  static Future<bool> start({
    void Function(double level)? onLevel,
    void Function(String text)? onText,
  }) async {
    try {
      if (isRecording) await cancel();
      final ok = await _rec.hasPermission();
      _permissionOk = ok;
      if (!ok) {
        _lastError = '麦克风权限未授予';
        return false;
      }
      final stream = await _rec.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );
      _startedAt = DateTime.now();
      _text = '';
      _lastError = null;
      _lastLevel = 0;
      _pendingPcm.clear();
      _uploadChain = Future<void>.value();

      _pcm = stream.listen(
        (data) {
          _pendingPcm.add(data);
        },
        onError: (Object error) => _lastError = '$error',
        cancelOnError: false,
      );
      _amp = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
            final v = ((a.current + 60) / 6).clamp(0, 10).toDouble();
            _lastLevel = v;
            onLevel?.call(v);
          });
      _chunkTimer = Timer.periodic(chunk, (_) => _flush(onText));
      return true;
    } catch (error) {
      _lastError = '$error';
      debugPrint('record start failed: $error');
      await cancel();
      return false;
    }
  }

  /// 把当前缓冲区切成一片上传，结果追加到预览文本。
  static void _flush(void Function(String text)? onText) {
    if (_pendingPcm.isEmpty) return;
    final pcm = _pendingPcm.takeBytes();
    // 太短的片子（<0.3s）识别价值不大，攒到下一次。
    if (pcm.length < _sampleRate * 2 * 3 ~/ 10) {
      _pendingPcm.add(pcm);
      return;
    }
    final wav = _wrapWav(pcm);
    _uploadChain = _uploadChain.then((_) async {
      try {
        final piece = await _transcribe(base64Encode(wav));
        if (piece.isEmpty) return;
        // 分词拼接，中文之间不加空格。
        _text = _text.isEmpty ? piece : '$_text$piece';
        onText?.call(_text);
      } catch (error) {
        _lastError = error is ApiException ? error.message : '$error';
      }
    });
  }

  /// 松手：停止录音，等最后一片转完，返回完整文本。
  static Future<String> finish() async {
    if (_startedAt == null) return '';
    _chunkTimer?.cancel();
    _chunkTimer = null;
    await _amp?.cancel();
    _amp = null;
    await _pcm?.cancel();
    _pcm = null;
    try {
      await _rec.stop();
    } catch (error) {
      debugPrint('record stop failed: $error');
    }
    _startedAt = null;
    _lastLevel = 0;

    if (_pendingPcm.isNotEmpty) {
      final pcm = _pendingPcm.takeBytes();
      if (pcm.length >= _sampleRate) {
        final wav = _wrapWav(pcm);
        _uploadChain = _uploadChain.then((_) async {
          try {
            final piece = await _transcribe(base64Encode(wav));
            if (piece.isEmpty) return;
            _text = _text.isEmpty ? piece : '$_text$piece';
          } catch (error) {
            _lastError = error is ApiException ? error.message : '$error';
          }
        });
      }
    }
    try {
      await _uploadChain.timeout(const Duration(seconds: 30));
    } catch (_) {}
    return _text.trim();
  }

  static Future<void> cancel() async {
    _chunkTimer?.cancel();
    _chunkTimer = null;
    await _amp?.cancel();
    _amp = null;
    await _pcm?.cancel();
    _pcm = null;
    _startedAt = null;
    _lastLevel = 0;
    _pendingPcm.clear();
    _text = '';
    try {
      await _rec.stop();
    } catch (_) {}
  }

  static Future<bool> hasPermission() async {
    try {
      final ok = await _rec.hasPermission();
      _permissionOk = ok;
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// PCM16 → 带 44 字节头的 WAV，服务端只收 wav/mp3。
  static Uint8List _wrapWav(Uint8List pcm) {
    final dataLen = pcm.length;
    final out = Uint8List(44 + dataLen);
    final b = ByteData.view(out.buffer);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        out[offset + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + dataLen, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, _sampleRate, Endian.little);
    b.setUint32(28, _sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    b.setUint32(40, dataLen, Endian.little);
    out.setRange(44, 44 + dataLen, pcm);
    return out;
  }

  static Future<String> _transcribe(String base64Audio) async {
    try {
      return await Api.transcribe(base64Audio);
    } on ApiException catch (error) {
      // 服务端还没部署 / 没配 key 时退到直连，别让语音整条不可用。
      if (error.code == 404 || error.code == 503) {
        return GlmAsr.transcribe(base64Audio);
      }
      rethrow;
    }
  }

  /// 给失败面板用的同步诊断文本。
  static String diagnoseNow() {
    return [
      '录音方式：本地 PCM 流 + 服务端分片转写',
      '麦克风权限：${_permissionOk ? '已授予' : '未授予'}',
      '音频格式：wav 16kHz 单声道',
      '转写服务：${Api.base}/api/asr',
      '最近错误：${_lastError ?? '无'}',
      '平台：${defaultTargetPlatform.name}',
    ].join('\n');
  }
}