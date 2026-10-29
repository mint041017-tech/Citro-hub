import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/game_sfx.dart';
import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'game_ui.dart';
import 'sudoku/sudoku_board_view.dart';
import 'sudoku/sudoku_cube_face_view.dart';
import 'sudoku/sudoku_cube_view.dart';
import 'sudoku/sudoku_kernel.dart';
import 'sudoku/sudoku_mode_select.dart';

/// 统一数独入口。
///
/// 进入先选模式：经典 / 异形（九宫、雪花、2/3/4/5/8/13 重叠）/ 高级阶数
/// （奇偶、对角、不等式、杀手、3D）。所有题目由纯 Dart 内核唯一解复核。
class GameSudokuPage extends StatefulWidget {
  const GameSudokuPage({
    super.key,
    this.initialModeKey,
    this.initialDifficulty,
    this.initialSeed,
  });

  /// 可选的直达模式（深链/测试）；为空时先显示模式选择。
  final String? initialModeKey;
  final SudokuDifficulty? initialDifficulty;

  /// 可选的固定随机种子（测试/复现用）；为空时每局随机。
  final int? initialSeed;

  @override
  State<GameSudokuPage> createState() => _GameSudokuPageState();
}

class _SudokuMove {
  const _SudokuMove({
    required this.index,
    required this.value,
    required this.notes,
    required this.given,
    this.clearedNotes = const {},
  });

  final int index;
  final int value;
  final Set<int> notes;
  final bool given;
  final Map<int, Set<int>> clearedNotes;
}

class _GameSudokuPageState extends State<GameSudokuPage> {
  SudokuModeSpec? _mode;
  SudokuDifficulty _difficulty = SudokuDifficulty.medium;
  SudokuPuzzle? _puzzle;
  List<int> _board = const [];
  List<bool> _given = const [];
  List<Set<int>> _notes = const [];
  Set<int> _conflicts = const {};
  final List<_SudokuMove> _history = [];
  int _selected = -1;
  int _errors = 0;
  int _hints = 3;
  int _seconds = 0;
  bool _noteMode = false;
  bool _paused = false;
  bool _over = false;
  bool _win = false;
  bool _roundCounted = false;
  bool _loading = false;
  bool _hideLargeNotice = false;
  String? _error;
  int _layer = 0;
  int _focusGrid = 0;
  SudokuCubeFace _cubeFace = SudokuCubeFace.top;
  bool _cubeFlat = false;
  bool _cubeFlatInit = false;
  int _revision = 0;
  int _lastScore = 0;
  Timer? _timer;
  final ValueNotifier<String> _progress = ValueNotifier<String>('数独 · 选择模式');
  final FocusNode _keyFocus = FocusNode(debugLabel: 'sudoku-keyboard');

  bool get _keyboardEnabled => platform.isWindows || kIsWeb;

  @override
  void initState() {
    super.initState();
    _progress.value = '数独 · 选择模式';
    final key = widget.initialModeKey;
    if (key != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final mode = sudokuModeByKey(key);
        _startMode(mode, widget.initialDifficulty ?? mode.defaultDifficulty);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubeFlatInit) return;
    _cubeFlatInit = true;
    _cubeFlat = MediaQuery.sizeOf(context).shortestSide < 600;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  bool get _isLargeBoard =>
      _mode?.variant == SudokuVariant.overlap ||
      _mode?.variant == SudokuVariant.cube3d;

  bool _isPhone(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.shortestSide >= 600) return false;
    if (platform.isDesktop) return false;
    return true;
  }

  int get _maxErrors {
    final v = _mode?.variant;
    if (v == SudokuVariant.overlap || v == SudokuVariant.cube3d) return 8;
    if (v == SudokuVariant.killer || v == SudokuVariant.inequality) return 6;
    return 5;
  }

  int get _baseScore {
    final mode = _mode!;
    if (mode.variant == SudokuVariant.classic) {
      return switch (_difficulty) {
        SudokuDifficulty.easy => 3600,
        SudokuDifficulty.medium => 5400,
        SudokuDifficulty.hard => 7200,
        SudokuDifficulty.expert => 9000,
      };
    }
    final weight = switch (mode.variant) {
      SudokuVariant.jigsaw => 1,
      SudokuVariant.snowflake => 2,
      SudokuVariant.overlap => 2 + mode.overlapCount ~/ 4,
      SudokuVariant.evenOdd => 2,
      SudokuVariant.diagonal => 1,
      SudokuVariant.inequality => 3,
      SudokuVariant.killer => 4,
      SudokuVariant.cube3d => 5,
      SudokuVariant.classic => 0,
    };
    return 2400 +
        weight * 600 +
        _difficulty.tier * 900 +
        (mode.isOverlap ? mode.overlapCount * 120 : 0);
  }

  String get _scoreKey =>
      'sudoku:${_mode!.rankKey(_difficulty)}';

  String get _modeLabel =>
      _mode!.variant == SudokuVariant.classic ? '经典九宫' : _mode!.title;

  String _cubeFaceLabel(SudokuCubeFace face) => switch (face) {
    SudokuCubeFace.top => '顶面',
    SudokuCubeFace.frontLeft => '左面',
    SudokuCubeFace.frontRight => '右面',
  };

  List<(String, String)> get _rankDifficulties {
    final mode = _mode!;
    if (mode.key == 'windmill') return mode.rankDifficulties;
    if (!mode.isOverlap) return mode.rankDifficulties;
    return [
      for (final m in kSudokuModes.where(
        (m) => m.isOverlap && m.key != 'windmill',
      ))
        (m.rankKey(m.defaultDifficulty), m.title),
    ];
  }

  String get _rankInitial => _mode!.rankKey(_difficulty);

  Future<void> _startMode(
    SudokuModeSpec mode,
    SudokuDifficulty difficulty,
  ) async {
    if (_isPhone(context) && _isLargeBoardMode(mode)) {
      final ok = await _showLargeBoardHint(mode);
      if (!ok || !mounted) return;
    }
    setState(() {
      _mode = mode;
      _difficulty = difficulty;
      _puzzle = null;
      _board = const [];
      _given = const [];
      _notes = const [];
      _conflicts = const {};
      _history.clear();
      _selected = -1;
      _errors = 0;
      _hints = 3;
      _seconds = 0;
      _noteMode = false;
      _paused = false;
      _over = false;
      _win = false;
      _roundCounted = false;
      _loading = true;
      _hideLargeNotice = false;
      _error = null;
      _layer = 0;
      _lastScore = 0;
      _focusGrid = 0;
      _cubeFace = SudokuCubeFace.top;
      _revision++;
    });
    _progress.value = '${mode.title} · ${difficulty.label} · 正在生成唯一解…';
    await _loadPuzzle();
  }

  bool _isLargeBoardMode(SudokuModeSpec mode) =>
      mode.variant == SudokuVariant.overlap ||
      mode.variant == SudokuVariant.cube3d;

