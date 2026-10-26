import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform.dart' as platform;
import 'prefs.dart';

/// 游戏音效 / 震动反馈（v1.5.9 新增）。
///
/// Web 原版每个游戏都有一组 `gbTone / gbNoiseBurst` 风格的合成音
/// （方波 / 锯齿 / 正弦 + 噪声脉冲），App 端用同样的思路：
/// Dart 直接合成 16bit PCM WAV 字节，交给 audioplayers 播放，
/// 不需要往包里塞任何音频资源。所有调用都带 try/catch，出错静默。
class GameSfx {
  GameSfx._();

  /// 测试环境（golden / widget test）不初始化播放器。
  /// Web 使用 audioplayers 的浏览器实现，首次播放仍由游戏手势触发。
  static bool get _supported => !_isTest && _available;
  static final bool _isTest = platform.isTest;
  static bool _available = true;

  // ---- 静音开关（持久化，与 web localStorage chimu_gbrake_mute 同语义）----
  static bool _muted = false;
  static bool get muted => _muted;

  /// v1.6.0：只有跳一跳 / 极限刹车保留音效（用户反馈），其余游戏只震动。
  /// 需要声音的页面在 initState 打开、dispose 恢复；tone/noise 在关闭时
  /// 直接跳过，语义化快捷方式里的 vibrate 不受影响。
  static bool soundsEnabled = false;

  static Future<void> loadMuted() async {
    try {
      _muted = Prefs.getString(PrefKeys.gameMuted) == '1';
    } catch (_) {}
  }

  static Future<void> setMuted(bool v) async {
    _muted = v;
    try {
      await Prefs.setString(PrefKeys.gameMuted, v ? '1' : '0');
    } catch (_) {}
    if (v) {
      unawaited(engineSet(0, false));
      unawaited(tireSet(0));
    }
  }

  // ------------------------------------------------------------------
  // 一次性短音（6 个播放器轮转，避免同帧叠放时互相打断太狠）
  // ------------------------------------------------------------------

  static final List<AudioPlayer?> _pool = List<AudioPlayer?>.filled(6, null);
  static int _poolIdx = 0;
  static final Map<String, Uint8List> _cache = {};

  static AudioPlayer? _nextPlayer() {
    final p = _pool[_poolIdx] ??= AudioPlayer();
    _poolIdx = (_poolIdx + 1) % _pool.length;
    return p;
  }

  /// 预热（游戏页进入时可调用，减小首响延迟）。
  static Future<void> warmup() async {
    if (!_supported) return;
    try {
      await _nextPlayer()!.setPlayerMode(PlayerMode.lowLatency);
    } catch (_) {}
  }

  /// 播放一段合成音。参数见 [_synth]。
  static Future<void> tone({
    required double freq,
    required double dur,
    String type = 'square',
    double vol = 0.18,
    double? slide,
    bool punchy = false,
  }) async {
    if (!_supported || _muted || !soundsEnabled) return;
    try {
      final key = 't$freq|$dur|$type|$vol|$slide|$punchy';
      final bytes = _cache[key] ??= _synth(
        freq: freq,
        dur: dur,
        type: type,
        vol: vol,
        slide: slide,
        punchy: punchy,
      );
      final p = _nextPlayer()!;
      await p.stop();
      await p.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } catch (e) {
      // 浏览器在手势外会拒绝播放；保留播放器以便后续手势重试。
      if (!kIsWeb) _available = false;
    }
  }

  /// 噪声脉冲（撞击 / 碎裂）。freq ≈ 带通中心。
  static Future<void> noise({
    required double dur,
    double vol = 0.3,
    double freq = 800,
    double q = 0.8,
  }) async {
    if (!_supported || _muted || !soundsEnabled) return;
    try {
      final key = 'n$dur|$vol|$freq';
      final bytes = _cache[key] ??= _noise(dur: dur, vol: vol, freq: freq);
      final p = _nextPlayer()!;
      await p.stop();
      await p.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } catch (e) {
      if (!kIsWeb) _available = false;
    }
  }

