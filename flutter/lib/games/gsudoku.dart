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
import '../widgets/browser_effects.dart';
import 'game_ui.dart';

/// 数独页面（web: index.html #gsudokuPage · styles/citro-games.css 第 1b / 4 / 9 节）
///
/// 移动端 390×844 light 实测坐标：
///   标题 @y71.2（ZCOOL 25.74）
///   难度切换 @121.66  229×43（padding 5 + border 1，4 个 52×31 药丸，gap 3）
///   三枚 HUD 药丸 @178.66（62×56.64，gap 9）
///   三枚操作按钮 @244.3（107.78 / 94.53 / 107.78 ×42，gap 8）
///   棋盘画框 @306.3  351×365（板 351×351 @320.3，内部 337×337 宫格，格 37.444）
///   数字键盘 @681.3（键 62.39×62.39，gap 8/9，两行 5+4）
///   工具行 @824.1（撤销/擦除/笔记 + 提示换行，42 高，gap 8）
///   live 条 @928.1（视口外，整页高 984.8）
class GameSudokuPage extends StatefulWidget {
  const GameSudokuPage({super.key});
  @override
  State<GameSudokuPage> createState() => _GameSudokuPageState();
}

class _GameSudokuPageState extends State<GameSudokuPage> {
  static const _diffs = {
    'easy': ('简单', 38, 3600),
    'med': ('中等', 46, 5400),
    'hard': ('困难', 52, 7200),
    'exp': ('专家', 56, 9000),
  };
  String diff = 'med';
  List<int> solution = List.filled(81, 0);
  List<int> puzzle = List.filled(81, 0);
  List<int> board = List.filled(81, 0);
  List<bool> given = List.filled(81, false);
  List<Set<int>> notes = List.generate(81, (_) => <int>{});
  List<Map<String, dynamic>> history = [];
  int errors = 0;
  int sel = -1;
  int hints = 3;
  int seconds = 0;
  bool noteMode = false;
  bool paused = false;
  bool over = false;
  bool win = false;
  bool submitted = false;
  Timer? timer;
  final _progress = ValueNotifier<String>('');
  final FocusNode _keyFocus = FocusNode(debugLabel: 'sudoku-keyboard');

  bool get _keyboardEnabled => platform.isWindows || kIsWeb;

  (String, int, int) get _meta => _diffs[diff]!;

