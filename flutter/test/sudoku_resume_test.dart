import 'dart:convert';

import 'package:citro/games/sudoku/sudoku_modes.dart';
import 'package:citro/games/sudoku/sudoku_puzzle.dart';
import 'package:citro/games/sudoku/sudoku_resume.dart';
import 'package:citro/services/prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SudokuResume _resume({DateTime? savedAt}) {
  final board = List<int>.filled(81, 0);
  board[0] = 5;
  final given = List<bool>.filled(81, false);
  given[0] = true;
  return SudokuResume(
    modeKey: 'classic',
    difficulty: SudokuDifficulty.medium,
    seed: 20260101,
    fingerprint: List<int>.filled(81, 0).join(','),
    board: board,
    notes: List<String>.generate(81, (i) => i == 0 ? '1,2' : ''),
    given: given,
    errors: 2,
    hints: 2,
    seconds: 123,
    layer: 0,
    focusGrid: 0,
    selected: 40,
    noteMode: true,
    cubeFace: SudokuCubeFace.top,
    savedAt: savedAt ?? DateTime.now(),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  test('存档编码后可原样解码', () {
    final resume = _resume();
    final decoded = SudokuResume.decode(resume.encode());
    expect(decoded, isNotNull);
    expect(decoded!.modeKey, 'classic');
    expect(decoded.difficulty, SudokuDifficulty.medium);
    expect(decoded.seed, 20260101);
    expect(decoded.board[0], 5);
    expect(decoded.given[0], isTrue);
    expect(decoded.notes[0], '1,2');
    expect(decoded.errors, 2);
    expect(decoded.hints, 2);
    expect(decoded.seconds, 123);
    expect(decoded.selected, 40);
    expect(decoded.noteMode, isTrue);
    expect(decoded.cubeFace, SudokuCubeFace.top);
    expect(
      decoded.savedAt.millisecondsSinceEpoch,
      resume.savedAt.millisecondsSinceEpoch,
    );
  });

  test('两小时内有效，超过两小时失效', () {
    final now = DateTime(2026, 11, 3, 12);
    final fresh = _resume(savedAt: now.subtract(const Duration(hours: 1)));
    expect(fresh.isExpired(now), isFalse);
    expect(fresh.remaining(now), const Duration(hours: 1));

    final edge = _resume(savedAt: now.subtract(const Duration(hours: 2)));
    expect(edge.isExpired(now), isTrue);
    expect(edge.remaining(now), Duration.zero);

    final stale = _resume(savedAt: now.subtract(const Duration(hours: 3)));
    expect(stale.isExpired(now), isTrue);
  });

  test('剩余时间文案可直接展示', () {
    final now = DateTime(2026, 11, 3, 12);
    final resume = _resume(
      savedAt: now.subtract(const Duration(hours: 1, minutes: 17)),
    );
    expect(resume.remainingLabel(now), '剩余 43 分');
    final nearly = _resume(savedAt: now.subtract(const Duration(minutes: 5)));
    expect(nearly.remainingLabel(now), '剩余 1 小时 55 分');
  });

  test('存档写入后可读取，过期读取会自动清理', () async {
    final resume = _resume();
    await SudokuResumeStore.save(resume);
    final loaded = SudokuResumeStore.load();
    expect(loaded, isNotNull);
    expect(loaded!.seed, resume.seed);

    final stale = _resume(
      savedAt: DateTime.now().subtract(const Duration(hours: 3)),
    );
    await SudokuResumeStore.save(stale);
    expect(SudokuResumeStore.load(), isNull);
    expect(Prefs.getString(PrefKeys.sudokuResume), isNull);
  });

  test('损坏或不合法的存档返回 null', () {
    expect(SudokuResume.decode('not-json'), isNull);
    expect(SudokuResume.decode('{}'), isNull);

    final badMode = _resume().toJson()..['mode'] = 'unknown-mode';
    expect(SudokuResume.decode(_json(badMode)), isNull);

    final badGiven = _resume().toJson()..['given'] = '101';
    expect(SudokuResume.decode(_json(badGiven)), isNull);

    final badBoard = _resume().toJson()..['board'] = '1,2,x';
    expect(SudokuResume.decode(_json(badBoard)), isNull);

    final noSavedAt = _resume().toJson()..remove('savedAt');
    expect(SudokuResume.decode(_json(noSavedAt)), isNull);
  });

  test('清除存档后读取为空', () async {
    await SudokuResumeStore.save(_resume());
    expect(SudokuResumeStore.load(), isNotNull);
    await SudokuResumeStore.clear();
    expect(SudokuResumeStore.load(), isNull);
  });
}

String _json(Map<String, Object?> value) => const JsonEncoder().convert(value);