  /// 带通中心从 from 扫到 to 的噪声（投掷/合并/结束的“气息”）。
  static Future<void> noiseSweep({
    required double dur,
    double vol = 0.3,
    double from = 1600,
    double to = 260,
  }) async {
    if (!_supported || _muted || !soundsEnabled) return;
    try {
      final key = 's$dur|$vol|$from|$to';
      final bytes = _cache[key] ??= _noiseSweep(
        dur: dur,
        vol: vol,
        from: from,
        to: to,
      );
      final p = _nextPlayer()!;
      await p.stop();
      await p.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } catch (e) {
      if (!kIsWeb) _available = false;
    }
  }

  // ------------------------------------------------------------------
  // 极限刹车的持续音（引擎 / 轮胎噪声循环）
  // ------------------------------------------------------------------

  static AudioPlayer? _engine;
  static AudioPlayer? _tire;

  static Future<void> _ensureLoop(AudioPlayer? p, Uint8List bytes) async {
    if (p == null) return;
    try {
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(BytesSource(bytes, mimeType: 'audio/wav'));
      await p.setVolume(0);
    } catch (_) {}
  }

  static Uint8List? _engineBuf;
  static Future<void> engineStart() async {
    if (!_supported) return;
    try {
      _engine ??= AudioPlayer();
      _engineBuf ??= _synth(freq: 55.125, dur: 1.0, type: 'engine', vol: 1);
      await _ensureLoop(_engine, _engineBuf!);
    } catch (_) {}
  }

  /// rate 0~1（速度比），on=false 时淡出。
  static Future<void> engineSet(double rate, bool on) async {
    final p = _engine;
    if (p == null || !_supported) return;
    try {
      final f = 48 + rate * 230;
      await p.setPlaybackRate((f / 55.125).clamp(0.4, 4.2));
      await p.setVolume(on && !_muted ? 0.055 + rate * 0.075 : 0);
    } catch (_) {}
  }

  static Future<void> engineStop() => engineSet(0, false);

  static Uint8List? _tireBuf;
  static Future<void> tireStart() async {
    if (!_supported) return;
    try {
      _tire ??= AudioPlayer();
      _tireBuf ??= _noise(dur: 1.2, vol: 1, freq: 2100);
      await _ensureLoop(_tire, _tireBuf!);
    } catch (_) {}
  }

  static Future<void> tireSet(double v) async {
    final p = _tire;
    if (p == null || !_supported) return;
    try {
      await p.setVolume(_muted ? 0 : v.clamp(0.0, 0.16));
    } catch (_) {}
  }

  static Future<void> disposeLoops() async {
    try {
      await _engine?.stop();
      await _engine?.release();
      await _tire?.stop();
      await _tire?.release();
    } catch (_) {}
    _engine = null;
    _tire = null;
  }

  // ------------------------------------------------------------------
  // 震动（HapticFeedback，无需权限）
  // ------------------------------------------------------------------

  static void vibrate(GameVibe v) {
    switch (v) {
      case GameVibe.tick:
        HapticFeedback.selectionClick();
      case GameVibe.light:
        HapticFeedback.lightImpact();
      case GameVibe.medium:
        HapticFeedback.mediumImpact();
      case GameVibe.heavy:
        HapticFeedback.heavyImpact();
    }
  }

  // ------------------------------------------------------------------
  // 语义化快捷方式（各游戏调用入口）
  // ------------------------------------------------------------------

  static void tap() {
    tone(freq: 720, dur: 0.05, vol: 0.10);
    vibrate(GameVibe.tick);
  }

  static void move() {
    tone(freq: 340, dur: 0.06, type: 'square', vol: 0.12);
    vibrate(GameVibe.tick);
  }

