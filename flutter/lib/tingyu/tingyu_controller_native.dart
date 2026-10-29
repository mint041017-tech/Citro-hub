import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/prefs.dart';
import '../state/app_state.dart';
import 'tingyu_models.dart';

/// 原生端声音控制器：六路 URL/本地音轨 + 总音量 + 定时渐弱。
///
/// Web 端走原来的 Web Audio 引擎（见 tingyu_controller_web.dart）；
/// 原生端用 audioplayers 做同一套状态机，页面代码完全复用。
class NookController extends ChangeNotifier {
  static final NookController instance = NookController();

  NookController() {
    available = sounds.map((sound) => sound.id).toSet();
    for (final sound in sounds) {
      if (sound.synthesized) kinds[sound.id] = 'synth';
    }
    _theme = _read('theme') ?? _themeFromApp();
    if (!['light', 'dark', 'system'].contains(_theme)) _theme = 'system';
    reducedMotion = _read('reducedMotion') == 'true';
    final fade = int.tryParse(_read('defaultFade') ?? '');
    if (fade != null && [0, 15, 30, 60, 120].contains(fade)) {
      defaultFade = fade;
    }
    final sort = _read('favoriteSort');
    if (['recent', 'created', 'name'].contains(sort)) favoriteSort = sort!;
    _loadFavorites();
    _loadLocals();
    _loadDraft();
    _baseline = signature;
  }

  final Map<String, AudioPlayer> _players = {};
  final Map<String, Future<void>> _contextReady = {};
  final Set<String> _loadedSources = {};
  AudioPlayer? _previewPlayer;
  Timer? _previewTimer;
  Timer? _timerTicker;

  /// 多轨混音不能各自抢音频焦点，否则 Android 上后启动的轨道会把前一条暂停。
  static final AudioContext _mixContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  List<Map<String, dynamic>> _tracks = [
    {'id': 'rain', 'volume': 65},
    {'id': 'forest', 'volume': 25},
    {'id': 'brown', 'volume': 20},
  ];
  List<Map<String, dynamic>> _locals = const [];
  List<Map<String, dynamic>> favorites = [];
  Set<String> available = {};
  Map<String, String> kinds = {};
  String _theme = 'system';
  String favoriteSort = 'recent';
  int defaultFade = 30;
  bool reducedMotion = false;
  bool _ready = false;
  String? error;
  String? favoriteId;
  bool fullFontLoaded = false;
  bool _loadingFullFont = false;

  bool _playing = false;
  bool _busy = false;
  int _master = 70;
  String _title = '窗边一页';
  String? previewId;
  int previewRemaining = 0;

  String _timerStatus = 'off';
  DateTime? _timerDeadline;
  int _timerDuration = 0;
  int _timerFade = 0;
  double _timerGain = 1;
  String _baseline = '';

  String get fontFamily => fullFontLoaded ? 'NookFull' : 'NookUI';
  List<Map<String, dynamic>> get tracks => _tracks;
  List<Map<String, dynamic>> get locals => _locals;
  bool get playing => _playing;
  bool get busy => _busy;
  int get master => _master;
  String get title => _title;
  bool get ready => _ready;
  String get theme => _theme;
  bool get supportsImport => true;

  Map<String, dynamic> get timer => {
    'status': _timerStatus,
    'remaining': remaining,
    'duration': _timerDuration,
    'fade': _timerFade,
  };

  String get timerStatus => _timerStatus;
  num get remaining {
    final deadline = _timerDeadline;
    if (deadline == null) return 0;
    final seconds = deadline.difference(DateTime.now()).inMilliseconds / 1000;
    return math.max(0, seconds);
  }

  int get timerDuration => _timerDuration;
  int get timerFade => _timerFade;
  bool get hasTimer => ['armed', 'running', 'fading'].contains(_timerStatus);
  String get timerLabel => switch (_timerStatus) {
    'armed' => '播放后计时',
    'running' => clockText(remaining),
    'fading' => '渐弱 ${clockText(remaining)}',
    'expired' => '已定时结束',
    _ => '定时关闭',
  };

