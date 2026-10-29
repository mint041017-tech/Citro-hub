import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tingyu_models.dart';

@JS('tingyuCommand')
external JSPromise<JSString> _command(JSString action, JSString payload);
@JS('tingyuSnapshot')
external JSString _snapshot();
@JS('tingyuRead')
external JSString _read(JSString key);
@JS('tingyuWrite')
external JSBoolean _write(JSString key, JSString value);

class NookController extends ChangeNotifier {
  static final NookController instance = NookController();

  NookController() {
    available = sounds.map((sound) => sound.id).toSet();
    for (final sound in sounds) {
      if (sound.synthesized) kinds[sound.id] = 'synth';
    }
    try {
      theme = _read('theme'.toJS).toDart;
      if (!['light', 'dark', 'system'].contains(theme)) theme = 'system';
      reducedMotion = _read('reducedMotion'.toJS).toDart == 'true';
      final fade = int.tryParse(_read('defaultFade'.toJS).toDart);
      if (fade != null && [0, 15, 30, 60, 120].contains(fade)) {
        defaultFade = fade;
      }
      final sort = _read('favoriteSort'.toJS).toDart;
      if (['recent', 'created', 'name'].contains(sort)) favoriteSort = sort;
      final saved = _read('favorites'.toJS).toDart;
      if (saved.isNotEmpty) {
        final value = jsonDecode(saved);
        if (value is List) {
          favorites = value
              .whereType<Map>()
              .where((v) => v['id'] is String && v['name'] is String)
              .map((v) => Map<String, dynamic>.from(v))
              .toList();
        }
      }
    } catch (_) {
      error = '本地设置没有读取成功，仍可使用内置声音。';
    }
    refresh();
    _baseline = signature;
    ready = state.isNotEmpty;
    _poll = Timer.periodic(const Duration(milliseconds: 300), (_) => refresh());
  }

  Map<String, dynamic> state = {};
  List<Map<String, dynamic>> favorites = [];
  Set<String> available = {};
  Map<String, String> kinds = {};
  String theme = 'system';
  String favoriteSort = 'recent';
  int defaultFade = 30;
  bool reducedMotion = false;
  bool ready = false;
  String? error;
  String? favoriteId;
  bool fullFontLoaded = false;
  bool _loadingFullFont = false;
  String _baseline = '';
  String _lastSnapshot = '';
  Timer? _poll;

