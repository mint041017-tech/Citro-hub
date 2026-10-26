import 'dart:async';
import 'dart:math' as math;

import '../services/game_sfx.dart';

/// 咕噜果冻铺的音效，参数逐项对齐原版 web（`liquid 2048/js/audio.js`）：
/// 同样的频率、滑音、时长、gain 比例与主音量 0.34。
class LiquidSfx {
  LiquidSfx._();

  static const double _master = 0.34;

  static double _clamp(double v, double a, double b) =>
      v < a ? a : (v > b ? b : v);

  static void start() {
    GameSfx.tone(
      freq: 392,
      slide: 523,
      dur: 0.12,
      type: 'triangle',
      vol: 0.06 * _master,
      punchy: true,
    );
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 100),
        () => GameSfx.tone(
          freq: 523,
          slide: 784,
          dur: 0.16,
          type: 'triangle',
          vol: 0.055 * _master,
          punchy: true,
        ),
      ),
    );
  }

  static void ui() {
    GameSfx.tone(
      freq: 620,
      slide: 720,
      dur: 0.05,
      type: 'sine',
      vol: 0.025 * _master,
      punchy: true,
    );
  }

  static void shoot(double power) {
    final p = _clamp(power, 0, 1);
    GameSfx.tone(
      freq: 170 + p * 120,
      slide: 62,
      dur: 0.15,
      type: 'sine',
      vol: 0.13 * _master,
      punchy: true,
    );
    GameSfx.noiseSweep(
      dur: 0.12,
      from: 1600 + p * 1500,
      to: 240,
      vol: (0.035 + p * 0.025) * _master,
    );
    GameSfx.vibrate(GameVibe.tick);
  }

  static void pop() {
    GameSfx.tone(
      freq: 560,
      slide: 980,
      dur: 0.08,
      type: 'sine',
      vol: 0.045 * _master,
      punchy: true,
    );
    GameSfx.vibrate(GameVibe.tick);
  }

  static void merge(int level, int combo) {
    final lv = _clamp(level.toDouble(), 1, 9);
    final base = _clamp(300 * math.pow(0.89, lv - 2).toDouble(), 92, 320);
    final c = math.min(combo < 1 ? 1 : combo, 8);
    final gain = 0.11 + math.min(0.05, lv * 0.006);

    GameSfx.tone(
      freq: base * 1.72,
      slide: base * 2.25,
      dur: 0.1,
      type: 'sine',
      vol: gain * _master,
      punchy: true,
    );
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 25),
        () => GameSfx.tone(
          freq: base * 1.08,
          slide: base * 0.82,
          dur: 0.24,
          type: 'triangle',
          vol: gain * 0.55 * _master,
          punchy: true,
        ),
      ),
    );
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 75),
        () => GameSfx.tone(
          freq: 760 + c * 90,
          slide: 1080 + c * 100,
          dur: 0.07,
          type: 'sine',
          vol: 0.025 * _master,
      punchy: true,
        ),
      ),
    );
    if (lv >= 7) {
      unawaited(
        Future.delayed(
          const Duration(milliseconds: 20),
          () => GameSfx.noiseSweep(
            dur: 0.18,
            from: 1800,
            to: 600,
            vol: 0.025 * _master,
          ),
        ),
      );
    }
    GameSfx.vibrate(GameVibe.light);
  }

  static void warn() {
    GameSfx.tone(
      freq: 250,
      slide: 220,
      dur: 0.18,
      type: 'triangle',
      vol: 0.055 * _master,
      punchy: true,
    );
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 140),
        () => GameSfx.tone(
          freq: 186,
          slide: 164,
          dur: 0.22,
          type: 'triangle',
          vol: 0.045 * _master,
          punchy: true,
        ),
      ),
    );
    GameSfx.vibrate(GameVibe.tick);
  }

  static void over() {
    GameSfx.tone(
      freq: 300,
      slide: 92,
      dur: 0.65,
      type: 'triangle',
      vol: 0.1 * _master,
      punchy: true,
    );
    unawaited(
      Future.delayed(
        const Duration(milliseconds: 60),
        () => GameSfx.tone(
          freq: 150,
          slide: 60,
          dur: 0.7,
          type: 'sine',
          vol: 0.09 * _master,
          punchy: true,
        ),
      ),
    );
    GameSfx.noiseSweep(
      dur: 0.35,
      from: 700,
      to: 120,
      vol: 0.03 * _master,
    );
    GameSfx.vibrate(GameVibe.medium);
  }
}
