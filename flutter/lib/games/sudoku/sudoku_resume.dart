import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../../services/prefs.dart';
import 'sudoku_modes.dart';
import 'sudoku_puzzle.dart';

/// 暂停后退出保留进度的有效期。
const Duration sudokuResumeTtl = Duration(hours: 2);

/// 一局被暂停并退出时的完整快照。
///
/// 题目本体不整份序列化：只存 [seed] + 题面指纹 [fingerprint]，
/// 恢复时用同一 seed 重新生成并校验 givens，避免存档随内核改动而错题。
class SudokuResume {
  const SudokuResume({
    required this.modeKey,
    required this.difficulty,
    required this.seed,
    required this.fingerprint,
    required this.board,
    required this.notes,
    required this.given,
    required this.errors,
    required this.hints,
    required this.seconds,
    required this.layer,
    required this.focusGrid,
    required this.selected,
    required this.noteMode,
    required this.cubeFace,
    required this.savedAt,
  });

  final String modeKey;
  final SudokuDifficulty difficulty;
  final int seed;

  /// 题面指纹（givens 逗号拼接），恢复时用于确认题目一致。
  final String fingerprint;
  final List<int> board;

  /// 每格笔记，元素为 "1,3,5" 形式的逗号串。
  final List<String> notes;
  final List<bool> given;
  final int errors;
  final int hints;
  final int seconds;
  final int layer;
  final int focusGrid;
  final int selected;
  final bool noteMode;
  final SudokuCubeFace cubeFace;
  final DateTime savedAt;

  String get modeLabel {
    for (final mode in kSudokuModes) {
      if (mode.key == modeKey) {
        return mode.variant == SudokuVariant.classic ? '经典九宫' : mode.title;
      }
    }
    return '数独';
  }

  String get difficultyLabel => difficulty.label;

  Duration get ttl => sudokuResumeTtl;

  bool isExpired(DateTime now) => !now.isBefore(savedAt.add(sudokuResumeTtl));

  Duration remaining(DateTime now) {
    final left = savedAt.add(sudokuResumeTtl).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  String remainingLabel(DateTime now) {
    final left = remaining(now);
    if (left == Duration.zero) return '已过期';
    final hours = left.inHours;
    final minutes = left.inMinutes % 60;
    if (hours > 0) {
      return minutes > 0 ? '剩余 $hours 小时 $minutes 分' : '剩余 $hours 小时';
    }
    return '剩余 ${math.max(1, minutes)} 分';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'mode': modeKey,
    'difficulty': difficulty.key,
    'seed': seed,
    'fp': fingerprint,
    'board': board.join(','),
    'given': [for (final v in given) v ? '1' : '0'].join(),
    'notes': notes,
    'errors': errors,
    'hints': hints,
    'seconds': seconds,
    'layer': layer,
    'focusGrid': focusGrid,
    'selected': selected,
    'noteMode': noteMode,
    'face': cubeFace.name,
    'savedAt': savedAt.millisecondsSinceEpoch,
  };

  String encode() => jsonEncode(toJson());

  /// 解析存档；任何字段异常都返回 null，调用方按“无存档”处理。
  static SudokuResume? decode(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      if ((data['v'] as num?)?.toInt() != 1) return null;

      final modeKey = data['mode'];
      if (modeKey is! String) return null;
      if (!kSudokuModes.any((m) => m.key == modeKey)) return null;

      final difficultyKey = data['difficulty'];
      if (difficultyKey is! String) return null;
      SudokuDifficulty? difficulty;
      for (final d in SudokuDifficulty.values) {
        if (d.key == difficultyKey) difficulty = d;
      }
      if (difficulty == null) return null;

      final seed = (data['seed'] as num?)?.toInt();
      final fingerprint = data['fp'];
      if (seed == null || fingerprint is! String || fingerprint.isEmpty) {
        return null;
      }

      final board = _ints(data['board']);
      if (board == null || board.isEmpty) return null;
      if (board.any((v) => v < 0 || v > 9)) return null;

      final givenRaw = data['given'];
      if (givenRaw is! String || givenRaw.length != board.length) return null;
      final given = <bool>[for (final ch in givenRaw.split('')) ch == '1'];

      final notesRaw = data['notes'];
      final notes = <String>[];
      if (notesRaw is List) {
        for (final item in notesRaw) {
          notes.add(item is String ? item : '');
        }
      }
      while (notes.length < board.length) {
        notes.add('');
      }
      if (notes.length != board.length) return null;

      final errors = (data['errors'] as num?)?.toInt() ?? 0;
      final hints = (data['hints'] as num?)?.toInt() ?? 3;
      final seconds = (data['seconds'] as num?)?.toInt() ?? 0;
      final layer = (data['layer'] as num?)?.toInt() ?? 0;
      final focusGrid = (data['focusGrid'] as num?)?.toInt() ?? 0;
      final selected = (data['selected'] as num?)?.toInt() ?? -1;
      final savedAt = (data['savedAt'] as num?)?.toInt();
      if (savedAt == null) return null;
      if (errors < 0 || seconds < 0) return null;
      if (hints < 0 || hints > 3) return null;
      if (layer < 0 || focusGrid < 0) return null;

      final faceName = data['face'];
      var cubeFace = SudokuCubeFace.top;
      if (faceName is String) {
        for (final face in SudokuCubeFace.values) {
          if (face.name == faceName) cubeFace = face;
        }
      }

      return SudokuResume(
        modeKey: modeKey,
        difficulty: difficulty,
        seed: seed,
        fingerprint: fingerprint,
        board: board,
        notes: notes,
        given: given,
        errors: errors,
        hints: hints,
        seconds: seconds,
        layer: layer,
        focusGrid: focusGrid,
        selected: selected.clamp(-1, board.length - 1).toInt(),
        noteMode: data['noteMode'] == true,
        cubeFace: cubeFace,
        savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt),
      );
    } catch (_) {
      return null;
    }
  }

  static List<int>? _ints(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final out = <int>[];
    for (final part in raw.split(',')) {
      final value = int.tryParse(part);
      if (value == null) return null;
      out.add(value);
    }
    return out;
  }
}

/// 单局存档的读写。只保留最近一局，2 小时后自动失效。
class SudokuResumeStore {
  static SudokuResume? load({DateTime? now}) {
    final raw = Prefs.getString(PrefKeys.sudokuResume);
    if (raw == null || raw.isEmpty) return null;
    final resume = SudokuResume.decode(raw);
    if (resume == null || resume.isExpired(now ?? DateTime.now())) {
      unawaited(clear());
      return null;
    }
    return resume;
  }

  static Future<void> save(SudokuResume resume) =>
      Prefs.setString(PrefKeys.sudokuResume, resume.encode());

  static Future<void> clear() => Prefs.setString(PrefKeys.sudokuResume, null);
}