  bool get dirty =>
      ready && _baseline.isNotEmpty && signature != _baseline;

  String get signature => jsonEncode({'tracks': tracks, 'master': master});

  List<Map<String, dynamic>> get sortedFavorites {
    final list = [...favorites];
    switch (favoriteSort) {
      case 'created':
        list.sort(
          (a, b) => _stamp(b, 'createdAt').compareTo(_stamp(a, 'createdAt')),
        );
        break;
      case 'name':
        list.sort(
          (a, b) => (a['name'] as String).toLowerCase().compareTo(
            (b['name'] as String).toLowerCase(),
          ),
        );
        break;
      default:
        list.sort(
          (a, b) => math
              .max(_stamp(b, 'lastUsedAt'), _stamp(b, 'updatedAt'))
              .compareTo(
                math.max(_stamp(a, 'lastUsedAt'), _stamp(a, 'updatedAt')),
              ),
        );
    }
    return list;
  }

  List<SoundSpec> get library => [
    ...sounds.where((s) => available.contains(s.id)),
    ..._locals.map(
      (m) => SoundSpec(
        m['id'] as String,
        m['name'] as String? ?? '本地声音',
        '本地',
        '${clockText(m['duration'] as num? ?? 0)}，保存在本机',
        Icons.audio_file_outlined,
      ),
    ),
  ];

  SoundSpec sound(String id) =>
      library.where((s) => s.id == id).firstOrNull ??
      sounds.where((s) => s.id == id).firstOrNull ??
      SoundSpec(id, '不可用的声音', '本地', '请重新导入音频', Icons.audio_file_outlined);

  bool contains(String id) => tracks.any((t) => t['id'] == id);

  int _stamp(Map<String, dynamic> item, String key) =>
      item[key] is num ? (item[key] as num).toInt() : 0;

  String? _read(String key) => Prefs.getString('citro_tingyu_$key');

  Future<void> _write(String key, Object value) =>
      Prefs.setString('citro_tingyu_$key', '$value');

  String _themeFromApp() => switch (AppState.instance.themeMode) {
    ThemeMode.dark => 'dark',
    ThemeMode.light => 'light',
    ThemeMode.system => 'system',
  };