  static void merge() {
    tone(freq: 420, dur: 0.1, type: 'square', vol: 0.16, slide: 880);
    vibrate(GameVibe.light);
  }

  static void flip() {
    tone(freq: 520, dur: 0.06, type: 'triangle', vol: 0.14);
    vibrate(GameVibe.tick);
  }

  static void match() {
    tone(freq: 523, dur: 0.1, type: 'sine', vol: 0.18);
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 90),
        () => tone(freq: 784, dur: 0.12, type: 'sine', vol: 0.16),
      ),
    );
    vibrate(GameVibe.light);
  }

  static void miss() {
    tone(freq: 240, dur: 0.12, type: 'square', vol: 0.13);
    vibrate(GameVibe.medium);
  }

  static void eat() {
    tone(freq: 600, dur: 0.08, type: 'square', vol: 0.16, slide: 980);
    vibrate(GameVibe.tick);
  }

  static void bounce() {
    tone(freq: 300, dur: 0.05, type: 'triangle', vol: 0.13, slide: 240);
    vibrate(GameVibe.tick);
  }

  static void warn() {
    tone(freq: 980, dur: 0.12, type: 'square', vol: 0.14);
    vibrate(GameVibe.tick);
  }

  static void win() {
    unawaited(tone(freq: 523, dur: 0.16, type: 'sine', vol: 0.2));
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 110),
        () => tone(freq: 659, dur: 0.16, type: 'sine', vol: 0.18),
      ),
    );
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 220),
        () => tone(freq: 784, dur: 0.16, type: 'sine', vol: 0.18),
      ),
    );
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 330),
        () => tone(freq: 1047, dur: 0.32, type: 'sine', vol: 0.18),
      ),
    );
    vibrate(GameVibe.medium);
  }

  static void lose() {
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 200),
        () => tone(freq: 392, dur: 0.2, type: 'triangle', vol: 0.2),
      ),
    );
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 420),
        () => tone(freq: 311, dur: 0.2, type: 'triangle', vol: 0.18),
      ),
    );
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 640),
        () => tone(freq: 233, dur: 0.36, type: 'triangle', vol: 0.18),
      ),
    );
    vibrate(GameVibe.heavy);
  }

  static void crash({bool heavy = false}) {
    unawaited(
      noise(
        dur: heavy ? 0.5 : 0.65,
        vol: heavy ? 0.5 : 0.6,
        freq: heavy ? 1600 : 420,
      ),
    );
    unawaited(
      tone(
        freq: heavy ? 220 : 120,
        dur: heavy ? 0.5 : 0.6,
        type: 'sawtooth',
        vol: 0.22,
        slide: heavy ? 60 : 44,
      ),
    );
    vibrate(GameVibe.heavy);
  }

  // ------------------------------------------------------------------
  // WAV 合成
  // ------------------------------------------------------------------

  static const int _rate = 44100;

  static Uint8List _synth({
    required double freq,
    required double dur,
    required String type,
    required double vol,
    double? slide,
    bool punchy = false,
  }) {
    final n = (dur * _rate).round();
    final data = Float32List(n);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / _rate;
      var f = freq;
      if (slide != null && freq > 0) {
        f = freq * math.pow(slide / freq, t / dur);
      }
      phase += f / _rate;
      phase %= 1;
      double s;
      switch (type) {
        case 'sine':
          s = math.sin(phase * 2 * math.pi);
        case 'sawtooth':
          s = 2 * phase - 1;
        case 'triangle':
          s = 4 * (phase - phase.round().abs()) * (phase < .5 ? 1 : -1);
          s = 1 - 4 * (phase - .5).abs();
        case 'engine':
          // 失谐锯齿 + 三次谐波，近似 web 的双振荡器引擎声
          final a = 2 * phase - 1;
          final b = 2 * ((phase * 1.503) % 1) - 1;
          s = 0.6 * a + 0.25 * b + 0.12 * math.sin(phase * 6 * math.pi);
        default:
          s = phase < 0.5 ? 1.0 : -1.0;
      }
      double env;
      if (punchy) {
        // 原版 WebAudio：8ms 快速起音到满音量，再指数衰减到接近 0。
        const attack = 0.008;
        if (t < attack) {
          env = t / attack;
        } else {
          env = math.exp(-(t - attack) / math.max(0.001, dur - attack) * 9.0);
        }
      } else {
        // 旧版包络：12ms 起音 + 全程指数衰减。
        final attack = math.min(1.0, t / 0.012);
        final release = math.exp(-t / dur * 9.0) * (1 - 0.0008) + 0.0008;
        env = attack * release;
      }
      data[i] = s * vol * env;
    }
    return _wav(data);
  }

  static Uint8List _noise({
    required double dur,
    required double vol,
    required double freq,
  }) {
    final n = (dur * _rate).round();
    final data = Float32List(n);
    final rnd = math.Random(0x5EED);
    // 简易带通：一阶低通 + 去直流，中心频率附近能量突出
    final rc = 1 / (2 * math.pi * freq);
    final a = rc / (rc + 1 / _rate);
    double lp = 0, prev = 0, prevLp = 0;
    for (var i = 0; i < n; i++) {
      final w = rnd.nextDouble() * 2 - 1;
      lp = lp + a * (w - lp);
      final bp = lp - prevLp;
      prevLp = lp;
      final s = (bp * 4.5).clamp(-1.0, 1.0);
      final env = (1 - i / n);
      data[i] = s * vol * env * 0.9 + prev * 0.02;
      prev = s;
    }
    return _wav(data);
  }

  static Uint8List _noiseSweep({
    required double dur,
    required double vol,
    required double from,
    required double to,
  }) {
    final n = (dur * _rate).round();
    final data = Float32List(n);
    final rnd = math.Random(0x5EED);

    // RBJ bandpass（Q=0.9），中心频率按原版指数扫频；每样本更新系数。
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
    const q = 0.9;
    const attack = 0.01;
    var peak = 0.0;
    for (var i = 0; i < n; i++) {
      final t = n > 1 ? i / (n - 1) : 0.0;
      final f0 = from * math.pow(to / from, t);
      final w0 = 2 * math.pi * f0 / _rate;
      final alpha = math.sin(w0) / (2 * q);
      final a0 = 1 + alpha;
      final b0 = alpha / a0;
      final b2 = -alpha / a0;
      final a1 = -2 * math.cos(w0) / a0;
      final a2 = (1 - alpha) / a0;

      final x = rnd.nextDouble() * 2 - 1;
      final y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1;
      x1 = x;
      y2 = y1;
      y1 = y;

      final time = i / _rate;
      final env = time < attack
          ? time / attack
          : math.exp(-(time - attack) / math.max(0.001, dur - attack) * 6.9);
      final s = (y * env * 2.8).clamp(-1.0, 1.0);
      data[i] = s;
      final mag = s.abs();
      if (mag > peak) peak = mag;
    }
    // 归一化到调用方给的 gain（原版 noiseSweep 的 gain 就是峰值量级）。
    if (peak > 1e-6) {
      final scale = (vol * 0.9) / peak;
      for (var i = 0; i < n; i++) {
        data[i] *= scale;
      }
    }
    return _wav(data);
  }

  static Uint8List _wav(Float32List samples) {
    final n = samples.length;
    final bytes = ByteData(44 + n * 2);
    void str(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    bytes.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, _rate, Endian.little);
    bytes.setUint32(28, _rate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    str(36, 'data');
    bytes.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      final v = (samples[i].clamp(-1.0, 1.0) * 32760).round();
      bytes.setInt16(44 + i * 2, v, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}

enum GameVibe { tick, light, medium, heavy }

/// 语义化音效（各游戏通用的短事件）。
extension GameSfxEvents on GameSfx {
  // 见 GameSfx 上的静态方法。
}