  Future<void> _loadPuzzle() async {
    final mode = _mode;
    if (mode == null) return;
    final difficulty = _difficulty;
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _puzzle = null;
      _over = false;
      _paused = false;
      _win = false;
      _roundCounted = false;
      _revision++;
    });
    _progress.value = '${mode.title} · ${difficulty.label} · 正在生成唯一解…';
    await Future<void>.delayed(const Duration(milliseconds: 16));
    try {
      SudokuPuzzle? puzzle;
      for (var attempt = 0; attempt < 3; attempt++) {
        final seed = widget.initialSeed != null
            ? widget.initialSeed! + attempt
            : math.Random().nextInt(1 << 31);
        puzzle = await SudokuEngine.generateAsync(
          mode,
          difficulty,
          seed: seed,
        );
        if (!mounted || _mode != mode || _difficulty != difficulty) return;
        if (puzzle.difficultyMet) break;
      }
      if (puzzle == null) {
        throw StateError('生成结果为空');
      }
      final generated = puzzle;
      setState(() {
        _puzzle = generated;
        _board = List<int>.from(generated.givens);
        _given = [for (final v in generated.givens) v != 0];
        _notes = List<Set<int>>.generate(
          generated.cellCount,
          (_) => <int>{},
        );
        _conflicts = SudokuEngine.conflicts(generated, _board);
        _history.clear();
        _selected = _keyboardEnabled ? _firstEmptyCell() : -1;
        _errors = 0;
        _hints = 3;
        _seconds = 0;
        _noteMode = false;
        _paused = false;
        _over = false;
        _win = false;
        _roundCounted = false;
          _loading = false;
        _error = null;
        _layer = 0;
        _focusGrid = generated.variant == SudokuVariant.overlap ? 0 : -1;
        _cubeFace = SudokuCubeFace.top;
        _lastScore = 0;
        _revision++;
      });
      _syncProgress();
      _startTimer();
      if (_keyboardEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _keyFocus.requestFocus();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '生成失败：$e';
        _revision++;
      });
      _progress.value = '${mode.title} · 生成失败';
    }
  }

  void _newGame() {
    if (_mode == null || _loading) return;
    _loadPuzzle();
  }

  void _changeDifficulty(SudokuDifficulty difficulty) {
    if (_mode == null || _difficulty == difficulty || _loading) return;
    setState(() => _difficulty = difficulty);
    _loadPuzzle();
  }

  Future<bool> _showLargeBoardHint(SudokuModeSpec mode) async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        maxWidth: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('大棋盘提示', style: ctx.heading(size: 25)),
            const SizedBox(height: 10),
            Text(
              '「${mode.title}」的棋盘较大，手机屏幕上格子会比较小。\n'
              '建议使用 iPad / 桌面端 / 网页端游玩；仍可在手机上双指放大。',
              textAlign: TextAlign.center,
              style: ctx.body(size: 13, color: ctx.c.ink2, height: 1.75),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GameActionButton(
                    label: '换一个模式',
                    expand: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameActionButton(
                    label: '仍然开始',
                    primary: true,
                    expand: true,
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<bool> _confirmLeaveGame() async {
    if (_puzzle == null || _over) return true;
    final filled = _board.where((v) => v != 0).length;
    final givens = _puzzle!.givens.where((v) => v != 0).length;
    if (filled <= givens) return true;
    final leave = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        maxWidth: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('返回模式选择？', style: ctx.heading(size: 24)),
            const SizedBox(height: 8),
            Text(
              '当前这一局还没有完成，返回后会放弃进度。',
              textAlign: TextAlign.center,
              style: ctx.body(size: 12.5, color: ctx.c.inkSoft, height: 1.7),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GameActionButton(
                    label: '继续本局',
                    expand: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameActionButton(
                    label: '放弃并返回',
                    primary: true,
                    expand: true,
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return leave == true;
  }

  Future<void> _backToModes() async {
    if (!await _confirmLeaveGame() || !mounted) return;
    _timer?.cancel();
    setState(() {
      _mode = null;
      _puzzle = null;
      _board = const [];
      _given = const [];
      _notes = const [];
      _conflicts = const {};
      _history.clear();
      _selected = -1;
      _loading = false;
      _error = null;
      _paused = false;
      _over = false;
      _win = false;
      _roundCounted = false;
      _layer = 0;
      _focusGrid = 0;
      _cubeFace = SudokuCubeFace.top;
      _revision++;
    });
    _progress.value = '数独 · 选择模式';
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused || _over || _loading) return;
      setState(() => _seconds++);
      _syncProgress();
    });
  }

  bool _isActive(int index) {
    final puzzle = _puzzle;
    if (puzzle == null || index < 0) return false;
    if (index >= puzzle.active.length) return true;
    return puzzle.active[index];
  }

  int _firstEmptyCell() {
    final puzzle = _puzzle;
    if (puzzle == null) return -1;
    for (var i = 0; i < _board.length; i++) {
      if (_isActive(i) && _board[i] == 0) return i;
    }
    for (var i = 0; i < _board.length; i++) {
      if (_isActive(i)) return i;
    }
    return 0;
  }

  int _firstCellInLayer(int layer) {
    final puzzle = _puzzle;
    if (puzzle == null) return -1;
    final base = layer * puzzle.rows * puzzle.cols;
    for (var i = base; i < base + puzzle.rows * puzzle.cols; i++) {
      if (_isActive(i) && _board[i] == 0) return i;
    }
    for (var i = base; i < base + puzzle.rows * puzzle.cols; i++) {
      if (_isActive(i)) return i;
    }
    return base;
  }

  int _gridIndexFor(int index) {
    final puzzle = _puzzle;
    if (puzzle == null || index < 0) return 0;
    final row = index ~/ puzzle.cols;
    final col = index % puzzle.cols;
    for (var gi = 0; gi < puzzle.grids.length; gi++) {
      final g = puzzle.grids[gi];
      if (row >= g.top &&
          row < g.top + g.size &&
          col >= g.left &&
          col < g.left + g.size) {
        return gi;
      }
    }
    return 0;
  }

  int _firstCellInGrid(int gi) {
    final puzzle = _puzzle;
    if (puzzle == null || gi < 0 || gi >= puzzle.grids.length) {
      return _firstEmptyCell();
    }
    final g = puzzle.grids[gi];
    final cells = <int>[];
    for (var r = g.top; r < g.top + g.size; r++) {
      for (var c = g.left; c < g.left + g.size; c++) {
        if (r < 0 || r >= puzzle.rows || c < 0 || c >= puzzle.cols) continue;
        final index = r * puzzle.cols + c;
        if (_isActive(index)) cells.add(index);
      }
    }
    for (final index in cells) {
      if (_board[index] == 0) return index;
    }
    return cells.isEmpty ? _firstEmptyCell() : cells.first;
  }

  void _select(int index) {
    if (_loading || _over || _paused || !_isActive(index)) return;
    setState(() {
      _selected = index;
      if (_puzzle?.isCube3d == true) {
        _layer = index ~/ (_puzzle!.rows * _puzzle!.cols);
      }
      if (_puzzle?.variant == SudokuVariant.overlap) {
        _focusGrid = _gridIndexFor(index);
      }
      _revision++;
    });
    if (_keyboardEnabled) _keyFocus.requestFocus();
  }

  void _moveSelection(int dx, int dy) {
    final puzzle = _puzzle;
    if (puzzle == null || _loading || _over || _paused) return;
    if (puzzle.isCube3d && puzzle.cubeFaces.isNotEmpty) {
      final refs = puzzle.cubeRefsOf(_selected);
      SudokuCubeCellRef? ref;
      for (final item in refs) {
        if (item.face == _cubeFace) {
          ref = item;
          break;
        }
      }
      ref ??= refs.isEmpty ? null : refs.first;
      if (ref == null) return;
      final nr = (ref.row + dy).clamp(0, 8).toInt();
      final nc = (ref.col + dx).clamp(0, 8).toInt();
      final index = puzzle.cubeIndex(_cubeFace, nr, nc);
      if (!puzzle.isActive(index)) return;
      setState(() => _selected = index);
      _keyFocus.requestFocus();
      return;
    }
    final rows = puzzle.rows;
    final cols = puzzle.cols;
    final base = _layer * rows * cols;
    var index = _selected;
    if (index < base || index >= base + rows * cols) {
      index = _firstCellInLayer(_layer);
      if (index < 0) return;
    }
    var r = (index - base) ~/ cols;
    var c = (index - base) % cols;
    for (var step = 0; step < math.max(rows, cols); step++) {
      r += dy;
      c += dx;
      if (r < 0 || r >= rows || c < 0 || c >= cols) break;
      final candidate = base + r * cols + c;
      if (_isActive(candidate)) {
        setState(() {
          _selected = candidate;
          if (puzzle.variant == SudokuVariant.overlap) {
            _focusGrid = _gridIndexFor(candidate);
          }
        });
        _keyFocus.requestFocus();
        return;
      }
    }
  }

  void _changeLayer(int delta) {
    final puzzle = _puzzle;
    if (puzzle == null || !puzzle.isCube3d) return;
    final next = (_layer + delta)
        .clamp(0, math.max(0, puzzle.layers - 1))
        .toInt();
    if (next == _layer) return;
    final oldBase = _layer * puzzle.rows * puzzle.cols;
    final oldRow = _selected >= oldBase
        ? (_selected - oldBase) ~/ puzzle.cols
        : 0;
    final oldCol = _selected >= oldBase
        ? (_selected - oldBase) % puzzle.cols
        : 0;
    final base = next * puzzle.rows * puzzle.cols;
    final same = base + oldRow * puzzle.cols + oldCol;
    setState(() {
      _layer = next;
      _selected = _isActive(same) ? same : _firstCellInLayer(next);
      _revision++;
    });
    _keyFocus.requestFocus();
  }

  void _changeCubeFaceTo(SudokuCubeFace face) {
    final puzzle = _puzzle;
    if (puzzle == null ||
        puzzle.cubeFaces.isEmpty ||
        face == _cubeFace) {
      return;
    }
    final refs = puzzle.cubeRefsOf(_selected);
    final index = refs.any((r) => r.face == face)
        ? _selected
        : _firstCellOnCubeFace(puzzle, face);
    setState(() {
      _cubeFace = face;
      _selected = index;
      _revision++;
    });
    _keyFocus.requestFocus();
  }

  int _firstCellOnCubeFace(SudokuPuzzle puzzle, SudokuCubeFace face) {
    SudokuCubeFaceMap? map;
    for (final m in puzzle.cubeFaces) {
      if (m.face == face) map = m;
    }
    if (map == null) return _firstEmptyCell();
    for (final index in map.cells) {
      if (puzzle.isActive(index) &&
          index < _board.length &&
          _board[index] == 0) {
        return index;
      }
    }
    for (final index in map.cells) {
      if (puzzle.isActive(index)) return index;
    }
    return map.cells.isEmpty ? _firstEmptyCell() : map.cells.first;
  }

  void _changeCubeFace(int delta) {
    final faces = SudokuCubeFace.values;
    final index = faces.indexOf(_cubeFace);
    _changeCubeFaceTo(faces[(index + delta) % faces.length]);
  }

  void _changeGrid(int delta) {
    final puzzle = _puzzle;
    if (puzzle == null || puzzle.grids.isEmpty) return;
    final current = _gridIndexFor(_selected);
    final next = (current + delta) % puzzle.grids.length;
    final target = (next + puzzle.grids.length) % puzzle.grids.length;
    setState(() {
      _focusGrid = target;
      _selected = _firstCellInGrid(target);
      _revision++;
    });
    _keyFocus.requestFocus();
  }

  Map<int, Set<int>> _peerNotesToClear(int index, int value) {
    final puzzle = _puzzle;
    if (puzzle == null) return const {};
    final cleared = <int, Set<int>>{};
    final visited = <int>{};
    for (final unit in puzzle.units) {
      if (!unit.contains(index)) continue;
      for (final peer in unit) {
        if (peer == index || !visited.add(peer)) continue;
        if (peer < 0 || peer >= _notes.length) continue;
        if (_notes[peer].contains(value)) {
          cleared[peer] = Set<int>.from(_notes[peer]);
        }
      }
    }
    return cleared;
  }

  void _clearPeerNotes(Map<int, Set<int>> cleared, int value) {
    for (final index in cleared.keys) {
      _notes[index].remove(value);
    }
  }

  void _input(int n) {
    if (_loading || _over || _paused || _selected < 0) return;
    if (_selected >= _given.length || _given[_selected]) return;
    final old = _selected < _board.length ? _board[_selected] : 0;
    final oldNotes = _selected < _notes.length
        ? Set<int>.from(_notes[_selected])
        : <int>{};
    final oldGiven = _selected < _given.length && _given[_selected];
    if (_noteMode) {
      _history.add(
        _SudokuMove(
          index: _selected,
          value: old,
          notes: oldNotes,
          given: oldGiven,
        ),
      );
      setState(() {
        if (_notes[_selected].contains(n)) {
          _notes[_selected].remove(n);
        } else {
          _notes[_selected].add(n);
        }
        _revision++;
      });
      return;
    }
    final solution = _puzzle!.solution[_selected];
    final clearedNotes = n == solution
        ? _peerNotesToClear(_selected, n)
        : const <int, Set<int>>{};
    _history.add(
      _SudokuMove(
        index: _selected,
        value: old,
        notes: oldNotes,
        given: oldGiven,
        clearedNotes: clearedNotes,
      ),
    );
    if (n == solution) {
      setState(() {
        _board[_selected] = n;
        _notes[_selected].clear();
        _clearPeerNotes(clearedNotes, n);
        _revision++;
      });
      GameSfx.move();
      _afterBoardChange();
    } else {
      setState(() {
        _board[_selected] = n;
        _errors++;
        _revision++;
      });
      GameSfx.miss();
      _afterBoardChange();
      if (_errors >= _maxErrors) _fail();
    }
  }

  void _erase() {
    if (_loading || _over || _paused || _selected < 0) return;
    if (_selected >= _given.length || _given[_selected]) return;
    final oldNotes = _selected < _notes.length
        ? Set<int>.from(_notes[_selected])
        : <int>{};
    _history.add(
      _SudokuMove(
        index: _selected,
        value: _board[_selected],
        notes: oldNotes,
        given: false,
      ),
    );
    setState(() {
      _board[_selected] = 0;
      _notes[_selected].clear();
      _revision++;
    });
    _afterBoardChange();
  }

  void _undo() {
    if (_loading || _over || _history.isEmpty) return;
    final move = _history.removeLast();
    setState(() {
      _board[move.index] = move.value;
      _notes[move.index] = Set<int>.from(move.notes);
      for (final entry in move.clearedNotes.entries) {
        _notes[entry.key] = Set<int>.from(entry.value);
      }
      if (move.index < _given.length) _given[move.index] = move.given;
      _selected = move.index;
      _revision++;
    });
    _afterBoardChange();
  }

  void _hint() {
    if (_loading || _over || _paused || _hints <= 0) return;
    final puzzle = _puzzle;
    if (puzzle == null) return;
    var index = _selected;
    if (index < 0 ||
        index >= _board.length ||
        _given[index] ||
        _board[index] == puzzle.solution[index]) {
      index = SudokuEngine.hintCell(puzzle, _board) ?? -1;
    }
    if (index < 0 || index >= _board.length) return;
    final oldNotes = index < _notes.length
        ? Set<int>.from(_notes[index])
        : <int>{};
    final solution = puzzle.solution[index];
    final clearedNotes = _peerNotesToClear(index, solution);
    _history.add(
      _SudokuMove(
        index: index,
        value: _board[index],
        notes: oldNotes,
        given: index < _given.length && _given[index],
        clearedNotes: clearedNotes,
      ),
    );
    setState(() {
      _board[index] = solution;
      _notes[index].clear();
      _clearPeerNotes(clearedNotes, solution);
      if (index < _given.length) _given[index] = true;
      _hints--;
      _selected = index;
      _revision++;
    });
    GameSfx.move();
    _afterBoardChange();
  }

  void _afterBoardChange() {
    final puzzle = _puzzle;
    if (puzzle == null) return;
    _conflicts = SudokuEngine.conflicts(puzzle, _board);
    _revision++;
    _syncProgress();
    _checkWin();
  }

  void _checkWin() {
    final puzzle = _puzzle;
    if (puzzle == null || _over) return;
    if (!SudokuEngine.isSolved(puzzle, _board)) {
      setState(() {});
      return;
    }
    _timer?.cancel();
    final score = _scoreForWin();
    _lastScore = score;
    _win = true;
    _over = true;
    GameSfx.win();
    final app = context.app;
    app.saveLocalBest(_scoreKey, score);
    app.submitScore(_scoreKey, score, countRound: !_roundCounted);
    setState(() => _revision++);
  }

  int _scoreForWin() {
    if (_mode!.variant == SudokuVariant.classic) {
      return math.max(1, _baseScore - _seconds);
    }
    return math.max(
      1,
      _baseScore - _seconds * 2 - _errors * 20 - (3 - _hints) * 15,
    );
  }

  void _fail() {
    if (_over) return;
    _timer?.cancel();
    _over = true;
    _roundCounted = true;
    GameSfx.lose();
    unawaited(AppState.instance.noteGameRound());
    setState(() => _revision++);
  }

  void _togglePause() {
    if (_over || _loading) return;
    setState(() {
      _paused = !_paused;
      _revision++;
    });
  }

  void _syncProgress() {
    final puzzle = _puzzle;
    final mode = _mode;
    if (puzzle == null || mode == null) return;
    var filled = 0;
    var total = 0;
    for (var i = 0; i < _board.length; i++) {
      if (!_isActive(i)) continue;
      total++;
      if (_board[i] != 0) filled++;
    }
    final layerText = puzzle.isCube3d
        ? (puzzle.cubeFaces.isNotEmpty
              ? ' · ${_cubeFaceLabel(_cubeFace)}'
              : ' · 第 ${_layer + 1} 层')
        : '';
    _progress.value =
        '${mode.title} · ${_difficulty.label}$layerText · '
        '${gameFmtDuration(_seconds)} · 已填 $filled/$total';
  }

  int? _digitFor(LogicalKeyboardKey key) {
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final index = digits.indexOf(key);
    if (index >= 0) return index + 1;
    const numpad = [
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    final padIndex = numpad.indexOf(key);
    return padIndex >= 0 ? padIndex + 1 : null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_keyboardEnabled || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    if (_puzzle == null || _loading) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(0, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(0, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveSelection(-1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveSelection(1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      if (_puzzle!.isCube3d && _puzzle!.cubeFaces.isNotEmpty) {
        _changeCubeFace(-1);
      } else if (_puzzle!.isCube3d) {
        _changeLayer(-1);
      } else if (_puzzle!.variant == SudokuVariant.overlap) {
        _changeGrid(-1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.tab) {
      if (_puzzle!.isCube3d && _puzzle!.cubeFaces.isNotEmpty) {
        _changeCubeFace(1);
      } else if (_puzzle!.isCube3d) {
        _changeLayer(1);
      } else if (_puzzle!.variant == SudokuVariant.overlap) {
        _changeGrid(1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.numpad0) {
      _erase();
      return KeyEventResult.handled;
    }
    final digit = _digitFor(key);
    if (digit != null) {
      _input(digit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openRank() {
    final mode = _mode;
    if (mode == null) return;
    showGameRank(
      context,
      game: 'sudoku',
      title: '数独 · $_modeLabel',
      difficulties: _rankDifficulties,
      initial: _rankInitial,
    );
  }

  List<int> _remaining() {
    final puzzle = _puzzle;
    if (puzzle == null ||
        puzzle.variant == SudokuVariant.overlap ||
        puzzle.isCube3d) {
      return const [];
    }
    final counts = List<int>.filled(10, 0);
    final start = puzzle.isCube3d ? _layer * puzzle.rows * puzzle.cols : 0;
    final end = puzzle.isCube3d
        ? start + puzzle.rows * puzzle.cols
        : _board.length;
    for (var i = start; i < end && i < _board.length; i++) {
      if (!_isActive(i)) continue;
      final v = _board[i];
      if (v > 0 && v <= 9) counts[v]++;
    }
    return [for (var n = 1; n <= 9; n++) math.max(0, 9 - counts[n])];
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    if (mode == null) return _buildModeSelect(context);
    if (_puzzle == null) return _buildLoadingShell(context);
    return Focus(
      focusNode: _keyFocus,
      autofocus: _keyboardEnabled,
      onKeyEvent: _onKey,
      child: _buildGameShell(context),
    );
  }

  Widget _buildModeSelect(BuildContext context) {
    return GameScaffold(
      gameKey: 'gsudoku',
      title: '数独',
      showLive: false,
      showSidePanels: false,
      contentMaxWidth: 1180,
      onBack: () => popOrHome(context),
      board: SudokuModeSelect(
        onStart: (mode, difficulty) {
          _startMode(mode, difficulty);
        },
      ),
    );
  }

  Widget _buildLoadingShell(BuildContext context) {
    final mode = _mode!;
    return GameScaffold(
      gameKey: 'gsudoku',
      title: '数独',
      showLive: false,
      showSidePanels: false,
      onBack: _backToModes,
      board: _error != null
          ? _ErrorPanel(
              message: _error!,
              onRetry: _loadPuzzle,
              onBack: _backToModes,
            )
          : _LoadingPanel(mode: mode, difficulty: _difficulty),
    );
  }

  Widget _buildGameShell(BuildContext context) {
    final mode = _mode!;
    final puzzle = _puzzle!;
    final bestScore = context.app.localBest(_scoreKey);
    final bestSeconds = bestScore > 0
        ? math.max(1, _baseScore - bestScore)
        : 0;
    final above = <Widget>[
      _ModeBar(
        mode: mode,
        difficulty: _difficulty,
        onDifficulty: _changeDifficulty,
        onMode: _backToModes,
      ),
      if (!puzzle.difficultyMet) const _DifficultyNotice(),
      if (_isPhone(context) && _isLargeBoard && !_hideLargeNotice)
        _LargeBoardNotice(
          onClose: () => setState(() => _hideLargeNotice = true),
        ),
      if (puzzle.isCube3d && puzzle.cubeFaces.isNotEmpty) ...[
        _CubeFaceTabs(face: _cubeFace, onChanged: _changeCubeFaceTo),
        _CubeViewToggle(
          flat: _cubeFlat,
          onChanged: (value) => setState(() => _cubeFlat = value),
        ),
      ]
      else if (puzzle.isCube3d) ...[
        _LayerTabs(
          layer: _layer,
          layers: puzzle.layers,
          board: _board,
          rows: puzzle.rows,
          cols: puzzle.cols,
          conflicts: _conflicts,
          active: puzzle.active,
          onChanged: (l) {
            final delta = l - _layer;
            _changeLayer(delta);
          },
        ),
      ],
      if (puzzle.variant == SudokuVariant.overlap) ...[
        _OverlapTabs(
          grids: puzzle.grids,
          selected: _focusGrid,
          conflicts: _conflicts,
          cols: puzzle.cols,
          rows: puzzle.rows,
          onChanged: (gi) {
            setState(() {
              _focusGrid = gi;
              _selected = _firstCellInGrid(gi);
              _revision++;
            });
            _keyFocus.requestFocus();
          },
        ),
      ],
    ];
    return GameScaffold(
      gameKey: 'gsudoku',
      title: '数独',
      rankGame: 'sudoku',
      rankDifficulties: _rankDifficulties,
      rankInitial: _rankInitial,
      liveProgress: _progress,
      liveInScroll: true,
      onBack: _backToModes,
      above: above,
      pills: [
        GameScorePill(label: '错误', value: '$_errors/$_maxErrors'),
        GameScorePill(label: '用时', value: gameFmtDuration(_seconds)),
        GameScorePill(
          label: '最佳',
          value: bestSeconds > 0 ? gameFmtDuration(bestSeconds) : '--',
        ),
      ],
      actions: [
        GameActionButton(
          label: '新游戏',
          icon: GameIcons.refresh,
          primary: true,
          enabled: !_loading,
          onTap: _newGame,
        ),
        GameActionButton(
          label: _paused ? '继续' : '暂停',
          icon: _paused ? GameIcons.play : GameIcons.pause,
          onTap: _togglePause,
        ),
        GameActionButton(
          label: '排行榜',
          icon: GameIcons.trophy,
          onTap: _openRank,
        ),
      ],
      board: _buildBoardArea(context, puzzle),
    );
  }

  Widget _buildBoardArea(BuildContext context, SudokuPuzzle puzzle) {
    final media = MediaQuery.sizeOf(context);
    final screenW = media.width;
    final tablet = screenW >= 900;
    final duoShort = CitroForm.duoInner(media) && media.width > media.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : screenW - GameMetrics.sidePad * 2;
        if (puzzle.isCube3d && puzzle.cubeFaces.isNotEmpty) {
          return _buildCubeBoardArea(
            context,
            puzzle,
            contentW,
            tablet,
            screenW,
          );
        }
        final boardMax = duoShort
            ? math.max(240.0, media.height - 386)
            : tablet
            ? (puzzle.variant == SudokuVariant.overlap ? 600.0 : (kIsWeb ? 500.0 : 520.0))
            : math.min(screenW * 0.92, puzzle.variant == SudokuVariant.overlap ? 520.0 : 470.0);
        final boardW = math.min(contentW, boardMax);
        final boardH = boardW * puzzle.rows / puzzle.cols;
        final stage = SizedBox(
          width: boardW,
          height: boardH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: SudokuBoardView(
                  puzzle: puzzle,
                  board: _board,
                  notes: _notes,
                  conflicts: _conflicts,
                  selected: _selected,
                  layer: _layer,
                  focusGrid: puzzle.variant == SudokuVariant.overlap
                      ? _focusGrid
                      : -1,
                  revision: _revision,
                  maxSide: boardW,
                  interactive: puzzle.variant == SudokuVariant.overlap,
                  paused: _paused,
                  over: _over,
                  onSelect: _select,
                ),
              ),
              ..._stageOverlays(puzzle),
            ],
          ),
        );
        final padW = duoShort
            ? math.max(190.0, math.min(340.0, contentW - boardW - 20))
            : contentW;
        final pad = _SudokuPad(
          contentW: padW,
          remaining: _remaining(),
          noteMode: _noteMode,
          hints: _hints,
          keyboardMode: _keyboardModeHint(puzzle),
          onInput: _input,
          onErase: _erase,
          onUndo: _undo,
          onHint: _hint,
          onNote: () => setState(() => _noteMode = !_noteMode),
        );
        final legend = _Legend(puzzle: puzzle, mode: _mode!);
        if (duoShort) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  stage,
                  const SizedBox(width: 20),
                  pad,
                ],
              ),
              const SizedBox(height: 8),
              legend,
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            stage,
            if (puzzle.isCube3d &&
                puzzle.cubeFaces.isEmpty &&
                _selected >= 0) ...[
              const SizedBox(height: 8),
              _ColumnPeek(
                puzzle: puzzle,
                board: _board,
                conflicts: _conflicts,
                selected: _selected,
                layer: _layer,
                onLayer: (l) => _changeLayer(l - _layer),
              ),
            ],
            const SizedBox(height: 10),
            pad,
            const SizedBox(height: 8),
            legend,
          ],
        );
      },
    );
  }

  Widget _buildCubeBoardArea(
    BuildContext context,
    SudokuPuzzle puzzle,
    double contentW,
    bool tablet,
    double screenW,
  ) {
    final side = math.min(
      contentW,
      tablet ? 500.0 : math.min(screenW * .94, 470.0),
    );
    final boardH = _cubeFlat
        ? side
        : SudokuCubeView.heightForWidth(side);
    final stage = SizedBox(
      width: side,
      height: boardH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: _cubeFlat
                ? SudokuCubeFaceView(
                    puzzle: puzzle,
                    face: _cubeFace,
                    board: _board,
                    notes: _notes,
                    conflicts: _conflicts,
                    selected: _selected,
                    revision: _revision,
                    maxSide: side,
                    onSelect: (index) {
                      setState(() {
                        _selected = index;
                        _revision++;
                      });
                      _keyFocus.requestFocus();
                    },
                  )
                : SudokuCubeView(
                    puzzle: puzzle,
                    board: _board,
                    notes: _notes,
                    conflicts: _conflicts,
                    selected: _selected,
                    focusFace: _cubeFace,
                    revision: _revision,
                    maxSide: side,
                    onSelect: (index, face) {
                      setState(() {
                        _selected = index;
                        _cubeFace = face;
                        _revision++;
                      });
                      _keyFocus.requestFocus();
                    },
                  ),
          ),
          ..._stageOverlays(puzzle),
        ],
      ),
    );
    final pad = _SudokuPad(
      contentW: contentW,
      remaining: const [],
      noteMode: _noteMode,
      hints: _hints,
      keyboardMode: _keyboardModeHint(puzzle),
      onInput: _input,
      onErase: _erase,
      onUndo: _undo,
      onHint: _hint,
      onNote: () => setState(() => _noteMode = !_noteMode),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        stage,
        const SizedBox(height: 10),
        pad,
        const SizedBox(height: 8),
        _Legend(puzzle: puzzle, mode: _mode!),
      ],
    );
  }

  List<Widget> _stageOverlays(SudokuPuzzle puzzle) => [
    if (_paused && !_over)
      Positioned.fill(
        child: _BoardOverlay(
          title: '已暂停',
          description: '',
          action: '继续游戏',
          onAction: _togglePause,
          solid: true,
        ),
      ),
    if (_over)
      Positioned.fill(
        child: _BoardOverlay(
          title: _win ? '恭喜通关！' : '挑战失败',
          fail: !_win,
          description:
              '${_win ? '用时 ${gameFmtDuration(_seconds)} · 得分 $_lastScore' : '错误已达 $_maxErrors 次 · 用时 ${gameFmtDuration(_seconds)}'}'
              '${puzzle.difficultyMet ? '' : ' · 难度未达标称档'}',
          action: '再来一局',
          onAction: _newGame,
        ),
      ),
  ];

  String? _keyboardModeHint(SudokuPuzzle puzzle) {
    if (!_keyboardEnabled) return null;
    if (puzzle.isCube3d && puzzle.cubeFaces.isNotEmpty) {
      return '键盘 1–9 填数 · 方向键在当前面移动 · PgUp/PgDn/Tab 换面 · 退格擦除';
    }
    if (puzzle.isCube3d) {
      return '键盘 1–9 填数 · 方向键移动 · PgUp/PgDn 换层 · 退格擦除';
    }
    if (puzzle.variant == SudokuVariant.overlap) {
      return '键盘 1–9 填数 · 方向键移动 · PgUp/PgDn 换盘 · 退格擦除';
    }
    return '键盘 1–9 填数 · 方向键移动 · 退格擦除';
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.mode,
    required this.difficulty,
    required this.onDifficulty,
    required this.onMode,
  });

  final SudokuModeSpec mode;
  final SudokuDifficulty difficulty;
  final ValueChanged<SudokuDifficulty> onDifficulty;
  final VoidCallback onMode;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = mode.variant == SudokuVariant.classic ? '经典九宫' : mode.title;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 9,
      runSpacing: 7,
      children: [
        Pressable(
          onTap: onMode,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.line2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: context.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: c.ink2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 4),
                gameIcon(GameIcons.arrowLeft, size: 11, color: c.inkSoft),
                Text(
                  '换',
                  style: context.body(
                    size: 10,
                    color: c.inkSoft,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (mode.difficulties.length > 1)
          _DiffTabs(
            mode: mode,
            value: difficulty,
            onChanged: onDifficulty,
          )
        else
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.hl,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.accent.withValues(alpha: .45)),
            ),
            child: Text(
              '${difficulty.label} · 唯一解',
              style: context.body(
                size: 11,
                weight: FontWeight.w700,
                color: c.accentInk,
                height: 1.2,
              ),
            ),
          ),
      ],
    );
  }
}