  void _loadFavorites() {
    final raw = _read('favorites');
    if (raw == null || raw.isEmpty) return;
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        favorites = value
            .whereType<Map>()
            .where((v) => v['id'] is String && v['name'] is String)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
      }
    } catch (_) {}
  }

  void _loadDraft() {
    final raw = _read('draft');
    if (raw == null || raw.isEmpty) return;
    try {
      final draft = jsonDecode(raw);
      if (draft is! Map) return;
      final parsed = validTracks(draft['tracks']);
      if (draft['tracks'] is List) _tracks = parsed;
      if (draft['master'] is num) {
        _master = ((draft['master'] as num).toInt()).clamp(0, 100);
      }
      if (draft['title'] is String) {
        final next = (draft['title'] as String).trim();
        if (next.isNotEmpty) _title = next;
      }
    } catch (_) {}
  }

  void _loadLocals() {
    final raw = _read('locals');
    if (raw == null || raw.isEmpty) return;
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        _locals = value
            .whereType<Map>()
            .where((v) => v['id'] is String && v['path'] is String)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        for (final local in _locals) {
          available.add(local['id'] as String);
        }
      }
    } catch (_) {}
  }

  Future<void> initialize() async {
    _ready = true;
    _baseline = signature;
    if (favorites.isNotEmpty || _locals.isNotEmpty) {
      unawaited(loadFullFont());
    }
    notifyListeners();
  }

  void refresh() {
    if (_timerStatus == 'running' || _timerStatus == 'fading') {
      _tickTimer();
    }
  }

  Future<void> loadFullFont() async {
    if (fullFontLoaded || _loadingFullFont) return;
    _loadingFullFont = true;
    try {
      final loader = FontLoader('NookFull')
        ..addFont(rootBundle.load('assets/tingyu/fonts/nook.ttf'));
      await loader.load();
      fullFontLoaded = true;
      notifyListeners();
    } catch (_) {
      // NookUI 子集已覆盖内置界面文字。
    } finally {
      _loadingFullFont = false;
    }
  }

  Future<bool> send(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    try {
      switch (action) {
        case 'init':
          await initialize();
          break;
        case 'play':
          await _play();
          break;
        case 'pause':
          await _pause();
          break;
        case 'toggle':
          if (_playing || _busy) {
            await _pause();
          } else {
            await _play();
          }
          break;
        case 'load':
          await _load(payload);
          break;
        case 'add':
          await _add(payload);
          break;
        case 'remove':
          await _remove('${payload['id'] ?? ''}');
          break;
        case 'volume':
          await _setTrackVolume(
            '${payload['id'] ?? ''}',
            (payload['value'] as num?)?.toInt() ?? 0,
          );
          break;
        case 'master':
          _master = ((payload['value'] as num?)?.toInt() ?? 70).clamp(0, 100);
          await _applyVolumes();
          await _write('draft', jsonEncode(_draft()));
          break;
        case 'preview':
          await _preview('${payload['id'] ?? ''}');
          break;
        case 'stopPreview':
          await _stopPreview();
          break;
        case 'timer':
          _setTimer(
            (payload['seconds'] as num?)?.toInt() ?? 0,
            (payload['fadeSeconds'] as num?)?.toInt() ?? 0,
          );
          break;
        case 'cancelTimer':
          _cancelTimer();
          break;
        case 'stop':
          await _pause();
          _cancelTimer();
          break;
        case 'import':
          await _importLocal();
          break;
        case 'deleteLocal':
          await _deleteLocal('${payload['id'] ?? ''}');
          break;
        default:
          throw StateError('未知的音频操作。');
      }
      error = null;
      notifyListeners();
      return true;
    } catch (e) {
      error = e is StateError
          ? e.message
          : e is AudioPlayerException
          ? '音频暂时无法播放，请稍后再试。'
          : '操作没有完成，请再试一次。';
      notifyListeners();
      return false;
    }
  }

  Map<String, dynamic> _draft() => {
    'tracks': tracks,
    'master': master,
    'title': title,
  };

  double _normalization() {
    final sum = _tracks.fold<double>(
      0,
      (total, track) => total + ((track['volume'] as num?) ?? 0) / 100,
    );
    return 0.85 / math.max(1, sum);
  }

  double _gainFor(Map<String, dynamic> track) {
    final volume = ((track['volume'] as num?) ?? 0) / 100;
    return (volume * _master / 100 * _normalization() * _timerGain)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Future<Source> _sourceFor(String id) async {
    if (id.startsWith('local:')) {
      for (final local in _locals) {
        if (local['id'] == id) return DeviceFileSource('${local['path']}');
      }
      throw StateError('本地声音文件不存在，请重新导入。');
    }
    if (kinds[id] == 'synth') {
      return AssetSource('tingyu/audio/$id.wav');
    }
    return UrlSource('https://obs.chimu-claw.xyz/ambient%20noise/$id.wav');
  }

  AudioPlayer _player(String id) {
    final existing = _players[id];
    if (existing != null) return existing;
    final player = AudioPlayer();
    _contextReady[id] = player.setAudioContext(_mixContext);
    unawaited(player.setReleaseMode(ReleaseMode.loop));
    _players[id] = player;
    return player;
  }

  Future<void> _preparePlayer(String id) async {
    final player = _player(id);
    await _contextReady[id];
    if (_loadedSources.add(id)) {
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setSource(await _sourceFor(id));
    }
  }

  Future<void> _applyVolumes() async {
    for (final track in _tracks) {
      final player = _players[track['id']];
      if (player == null) continue;
      final gain = _gainFor(track);
      await player.setVolume(gain);
    }
  }

  Future<void> _play() async {
    if (_tracks.isEmpty) throw StateError('先加入至少一种声音。');
    _busy = true;
    notifyListeners();
    try {
      var started = 0;
      for (final track in _tracks) {
        final id = '${track['id']}';
        try {
          await _preparePlayer(id);
          final player = _player(id);
          await player.setVolume(_gainFor(track));
          await player.resume();
          started++;
        } catch (_) {}
      }
      if (started == 0) {
        throw StateError('声音加载失败，请检查网络后重试。');
      }
      _playing = true;
      if (_timerStatus == 'armed') {
        _timerDeadline = DateTime.now().add(
          Duration(seconds: _timerDuration),
        );
        _timerStatus = 'running';
        _ensureTicker();
      }
      await _write('draft', jsonEncode(_draft()));
    } finally {
      _busy = false;
    }
  }

  Future<void> _pause() async {
    _playing = false;
    await _stopPreview();
    for (final player in _players.values) {
      try {
        await player.pause();
      } catch (_) {}
    }
  }

  Future<void> _load(Map<String, dynamic> payload) async {
    final next = validTracks(payload['tracks']);
    if (next.length > 6) throw StateError('最多同时播放 6 种声音。');
    final ids = next.map((t) => '${t['id']}').toSet();
    for (final id in ids) {
      if (!available.contains(id)) throw StateError('选中的声音已不可用。');
    }
    for (final entry in _players.entries.toList()) {
      if (!ids.contains(entry.key)) {
        await entry.value.stop();
        _loadedSources.remove(entry.key);
        _contextReady.remove(entry.key);
        _players.remove(entry.key);
      }
    }
    _tracks = next;
    if (payload['title'] is String) {
      final nextTitle = (payload['title'] as String).trim();
      if (nextTitle.isNotEmpty) _title = nextTitle;
    }
    if (payload['master'] is num) {
      _master = ((payload['master'] as num).toInt()).clamp(0, 100);
    }
    if (validTracks(payload['tracks']).isEmpty) {
      await _pause();
    } else if (payload['autoplay'] == true) {
      await _play();
    } else {
      await _pause();
    }
    await _write('draft', jsonEncode(_draft()));
  }

  Future<void> _add(Map<String, dynamic> payload) async {
    final id = '${payload['id'] ?? ''}';
    if (!available.contains(id)) throw StateError('这个声音暂时不可用。');
    if (contains(id)) return;
    if (_tracks.length >= 6) throw StateError('最多同时播放 6 种声音。');
    final volume = ((payload['volume'] as num?)?.toInt() ?? 45).clamp(0, 100);
    _tracks = [..._tracks, {'id': id, 'volume': volume}];
    if (_playing) {
      await _preparePlayer(id);
      final player = _player(id);
      await player.setVolume(_gainFor(_tracks.last));
      await player.resume();
    }
    await _write('draft', jsonEncode(_draft()));
  }

  Future<void> _remove(String id) async {
    _tracks = _tracks.where((t) => t['id'] != id).toList();
    final player = _players.remove(id);
    _loadedSources.remove(id);
    _contextReady.remove(id);
    if (player != null) await player.stop();
    await _write('draft', jsonEncode(_draft()));
  }

  Future<void> _setTrackVolume(String id, int value) async {
    final index = _tracks.indexWhere((t) => t['id'] == id);
    if (index < 0) throw StateError('此声音不在当前混音中。');
    final next = [..._tracks];
    next[index] = {'id': id, 'volume': value.clamp(0, 100)};
    _tracks = next;
    final player = _players[id];
    if (player != null) await player.setVolume(_gainFor(next[index]));
    await _write('draft', jsonEncode(_draft()));
  }

  Future<void> _importLocal() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3', 'm4a', 'ogg', 'flac'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) throw StateError('没有读到音频文件。');
    if (bytes.length > 50 * 1024 * 1024) {
      throw StateError('单个音频不能超过 50 MB。');
    }
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/tingyu',
    );
    await dir.create(recursive: true);
    final id = 'local:${DateTime.now().millisecondsSinceEpoch}';
    final ext = (picked.extension ?? 'audio').toLowerCase();
    final path = '${dir.path}/$id.$ext';
    await File(path).writeAsBytes(bytes, flush: true);
    final probe = AudioPlayer();
    try {
      await probe.setSourceDeviceFile(path);
      final duration = await probe.getDuration() ?? Duration.zero;
      final seconds = duration.inMilliseconds / 1000;
      if (seconds < 5 || seconds > 600) {
        try {
          await File(path).delete();
        } catch (_) {}
        throw StateError('音频时长需在 5 秒到 10 分钟之间。');
      }
      _locals = [
        ..._locals,
        {
          'id': id,
          'name': picked.name,
          'duration': seconds.round(),
          'size': bytes.length,
          'bytes': bytes.length,
          'path': path,
        },
      ];
      available.add(id);
      await _write('locals', jsonEncode(_locals));
    } finally {
      await probe.dispose();
    }
  }

  Future<void> _deleteLocal(String id) async {
    final index = _locals.indexWhere((local) => local['id'] == id);
    if (index < 0) return;
    final local = _locals[index];
    final player = _players.remove(id);
    _loadedSources.remove(id);
    _contextReady.remove(id);
    if (player != null) await player.stop();
    final path = local['path'] as String?;
    if (path != null && path.isNotEmpty) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    _locals = _locals.where((entry) => entry['id'] != id).toList();
    available.remove(id);
    _tracks = _tracks.where((track) => track['id'] != id).toList();
    await _write('locals', jsonEncode(_locals));
  }

  Future<void> _preview(String id) async {
    if (!available.contains(id)) throw StateError('这个声音暂时不可用。');
    await _stopPreview();
    final player = AudioPlayer();
    _previewPlayer = player;
    previewId = id;
    previewRemaining = 10;
    await player.setAudioContext(_mixContext);
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setSource(await _sourceFor(id));
    await player.setVolume((_master / 100 * 0.7).clamp(0.0, 1.0));
    await player.resume();
    notifyListeners();
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!identical(_previewPlayer, player)) {
        timer.cancel();
        return;
      }
      previewRemaining--;
      if (previewRemaining <= 0) {
        timer.cancel();
        unawaited(_stopPreview());
      }
      notifyListeners();
    });
  }

  Future<void> _stopPreview() async {
    _previewTimer?.cancel();
    _previewTimer = null;
    final player = _previewPlayer;
    _previewPlayer = null;
    previewId = null;
    previewRemaining = 0;
    if (player != null) {
      try {
        await player.stop();
        await player.dispose();
      } catch (_) {}
    }
  }

  void _setTimer(int seconds, int fadeSeconds) {
    if (seconds < 1 || seconds > 43200) {
      throw StateError('定时时长须为 1 至 720 分钟。');
    }
    _timerDuration = seconds;
    _timerFade = fadeSeconds.clamp(0, seconds);
    _timerGain = 1;
    if (_playing) {
      _timerDeadline = DateTime.now().add(Duration(seconds: seconds));
      _timerStatus = 'running';
      _ensureTicker();
    } else {
      _timerDeadline = null;
      _timerStatus = 'armed';
    }
    notifyListeners();
  }

  void _cancelTimer() {
    _timerTicker?.cancel();
    _timerTicker = null;
    _timerStatus = 'off';
    _timerDeadline = null;
    _timerGain = 1;
    unawaited(_applyVolumes());
    notifyListeners();
  }

  void _ensureTicker() {
    _timerTicker ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _tickTimer(),
    );
  }

  void _tickTimer() {
    if (_timerStatus != 'running' && _timerStatus != 'fading') return;
    final deadline = _timerDeadline;
    if (deadline == null) return;
    final left = deadline.difference(DateTime.now()).inMilliseconds / 1000;
    if (left <= 0) {
      _timerStatus = 'expired';
      _timerDeadline = null;
      _timerGain = 0;
      _timerTicker?.cancel();
      _timerTicker = null;
      _playing = false;
      for (final player in _players.values) {
        unawaited(player.pause());
      }
      unawaited(_applyVolumes());
      notifyListeners();
      return;
    }
    _timerStatus = _timerFade > 0 && left <= _timerFade ? 'fading' : 'running';
    if (_timerFade > 0 && left <= _timerFade) {
      final t = left / _timerFade;
      _timerGain = math.pow(math.sin(t * math.pi / 2), 2).toDouble();
      unawaited(_applyVolumes());
    }
    notifyListeners();
  }

  void setTheme(String value) {
    if (!['light', 'dark', 'system'].contains(value)) return;
    _theme = value;
    unawaited(_write('theme', value));
    AppState.instance.setThemeMode(switch (value) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    });
    notifyListeners();
  }

  void setReducedMotion(bool value) {
    reducedMotion = value;
    unawaited(_write('reducedMotion', '$value'));
    notifyListeners();
  }

  void setDefaultFade(int value) {
    defaultFade = [0, 15, 30, 60, 120].contains(value) ? value : 30;
    unawaited(_write('defaultFade', '$defaultFade'));
    notifyListeners();
  }

  void setFavoriteSort(String value) {
    if (!['recent', 'created', 'name'].contains(value)) return;
    favoriteSort = value;
    unawaited(_write('favoriteSort', value));
    notifyListeners();
  }

  void markLoaded([String? id]) {
    favoriteId = id;
    _baseline = signature;
    notifyListeners();
  }

  void touchFavorite(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = favorites
        .map((f) => f['id'] == id ? {...f, 'lastUsedAt': now} : f)
        .toList();
    favorites = next;
    unawaited(_saveFavorites());
    notifyListeners();
  }

  bool renameFavorite(String id, String name) {
    final title = name.trim();
    if (title.isEmpty) {
      error = '给这份混音起个名字。';
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    favorites = favorites
        .map((f) => f['id'] == id ? {...f, 'name': title, 'updatedAt': now} : f)
        .toList();
    unawaited(_saveFavorites());
    notifyListeners();
    return true;
  }

  bool saveFavorite(
    String name, {
    bool withTimer = false,
    bool update = false,
  }) {
    if (name.trim().isEmpty || tracks.isEmpty) {
      error = tracks.isEmpty ? '先加入至少一种声音。' : '给这份混音起个名字。';
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic>? existing;
    for (final favorite in favorites) {
      if (favorite['id'] == favoriteId) {
        existing = favorite;
        break;
      }
    }
    final id = update && favoriteId != null ? favoriteId! : now.toString();
    final item = <String, dynamic>{
      'id': id,
      'name': name.trim(),
      'tracks': tracks,
      'master': master,
      'seconds': withTimer && hasTimer ? timer['duration'] : null,
      'fade': withTimer && hasTimer ? timer['fade'] : null,
      'createdAt': update && existing != null
          ? existing['createdAt'] ?? now
          : now,
      'updatedAt': now,
      'lastUsedAt': now,
    };
    favorites = [item, ...favorites.where((f) => f['id'] != id)];
    unawaited(_saveFavorites());
    markLoaded(id);
    return true;
  }

  bool deleteFavorite(String id) {
    favorites = favorites.where((v) => v['id'] != id).toList();
    unawaited(_saveFavorites());
    if (favoriteId == id) favoriteId = null;
    notifyListeners();
    return true;
  }

  Future<void> _saveFavorites() =>
      _write('favorites', jsonEncode(favorites));

  @override
  void dispose() {
    _timerTicker?.cancel();
    _previewTimer?.cancel();
    super.dispose();
  }
}
