import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent campaign progress: unlocked levels, completions, stars and the
/// last played level. Levels unlock sequentially; a locked level is never
/// selectable.
class ProgressStore {
  static const _kUnlocked = 'kw_unlocked';
  static const _kCompleted = 'kw_completed';
  static const _kStars = 'kw_stars';
  static const _kLastPlayed = 'kw_last_played';
  static const _kCheckpoint = 'kw_checkpoint';

  final SharedPreferences? _prefs;
  int _highestUnlocked;
  final Set<int> _completed;
  final Map<int, int> _stars;
  int _lastPlayed;
  String? _checkpoint;

  ProgressStore.memory()
    : _prefs = null,
      _highestUnlocked = 1,
      _completed = <int>{},
      _stars = <int, int>{},
      _lastPlayed = 1,
      _checkpoint = null;

  ProgressStore._(
    this._prefs,
    this._highestUnlocked,
    this._completed,
    this._stars,
    this._lastPlayed,
    this._checkpoint,
  );

  static Future<ProgressStore> load({int totalLevels = 72}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final unlocked = (prefs.getInt(_kUnlocked) ?? 1).clamp(1, totalLevels);
      final last = (prefs.getInt(_kLastPlayed) ?? 1).clamp(1, totalLevels);
      final completed = <int>{};
      for (final raw in prefs.getStringList(_kCompleted) ?? const <String>[]) {
        final n = int.tryParse(raw);
        if (n != null && n >= 1 && n <= totalLevels) completed.add(n);
      }
      final stars = <int, int>{};
      for (final part in (prefs.getString(_kStars) ?? '').split(',')) {
        final bits = part.split(':');
        if (bits.length != 2) continue;
        final n = int.tryParse(bits[0]);
        final s = int.tryParse(bits[1]);
        if (n != null && s != null && n >= 1 && n <= totalLevels) {
          stars[n] = s.clamp(1, 3);
        }
      }
      final maxCompleted = completed.isEmpty
          ? 0
          : completed.reduce(math.max);
      final highest = math.max(
        math.max(unlocked, last),
        math.min(totalLevels, maxCompleted + 1),
      );
      final checkpoint = prefs.getString(_kCheckpoint);
      return ProgressStore._(
        prefs,
        highest,
        completed,
        stars,
        last,
        checkpoint,
      );
    } catch (_) {
      // A broken/missing store must never prevent the game from starting.
      return ProgressStore.memory();
    }
  }

  int get highestUnlocked => _highestUnlocked;
  int get lastPlayed => _lastPlayed;
  int get completedCount => _completed.length;
  String? get checkpoint => _checkpoint;
  bool get hasCheckpoint =>
      _checkpoint != null && _checkpoint!.trim().isNotEmpty;

  bool isUnlocked(int zeroBasedIndex) =>
      zeroBasedIndex >= 0 && zeroBasedIndex < _highestUnlocked;

  bool isCompleted(int zeroBasedIndex) =>
      _completed.contains(zeroBasedIndex + 1);

  int starsFor(int zeroBasedIndex) => _stars[zeroBasedIndex + 1] ?? 0;

  Future<void> markPlayed(int zeroBasedIndex, {int totalLevels = 72}) async {
    final one = zeroBasedIndex + 1;
    if (one < 1 || one > totalLevels || one > _highestUnlocked) return;
    _lastPlayed = one;
    await _persist();
  }

  Future<void> complete(
    int zeroBasedIndex,
    int stars, {
    int totalLevels = 72,
  }) async {
    final one = zeroBasedIndex + 1;
    if (one < 1 || one > totalLevels) return;
    _completed.add(one);
    _stars[one] = math.max(_stars[one] ?? 0, stars.clamp(1, 3));
    _highestUnlocked = math.max(
      _highestUnlocked,
      math.min(totalLevels, one + 1),
    );
    // Continue points at the newly unlocked next level; on the final level
    // stay on the final level.
    _lastPlayed = one < totalLevels ? one + 1 : one;
    _checkpoint = null;
    await _persist();
    await _clearCheckpointPersist();
  }

  Future<void> saveCheckpoint(String json) async {
    _checkpoint = json;
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setString(_kCheckpoint, json);
    } catch (_) {
      // Best-effort; in-memory checkpoint remains valid.
    }
  }

  Future<void> clearCheckpoint() async {
    _checkpoint = null;
    await _clearCheckpointPersist();
  }

  Future<void> _clearCheckpointPersist() async {
    final p = _prefs;
    if (p == null) return;
    try {
      await p.remove(_kCheckpoint);
    } catch (_) {}
  }

  Future<void> _persist() async {
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setInt(_kUnlocked, _highestUnlocked);
      await p.setInt(_kLastPlayed, _lastPlayed);
      final completed = _completed.toList()..sort();
      await p.setStringList(
        _kCompleted,
        <String>[for (final n in completed) '$n'],
      );
      await p.setString(
        _kStars,
        <String>[
          for (final entry in _stars.entries) '${entry.key}:${entry.value}',
        ].join(','),
      );
    } catch (_) {
      // Persistence is best-effort; the in-memory state stays valid.
    }
  }
}
