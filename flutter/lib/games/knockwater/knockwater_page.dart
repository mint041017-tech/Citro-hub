// 铃渡（Knockwater）· Citro 游戏页
//
// 玩法内核（engine / levels / painter / progress / sfx）与源游戏一致，
// 这里只做页面层迁移：接入 Citro 标准 GameScaffold（头部返回、账号、
// 排行榜、正在玩条、宽屏侧栏），把水面与局内 HUD 放进 board 槽位。
//
// 源版：C:\webflu\Citro\lipper game\lib\main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/game_sfx.dart';
import '../../services/platform.dart' as platform;
import '../../state/app_state.dart';
import '../game_ui.dart';
import 'engine.dart';
import 'hud_snapshot.dart';
import 'levels.dart';
import 'painter.dart';
import 'progress.dart';
import 'sfx.dart';

const TextStyle _serif = TextStyle(
  fontFamily: 'Songti SC',
  fontFamilyFallback: <String>[
    'STSong',
    'SimSun',
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'serif',
  ],
);

const Color _paper = Color(0xFFF2E9D8);

/// 源版竖屏 390 宽时水面板的宽度（390 - 14*2）。board 内的字号、
/// 按钮和间距都按这个基准缩放，避免小窗口里 UI 压过水面。
const double _boardBaseWidth = 362;

/// 把一次拖动映射到八个引擎方向之一。
///
/// 明显斜向的拖动产生斜步；较浅的斜向拖动退回主轴，保证普通横竖滑动
/// 依然容易触发。
List<int>? directionForDrag(
  Offset delta, {
  double threshold = 38,
  double diagonalRatio = 0.45,
}) {
  if (delta.distance < threshold) return null;
  final adx = delta.dx.abs();
  final ady = delta.dy.abs();
  if (adx == 0 && ady == 0) return null;
  final sx = delta.dx.sign.toInt();
  final sy = delta.dy.sign.toInt();
  if (adx > 0 && ady > 0) {
    final ratio = math.min(adx, ady) / math.max(adx, ady);
    if (ratio >= diagonalRatio) return <int>[sx, sy];
  }
  if (adx >= ady) return <int>[sx, 0];
  return <int>[0, sy];
}

class KnockwaterPage extends StatefulWidget {
  const KnockwaterPage({super.key, this.progress});

  /// 测试/独立运行时注入；生产环境为 null，从 kw_ 前缀本地存档加载。
  final ProgressStore? progress;

  /// 测试专用：最近一次挂载的引擎，用于验证真实输入落点。
  static Engine? debugEngine;

  /// 测试专用：最近一次推送的 HUD 快照。
  static GameHudSnapshot? debugHud;

  /// 测试专用：最近一次推送给「正在玩」的进度文案。
  static String debugLive = '';

  /// 测试专用：页面 build 次数（仅在 debug / 测试中累加）。
  static int debugBuildCount = 0;

  /// 测试专用：HUD 快照子树的 build 次数（仅在 debug / 测试中累加）。
  static int debugHudBuildCount = 0;

  /// 测试专用：标题浮层是否可见（AnimatedOpacity 仍在树上）。
  static bool debugTitleVisible = true;

  @override
  State<KnockwaterPage> createState() => _KnockwaterPageState();
}

