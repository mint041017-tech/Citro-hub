import 'package:audioplayers/audioplayers.dart';

class Sfx {
  Sfx._();

  static bool muted = false;

  /// Widget tests use fake time and do not have an audio plugin; disabling
  /// loading keeps the suite deterministic.
  static bool testMode = false;
  static bool _ready = false;
  static final List<AudioPlayer> _steps = <AudioPlayer>[];
  static final Map<AudioPlayer, double> _baseVolume = <AudioPlayer, double>{};
  static AudioPlayer? _knock;
  static AudioPlayer? _chime;
  static AudioPlayer? _settle;
  static AudioPlayer? _strand;
  static AudioPlayer? _win;
  static AudioPlayer? _lose;
  static AudioPlayer? _ui;
  static AudioPlayer? _charge;

  static Future<void> init() async {
    if (_ready || testMode) return;
    _ready = true;
    for (var i = 0; i < 5; i++) {
      final p = await _tryLoad('knockwater/audio/step_$i.wav', 0.45);
      if (p != null) _steps.add(p);
    }
    _knock = await _tryLoad('knockwater/audio/knock.wav', 0.62);
    _chime = await _tryLoad('knockwater/audio/chime.wav', 0.5);
    _settle = await _tryLoad('knockwater/audio/settle.wav', 0.5);
    _strand = await _tryLoad('knockwater/audio/strand.wav', 0.55);
    _win = await _tryLoad('knockwater/audio/win.wav', 0.6);
    _lose = await _tryLoad('knockwater/audio/lose.wav', 0.5);
    _ui = await _tryLoad('knockwater/audio/ui.wav', 0.3);
    _charge = await _tryLoad('knockwater/audio/charge.wav', 0.3);
  }

  static Future<AudioPlayer?> _tryLoad(String asset, double volume) async {
    try {
      return await _load(asset, volume);
    } catch (_) {
      return null;
    }
  }

  static Future<AudioPlayer> _load(String asset, double volume) async {
    final p = AudioPlayer();
    _baseVolume[p] = volume;
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setVolume(muted ? 0 : volume);
    await p.setSource(AssetSource(asset));
    return p;
  }

  static void _play(AudioPlayer? p) {
    if (p == null || muted) return;
    p.stop().then((_) => p.resume()).catchError((_) {});
  }

  static void step(int streak) {
    if (_steps.isEmpty) return;
    _play(_steps[streak % _steps.length]);
  }

  static void knock(double power) {
    final p = _knock;
    if (p == null) return;
    final v = _baseVolume[p] ?? 0.78;
    p.setVolume(muted ? 0 : v * (0.75 + 0.25 * power));
    _play(p);
  }

  static void chime() => _play(_chime);
  static void settle() => _play(_settle);
  static void strand() => _play(_strand);
  static void win() => _play(_win);
  static void lose() => _play(_lose);
  static void ui() => _play(_ui);
  static void charge() => _play(_charge);

  static void chargeStop() {
    final p = _charge;
    if (p == null) return;
    p.stop().catchError((_) {});
  }

  static Future<void> setMuted(bool value) async {
    muted = value;
    for (final entry in _baseVolume.entries) {
      try {
        await entry.key.setVolume(muted ? 0 : entry.value);
      } catch (_) {}
    }
    if (!muted) {
      for (final p in _steps) {
        if (p.state == PlayerState.playing) {
          try {
            await p.resume();
          } catch (_) {}
        }
      }
    }
  }
}