  @override
  void initState() {
    super.initState();
    _newGame();
    if (_keyboardEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keyFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    _progress.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  void _newGame() {
    timer?.cancel();
    final gen = _SudokuGenerator(math.Random());
    solution = gen.generateSolution();
    board = List<int>.from(solution);
    given = List.filled(81, false);
    puzzle = List<int>.from(solution);
    final cells = List.generate(81, (i) => i)..shuffle(math.Random());
    var holes = 0;
    for (final i in cells) {
      if (holes >= _meta.$2) break;
      final old = puzzle[i];
      puzzle[i] = 0;
      board[i] = 0;
      if (!gen.hasUniqueSolution(puzzle)) {
        puzzle[i] = old;
        board[i] = old;
      } else {
        holes++;
      }
    }
    for (var i = 0; i < 81; i++) {
      given[i] = puzzle[i] != 0;
    }
    notes = List.generate(81, (_) => <int>{});
    history = [];
    errors = 0;
    sel = _keyboardEnabled ? _firstEmptyCell() : -1;
    hints = 3;
    seconds = 0;
    noteMode = false;
    paused = false;
    over = false;
    win = false;
    submitted = false;
    _progress.value = '${_meta.$1} · 用时 0:00';
    _startTimer();
    setState(() {});
  }

  int _firstEmptyCell() {
    for (var i = 0; i < board.length; i++) {
      if (board[i] == 0) return i;
    }
    return 0;
  }

  void _startTimer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || paused || over) return;
      setState(() => seconds++);
      _progress.value = '${_meta.$1} · 用时 ${gameFmtDuration(seconds)}';
    });
  }

  void _select(int i) {
    if (over || paused) return;
    setState(() => sel = i);
    if (_keyboardEnabled) _keyFocus.requestFocus();
  }

  void _moveSelection(int dx, int dy) {
    if (over || paused) return;
    final current = sel < 0 ? 0 : sel;
    final row = (current ~/ 9 + dy).clamp(0, 8);
    final col = (current % 9 + dx).clamp(0, 8);
    setState(() => sel = row * 9 + col);
    _keyFocus.requestFocus();
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

  void _input(int n) {
    if (over || paused || sel < 0 || given[sel]) return;
    final old = board[sel];
    final oldNotes = Set<int>.from(notes[sel]);
    if (noteMode) {
      history.add({'i': sel, 'value': old, 'notes': oldNotes});
      setState(() {
        if (notes[sel].contains(n)) {
          notes[sel].remove(n);
        } else {
          notes[sel].add(n);
        }
      });
      return;
    }
    history.add({'i': sel, 'value': old, 'notes': oldNotes});
    if (n == solution[sel]) {
      setState(() {
        board[sel] = n;
        notes[sel].clear();
      });
      GameSfx.move();
      _checkWin();
    } else {
      setState(() {
        board[sel] = n;
        errors++;
      });
      GameSfx.miss();
      if (errors >= 5) _fail();
    }
  }

  void _erase() {
    if (sel < 0 || given[sel] || over) return;
    history.add({
      'i': sel,
      'value': board[sel],
      'notes': Set<int>.from(notes[sel]),
    });
    setState(() {
      board[sel] = 0;
      notes[sel].clear();
    });
  }

  void _undo() {
    if (history.isEmpty || over) return;
    final h = history.removeLast();
    setState(() {
      board[h['i'] as int] = h['value'] as int;
      notes[h['i'] as int] = Set<int>.from(h['notes'] as Set<int>);
      sel = h['i'] as int;
    });
  }

  void _hint() {
    if (over || hints <= 0) return;
    var i = sel;
    if (i < 0 || given[i] || board[i] == solution[i]) {
      i = List.generate(
        81,
        (k) => k,
      ).firstWhere((k) => board[k] != solution[k], orElse: () => -1);
    }
    if (i < 0) return;
    history.add({'i': i, 'value': board[i], 'notes': Set<int>.from(notes[i])});
    setState(() {
      board[i] = solution[i];
      notes[i].clear();
      given[i] = true;
      hints--;
      sel = i;
    });
    _checkWin();
  }

  void _checkWin() {
    for (var i = 0; i < 81; i++) {
      if (board[i] != solution[i]) return;
    }
    win = true;
    over = true;
    timer?.cancel();
    GameSfx.win();
    final score = math.max(1, _meta.$3 - seconds);
    final app = context.app;
    app.saveLocalBest('sudoku:$diff', score);
    if (!submitted) {
      submitted = true;
      app.submitScore('sudoku:$diff', score);
    }
    setState(() {});
  }

  void _fail() {
    over = true;
    timer?.cancel();
    GameSfx.lose();
    setState(() {});
  }

  void _togglePause() {
    if (over) return;
    setState(() => paused = !paused);
  }

  void _changeDiff(String key) {
    if (diff == key) return;
    setState(() => diff = key);
    _newGame();
  }

  void _openRank() {
    showGameRank(
      context,
      game: 'sudoku',
      title: '数独',
      difficulties: const [
        ('easy', '简单'),
        ('med', '中等'),
        ('hard', '困难'),
        ('exp', '专家'),
      ],
      initial: diff,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bestScore = context.app.localBest('sudoku:$diff');
    final bestSecs = bestScore > 0 ? math.max(1, _meta.$3 - bestScore) : 0;
    final view = GameSudokuView(
      keyboardMode: _keyboardEnabled,
      diff: diff,
      board: board,
      given: given,
      notes: notes,
      solution: solution,
      errors: errors,
      seconds: seconds,
      bestSeconds: bestSecs,
      sel: sel,
      paused: paused,
      over: over,
      win: win,
      noteMode: noteMode,
      hints: hints,
      progress: _progress,
      onDiff: _changeDiff,
      onNew: _newGame,
      onPause: _togglePause,
      onRank: _openRank,
      onSelect: _select,
      onInput: _input,
      onErase: _erase,
      onUndo: _undo,
      onHint: _hint,
      onNote: () => setState(() => noteMode = !noteMode),
    );
    return Focus(
      focusNode: _keyFocus,
      autofocus: _keyboardEnabled,
      onKeyEvent: _onKey,
      child: view,
    );
  }
}

/// 纯视觉层（golden 测试用固定数据渲染）。
class GameSudokuView extends StatelessWidget {
  const GameSudokuView({
    super.key,
    this.diff = 'med',
    this.board = const [],
    this.given = const [],
    this.notes = const [],
    this.solution = const [],
    this.errors = 0,
    this.seconds = 0,
    this.bestSeconds = 0,
    this.sel = -1,
    this.paused = false,
    this.over = false,
    this.win = false,
    this.noteMode = false,
    this.hints = 3,
    this.keyboardMode = false,
    this.progress,
    this.onDiff,
    this.onNew,
    this.onPause,
    this.onRank,
    this.onSelect,
    this.onInput,
    this.onErase,
    this.onUndo,
    this.onHint,
    this.onNote,
  });

  final String diff;
  final List<int> board;
  final List<bool> given;
  final List<Set<int>> notes;
  final List<int> solution;
  final int errors;
  final int seconds;
  final int bestSeconds;
  final int sel;
  final bool paused;
  final bool over;
  final bool win;
  final bool noteMode;
  final int hints;
  final bool keyboardMode;
  final ValueNotifier<String>? progress;
  final ValueChanged<String>? onDiff;
  final VoidCallback? onNew;
  final VoidCallback? onPause;
  final VoidCallback? onRank;
  final ValueChanged<int>? onSelect;
  final ValueChanged<int>? onInput;
  final VoidCallback? onErase;
  final VoidCallback? onUndo;
  final VoidCallback? onHint;
  final VoidCallback? onNote;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final screenW = media.width;
    final tablet = screenW >= 900;
    final duoShort = CitroForm.duoInner(media) && media.width > media.height;
    final counts = List<int>.filled(10, 0);
    for (final v in board) {
      if (v > 0 && v <= 9) counts[v]++;
    }
    final remaining = [for (var n = 1; n <= 9; n++) math.max(0, 9 - counts[n])];
    return GameScaffold(
      gameKey: 'gsudoku',
      title: '数独',
      liveProgress: progress,
      liveInScroll: true,
      rankDifficulties: const [
        ('easy', '简单'),
        ('med', '中等'),
        ('hard', '困难'),
        ('exp', '专家'),
      ],
      rankInitial: diff,
      boardGap: 20.11,
      hud: _SudokuHud(
        diff: diff,
        errors: errors,
        seconds: seconds,
        bestSeconds: bestSeconds,
        paused: paused,
        sel: sel,
        onDiff: onDiff,
        onNew: onNew,
        onPause: onPause,
        onRank: onRank,
      ),
      board: LayoutBuilder(
        builder: (context, constraints) {
          final contentW = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : screenW - GameMetrics.sidePad * 2;
          final webWide = kIsWeb && tablet;
          final boardW = duoShort
              ? math.max(240.0, media.height - 386)
              : tablet
              ? math.min(webWide ? 500.0 : 520.0, contentW)
              : math.min(screenW * 0.9, 470.0);
          final keySize = duoShort
              ? 56.0
              : tablet
              ? (webWide ? 60.0 : 68.0)
              : (screenW * 0.16).clamp(44.0, 70.0);
          final stage = _SudokuStage(
            width: boardW,
            board: board,
            given: given,
            notes: notes,
            solution: solution,
            sel: sel,
            paused: paused,
            over: over,
            win: win,
            seconds: seconds,
            onSelect: onSelect,
            onPause: onPause,
            onNew: onNew,
          );
          final pad = (keyboardMode && !kIsWeb)
              ? _SudokuTools(
                  contentW: duoShort
                      ? math.min(340.0, contentW - boardW - 20)
                      : contentW,
                  noteMode: noteMode,
                  hints: hints,
                  onErase: onErase,
                  onUndo: onUndo,
                  onHint: onHint,
                  onNote: onNote,
                )
              : _SudokuPad(
                  contentW: duoShort
                      ? math.min(340.0, contentW - boardW - 20)
                      : contentW,
                  keySize: keySize,
                  remaining: remaining,
                  noteMode: noteMode,
                  hints: hints,
                  onInput: onInput,
                  onErase: onErase,
                  onUndo: onUndo,
                  onHint: onHint,
                  onNote: onNote,
                );
          if (duoShort) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [stage, const SizedBox(width: 20), pad],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [stage, const SizedBox(height: 10), pad],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

class _SudokuHud extends StatelessWidget {
  const _SudokuHud({
    required this.diff,
    required this.errors,
    required this.seconds,
    required this.bestSeconds,
    required this.paused,
    required this.sel,
    this.onDiff,
    this.onNew,
    this.onPause,
    this.onRank,
  });

  final String diff;
  final int errors;
  final int seconds;
  final int bestSeconds;
  final bool paused;
  final int sel;
  final ValueChanged<String>? onDiff;
  final VoidCallback? onNew;
  final VoidCallback? onPause;
  final VoidCallback? onRank;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DiffTabs(value: diff, onChanged: onDiff),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 9,
          runSpacing: 9,
          children: [
            GameScorePill(label: '错误', value: '$errors/5'),
            GameScorePill(label: '用时', value: gameFmtDuration(seconds)),
            GameScorePill(
              label: '最佳',
              value: bestSeconds > 0 ? gameFmtDuration(bestSeconds) : '--',
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _SudokuBtn(
              label: '新游戏',
              icon: GameIcons.refresh,
              primary: true,
              onTap: onNew,
            ),
            _SudokuBtn(
              label: paused ? '继续' : '暂停',
              icon: paused ? GameIcons.play : GameIcons.pause,
              onTap: onPause,
            ),
            _SudokuBtn(label: '排行榜', icon: GameIcons.trophy, onTap: onRank),
          ],
        ),
      ],
    );
  }
}

/// 正文难度切换：229×43 凹槽，4 个 52×31 药丸。
class _DiffTabs extends StatelessWidget {
  const _DiffTabs({required this.value, this.onChanged});

  static const double width = 229;
  static const double height = 43;
  static const double _tabW = 52;
  static const double _tabH = 31;
  static const _items = [
    ('easy', '简单'),
    ('med', '中等'),
    ('hard', '困难'),
    ('exp', '专家'),
  ];

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            _tab(context, c, _items[i].$1, _items[i].$2),
          ],
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, CitroColors c, String key, String label) {
    final on = key == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged?.call(key),
      child: Container(
        width: _tabW,
        height: _tabH,
        alignment: Alignment.center,
        decoration: on
            ? BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66FE923B),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              )
            : null,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.noto,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: on ? const Color(0xFF2E2C22) : const Color(0xFF4E4A40),
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// 与 web .g-btn 同尺寸的操作按钮（web 移动端字号 13、图标 15、左右内边距 23）。
class _SudokuBtn extends StatelessWidget {
  const _SudokuBtn({
    required this.label,
    required this.icon,
    this.primary = false,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String icon;
  final bool primary;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? const Color(0xFF3B2A10) : const Color(0xFF4E4A40);
    return GestureDetector(
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
              color: primary ? null : const Color(0xB8FFFCF4),
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
                    : const Color(0x294A3A22),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 23),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  gameIcon(icon, size: 15, color: fg),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .26,
                      color: fg,
                      height: 1.2,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 7),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 棋盘
// ---------------------------------------------------------------------------

class _SudokuStage extends StatelessWidget {
  const _SudokuStage({
    required this.width,
    required this.board,
    required this.given,
    required this.notes,
    required this.solution,
    required this.sel,
    required this.paused,
    required this.over,
    required this.win,
    required this.seconds,
    this.onSelect,
    this.onPause,
    this.onNew,
  });

  final double width;
  final List<int> board;
  final List<bool> given;
  final List<Set<int>> notes;
  final List<int> solution;
  final int sel;
  final bool paused;
  final bool over;
  final bool win;
  final int seconds;
  final ValueChanged<int>? onSelect;
  final VoidCallback? onPause;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width + 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 14,
            left: 0,
            width: width,
            height: width,
            child: _SudokuBoard(
              width: width,
              board: board,
              given: given,
              notes: notes,
              solution: solution,
              sel: sel,
              onSelect: onSelect,
            ),
          ),
          Positioned(
            top: 3,
            left: (width - 82) / 2,
            child: const IgnorePointer(child: GameTape()),
          ),
          if (paused)
            Positioned.fill(
              child: _SudokuOverlay(
                title: '已暂停',
                titleSize: 24,
                titleHeight: 39.6,
                description: '',
                action: '继续游戏',
                onAction: onPause,
              ),
            ),
          if (over)
            Positioned.fill(
              child: _SudokuOverlay(
                title: win ? '恭喜通关！' : '挑战失败',
                titleSize: 28,
                titleHeight: 46.2,
                fail: !win,
                description: win
                    ? '用时 ${gameFmtDuration(seconds)} · 得分 ${math.max(1, 5400 - seconds)}'
                    : '错误已达 5 次 · 用时 ${gameFmtDuration(seconds)}',
                action: '再来一局',
                onAction: onNew,
              ),
            ),
        ],
      ),
    );
  }
}