class _KnockwaterPageState extends State<KnockwaterPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final FocusNode _focus;
  late final ValueNotifier<int> _frame;
  late final ValueNotifier<GameHudSnapshot> _hud;
  late final ValueNotifier<String> _live;
  late Engine _engine;
  ProgressStore _progress = ProgressStore.memory();
  bool _progressReady = false;

  int _level = 0;
  bool _showTitle = true;
  bool _showEnd = false;
  bool _showSelect = false;
  bool _progressSaved = false;
  double _lastCheckpointAt = -1;
  String? _lastCheckpointJson;
  bool _hintVisible = false;
  String? _toast;
  double _shakeUntil = 0;
  bool _knockHeld = false;
  bool _introVisible = false;
  bool _coachVisible = false;
  bool _hasKnocked = false;
  bool _soundOn = true;
  int? _bufferDx;
  int? _bufferDy;
  double _bufferAt = 0;
  final Set<LogicalKeyboardKey> _heldDirections = <LogicalKeyboardKey>{};
  Timer? _keyStepTimer;
  List<int>? _pendingKeyDir;
  bool _keyStepPending = false;

  Timer? _hintTimer;
  Timer? _toastTimer;
  Timer? _introTimer;
  Timer? _coachTimer;
  Duration _lastElapsed = Duration.zero;
  Offset? _dragLast;

  int get _starTotal {
    var sum = 0;
    for (var i = 0; i < kLevels.length; i++) {
      sum += _progress.starsFor(i);
    }
    return sum;
  }

  int get _maxStars => kLevels.length * 3;

  String _liveText(Engine e) =>
      '第 ${e.levelIndex + 1} 关 · 铃息 ${e.charges} / ${e.maxCharges}';

  @override
  void initState() {
    super.initState();
    KnockwaterPage.debugBuildCount = 0;
    KnockwaterPage.debugHudBuildCount = 0;
    KnockwaterPage.debugTitleVisible = true;
    _progress = widget.progress ?? ProgressStore.memory();
    _progressReady = widget.progress != null;
    _engine = Engine(0);
    KnockwaterPage.debugEngine = _engine;
    _frame = ValueNotifier<int>(0);
    _focus = FocusNode(debugLabel: 'knockwater-pond');
    // Citro 全局静音（极限刹车里的声音开关）也要约束本游戏；
    // 局内声音按钮仍可随时切回，不改变源版 Sfx 语义。
    _soundOn = !GameSfx.muted;
    Sfx.setMuted(!_soundOn);
    unawaited(_syncGlobalMute());
    _bindAudio(_engine);
    _hud = ValueNotifier<GameHudSnapshot>(GameHudSnapshot.of(_engine));
    _live = ValueNotifier<String>(_liveText(_engine));
    KnockwaterPage.debugHud = _hud.value;
    KnockwaterPage.debugLive = _live.value;
    _ticker = createTicker(_onTick)..start();
    if (widget.progress == null) unawaited(_loadProgress());
  }

  Future<void> _loadProgress() async {
    final loaded = await ProgressStore.load(totalLevels: kLevels.length);
    if (!mounted) return;
    setState(() {
      _progress = loaded;
      _progressReady = true;
    });
  }

  Future<void> _syncGlobalMute() async {
    await GameSfx.loadMuted();
    if (!mounted || !_soundOn) return;
    if (GameSfx.muted) {
      setState(() => _soundOn = false);
      Sfx.setMuted(true);
    }
  }

  @override
  void dispose() {
    Sfx.chargeStop();
    _ticker.dispose();
    _focus.dispose();
    _frame.dispose();
    _hud.dispose();
    _live.dispose();
    _hintTimer?.cancel();
    _toastTimer?.cancel();
    _introTimer?.cancel();
    _coachTimer?.cancel();
    _keyStepTimer?.cancel();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    _engine.update(dt.clamp(0.0, 0.05).toDouble());
    if (_bufferDx != null && !_engine.moving) {
      final dx = _bufferDx!;
      final dy = _bufferDy!;
      _bufferDx = null;
      _bufferDy = null;
      if (_engine.status == GameStatus.playing &&
          _engine.charges > 0 &&
          _engine.time - _bufferAt < 0.7) {
        _tryStep(dx, dy, buffered: true);
      }
    }
    _frame.value++;
    _syncHud();
    if (_engine.status != GameStatus.playing && !_progressSaved) {
      _progressSaved = true;
      if (_engine.status == GameStatus.won) {
        unawaited(_completeAndSubmit());
      } else {
        unawaited(_progress.clearCheckpoint());
      }
    }
    if (_engine.status == GameStatus.playing &&
        !_showTitle &&
        !_showEnd &&
        !_showSelect &&
        !_engine.moving &&
        !_engine.charging &&
        _engine.waves.isEmpty &&
        _engine.pending.isEmpty &&
        _engine.petals.every((p) => !p.stranded) &&
        _engine.time - _lastCheckpointAt >= 0.8) {
      _lastCheckpointAt = _engine.time;
      final raw = _checkpointJson();
      if (raw != _lastCheckpointJson) {
        _lastCheckpointJson = raw;
        unawaited(_progress.saveCheckpoint(raw));
      }
    }
    if (!_showTitle &&
        !_showEnd &&
        _engine.status != GameStatus.playing &&
        _engine.endDelay <= 0) {
      setState(() {
        _showEnd = true;
        _introVisible = false;
        _hintVisible = false;
        _coachVisible = false;
        _bufferDx = null;
        _bufferDy = null;
      });
    }
  }

  void _syncHud() {
    final next = GameHudSnapshot.of(_engine);
    KnockwaterPage.debugHud = next;
    if (next == _hud.value) return;
    _hud.value = next;
    final text = _liveText(_engine);
    KnockwaterPage.debugLive = text;
    if (_live.value != text) _live.value = text;
  }

  Future<void> _completeAndSubmit() async {
    final level = _level;
    final stars = _engine.stars;
    await _progress.complete(level, stars, totalLevels: kLevels.length);
    if (!mounted) return;
    setState(() {});
    final total = _starTotal;
    if (total > 0) {
      // 现有游戏接口：内部吞掉网络异常，失败不影响结算。
      unawaited(AppState.instance.submitScore('knockwater', total));
    }
  }

  void _startLevel(int index, {bool resume = false}) {
    if (index < 0 || index >= kLevels.length) return;
    if (!_progress.isUnlocked(index)) return;
    _introTimer?.cancel();
    _hintTimer?.cancel();
    _coachTimer?.cancel();
    _clearKeyboardStep();
    Sfx.init();
    Sfx.ui();
    final restored = resume ? _restoreCheckpoint(index) : null;
    final next = restored ?? Engine(index);
    if (restored == null) unawaited(_progress.clearCheckpoint());
    _bindAudio(next);
    _progressSaved = false;
    _lastCheckpointAt = -1;
    _lastCheckpointJson = null;
    setState(() {
      _level = index;
      _engine = next;
      KnockwaterPage.debugEngine = _engine;
      _showTitle = false;
      KnockwaterPage.debugTitleVisible = false;
      _showEnd = false;
      _showSelect = false;
      _introVisible = true;
      _hintVisible = false;
      _coachVisible = false;
      _toast = null;
      _shakeUntil = 0;
      _bufferDx = null;
      _bufferDy = null;
    });
    unawaited(_progress.markPlayed(index, totalLevels: kLevels.length));
    _focus.requestFocus();
    _syncHud();
    _schedulePresentation();
  }

  Engine? _restoreCheckpoint(int index) {
    final raw = _progress.checkpoint;
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      if ((data['v'] as num?)?.toInt() != 1) return null;
      if ((data['level'] as num?)?.toInt() != index + 1) return null;
      final petalsData = data['petals'];
      if (petalsData is! List) return null;
      final e = Engine(index);
      if (petalsData.length != e.petals.length) return null;
      final cx = (data['cellX'] as num?)?.toInt();
      final cy = (data['cellY'] as num?)?.toInt();
      if (cx == null || cy == null) return null;
      if (cx < 0 || cx >= kCols || cy < 0 || cy >= kRows) return null;
      final charges = (data['charges'] as num?)?.toInt();
      if (charges == null || charges < 0 || charges > e.maxCharges) {
        return null;
      }
      e.charges = charges;
      e.cellX = cx;
      e.cellY = cy;
      e.bx = cx + 0.5;
      e.by = cy + 0.5;
      e.fromX = e.bx;
      e.fromY = e.by;
      e.toX = e.bx;
      e.toY = e.by;
      e.moving = false;
      e.moveT = 0;
      e.charging = false;
      e.chargeT = 0;
      e.steps = (data['steps'] as num?)?.toInt() ?? 0;
      e.status = GameStatus.playing;
      e.loseReason = LoseReason.none;
      e.winTimer = 0;
      e.loseTimer = 0;
      e.idleTimer = 0;
      e.endDelay = 0;
      e.wonAt = -1;
      e.shake = 0;
      e.bayFlash = 0;
      e.time = 0;
      e.waves.clear();
      e.pending.clear();
      e.sparks.clear();
      for (var i = 0; i < e.petals.length; i++) {
        final p = data['petals'][i];
        if (p is! Map<String, dynamic>) return null;
        final petal = e.petals[i];
        petal.x = (p['x'] as num).toDouble();
        petal.y = (p['y'] as num).toDouble();
        petal.vx = (p['vx'] as num?)?.toDouble() ?? 0;
        petal.vy = (p['vy'] as num?)?.toDouble() ?? 0;
        petal.spin = (p['spin'] as num?)?.toDouble() ?? 0;
        petal.stranded = p['stranded'] == true;
        petal.settled = p['settled'] == true;
        petal.bayTime = (p['bayTime'] as num?)?.toDouble() ?? 0;
        if (petal.stranded) return null;
        final dx = petal.x - e.bay.x;
        final dy = petal.y - e.bay.y;
        petal.inBay = dx * dx + dy * dy < (e.bay.r - 0.05) * (e.bay.r - 0.05);
      }
      return e;
    } catch (_) {
      return null;
    }
  }

  String _checkpointJson() {
    return jsonEncode(<String, Object?>{
      'v': 1,
      'level': _level + 1,
      'charges': _engine.charges,
      'cellX': _engine.cellX,
      'cellY': _engine.cellY,
      'steps': _engine.steps,
      'petals': <Map<String, Object?>>[
        for (final p in _engine.petals)
          <String, Object?>{
            'x': p.x,
            'y': p.y,
            'vx': p.vx,
            'vy': p.vy,
            'spin': p.spin,
            'stranded': p.stranded,
            'settled': p.settled,
            'bayTime': p.bayTime,
          },
      ],
    });
  }

  void _openSelect() {
    if (_showSelect) return;
    Sfx.ui();
    setState(() => _showSelect = true);
  }

  void _closeSelect() {
    if (!_showSelect) return;
    Sfx.ui();
    setState(() => _showSelect = false);
  }

  void _bindAudio(Engine e) {
    e.onSettle = () => _safeSfx(Sfx.settle);
    e.onStrand = () => _safeSfx(Sfx.strand);
    e.onWin = () => _safeSfx(Sfx.win);
    e.onLose = () => _safeSfx(Sfx.lose);
  }

  void _safeSfx(void Function() fn) {
    try {
      fn();
    } catch (_) {}
  }

  void _toggleSound() {
    setState(() => _soundOn = !_soundOn);
    unawaited(Sfx.setMuted(!_soundOn));
    Sfx.init();
    if (_soundOn) Sfx.ui();
  }

  void _schedulePresentation() {
    _introTimer?.cancel();
    _hintTimer?.cancel();
    _introTimer = Timer(const Duration(milliseconds: 1900), () {
      if (!mounted || _showTitle || _showEnd) return;
      setState(() {
        _introVisible = false;
        _hintVisible = true;
      });
      _hintTimer = Timer(const Duration(seconds: 10), () {
        if (!mounted) return;
        setState(() => _hintVisible = false);
      });
      _maybeShowCoach();
    });
  }

  void _skipIntro() {
    if (!_introVisible) return;
    _introTimer?.cancel();
    setState(() {
      _introVisible = false;
      _hintVisible = true;
    });
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _hintVisible = false);
    });
    _maybeShowCoach();
  }

  void _maybeShowCoach() {
    if (_hasKnocked || _coachVisible || _showTitle || _showEnd) return;
    if (!_engine.level.allowHeavy) return;
    if (_introVisible) return;
    if (_engine.charges < 3) return;
    if (_engine.levelIndex == 0 && _engine.steps < 4) return;
    setState(() => _coachVisible = true);
    _coachTimer?.cancel();
    _coachTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() => _coachVisible = false);
    });
  }

  void _restart() {
    _startLevel(_level);
    HapticFeedback.selectionClick();
  }

  void _nextLevel() {
    if (_level + 1 < kLevels.length) {
      _startLevel(_level + 1);
    } else {
      _startLevel(0);
    }
  }

  void _undo() {
    if (_engine.undo()) {
      _bufferDx = null;
      _bufferDy = null;
      _progressSaved = false;
      _lastCheckpointAt = -1;
      _lastCheckpointJson = null;
      Sfx.ui();
      setState(() => _showEnd = false);
      _syncHud();
      HapticFeedback.selectionClick();
    }
  }

  bool _tryStep(int dx, int dy, {bool buffered = false}) {
    if (dx == 0 && dy == 0) return false;
    if (_showTitle || _showEnd) return false;
    final e = _engine;
    if (e.moving && !buffered && e.charges > 0) {
      _bufferDx = dx;
      _bufferDy = dy;
      _bufferAt = e.time;
      return true;
    }
    final ok = e.step(dx, dy);
    if (!ok) {
      if (e.charges <= 0 && !e.moving && !e.charging) {
        _showToast('铃息用尽了');
      }
      return false;
    }
    _bufferDx = null;
    _bufferDy = null;
    if (_introVisible) _skipIntro();
    HapticFeedback.selectionClick();
    Sfx.step(e.steps);
    if (e.steps >= 2 && _hintVisible) {
      _hintTimer?.cancel();
      setState(() => _hintVisible = false);
    }
    if (e.levelIndex == 0 && e.steps >= 4) _maybeShowCoach();
    _syncHud();
    return true;
  }

  void _onKnockStart() {
    if (_showTitle || _showEnd) return;
    if (!_engine.level.allowHeavy) {
      _showToast('静水章：重叩失效，只能走步');
      return;
    }
    if (_engine.startCharge()) {
      _knockHeld = true;
      _hasKnocked = true;
      _coachTimer?.cancel();
      _bufferDx = null;
      _bufferDy = null;
      Sfx.init();
      Sfx.charge();
      if (_coachVisible) setState(() => _coachVisible = false);
      if (_introVisible) _skipIntro();
      _syncHud();
      HapticFeedback.selectionClick();
      return;
    }
    if (_engine.charges < 3 && !_engine.moving) {
      _showToast('重叩需要 3 点铃息');
      setState(() => _shakeUntil = _engine.time + 0.36);
    }
  }

  void _onKnockEnd() {
    _knockHeld = false;
    Sfx.chargeStop();
    final p = _engine.releaseCharge();
    _syncHud();
    if (p != null) {
      HapticFeedback.mediumImpact();
      Sfx.knock(p);
    }
  }

  void _onKnockCancel() {
    _knockHeld = false;
    Sfx.chargeStop();
    _engine.cancelCharge();
    _syncHud();
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted) return;
      setState(() => _toast = null);
    });
  }

  bool _isDirectionKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.keyD ||
        key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.keyS;
  }

  bool _isGameKey(LogicalKeyboardKey key) {
    return _isDirectionKey(key) ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyZ ||
        key == LogicalKeyboardKey.keyR ||
        key == LogicalKeyboardKey.keyQ ||
        key == LogicalKeyboardKey.keyE ||
        key == LogicalKeyboardKey.keyC ||
        key == LogicalKeyboardKey.keyV;
  }

  List<int>? _directionFromHeld() {
    var dx = 0;
    var dy = 0;
    if (_heldDirections.contains(LogicalKeyboardKey.arrowLeft) ||
        _heldDirections.contains(LogicalKeyboardKey.keyA)) {
      dx -= 1;
    }
    if (_heldDirections.contains(LogicalKeyboardKey.arrowRight) ||
        _heldDirections.contains(LogicalKeyboardKey.keyD)) {
      dx += 1;
    }
    if (_heldDirections.contains(LogicalKeyboardKey.arrowUp) ||
        _heldDirections.contains(LogicalKeyboardKey.keyW)) {
      dy -= 1;
    }
    if (_heldDirections.contains(LogicalKeyboardKey.arrowDown) ||
        _heldDirections.contains(LogicalKeyboardKey.keyS)) {
      dy += 1;
    }
    if (dx == 0 && dy == 0) return null;
    return <int>[dx, dy];
  }

  void _onDirectionKeyDown(LogicalKeyboardKey key) {
    _heldDirections.add(key);
    _pendingKeyDir = _directionFromHeld();
    _keyStepPending = true;
    _keyStepTimer?.cancel();
    // A short window lets W+A / ↑+← become one diagonal step instead of two
    // cardinal steps. A lone key still moves after this window.
    _keyStepTimer = Timer(const Duration(milliseconds: 45), _flushKeyboardStep);
  }

  void _onDirectionKeyUp(LogicalKeyboardKey key) {
    _heldDirections.remove(key);
    if (_heldDirections.isEmpty && !_keyStepPending) {
      _keyStepTimer?.cancel();
      _keyStepTimer = null;
    }
  }

  void _flushKeyboardStep() {
    _keyStepTimer = null;
    final direction = _directionFromHeld() ?? _pendingKeyDir;
    _pendingKeyDir = null;
    _keyStepPending = false;
    if (direction == null) return;
    _tryStep(direction[0], direction[1]);
    if (_heldDirections.isNotEmpty) {
      _keyStepTimer = Timer(
        const Duration(milliseconds: 140),
        _flushKeyboardStep,
      );
    }
  }

  void _clearKeyboardStep() {
    _heldDirections.clear();
    _pendingKeyDir = null;
    _keyStepPending = false;
    _keyStepTimer?.cancel();
    _keyStepTimer = null;
  }

  void _handleKey(KeyEvent event) {
    if (_showTitle) return;
    final key = event.logicalKey;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (_isDirectionKey(key)) {
        _onDirectionKeyDown(key);
      } else if (key == LogicalKeyboardKey.space && event is KeyDownEvent) {
        _onKnockStart();
      } else if (key == LogicalKeyboardKey.keyZ && event is KeyDownEvent) {
        _undo();
      } else if (key == LogicalKeyboardKey.keyR && event is KeyDownEvent) {
        _restart();
      } else if (key == LogicalKeyboardKey.keyQ) {
        _tryStep(-1, -1);
      } else if (key == LogicalKeyboardKey.keyE) {
        _tryStep(1, -1);
      } else if (key == LogicalKeyboardKey.keyC) {
        _tryStep(-1, 1);
      } else if (key == LogicalKeyboardKey.keyV) {
        _tryStep(1, 1);
      }
    } else if (event is KeyUpEvent) {
      if (_isDirectionKey(key)) {
        _onDirectionKeyUp(key);
      } else if (key == LogicalKeyboardKey.space && _knockHeld) {
        _onKnockEnd();
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_isGameKey(event.logicalKey)) return KeyEventResult.ignored;
    _handleKey(event);
    return KeyEventResult.handled;
  }

  // GameScaffold 把 board 放在 SingleChildScrollView 里；PanGestureRecognizer
  // 只会拿到 onPanStart，后续 update 会被滚动视图吃掉。这里用
  // EagerGestureRecognizer 先赢下竞技场，再用 Listener 的原始指针算方向，
  // 保证水面拖动和源版一致，同时避免拖水时整页跟着滚。
  int? _activePointer;

  void _handlePointerDown(PointerDownEvent d) {
    if (_showTitle || _showEnd) return;
    if (d.kind == PointerDeviceKind.mouse && d.buttons != kPrimaryButton) {
      return;
    }
    if (_activePointer != null) return;
    _activePointer = d.pointer;
    Sfx.init();
    _focus.requestFocus();
    _dragLast = d.localPosition;
  }

  void _handlePointerMove(PointerMoveEvent d) {
    if (d.pointer != _activePointer) return;
    if (_showTitle || _showEnd) {
      _dragLast = null;
      return;
    }
    final last = _dragLast;
    if (last == null) return;
    final v = d.localPosition - last;
    final dir = directionForDrag(v);
    if (dir == null) return;
    final adx = v.dx.abs();
    final ady = v.dy.abs();
    final sx = v.dx.sign.toInt();
    final sy = v.dy.sign.toInt();
    var ok = _tryStep(dir[0], dir[1]);
    if (!ok) {
      // 明显被挡住的斜步退回主轴，横竖滑动依然宽容。
      if (adx >= ady) {
        ok = _tryStep(sx, 0) || (sy != 0 && _tryStep(0, sy));
      } else {
        ok = _tryStep(0, sy) || (sx != 0 && _tryStep(sx, 0));
      }
    }
    if (ok) {
      _dragLast = d.localPosition;
    }
  }

  void _handlePointerUp(PointerUpEvent d) {
    if (d.pointer != _activePointer) return;
    _activePointer = null;
    _dragLast = null;
  }

  void _handlePointerCancel(PointerCancelEvent d) {
    if (d.pointer != _activePointer) return;
    _activePointer = null;
    _dragLast = null;
  }

  ({double width, double height}) _boardSize(Size screen, bool wide) {
    final contentW = math.min(screen.width - 28, 760.0);
    // 棋盘优先：去掉重复的 pill 与底部动作行后，board 吃满剩余视口。
    // 固定占高约为 头部 56 + bodyTop + 标题(20) + 8 + 排行榜 42
    // + boardGap 8 + 正在玩条 56.7 + bodyBottom 12。
    final chromeInset = platform.isWindows ? 40.0 : 0.0;
    final maxH = wide
        ? math.max(260.0, screen.height - 130 - chromeInset)
        : math.max(260.0, screen.height - 240 - chromeInset);
    final capH = math.min(900.0, maxH);
    final width = math.min(
      contentW,
      math.min(560.0, math.max(260.0, capH * 0.75)),
    );
    final height = math.min(capH, width / 0.60);
    return (width: width, height: height);
  }

  @override
  Widget build(BuildContext context) {
    assert(() {
      KnockwaterPage.debugBuildCount++;
      return true;
    }());
    final mq = MediaQuery.sizeOf(context);
    final wide = mq.width >= 1100 && mq.width > mq.height;
    final size = _boardSize(mq, wide);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ValueListenableBuilder<GameHudSnapshot>(
        valueListenable: _hud,
        builder: (context, hud, _) {
          assert(() {
            KnockwaterPage.debugHudBuildCount++;
            return true;
          }());
          return GameScaffold(
            gameKey: 'gknockwater',
            title: '铃渡',
            titleSize: 20,
            rankGame: 'knockwater',
            liveProgress: _live,
            boardGap: 8,
            actions: <Widget>[
              GameActionButton(
                key: const ValueKey('kw-rank'),
                label: '排行榜',
                icon: GameIcons.trophy,
                onTap: () =>
                    showGameRank(context, game: 'knockwater', title: '铃渡'),
              ),
            ],
            board: SizedBox(
              key: const ValueKey('kw-board'),
              width: size.width,
              height: size.height,
              child: CssShadowLayer(
                radius: 18,
                shadows: const <CssShadowSpec>[
                  CssShadowSpec(
                    color: Color(0x3D14201D),
                    offset: Offset(0, 12),
                    blur: 30,
                    spread: -14,
                  ),
                  CssShadowSpec(
                    color: Color(0x1F5A4A2C),
                    offset: Offset(0, 2),
                    blur: 6,
                  ),
                ],
                child: _buildBoard(hud, size.width, size.height),
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 水面板
  // -------------------------------------------------------------------------

  Widget _buildBoard(GameHudSnapshot hud, double width, double height) {
    final s = (width / _boardBaseWidth).clamp(0.66, 1.12);
    final knockSize = 84 * s;
    final circleSize = 50 * s;
    final chromeHidden = _showTitle || _showEnd || _introVisible;
    final playRect = Rect.fromLTWH(4, 4, width - 8, height - 8);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF030A0B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kGold.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const RepaintBoundary(
            child: CustomPaint(
              painter: BackdropPainter(),
              isComplex: true,
              willChange: false,
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.precise,
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: <Type, GestureRecognizerFactory>{
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      EagerGestureRecognizer
                    >(
                      EagerGestureRecognizer.new,
                      (EagerGestureRecognizer instance) {},
                    ),
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                onPointerCancel: _handlePointerCancel,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: PondPainter(
                      engine: _engine,
                      playRect: playRect,
                      showGame: !_showTitle,
                      repaint: _frame,
                    ),
                    isComplex: true,
                    willChange: true,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: math.min(150 * s, height * 0.36),
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0xCC030A0B), Color(0x00030A0B)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: math.min(250 * s, height * 0.48),
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x00030A0B), Color(0xF2030A0B)],
                  ),
                ),
              ),
            ),
          ),
          _buildBoardHud(hud, s, knockSize, chromeHidden),
          _buildBoardHint(hud, s, width),
          _buildBoardBottom(circleSize, knockSize, s, chromeHidden),
          _buildIntro(s, width),
          _buildTitle(s, width, height < 430),
          if (_showEnd) _buildEnd(s, width),
          _buildToast(s, knockSize),
          if (_showSelect) _buildLevelSelect(s, width),
        ],
      ),
    );
  }

  Widget _buildBoardHud(
    GameHudSnapshot hud,
    double s,
    double knockSize,
    bool chromeHidden,
  ) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        ignoring: chromeHidden,
        child: AnimatedOpacity(
          opacity: chromeHidden ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          child: Padding(
            padding: EdgeInsets.fromLTRB(14 * s, 12 * s, 12 * s, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Text(
                            '第 ${hud.levelIndex + 1} 关',
                            style: TextStyle(
                              fontSize: 10 * s,
                              letterSpacing: 2.2 * s,
                              color: kGlow.withValues(alpha: 0.42),
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          Flexible(
                            child: Text(
                              hud.levelName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _serif.copyWith(
                                fontSize: 21 * s,
                                letterSpacing: 4.6 * s,
                                color: _paper.withValues(alpha: 0.94),
                                height: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 7 * s),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: EdgeInsets.only(top: 1.5 * s),
                            child: Text(
                              '铃息',
                              style: TextStyle(
                                fontSize: 10 * s,
                                letterSpacing: 2 * s,
                                color: kGlow.withValues(alpha: 0.38),
                              ),
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          Expanded(
                            child: Wrap(
                              spacing: 3.4 * s,
                              runSpacing: 3.4 * s,
                              children: <Widget>[
                                for (var i = 0; i < hud.maxCharges; i++)
                                  _ChargeDot(filled: i < hud.charges, scale: s),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 6 * s),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    GestureDetector(
                      key: const ValueKey('kw-sound'),
                      onTap: _toggleSound,
                      child: Container(
                        width: 32 * s,
                        height: 32 * s,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF07181A)
                              .withValues(alpha: 0.55),
                          border: Border.all(
                            color: kGlow.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Icon(
                          _soundOn
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          size: 16 * s,
                          color: kGlow.withValues(alpha: _soundOn ? 0.7 : 0.3),
                        ),
                      ),
                    ),
                    SizedBox(height: 6 * s),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          '花瓣',
                          style: TextStyle(
                            fontSize: 9.5 * s,
                            letterSpacing: 1.4 * s,
                            color: kGlow.withValues(alpha: 0.4),
                          ),
                        ),
                        SizedBox(width: 4 * s),
                        Text(
                          '${hud.petalsInBay}/${hud.petalCount}',
                          style: TextStyle(
                            fontSize: 12.5 * s,
                            letterSpacing: 1 * s,
                            color: kCoral,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 3 * s),
                    Text(
                      '星数 $_starTotal/$_maxStars',
                      key: const ValueKey('kw-hud-stars'),
                      style: TextStyle(
                        fontSize: 8.5 * s,
                        letterSpacing: 0.6 * s,
                        color: kGold.withValues(alpha: 0.55),
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoardHint(GameHudSnapshot hud, double s, double width) {
    return Positioned(
      left: 0,
      right: 0,
      top: 86 * s,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _hintVisible ? 1 : 0,
          duration: const Duration(milliseconds: 600),
          child: Center(
            child: SizedBox(
              width: math.min(340 * s, width - 28),
              child: Container(
                key: const ValueKey('kw-hint'),
                padding: EdgeInsets.fromLTRB(14 * s, 9 * s, 16 * s, 10 * s),
                decoration: BoxDecoration(
                  color: const Color(0xFF051214).withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(24 * s),
                  border: Border.all(color: _paper.withValues(alpha: 0.09)),
                ),
                child: hud.levelIndex == 0
                    ? _tutorialTip(s)
                    : Row(
                        children: <Widget>[
                          Container(
                            width: 4 * s,
                            height: 4 * s,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kGold,
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: kGold.withValues(alpha: 0.7),
                                  blurRadius: 8 * s,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          Expanded(
                            child: Text(
                              kLevels[hud.levelIndex].hint,
                              style: TextStyle(
                                fontSize: 12 * s,
                                height: 1.65,
                                letterSpacing: 0.3 * s,
                                color: _paper.withValues(alpha: 0.76),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoardBottom(
    double circleSize,
    double knockSize,
    double s,
    bool chromeHidden,
  ) {
    return Positioned(
      left: 14 * s,
      right: 14 * s,
      bottom: 12 * s,
      child: IgnorePointer(
        ignoring: chromeHidden,
        child: AnimatedOpacity(
          opacity: chromeHidden ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _CircleButton(
                key: const ValueKey('kw-undo'),
                label: '撤销',
                size: circleSize,
                scale: s,
                dim: !_engine.canUndo,
                onTap: _undo,
              ),
              SizedBox(width: 9 * s),
              _CircleButton(
                key: const ValueKey('kw-restart'),
                label: '重开',
                size: circleSize,
                scale: s,
                onTap: _restart,
              ),
              SizedBox(width: 9 * s),
              _CircleButton(
                key: const ValueKey('kw-open-select'),
                label: '选关',
                size: circleSize,
                scale: s,
                onTap: _openSelect,
              ),
              const Spacer(),
              _ShakeOnFrame(
                frames: _frame,
                engine: _engine,
                shakeUntil: _shakeUntil,
                child: _buildKnockButton(knockSize, s),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKnockButton(double size, double s) {
    final e = _engine;
    final charging = e.charging;
    final available = e.charges >= 3 && e.level.allowHeavy;
    final coach = _coachVisible && !charging;
    final content = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CustomPaint(
          painter: _KnockRingPainter(engine: e, repaint: _frame),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '重叩',
                style: _serif.copyWith(
                  fontSize: 17 * s,
                  letterSpacing: 3 * s,
                  color: kGold,
                ),
              ),
              SizedBox(height: 2 * s),
              Text(
                coach ? '按住蓄力' : '3',
                style: TextStyle(
                  fontSize: (coach ? 8.5 : 9) * s,
                  letterSpacing: 0.6 * s,
                  color: kGold.withValues(alpha: coach ? 0.8 : 0.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    Widget shell;
    if (coach) {
      shell = AnimatedBuilder(
        animation: _frame,
        child: content,
        builder: (context, child) {
          final pulse = 0.5 + 0.5 * math.sin(e.time * 4);
          return _knockShell(
            size: size,
            charging: charging,
            coach: true,
            coachPulse: pulse,
            child: child!,
          );
        },
      );
    } else {
      shell = _knockShell(
        size: size,
        charging: charging,
        coach: false,
        coachPulse: 0,
        child: content,
      );
    }

    return Listener(
      key: const ValueKey('kw-knock'),
      onPointerDown: (_) => _onKnockStart(),
      onPointerUp: (_) => _onKnockEnd(),
      onPointerCancel: (_) => _onKnockCancel(),
      child: AnimatedOpacity(
        opacity: available ? 1 : 0.38,
        duration: const Duration(milliseconds: 250),
        child: AnimatedScale(
          scale: charging ? 1.045 : 1,
          duration: const Duration(milliseconds: 180),
          child: shell,
        ),
      ),
    );
  }

  Widget _knockShell({
    required double size,
    required bool charging,
    required bool coach,
    required double coachPulse,
    required Widget child,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(0, -0.15),
          colors: <Color>[Color(0xFF33594F), Color(0xFF081A1C)],
          stops: <double>[0, 0.72],
        ),
        border: Border.all(
          color: kGold.withValues(
            alpha: charging ? 0.8 : (coach ? 0.48 + 0.22 * coachPulse : 0.36),
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kGold.withValues(
              alpha: charging ? 0.22 : (coach ? 0.08 + 0.1 * coachPulse : 0.07),
            ),
            blurRadius: charging ? 34 : (coach ? 26 : 18),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _tutorialTip(double s) {
    final moved = _engine.steps > 0;
    final knocked = _hasKnocked;
    final banked = _engine.petalsInBay > 0;
    final done = (moved ? 1 : 0) + (knocked ? 1 : 0) + (banked ? 1 : 0);
    Widget row(String text, bool ok) {
      return Row(
        children: <Widget>[
          Icon(
            ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 12 * s,
            color: ok ? kGlow : _paper.withValues(alpha: 0.3),
          ),
          SizedBox(width: 6 * s),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11 * s,
                height: 1.5,
                letterSpacing: 0.2 * s,
                color: _paper.withValues(alpha: ok ? 0.82 : 0.6),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '教学 · 三步',
              style: TextStyle(
                fontSize: 10 * s,
                letterSpacing: 2 * s,
                color: kGold.withValues(alpha: 0.8),
              ),
            ),
            const Spacer(),
            Text(
              '$done/3',
              style: TextStyle(
                fontSize: 10 * s,
                color: kGlow.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        SizedBox(height: 5 * s),
        row('拖动水面，走一步', moved),
        row('按住重叩，蓄满松手', knocked),
        row('让花瓣落进湾心', banked),
      ],
    );
  }

  Widget _buildIntro(double s, double width) {
    final level = _engine.level;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _introVisible ? 1 : 0,
          duration: const Duration(milliseconds: 520),
          child: Align(
            alignment: const Alignment(0, -0.38),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18 * s),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey<int>(_level),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) {
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - t)),
                        child: child,
                      ),
                    );
                  },
                  child: SizedBox(
                    width: math.min(300 * s, width - 36),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 26 * s,
                        vertical: 18 * s,
                      ),
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          radius: 0.85,
                          colors: <Color>[Color(0x73030A0B), Color(0x00030A0B)],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            level.chapter,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10 * s,
                              letterSpacing: 4 * s,
                              color: kGold.withValues(alpha: 0.65),
                              shadows: <Shadow>[
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  blurRadius: 12 * s,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 10 * s),
                          Text(
                            level.name,
                            style: _serif.copyWith(
                              fontSize: 34 * s,
                              letterSpacing: 10 * s,
                              color: _paper.withValues(alpha: 0.96),
                              shadows: <Shadow>[
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  blurRadius: 22 * s,
                                ),
                                Shadow(
                                  color: kGlow.withValues(alpha: 0.18),
                                  blurRadius: 30 * s,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 13 * s),
                          Container(
                            width: 30 * s,
                            height: 1,
                            color: kGold.withValues(alpha: 0.45),
                          ),
                          SizedBox(height: 13 * s),
                          Text(
                            level.blurb,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11 * s,
                              height: 1.75,
                              letterSpacing: 0.8 * s,
                              color: _paper.withValues(alpha: 0.66),
                              shadows: <Shadow>[
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  blurRadius: 12 * s,
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(double s, double width, bool compact) {
    final hasProgress =
        _progress.completedCount > 0 ||
        _progress.highestUnlocked > 1 ||
        _progress.hasCheckpoint;
    var resumeIndex = (_progress.lastPlayed - 1)
        .clamp(0, kLevels.length - 1)
        .toInt();
    if (!_progress.isUnlocked(resumeIndex)) {
      resumeIndex = (_progress.highestUnlocked - 1)
          .clamp(0, kLevels.length - 1)
          .toInt();
    }
    final startLabel = !_progressReady ? '水面初醒' : (hasProgress ? '继 续' : '入 水');
    return IgnorePointer(
      ignoring: !_showTitle,
      child: AnimatedOpacity(
        opacity: _showTitle ? 1 : 0,
        duration: const Duration(milliseconds: 650),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Container(
            key: const ValueKey('kw-title'),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xCC030B0C),
                  Color(0x30030B0C),
                  Color(0xE0030B0C),
                ],
                stops: <double>[0, 0.38, 1],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: (compact ? 18 : 24) * s,
                  vertical: (compact ? 14 : 24) * s,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: (compact ? 34 : 42) * s,
                      height: (compact ? 34 : 42) * s,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: kGold.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        '铃',
                        style: _serif.copyWith(
                          fontSize: (compact ? 17 : 20) * s,
                          color: kGold,
                        ),
                      ),
                    ),
                    SizedBox(height: (compact ? 14 : 24) * s),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '铃渡',
                        style: _serif.copyWith(
                          fontSize: (compact ? 48 : 58) * s,
                          height: 1.1,
                          letterSpacing: 18 * s,
                          color: _paper.withValues(alpha: 0.97),
                          shadows: <Shadow>[
                            Shadow(
                              color: kGlow.withValues(alpha: 0.28),
                              blurRadius: 46 * s,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: (compact ? 2 : 6) * s),
                    Text(
                      '一 步 一 纹',
                      style: TextStyle(
                        fontSize: 11 * s,
                        letterSpacing: 6 * s,
                        color: kGlow.withValues(alpha: 0.5),
                      ),
                    ),
                    if (!compact) ...<Widget>[
                      SizedBox(height: 24 * s),
                      Text(
                        '你走过的路，就是你的手。',
                        textAlign: TextAlign.center,
                        style: _serif.copyWith(
                          fontSize: 14 * s,
                          letterSpacing: 1.8 * s,
                          color: _paper.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                    SizedBox(height: (compact ? 16 : 28) * s),
                    _PrimaryButton(
                      key: const ValueKey('kw-start'),
                      label: startLabel,
                      scale: s,
                      onTap: !_progressReady
                          ? null
                          : () => _startLevel(
                              hasProgress ? resumeIndex : 0,
                              resume: _progress.hasCheckpoint,
                            ),
                    ),
                    SizedBox(height: (compact ? 2 : 8) * s),
                    TextButton(
                      key: const ValueKey('kw-title-select'),
                      onPressed: _progressReady ? _openSelect : null,
                      style: TextButton.styleFrom(
                        foregroundColor: kGlow,
                        padding: EdgeInsets.symmetric(
                          horizontal: 26 * s,
                          vertical: 10 * s,
                        ),
                      ),
                      child: Text(
                        '选 关',
                        style: TextStyle(
                          fontSize: 12 * s,
                          letterSpacing: 6 * s,
                          color: kGlow.withValues(
                            alpha: _progressReady ? 0.72 : 0.35,
                          ),
                        ),
                      ),
                    ),
                    if (hasProgress && !compact) ...<Widget>[
                      SizedBox(height: 8 * s),
                      Text(
                        '已通关 ${_progress.completedCount}/${kLevels.length} · '
                        '已解锁 ${_progress.highestUnlocked}/${kLevels.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10 * s,
                          letterSpacing: 1.4 * s,
                          color: _paper.withValues(alpha: 0.38),
                        ),
                      ),
                      SizedBox(height: 4 * s),
                      Text(
                        '累计星数 $_starTotal/$_maxStars · 全站榜按星数排名',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10 * s,
                          letterSpacing: 1.1 * s,
                          color: kGold.withValues(alpha: 0.42),
                        ),
                      ),
                    ],
                    if (!compact) ...<Widget>[
                      SizedBox(height: 24 * s),
                      Text(
                        '拖动水面行走 · 每一步荡开一圈铃波\n把花瓣推回湾心，别让它搁浅',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11 * s,
                          height: 2,
                          letterSpacing: 1 * s,
                          color: _paper.withValues(alpha: 0.3),
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

  Widget _buildEnd(double s, double width) {
    final e = _engine;
    final won = e.status == GameStatus.won;
    final finalLevel = won && _level == kLevels.length - 1;
    final title = won
        ? (finalLevel ? '全池已醒' : '湾心已满')
        : (e.loseReason == LoseReason.stranded ? '花瓣搁浅' : '铃息已尽');
    final text = won
        ? (finalLevel
              ? '水记住了你的脚步。\n湾心重新亮起来，池水开始唱歌。'
              : '还剩 ${e.charges} 点铃息。\n水面安静下来，听它慢慢合上。')
        : (e.loseReason == LoseReason.stranded
              ? '它留在了浅滩上。\n再轻一点，或者换一条路。'
              : '水面安静下来，还有花瓣没有回到湾心。');

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          key: const ValueKey('kw-end'),
          color: const Color(0xFF030B0C).withValues(alpha: 0.62),
          alignment: Alignment.center,
          padding: EdgeInsets.all(6 * s),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - t)),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: math.min(330 * s, width - 32),
                  padding: EdgeInsets.fromLTRB(24 * s, 24 * s, 24 * s, 20 * s),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0xF20C2223), Color(0xF7051012)],
                    ),
                    border: Border.all(color: kGold.withValues(alpha: 0.24)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(color: Color(0x99000000), blurRadius: 60),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        won ? '第 ${_level + 1} 关 · 完成' : '水 面',
                        style: TextStyle(
                          fontSize: 10 * s,
                          letterSpacing: 4 * s,
                          color: kGold.withValues(alpha: 0.6),
                        ),
                      ),
                      SizedBox(height: 10 * s),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          style: _serif.copyWith(
                            fontSize: 28 * s,
                            letterSpacing: 5 * s,
                            color: _paper.withValues(alpha: 0.96),
                          ),
                        ),
                      ),
                      if (won) ...<Widget>[
                        SizedBox(height: 16 * s),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOut,
                          builder: (context, t, _) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                for (var i = 0; i < 3; i++)
                                  Opacity(
                                    opacity: t,
                                    child: Transform.scale(
                                      scale:
                                          0.45 +
                                          0.55 *
                                              Curves.easeOutBack.transform(
                                                ((t * 1.7) - i * 0.35).clamp(
                                                  0.0,
                                                  1.0,
                                                ),
                                              ),
                                      child: Container(
                                        width: 10 * s,
                                        height: 10 * s,
                                        margin: EdgeInsets.symmetric(
                                          horizontal: 5 * s,
                                        ),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: i < e.stars
                                              ? kGold
                                              : Colors.transparent,
                                          border: Border.all(
                                            color: kGold.withValues(
                                              alpha: i < e.stars ? 1 : 0.3,
                                            ),
                                          ),
                                          boxShadow: i < e.stars
                                              ? <BoxShadow>[
                                                  BoxShadow(
                                                    color: kGold.withValues(
                                                      alpha: 0.5,
                                                    ),
                                                    blurRadius: 10 * s,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        SizedBox(height: 4 * s),
                        Text(
                          '累计星数 $_starTotal/$_maxStars · 全站榜按星数排名',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10 * s,
                            letterSpacing: 0.8 * s,
                            color: kGold.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                      SizedBox(height: 12 * s),
                      Text(
                        text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12 * s,
                          height: 1.9,
                          letterSpacing: 0.4 * s,
                          color: _paper.withValues(alpha: 0.5),
                        ),
                      ),
                      SizedBox(height: 20 * s),
                      if (won) ...<Widget>[
                        _ActionButton(
                          key: const ValueKey('kw-next'),
                          label: finalLevel ? '回到第一关' : '下一关',
                          primary: true,
                          scale: s,
                          onTap: _nextLevel,
                        ),
                        SizedBox(height: 9 * s),
                      ] else if (e.canUndo) ...<Widget>[
                        _ActionButton(
                          key: const ValueKey('kw-end-undo'),
                          label: '回溯一步',
                          primary: true,
                          scale: s,
                          onTap: _undo,
                        ),
                        SizedBox(height: 9 * s),
                      ],
                      _ActionButton(
                        key: const ValueKey('kw-end-restart'),
                        label: won ? '再走一次' : '重开',
                        primary: !won && !e.canUndo,
                        scale: s,
                        onTap: _restart,
                      ),
                      SizedBox(height: 2 * s),
                      TextButton(
                        key: const ValueKey('kw-end-select'),
                        onPressed: _openSelect,
                        style: TextButton.styleFrom(
                          foregroundColor: kGlow,
                          padding: EdgeInsets.symmetric(vertical: 8 * s),
                        ),
                        child: Text(
                          '选 关',
                          style: TextStyle(
                            fontSize: 11 * s,
                            letterSpacing: 3 * s,
                            color: kGlow.withValues(alpha: 0.68),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLevelSelect(double s, double width) {
    final byChapter = <String, List<int>>{};
    for (var i = 0; i < kLevels.length; i++) {
      byChapter.putIfAbsent(kLevels[i].chapter, () => <int>[]).add(i);
    }
    const gap = 8.0;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          key: const ValueKey('kw-select'),
          color: const Color(0xF7030B0C),
          child: Column(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(6 * s, 6 * s, 14 * s, 2 * s),
                child: Row(
                  children: <Widget>[
                    GestureDetector(
                      key: const ValueKey('kw-select-close'),
                      onTap: _closeSelect,
                      child: Padding(
                        padding: EdgeInsets.all(8 * s),
                        child: Icon(
                          Icons.close_rounded,
                          size: 20 * s,
                          color: _paper.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    SizedBox(width: 2 * s),
                    Text(
                      '选 关',
                      style: _serif.copyWith(
                        fontSize: 24 * s,
                        letterSpacing: 5 * s,
                        color: _paper.withValues(alpha: 0.96),
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        '已通关 ${_progress.completedCount}/${kLevels.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10 * s,
                          letterSpacing: 1 * s,
                          color: kGold.withValues(alpha: 0.68),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(14 * s, 6 * s, 14 * s, 22 * s),
                  children: <Widget>[
                    for (final entry in byChapter.entries) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              entry.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11 * s,
                                letterSpacing: 2.2 * s,
                                color: kGold.withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${entry.value.where(_progress.isCompleted).length}'
                            '/${entry.value.length}',
                            style: TextStyle(
                              fontSize: 10 * s,
                              color: _paper.withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8 * s),
                      LayoutBuilder(
                        builder: (context, cons) {
                          final tileW = (cons.maxWidth - gap * 3) / 4;
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: <Widget>[
                              for (final i in entry.value)
                                SizedBox(width: tileW, child: _levelTile(i, s)),
                            ],
                          );
                        },
                      ),
                      SizedBox(height: 16 * s),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _levelTile(int index, double s) {
    final unlocked = _progress.isUnlocked(index);
    final completed = _progress.isCompleted(index);
    final stars = _progress.starsFor(index);
    final current = index == _level;
    final border = current
        ? kGold.withValues(alpha: 0.75)
        : completed
        ? kGlow.withValues(alpha: 0.42)
        : _paper.withValues(alpha: 0.12);
    return IgnorePointer(
      ignoring: !unlocked,
      child: GestureDetector(
        key: ValueKey<String>('kw-level-${index + 1}'),
        onTap: unlocked ? () => _startLevel(index) : null,
        child: Opacity(
          opacity: unlocked ? 1 : 0.42,
          child: Container(
            height: 66 * s,
            padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 6 * s),
            decoration: BoxDecoration(
              color: unlocked
                  ? const Color(0xCC0A1D1F)
                  : const Color(0x99071113),
              border: Border.all(color: border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 10 * s,
                    letterSpacing: 1 * s,
                    color: unlocked
                        ? kGold.withValues(alpha: 0.82)
                        : _paper.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 2 * s),
                Text(
                  kLevels[index].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11 * s,
                    letterSpacing: 0.5 * s,
                    color: _paper.withValues(alpha: unlocked ? 0.82 : 0.45),
                  ),
                ),
                SizedBox(height: 2 * s),
                if (!unlocked)
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 11 * s,
                    color: _paper.withValues(alpha: 0.34),
                  )
                else if (completed)
                  Text(
                    stars > 0 ? List<String>.filled(stars, '★').join() : '✓',
                    style: TextStyle(
                      fontSize: 9 * s,
                      letterSpacing: 1 * s,
                      color: kGold.withValues(alpha: 0.8),
                    ),
                  )
                else
                  SizedBox(height: 9 * s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToast(double s, double knockSize) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 12 * s + knockSize + 16 * s,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _toast == null ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 16 * s,
                vertical: 8 * s,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF051012).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(30 * s),
                border: Border.all(color: _paper.withValues(alpha: 0.1)),
              ),
              child: Text(
                _toast ?? '',
                style: TextStyle(
                  fontSize: 11 * s,
                  letterSpacing: 1 * s,
                  color: _paper.withValues(alpha: 0.66),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 小组件
// ---------------------------------------------------------------------------

class _ShakeOnFrame extends StatefulWidget {
  const _ShakeOnFrame({
    required this.frames,
    required this.engine,
    required this.shakeUntil,
    required this.child,
  });

  final Listenable frames;
  final Engine engine;
  final double shakeUntil;
  final Widget child;

  @override
  State<_ShakeOnFrame> createState() => _ShakeOnFrameState();
}

/// 只在「铃息不足」的 0.36s 内监听逐帧值。
/// 空闲时不订阅 Ticker，也不重建/重绘按钮子树。
class _ShakeOnFrameState extends State<_ShakeOnFrame> {
  double _dx = 0;
  bool _listening = false;

  double get _shakeOffset {
    final t = (widget.shakeUntil - widget.engine.time)
        .clamp(0.0, 0.36)
        .toDouble();
    if (t <= 0) return 0;
    return math.sin(widget.engine.time * 72) * 5 * (t / 0.36);
  }

  @override
  void initState() {
    super.initState();
    _syncListener();
  }

  @override
  void didUpdateWidget(covariant _ShakeOnFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frames != widget.frames && _listening) {
      oldWidget.frames.removeListener(_onFrame);
      _listening = false;
    }
    _syncListener();
  }

  void _syncListener() {
    final active = widget.shakeUntil > widget.engine.time;
    if (active) {
      if (!_listening) {
        widget.frames.addListener(_onFrame);
        _listening = true;
      }
      _dx = _shakeOffset;
    } else {
      _stop();
      _dx = 0;
    }
  }

  void _onFrame() {
    final next = _shakeOffset;
    if (next == 0) _stop();
    if (next != _dx) setState(() => _dx = next);
  }

  void _stop() {
    if (_listening) {
      widget.frames.removeListener(_onFrame);
      _listening = false;
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dx == 0) return widget.child;
    return Transform.translate(offset: Offset(_dx, 0), child: widget.child);
  }
}

class _ChargeDot extends StatelessWidget {
  const _ChargeDot({required this.filled, required this.scale});

  final bool filled;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: (filled ? 6 : 5) * scale,
      height: (filled ? 6 : 5) * scale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? kGold.withValues(alpha: 0.86) : Colors.transparent,
        border: filled
            ? null
            : Border.all(color: kGold.withValues(alpha: 0.22)),
        boxShadow: filled
            ? <BoxShadow>[
                BoxShadow(
                  color: kGold.withValues(alpha: 0.45),
                  blurRadius: 7 * scale,
                ),
              ]
            : null,
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    super.key,
    required this.label,
    required this.size,
    required this.scale,
    required this.onTap,
    this.dim = false,
  });

  final String label;
  final double size;
  final double scale;
  final VoidCallback onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: dim ? 0.32 : 1,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF07181A).withValues(alpha: 0.62),
            border: Border.all(color: kGold.withValues(alpha: 0.28)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11 * scale,
              letterSpacing: 0.6 * scale,
              color: _paper.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,
    required this.label,
    required this.scale,
    required this.onTap,
  });

  final String label;
  final double scale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 40 * scale,
            vertical: 12 * scale,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xA62E524A), Color(0xCC0C2222)],
            ),
            border: Border.all(color: kGold.withValues(alpha: 0.55)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: kGold.withValues(alpha: 0.1),
                blurRadius: 34 * scale,
              ),
            ],
          ),
          child: Text(
            label,
            style: _serif.copyWith(
              fontSize: 15 * scale,
              letterSpacing: 6 * scale,
              color: const Color(0xFFF6ECD9),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.scale,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final double scale;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 11 * scale),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: primary
              ? const LinearGradient(
                  colors: <Color>[Color(0x8C34584F), Color(0xBF0C2222)],
                )
              : null,
          color: primary ? null : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: primary
                ? kGold.withValues(alpha: 0.5)
                : _paper.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13 * scale,
            letterSpacing: 2.2 * scale,
            color: primary
                ? const Color(0xFFF6ECD9)
                : _paper.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }
}

class _KnockRingPainter extends CustomPainter {
  _KnockRingPainter({required this.engine, required Listenable repaint})
    : super(repaint: repaint);

  final Engine engine;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = engine.charging ? engine.chargeRatio : 0.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = kGold.withValues(alpha: 0.16);
    canvas.drawCircle(center, radius, base);
    if (progress <= 0.001) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD08A).withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD79A).withValues(alpha: 0.9);
    final sweep = progress * math.pi * 2;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, glow);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _KnockRingPainter oldDelegate) =>
      oldDelegate.engine != engine;
}