class _DiffTabs extends StatelessWidget {
  const _DiffTabs({
    required this.mode,
    required this.value,
    required this.onChanged,
  });

  final SudokuModeSpec mode;
  final SudokuDifficulty value;
  final ValueChanged<SudokuDifficulty> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < mode.difficulties.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            _tab(context, c, mode.difficulties[i]),
          ],
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    CitroColors c,
    SudokuDifficulty difficulty,
  ) {
    final on = difficulty == value;
    return GameHover(
      enabled: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(difficulty),
        child: Container(
          height: 28,
          constraints: const BoxConstraints(minWidth: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: on
              ? BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66FE923B),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ],
                )
              : null,
          child: Text(
            difficulty.label,
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: on ? const Color(0xFF2E2C22) : c.ink2,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _CubeViewToggle extends StatelessWidget {
  const _CubeViewToggle({required this.flat, required this.onChanged});

  final bool flat;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget item(String label, bool value) {
      final on = flat == value;
      return Pressable(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(999),
        scale: .96,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: context.body(
              size: 10.5,
              weight: FontWeight.w700,
              color: on ? const Color(0xFF2E2C22) : c.ink2,
              height: 1,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item('立体', false),
          const SizedBox(width: 3),
          item('平面', true),
        ],
      ),
    );
  }
}

class _CubeFaceTabs extends StatelessWidget {
  const _CubeFaceTabs({required this.face, required this.onChanged});

  final SudokuCubeFace face;
  final ValueChanged<SudokuCubeFace> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '面',
          style: context.body(
            size: 11,
            weight: FontWeight.w700,
            color: c.inkSoft,
          ),
        ),
        const SizedBox(width: 6),
        for (final item in SudokuCubeFace.values) ...[
          if (item != SudokuCubeFace.top) const SizedBox(width: 5),
          _cubeChip(context, c, item),
        ],
      ],
    );
  }

  Widget _cubeChip(
    BuildContext context,
    CitroColors c,
    SudokuCubeFace item,
  ) {
    final on = item == face;
    final label = switch (item) {
      SudokuCubeFace.top => '顶面',
      SudokuCubeFace.frontLeft => '左面',
      SudokuCubeFace.frontRight => '右面',
    };
    return Pressable(
      onTap: () => onChanged(item),
      borderRadius: BorderRadius.circular(999),
      scale: .96,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? c.accent : c.line2),
        ),
        child: Text(
          label,
          style: context.body(
            size: 11,
            weight: FontWeight.w700,
            color: on ? const Color(0xFF2E2C22) : c.ink2,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _LayerTabs extends StatelessWidget {
  const _LayerTabs({
    required this.layer,
    required this.layers,
    required this.board,
    required this.rows,
    required this.cols,
    required this.conflicts,
    required this.active,
    required this.onChanged,
  });

  final int layer;
  final int layers;
  final List<int> board;
  final int rows;
  final int cols;
  final Set<int> conflicts;
  final List<bool> active;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '层',
            style: context.body(
              size: 11,
              weight: FontWeight.w700,
              color: c.inkSoft,
            ),
          ),
          const SizedBox(width: 6),
          for (var l = 0; l < layers; l++) ...[
            if (l > 0) const SizedBox(width: 5),
            _LayerChip(
              index: l,
              selected: l == layer,
              board: board,
              rows: rows,
              cols: cols,
              conflicts: conflicts,
              active: active,
              onTap: () => onChanged(l),
            ),
          ],
        ],
      ),
    );
  }
}