class _SudokuBoard extends StatelessWidget {
  const _SudokuBoard({
    required this.width,
    required this.board,
    required this.given,
    required this.notes,
    required this.solution,
    required this.sel,
    this.onSelect,
  });

  final double width;
  final List<int> board;
  final List<bool> given;
  final List<Set<int>> notes;
  final List<int> solution;
  final int sel;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fontSize = math.min(34.0, math.max(12.0, (width - 14) * 0.08));
    final noteSize = math.min(15.0, math.max(8.0, (width - 14) * 0.034));
    final selValue = sel >= 0 && sel < board.length ? board[sel] : 0;
    return SizedBox(
      width: width,
      height: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.line2),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ColoredBox(
                  color: c.line2,
                  child: Column(
                    children: [
                      for (var r = 0; r < 9; r++)
                        Expanded(
                          child: Row(
                            children: [
                              for (var col = 0; col < 9; col++)
                                Expanded(
                                  child: _SudokuCell(
                                    index: r * 9 + col,
                                    row: r,
                                    col: col,
                                    value: r * 9 + col < board.length
                                        ? board[r * 9 + col]
                                        : 0,
                                    isGiven: r * 9 + col < given.length
                                        ? given[r * 9 + col]
                                        : false,
                                    cellNotes: r * 9 + col < notes.length
                                        ? notes[r * 9 + col]
                                        : const <int>{},
                                    answer: r * 9 + col < solution.length
                                        ? solution[r * 9 + col]
                                        : 0,
                                    selected: sel == r * 9 + col,
                                    sel: sel,
                                    selValue: selValue,
                                    fontSize: fontSize,
                                    noteSize: noteSize,
                                    onTap: onSelect,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SudokuGridLinesPainter(
                  line2: c.line2,
                  inkSoft: c.inkSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按设备像素对齐的 9×9 分隔线（Chrome 会把 1/2px 边框 snap 到整像素）。
class _SudokuGridLinesPainter extends CustomPainter {
  const _SudokuGridLinesPainter({required this.line2, required this.inkSoft});

  final Color line2;
  final Color inkSoft;

  @override
  void paint(Canvas canvas, Size size) {
    final m = canvas.getTransform();
    final sx = m[0] == 0 ? 1.0 : m[0];
    final sy = m[5] == 0 ? 1.0 : m[5];
    final tx = m[12];
    final ty = m[13];
    double snapX(double x) => ((tx + x * sx).round() - tx) / sx;
    double snapY(double y) => ((ty + y * sy).round() - ty) / sy;
    const gridLeft = 7.0;
    final cell = (size.width - 14) / 9;
    final gridRight = gridLeft + cell * 9;
    final gridBottom = gridLeft + cell * 9;
    final paint = Paint()..style = PaintingStyle.fill;
    // 横向分隔线（薄线 line2，宫界 2px ink-soft；最后一条与 board 边重合，按 web 只画 1px）
    for (var k = 1; k <= 9; k++) {
      final thick = k % 3 == 0 && k != 9;
      final w = thick ? 2.0 : 1.0;
      final y0 = snapY(gridLeft + k * cell - w);
      final y1 = snapY(gridLeft + k * cell);
      paint.color = thick ? inkSoft : line2;
      canvas.drawRect(
        Rect.fromLTRB(snapX(gridLeft), y0, snapX(gridRight), y1),
        paint,
      );
    }
    // 纵向分隔线
    for (var k = 1; k <= 9; k++) {
      final thick = k % 3 == 0 && k != 9;
      final w = thick ? 2.0 : 1.0;
      final x0 = snapX(gridLeft + k * cell - w);
      final x1 = snapX(gridLeft + k * cell);
      paint.color = thick ? inkSoft : line2;
      canvas.drawRect(
        Rect.fromLTRB(x0, snapY(gridLeft), x1, snapY(gridBottom)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SudokuGridLinesPainter oldDelegate) =>
      oldDelegate.line2 != line2 || oldDelegate.inkSoft != inkSoft;
}

class _SudokuCell extends StatelessWidget {
  const _SudokuCell({
    required this.index,
    required this.row,
    required this.col,
    required this.value,
    required this.isGiven,
    required this.cellNotes,
    required this.answer,
    required this.selected,
    required this.sel,
    required this.selValue,
    required this.fontSize,
    required this.noteSize,
    this.onTap,
  });

  final int index;
  final int row;
  final int col;
  final int value;
  final bool isGiven;
  final Set<int> cellNotes;
  final int answer;
  final bool selected;
  final int sel;
  final int selValue;
  final double fontSize;
  final double noteSize;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isError = value != 0 && value != answer;
    final peer =
        sel >= 0 &&
        (sel ~/ 9 == row ||
            sel % 9 == col ||
            (sel ~/ 27 == row ~/ 3 && (sel % 9) ~/ 3 == col ~/ 3));
    final same = sel >= 0 && value != 0 && value == selValue;
    Color bg = c.surface2;
    if (peer) bg = c.mintSoft;
    if (same)
      bg = Color.alphaBlend(c.accent.withValues(alpha: .18), c.surface2);
    if (selected) {
      bg = Color.alphaBlend(c.accent.withValues(alpha: .26), c.surface2);
    }
    if (isError) {
      bg = Color.alphaBlend(
        c.stamp.withValues(alpha: selected ? .26 : .14),
        c.surface2,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap?.call(index),
      child: Container(
        decoration: BoxDecoration(color: bg),
        foregroundDecoration: selected
            ? BoxDecoration(
                border: Border.all(
                  color: isError ? c.stamp : c.accent,
                  width: 2,
                ),
              )
            : null,
        child: Center(
          child: value != 0
              ? Transform.translate(
                  // web 用 line-height:1 的行盒居中，字形整体比 Flutter 默认高 1px
                  offset: const Offset(0, -1),
                  child: Text(
                    '$value',
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontSize: fontSize,
                      fontWeight: isGiven ? FontWeight.w700 : FontWeight.w600,
                      color: isError ? c.stamp : (isGiven ? c.ink : c.mintInk),
                      height: 1,
                    ),
                  ),
                )
              : (cellNotes.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.all(2),
                        child: Column(
                          children: [
                            for (var r = 0; r < 3; r++)
                              Expanded(
                                child: Row(
                                  children: [
                                    for (var q = 0; q < 3; q++)
                                      Expanded(
                                        child: Center(
                                          child:
                                              cellNotes.contains(r * 3 + q + 1)
                                              ? Text(
                                                  '${r * 3 + q + 1}',
                                                  style: TextStyle(
                                                    fontFamily: AppFonts.noto,
                                                    fontSize: noteSize,
                                                    fontWeight: FontWeight.w600,
                                                    color: c.ink2,
                                                    height: 1,
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      )),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 数字键盘 / 工具行
// ---------------------------------------------------------------------------

class _SudokuTools extends StatelessWidget {
  const _SudokuTools({
    required this.contentW,
    required this.noteMode,
    required this.hints,
    this.onErase,
    this.onUndo,
    this.onHint,
    this.onNote,
  });

  final double contentW;
  final bool noteMode;
  final int hints;
  final VoidCallback? onErase;
  final VoidCallback? onUndo;
  final VoidCallback? onHint;
  final VoidCallback? onNote;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: contentW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '键盘 1–9 填数 · 方向键移动 · 退格擦除',
            style: context.body(size: 11, color: context.c.inkSoft),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _SudokuBtn(label: '撤销', icon: GameIcons.undo, onTap: onUndo),
              _SudokuBtn(label: '擦除', icon: GameIcons.eraser, onTap: onErase),
              _SudokuBtn(
                label: '笔记',
                icon: GameIcons.pencil,
                primary: noteMode,
                onTap: onNote,
              ),
              _SudokuBtn(
                label: '提示',
                icon: GameIcons.lightbulb,
                onTap: onHint,
                trailing: Text(
                  '$hints',
                  style: const TextStyle(
                    fontFamily: AppFonts.noto,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4E4A40),
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SudokuPad extends StatelessWidget {
  const _SudokuPad({
    required this.contentW,
    required this.keySize,
    required this.remaining,
    required this.noteMode,
    required this.hints,
    this.onInput,
    this.onErase,
    this.onUndo,
    this.onHint,
    this.onNote,
  });

  final double contentW;
  final double keySize;
  final List<int> remaining;
  final bool noteMode;
  final int hints;
  final ValueChanged<int>? onInput;
  final VoidCallback? onErase;
  final VoidCallback? onUndo;
  final VoidCallback? onHint;
  final VoidCallback? onNote;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget row(List<int> digits) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < digits.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _key(context, c, digits[i]),
        ],
      ],
    );
    return SizedBox(
      width: contentW,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kIsWeb && MediaQuery.sizeOf(context).width >= 900) ...[
                Text(
                  '键盘 1–9 填数 · 方向键移动 · 退格擦除',
                  style: context.body(size: 11, color: context.c.inkSoft),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: keySize * 2 + 9,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    row(const [1, 2, 3, 4, 5]),
                    const SizedBox(height: 9),
                    row(const [6, 7, 8, 9]),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SudokuBtn(label: '撤销', icon: GameIcons.undo, onTap: onUndo),
                  _SudokuBtn(
                    label: '擦除',
                    icon: GameIcons.eraser,
                    onTap: onErase,
                  ),
                  _SudokuBtn(
                    label: '笔记',
                    icon: GameIcons.pencil,
                    primary: noteMode,
                    onTap: onNote,
                  ),
                  _SudokuBtn(
                    label: '提示',
                    icon: GameIcons.lightbulb,
                    onTap: onHint,
                    trailing: Text(
                      '$hints',
                      style: TextStyle(
                        fontFamily: AppFonts.noto,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4E4A40).withValues(alpha: .7),
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _key(BuildContext context, CitroColors c, int n) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onInput?.call(n),
      child: SizedBox(
        width: keySize,
        height: keySize,
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
                  fontSize: 23.4,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                  height: 1,
                ),
              ),
            ),
            Positioned(
              right: 6,
              bottom: 4,
              child: Text(
                '${remaining.length >= n ? remaining[n - 1] : 0}',
                style: const TextStyle(
                  fontFamily: AppFonts.kalam,
                  fontSize: 9.36,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF76715E),
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 数字键盘按键边框（按设备像素对齐，Chrome 会把 1px 边框 snap 到整像素）
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 浮层
// ---------------------------------------------------------------------------

class _SudokuOverlay extends StatelessWidget {
  const _SudokuOverlay({
    required this.title,
    required this.titleSize,
    required this.titleHeight,
    required this.description,
    required this.action,
    this.fail = false,
    this.onAction,
  });

  final String title;
  final double titleSize;
  final double titleHeight;
  final String description;
  final String action;
  final bool fail;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CssShadowLayer(
      radius: 16,
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
        borderRadius: BorderRadius.circular(16),
        child: CitroBackdropBlur(
          sigma: 6,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xF0FBF7EC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppFonts.zcool,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w400,
                    height: titleHeight / titleSize,
                    letterSpacing: titleSize * .06,
                    color: fail ? c.stamp : c.mintInk,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontSize: 13,
                      color: c.ink2,
                      height: 1.7,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _SudokuBtn(
                  label: action,
                  icon: GameIcons.reset,
                  primary: true,
                  onTap: onAction,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 生成器
// ---------------------------------------------------------------------------

class _SudokuGenerator {
  final math.Random rnd;
  _SudokuGenerator(this.rnd);

  List<int> generateSolution() {
    final grid = List<int>.filled(81, 0);
    _fill(grid);
    return grid;
  }

  bool _fill(List<int> grid) {
    var best = -1;
    var bestCands = <int>[];
    for (var i = 0; i < 81; i++) {
      if (grid[i] != 0) continue;
      final cands = _candidates(grid, i);
      if (cands.isEmpty) return false;
      if (best < 0 || cands.length < bestCands.length) {
        best = i;
        bestCands = cands;
        if (cands.length == 1) break;
      }
    }
    if (best < 0) return true;
    bestCands.shuffle(rnd);
    for (final n in bestCands) {
      grid[best] = n;
      if (_fill(grid)) return true;
      grid[best] = 0;
    }
    return false;
  }

  List<int> _candidates(List<int> g, int i) {
    final used = <int>{};
    final r = i ~/ 9, col = i % 9;
    for (var k = 0; k < 9; k++) {
      used.add(g[r * 9 + k]);
      used.add(g[k * 9 + col]);
    }
    final br = r ~/ 3 * 3, bc = col ~/ 3 * 3;
    for (var rr = br; rr < br + 3; rr++) {
      for (var cc = bc; cc < bc + 3; cc++) {
        used.add(g[rr * 9 + cc]);
      }
    }
    return [
      for (var n = 1; n <= 9; n++)
        if (!used.contains(n)) n,
    ];
  }

  bool hasUniqueSolution(List<int> source) {
    final g = List<int>.from(source);
    var count = 0;
    bool solve() {
      var best = -1;
      var bestCands = <int>[];
      for (var i = 0; i < 81; i++) {
        if (g[i] != 0) continue;
        final cands = _candidates(g, i);
        if (cands.isEmpty) return false;
        if (best < 0 || cands.length < bestCands.length) {
          best = i;
          bestCands = cands;
          if (cands.length == 1) break;
        }
      }
      if (best < 0) {
        count++;
        return count > 1;
      }
      for (final n in bestCands) {
        g[best] = n;
        if (solve()) return true;
        g[best] = 0;
      }
      return false;
    }

    solve();
    return count == 1;
  }
}