  String get fontFamily => fullFontLoaded ? 'NookFull' : 'NookUI';
  bool get supportsImport => true;

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
      // The interface subset already covers all built-in labels.
    } finally {
      _loadingFullFont = false;
    }
  }

  List<Map<String, dynamic>> get tracks => validTracks(state['tracks']);
  List<Map<String, dynamic>> get locals => (state['locals'] as List? ?? [])
      .whereType<Map>()
      .map((v) => Map<String, dynamic>.from(v))
      .toList();
  bool get playing => state['playing'] == true;
  bool get busy => state['busy'] == true;
  int get master => ((state['master'] as num?) ?? 70).round();
  String get title => state['title'] as String? ?? '窗边一页';
  String? get previewId => state['previewId'] as String?;
  num get previewRemaining =>
      previewId == null ? 0 : ((state['previewRemaining'] as num?) ?? 0);
  Map<String, dynamic> get timer => state['timer'] is Map
      ? Map<String, dynamic>.from(state['timer'])
      : {'status': 'off', 'remaining': 0};
  String get timerStatus => timer['status'] as String? ?? 'off';
  num get remaining => timer['remaining'] as num? ?? 0;
  int get timerDuration => ((timer['duration'] as num?) ?? 0).round();
  int get timerFade => ((timer['fade'] as num?) ?? 0).round();
  bool get hasTimer => ['armed', 'running', 'fading'].contains(timerStatus);
  String get signature => jsonEncode({'tracks': tracks, 'master': master});
  bool get dirty => ready && _baseline.isNotEmpty && signature != _baseline;
  String get timerLabel => switch (timerStatus) {
    'armed' => '播放后计时',
    'running' => clockText(remaining),
    'fading' => '渐弱 ${clockText(remaining)}',
    'expired' => '已定时结束',
    _ => '定时关闭',
  };

  int _stamp(Map<String, dynamic> item, String key) =>
      item[key] is num ? (item[key] as num).toInt() : 0;

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
    ...locals.map(
      (m) => SoundSpec(
        m['id'] as String,
        m['name'] as String? ?? '本地声音',
        '本地',
        '${clockText(m['duration'] as num? ?? 0)}，保存在此浏览器',
        Icons.audio_file_outlined,
      ),
    ),
  ];

  SoundSpec sound(String id) =>
      library.where((s) => s.id == id).firstOrNull ??
      sounds.where((s) => s.id == id).firstOrNull ??
      SoundSpec(id, '不可用的声音', '本地', '请重新导入音频', Icons.audio_file_outlined);
  bool contains(String id) => tracks.any((t) => t['id'] == id);

  Future<void> initialize() async {
    try {
      await send('init');
      _baseline = signature;
      if (favorites.isNotEmpty || locals.isNotEmpty) {
        unawaited(loadFullFont());
      }
    } catch (_) {
      error = '本地音频信息没有读取完成，仍可试听内置声音。';
    }
    ready = true;
    notifyListeners();
  }

  void refresh() {
    try {
      final raw = _snapshot().toDart;
      if (raw == _lastSnapshot) return;
      _lastSnapshot = raw;
      state = Map<String, dynamic>.from(jsonDecode(raw));
      notifyListeners();
    } catch (_) {
      error = '声音状态暂时无法读取。';
    }
  }

  Future<bool> send(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    try {
      final result =
          jsonDecode(
                (await _command(
                  action.toJS,
                  jsonEncode(payload).toJS,
                ).toDart).toDart,
              )
              as Map;
      error = result['ok'] == true
          ? null
          : result['error'] as String? ?? '操作没有完成，请再试一次。';
      refresh();
      notifyListeners();
      return result['ok'] == true;
    } catch (_) {
      error = '浏览器未能完成音频操作，请重试。';
      notifyListeners();
      return false;
    }
  }

  bool persist(String key, Object value) {
    try {
      if (!_write(
        key.toJS,
        (value is String ? value : jsonEncode(value)).toJS,
      ).toDart) {
        error = '浏览器未允许保存数据，请检查存储空间或隐私设置。';
        return false;
      }
      return true;
    } catch (_) {
      error = '本地保存失败，请检查浏览器存储设置。';
      return false;
    }
  }

  void setTheme(String value) {
    theme = value;
    persist('theme', value);
    notifyListeners();
  }

  void setReducedMotion(bool value) {
    reducedMotion = value;
    persist('reducedMotion', value.toString());
    notifyListeners();
  }

  void setDefaultFade(int value) {
    defaultFade = [0, 15, 30, 60, 120].contains(value) ? value : 30;
    persist('defaultFade', '$defaultFade');
    notifyListeners();
  }

  void setFavoriteSort(String value) {
    if (!['recent', 'created', 'name'].contains(value)) return;
    favoriteSort = value;
    persist('favoriteSort', value);
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
    if (persist('favorites', next)) {
      favorites = next;
      notifyListeners();
    }
  }

  bool renameFavorite(String id, String name) {
    final title = name.trim();
    if (title.isEmpty) {
      error = '给这份混音起个名字。';
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = favorites
        .map((f) => f['id'] == id ? {...f, 'name': title, 'updatedAt': now} : f)
        .toList();
    if (!persist('favorites', next)) return false;
    favorites = next;
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
    final next = [item, ...favorites.where((f) => f['id'] != id)];
    if (!persist('favorites', next)) return false;
    favorites = next;
    markLoaded(id);
    return true;
  }

  bool deleteFavorite(String id) {
    final next = favorites.where((v) => v['id'] != id).toList();
    if (!persist('favorites', next)) return false;
    favorites = next;
    if (favoriteId == id) favoriteId = null;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