class _LayerChip extends StatelessWidget {
  const _LayerChip({
    required this.index,
    required this.selected,
    required this.board,
    required this.rows,
    required this.cols,
    required this.conflicts,
    required this.active,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final List<int> board;
  final int rows;
  final int cols;
  final Set<int> conflicts;
  final List<bool> active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = index * rows * cols;
    var filled = 0;
    var total = 0;
    var bad = false;
    for (var i = base; i < base + rows * cols && i < board.length; i++) {
      if (i < active.length && !active[i]) continue;
      total++;
      if (board[i] != 0) filled++;
      if (conflicts.contains(i)) bad = true;
    }
    final complete = total > 0 && filled == total;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      scale: .95,
      child: Container(
        width: 34,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: bad
                ? c.stamp
                : (selected ? c.accent : c.line2),
            width: bad ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                fontFamily: AppFonts.kalam,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF2E2C22) : c.ink2,
                height: 1,
              ),
            ),
            const SizedBox(height: 1),
            Container(
              width: complete ? 7 : 4,
              height: 2,
              decoration: BoxDecoration(
                color: bad
                    ? c.stamp
                    : (selected
                          ? const Color(0xFF2E2C22)
                          : (complete ? c.accentInk : c.line2)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlapTabs extends StatelessWidget {
  const _OverlapTabs({
    required this.grids,
    required this.selected,
    required this.conflicts,
    required this.rows,
    required this.cols,
    required this.onChanged,
  });

  final List<SudokuSubGrid> grids;
  final int selected;
  final Set<int> conflicts;
  final int rows;
  final int cols;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final palette = sudokuSubgridPalette(c);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '盘',
            style: context.body(
              size: 11,
              weight: FontWeight.w700,
              color: c.inkSoft,
            ),
          ),
          const SizedBox(width: 6),
          for (var i = 0; i < grids.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            _OverlapChip(
              index: i,
              selected: i == selected,
              color: palette[i % palette.length],
              grid: grids[i],
              conflicts: conflicts,
              rows: rows,
              cols: cols,
              onTap: () => onChanged(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _OverlapChip extends StatelessWidget {
  const _OverlapChip({
    required this.index,
    required this.selected,
    required this.color,
    required this.grid,
    required this.conflicts,
    required this.rows,
    required this.cols,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final Color color;
  final SudokuSubGrid grid;
  final Set<int> conflicts;
  final int rows;
  final int cols;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    var bad = false;
    for (var r = grid.top; r < grid.top + grid.size && !bad; r++) {
      for (var col = grid.left; col < grid.left + grid.size; col++) {
        if (r < 0 || r >= rows || col < 0 || col >= cols) continue;
        if (conflicts.contains(r * cols + col)) {
          bad = true;
          break;
        }
      }
    }
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      scale: .96,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? Color.alphaBlend(color.withValues(alpha: .20), c.surface2)
              : c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: bad ? c.stamp : (selected ? color : c.line2),
            width: bad ? 1.5 : (selected ? 1.6 : 1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              '${index + 1}',
              style: TextStyle(
                fontFamily: AppFonts.kalam,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? color : c.ink2,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColumnPeek extends StatelessWidget {
  const _ColumnPeek({
    required this.puzzle,
    required this.board,
    required this.conflicts,
    required this.selected,
    required this.layer,
    required this.onLayer,
  });

  final SudokuPuzzle puzzle;
  final List<int> board;
  final Set<int> conflicts;
  final int selected;
  final int layer;
  final ValueChanged<int> onLayer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final row = puzzle.rowOf(selected);
    final col = puzzle.colOf(selected);
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '纵列',
              style: context.body(
                size: 10.5,
                weight: FontWeight.w700,
                color: c.inkSoft,
              ),
            ),
            const SizedBox(width: 6),
            for (var l = 0; l < puzzle.layers; l++) ...[
              if (l > 0) const SizedBox(width: 4),
              _peekChip(context, c, l, row, col),
            ],
          ],
        ),
      ),
    );
  }

  Widget _peekChip(
    BuildContext context,
    CitroColors c,
    int l,
    int row,
    int col,
  ) {
    final index = puzzle.indexOf(l, row, col);
    final value = index >= 0 && index < board.length ? board[index] : 0;
    final bad = conflicts.contains(index);
    final on = l == layer;
    return Pressable(
      onTap: () => onLayer(l),
      borderRadius: BorderRadius.circular(8),
      scale: .95,
      child: Container(
        width: 31,
        height: 33,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: bad ? c.stamp : (on ? c.accent : c.line2),
            width: bad ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${l + 1}',
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontSize: 7.5,
                fontWeight: FontWeight.w700,
                color: on ? const Color(0xFF2E2C22) : c.inkSoft,
                height: 1,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              value == 0 ? '·' : '$value',
              style: TextStyle(
                fontFamily: AppFonts.kalam,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: bad
                    ? c.stamp
                    : (on ? const Color(0xFF2E2C22) : c.accentInk),
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DifficultyNotice extends StatelessWidget {
  const _DifficultyNotice();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          c.stamp.withValues(alpha: .08),
          c.surface2,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.stamp.withValues(alpha: .38)),
      ),
      child: Row(
        children: [
          gameIcon(GameIcons.lightbulb, size: 14, color: c.stamp),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '本局实际评级低于标称档（已自动重试 3 次）。点「新游戏」可再换一局。',
              style: context.body(
                size: 10.5,
                color: c.ink2,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LargeBoardNotice extends StatelessWidget {
  const _LargeBoardNotice({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.hl,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.accent.withValues(alpha: .38)),
      ),
      child: Row(
        children: [
          gameIcon(GameIcons.lightbulb, size: 14, color: c.accentInk),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '手机屏幕较小，建议使用 iPad / 桌面端 / 网页端游玩；可双指放大。',
              style: context.body(
                size: 10.5,
                color: c.accentInk,
                height: 1.5,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: gameIcon(GameIcons.close, size: 12, color: c.accentInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _SudokuPad extends StatelessWidget {
  const _SudokuPad({
    required this.contentW,
    required this.remaining,
    required this.noteMode,
    required this.hints,
    required this.onInput,
    required this.onErase,
    required this.onUndo,
    required this.onHint,
    required this.onNote,
    this.keyboardMode,
  });

  final double contentW;
  final List<int> remaining;
  final bool noteMode;
  final int hints;
  final String? keyboardMode;
  final ValueChanged<int>? onInput;
  final VoidCallback? onErase;
  final VoidCallback? onUndo;
  final VoidCallback? onHint;
  final VoidCallback? onNote;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final keySize = math.min(56.0, math.max(40.0, (contentW - 8 * 4) / 5));
    Widget row(List<int> digits) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < digits.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _key(context, c, digits[i], keySize),
        ],
      ],
    );
    return SizedBox(
      width: contentW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (keyboardMode != null) ...[
            Text(
              keyboardMode!,
              textAlign: TextAlign.center,
              style: context.body(size: 10.5, color: c.inkSoft),
            ),
            const SizedBox(height: 7),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(const [1, 2, 3, 4, 5]),
              const SizedBox(height: 9),
              row(const [6, 7, 8, 9]),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _ToolBtn(label: '撤销', icon: GameIcons.undo, onTap: onUndo),
              _ToolBtn(label: '擦除', icon: GameIcons.eraser, onTap: onErase),
              _ToolBtn(
                label: '笔记',
                icon: GameIcons.pencil,
                primary: noteMode,
                onTap: onNote,
              ),
              _ToolBtn(
                label: '提示',
                icon: GameIcons.lightbulb,
                onTap: onHint,
                trailing: '$hints',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _key(BuildContext context, CitroColors c, int n, double size) {
    return GameHover(
      enabled: onInput != null,
      scale: 1.04,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onInput?.call(n),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.line2, width: 1),
                  ),
                ),
              ),
              Center(
                child: Text(
                  '$n',
                  style: TextStyle(
                    fontFamily: AppFonts.kalam,
                    fontSize: size * .42,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                    height: 1,
                  ),
                ),
              ),
              if (remaining.length >= n)
                Positioned(
                  right: 6,
                  bottom: 4,
                  child: Text(
                    '${remaining[n - 1]}',
                    style: TextStyle(
                      fontFamily: AppFonts.kalam,
                      fontSize: size * .18,
                      fontWeight: FontWeight.w600,
                      color: c.inkSoft,
                      height: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.trailing,
  });

  final String label;
  final String icon;
  final VoidCallback? onTap;
  final bool primary;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = primary ? const Color(0xFF3B2A10) : c.ink2;
    return GameHover(
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CssShadowLayer(
          radius: 999,
          shadows: primary
              ? const [
                  CssShadowSpec(
                    color: Color(0xA694530A),
                    offset: Offset(0, 11),
                    blur: 22,
                    spread: -12,
                  ),
                ]
              : const [
                  CssShadowSpec(
                    color: Color(0x803C301A),
                    offset: Offset(0, 4),
                    blur: 12,
                    spread: -8,
                  ),
                ],
          child: SizedBox(
            height: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: primary
                    ? null
                    : (c.dark ? c.surface2 : const Color(0xB8FFFCF4)),
                gradient: primary
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF9C98C), Color(0xFFF0A85C)],
                      )
                    : null,
                border: Border.all(
                  color: primary
                      ? const Color(0x2E94530A)
                      : (c.dark ? c.line2 : const Color(0x294A3A22)),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    gameIcon(icon, size: 15, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AppFonts.noto,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                        color: fg,
                        height: 1.2,
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 5),
                      Text(
                        trailing!,
                        style: TextStyle(
                          fontFamily: AppFonts.noto,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: fg.withValues(alpha: .7),
                          height: 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.puzzle, required this.mode});

  final SudokuPuzzle puzzle;
  final SudokuModeSpec mode;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final parityComplete =
        puzzle.evenCells.length + puzzle.oddCells.length >= puzzle.activeCount;
    final text = switch (puzzle.variant) {
      SudokuVariant.classic => '每行、每列、每个 3×3 宫都填 1–9，且不重复。',
      SudokuVariant.jigsaw => '每局宫形不同；每行、每列、每个异形宫都填 1–9。',
      SudokuVariant.snowflake => '雪花形异形宫；每行、每列、每个宫都填 1–9。',
      SudokuVariant.overlap => mode.key == 'windmill'
          ? '五盘风车式错位，中心盘与每盘共享 3×6 同数；点盘号切换配色，双指可放大。'
          : '共享格同数；每一盘仍是完整九宫。点盘号切换配色，双指可放大。',
      SudokuVariant.evenOdd => parityComplete
          ? '圆形格必须填奇数，方形格必须填偶数。'
          : '圆形=奇数，方形=偶数；未标记格不限奇偶。',
      SudokuVariant.diagonal => '两条主对角线也必须是 1–9，且不重复。',
      SudokuVariant.inequality => '箭头由小数指向大数，相邻格必须满足大小关系。',
      SudokuVariant.killer => '浅色笼内数字不重复，和见左上角。',
      SudokuVariant.cube3d => puzzle.cubeFaces.isNotEmpty
          ? '顶面、左面、右面各为九宫；共享边同数。立体视图可拖动旋转，右上角复位。'
          : '每层是九宫数独；同一行/列的纵向 9 格也必须是 1–9。',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          gameIcon(GameIcons.sparkle, size: 13, color: c.accentInk),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: context.body(
                size: 10.5,
                color: c.inkSoft,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardOverlay extends StatelessWidget {
  const _BoardOverlay({
    required this.title,
    required this.description,
    required this.action,
    required this.onAction,
    this.fail = false,
    this.solid = false,
  });

  final String title;
  final String description;
  final String action;
  final VoidCallback? onAction;
  final bool fail;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final card = CssShadowLayer(
      radius: 14,
      shadows: const [
        CssShadowSpec(color: Color(0x0F5A4A2C), offset: Offset(0, 2), blur: 4),
        CssShadowSpec(
          color: Color(0x6B5A4A2C),
          offset: Offset(0, 22),
          blur: 48,
          spread: -24,
        ),
      ],
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: solid
                ? (c.dark ? c.surface2 : const Color(0xFFFFFDF8))
                : (c.dark
                      ? c.surface.withAlpha(0xF0)
                      : const Color(0xF0FBF7EC)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.zcool,
                    fontFamilyFallback: AppFonts.bodyFallback,
                    fontSize: 25,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                    letterSpacing: 1.4,
                    color: fail ? c.stamp : c.mintInk,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontSize: 12,
                      color: c.ink2,
                      height: 1.6,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _ToolBtn(
                  label: action,
                  icon: GameIcons.reset,
                  primary: true,
                  onTap: onAction,
                ),
              ],
            ),
          ),
        ),
    );
    if (!solid) return card;
    return Container(
      color: c.dark ? c.surface : const Color(0xFFFBF7EC),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: card,
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({required this.mode, required this.difficulty});

  final SudokuModeSpec mode;
  final SudokuDifficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: c.accent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '正在生成「${mode.title}」',
              style: context.heading(size: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '${difficulty.label} · 正在复核唯一解与难度\n'
              '大棋盘首次生成可能需要几秒，请稍候。',
              textAlign: TextAlign.center,
              style: context.body(size: 12, color: c.inkSoft, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('生成没有成功', style: context.heading(size: 22)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.body(size: 11.5, color: c.inkSoft, height: 1.6),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GameActionButton(label: '返回模式', onTap: onBack),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameActionButton(
                    label: '再试一次',
                    primary: true,
                    onTap: onRetry,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
