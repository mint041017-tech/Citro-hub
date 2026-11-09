import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'platform.dart' as platform;

/// 柔和提示音：呼吸换相与番茄钟完成。纯 Dart 合成 WAV，无需额外音频资源。
class Chime {
  Chime._();

  static AudioPlayer? _player;
  static final Map<String, Uint8List> _cache = {};
  static bool _available = true;

  /// 提示音要和听隅的多轨混音共存，不能抢走音频焦点。
  static final AudioContext _mixContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  static bool get _supported => !platform.isTest && _available;

  static Future<void> breath({required bool inhale}) async {
    final played = await _playAsset(
      inhale ? 'breath_in' : 'breath_out',
      volume: .24,
      maxMs: inhale ? 950 : 1100,
    );
    if (played) return;
    await _play(
      inhale ? 'breath-in' : 'breath-out',
      freq: inhale ? 392 : 329.63,
      dur: .42,
      vol: .1,
      soft: true,
    );
  }

  static Future<void> done({bool wood = false, int volume = 55}) async {
    final level = (volume / 100).clamp(0.0, 1.0);
    final played = await _playAsset(
      wood ? 'chime_wood' : 'chime_bell',
      volume: level,
      maxMs: wood ? 1100 : 2800,
    );
    if (played) return;
    final gain = (volume / 55).clamp(0.0, 1.6);
    if (wood) {
      await _play(
        'done-wood-a',
        freq: 392,
        dur: .5,
        vol: .30 * gain,
        wood: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 210));
      await _play(
        'done-wood-b',
        freq: 587.33,
        dur: .9,
        vol: .26 * gain,
        wood: true,
      );
      return;
    }
    await _play('done-a', freq: 659.25, dur: .8, vol: .34 * gain);
    await Future<void>.delayed(const Duration(milliseconds: 190));
    await _play('done-b', freq: 987.77, dur: 1.25, vol: .3 * gain);
  }

  /// 原版听隅的音频素材优先；素材不可用时再退回合成音。
  static Future<bool> _playAsset(
    String name, {
    required double volume,
    required int maxMs,
  }) async {
    if (!_supported) return false;
    try {
      final player = _player ??= AudioPlayer();
      if (!kIsWeb) {
        await player.setAudioContext(_mixContext);
      }
      await player.stop();
      await player.play(AssetSource('tingyu/audio/$name.wav'), volume: volume);
      Timer(Duration(milliseconds: maxMs), () {
        unawaited(player.stop());
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _play(
    String key, {
    required double freq,
    required double dur,
    required double vol,
    bool soft = false,
    bool wood = false,
  }) async {
    if (!_supported) return;
    try {
      final bytes = _cache[key] ??= wood
          ? _wood(freq: freq, dur: dur, vol: vol)
          : soft
          ? _soft(freq: freq, dur: dur, vol: vol)
          : _bell(freq: freq, dur: dur, vol: vol);
      final player = _player ??= AudioPlayer();
      if (!kIsWeb) {
        await player.setAudioContext(_mixContext);
      }
      await player.stop();
      await player.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } catch (_) {
      // 浏览器在无手势时可能拒绝播放：静默跳过，后续换相再试。
      if (!kIsWeb) _available = false;
    }
  }

  static Uint8List _bell({
    required double freq,
    required double dur,
    required double vol,
  }) => _render(
    dur: dur,
    sample: (t) {
      final attack = math.min(1.0, t / .012);
      final decay = math.exp(-3.6 * t / dur);
      final shimmer = 1 + .05 * math.sin(2 * math.pi * 5.2 * t);
      var value =
          math.sin(2 * math.pi * freq * t) +
          .34 * math.sin(2 * math.pi * freq * 2.01 * t) +
          .14 * math.sin(2 * math.pi * freq * 3.02 * t);
      return value * attack * decay * shimmer * vol;
    },
  );

  /// 呼吸换相的轻提示：近乎纯音的短音，音量很低。
  static Uint8List _soft({
    required double freq,
    required double dur,
    required double vol,
  }) => _render(
    dur: dur,
    sample: (t) {
      final attack = math.min(1.0, t / .02);
      final decay = math.exp(-8 * t / dur);
      final value =
          math.sin(2 * math.pi * freq * t) +
          .08 * math.sin(2 * math.pi * freq * 2 * t);
      return value * attack * decay * vol;
    },
  );

  /// 木鱼：短促、闷一点的木质敲击。
  static Uint8List _wood({
    required double freq,
    required double dur,
    required double vol,
  }) => _render(
    dur: dur,
    sample: (t) {
      final attack = math.min(1.0, t / .004);
      final decay = math.exp(-9 * t / dur);
      final value =
          math.sin(2 * math.pi * freq * t) +
          .22 * math.sin(2 * math.pi * freq * 1.87 * t) +
          .06 * math.sin(2 * math.pi * freq * 3.3 * t);
      return value * attack * decay * vol;
    },
  );

  static Uint8List _render({
    required double dur,
    required double Function(double t) sample,
  }) {
    const rate = 22050;
    final count = (dur * rate).round();
    final data = ByteData(44 + count * 2);
    void tag(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        data.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    data.setUint32(4, 36 + count * 2, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    data.setUint32(40, count * 2, Endian.little);

    for (var i = 0; i < count; i++) {
      final value = (sample(i / rate).clamp(-1.0, 1.0) * 32767).round();
      data.setInt16(44 + i * 2, value, Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
