import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'game_ui.dart';

/// 跳一跳 —— 1:1 复刻 web `#gjumpPage`（index.html 8509-8555 / 19749-20529）。
///
/// 视觉基准（390×844 light）：
///   .g-body            padding 15.192/14/12，纵向居中
///   h1                 跳一跳，ZCOOL 25.74px / line-height 1.65 / ls .06em（无下划线）
///   .g-hud             单行 56.6406：pills 62 + 63.0469 + actions 215.469，gap 9 / 8
///   .gjump-wrap        362×568 纸底 #FFFDF8 + 1px #E4DCC9 + r14 + paper-shadow
///   canvas             360×566；等距投影 sx=CW/2+(x-y-camX)*0.86*SC,
///                      sy=anchorY+(cam-(x+y))*0.44*SC-z；SC=min(1,w/700)
///   .gjump-hint        163.062×33.797 @bottom 12，纸底 + #D2C8B0 边 + r99
///   .gjump-overlay     360×566 rgba(246,239,223,.93)，r22
class GameJumpPage extends StatefulWidget {
  const GameJumpPage({super.key});
  @override
  State<GameJumpPage> createState() => _GameJumpPageState();
}

// ---------------------------------------------------------------------------
// 数据模型（与 web JS 的 block / style 结构一一对应）
// ---------------------------------------------------------------------------

const double _ix = .86; // GJUMP_IX
const double _iy = .44; // GJUMP_IY
const double _minD = 42; // GJUMP_MIN_D
const double _maxD = 322; // GJUMP_MAX_D
const double _chargeMs = 1350; // GJUMP_CHARGE_MS

class _JumpStyle {
  const _JumpStyle({
    required this.shape,
    required this.top,
    required this.left,
    required this.right,
    required this.pat,
    this.ac,
  });

  final String shape; // box / cyl / cone / hex
  final Color top;
  final Color left;
  final Color right;
  final String
  pat; // inset/checker/rubik/ribbon/wood/grid/dots/ring/lantern/floral
  final Color? ac;
}

class _JumpBlock {
  _JumpBlock({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.style,
    this.special,
    this.ax = 0,
  });

  final double x;
  final double y;
  final double w;
  final double h;
  final _JumpStyle style;
  final String? special; // music / manhole
  final int ax;
  bool gotBonus = false;

  /// web block.cyl：圆/棱柱（special 恒为圆柱）
  bool get cyl => special != null || style.shape != 'box';
}

class _JumpFloat {
  _JumpFloat({
    required this.x,
    required this.y,
    required this.text,
    required this.big,
  });
  final double x;
  double y;
  double life = 1;
  final String text;
  final bool big;
}

class _JumpParticle {
  _JumpParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.color,
  });
  double x;
  double y;
  double vx;
  double vy;
  double life = 1;
  final double r;
  final Color color;
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// web GJUMP_STYLES（顺序与 index.html 19761-19774 完全一致）
const List<_JumpStyle> _jumpStyles = [
  _JumpStyle(
    shape: 'box',
    top: Color(0xFFF7EFDD),
    left: Color(0xFFD8C7A5),
    right: Color(0xFFC9B48C),
    pat: 'inset',
  ),
  _JumpStyle(
    shape: 'box',
    top: Color(0xFFF3E6C9),
    left: Color(0xFFD3BB92),
    right: Color(0xFFC3AA7F),
    pat: 'checker',
    ac: Color(0xFFB04E00),
  ),
  _JumpStyle(
    shape: 'box',
    top: Color(0xFFE8B98A),
    left: Color(0xFFC68F5C),
    right: Color(0xFFB57F4C),
    pat: 'rubik',
  ),
  _JumpStyle(
    shape: 'box',
    top: Color(0xFFF6D9D0),
    left: Color(0xFFD8AC9E),
    right: Color(0xFFC79A8B),
    pat: 'ribbon',
    ac: Color(0xFFFE923B),
  ),
  _JumpStyle(
    shape: 'box',
    top: Color(0xFFE2C195),
    left: Color(0xFFBC9768),
    right: Color(0xFFAA8557),
    pat: 'wood',
  ),
  _JumpStyle(
    shape: 'box',
    top: Color(0xFFEFD9B8),
    left: Color(0xFFCEAE82),
    right: Color(0xFFBD9C6F),
    pat: 'grid',
  ),
  _JumpStyle(
    shape: 'cyl',
    top: Color(0xFFF6E7D6),
    left: Color(0xFFDBC2A7),
    right: Color(0xFFCAB092),
    pat: 'dots',
    ac: Color(0xFFB04E00),
  ),
  _JumpStyle(
    shape: 'cyl',
    top: Color(0xFFEAD2C2),
    left: Color(0xFFC8AB96),
    right: Color(0xFFB79B85),
    pat: 'ring',
  ),
  _JumpStyle(
    shape: 'cyl',
    top: Color(0xFFF4C467),
    left: Color(0xFFB84A1C),
    right: Color(0xFFC5531F),
    pat: 'lantern',
    ac: Color(0xFFF4C467),
  ),
  _JumpStyle(
    shape: 'cyl',
    top: Color(0xFFE3ECE6),
    left: Color(0xFFB4C6BD),
    right: Color(0xFFA3B7AC),
    pat: 'floral',
    ac: Color(0xFF4A7A6A),
  ),
  _JumpStyle(
    shape: 'cone',
    top: Color(0xFFF0DFC0),
    left: Color(0xFFCFB287),
    right: Color(0xFFBFA276),
    pat: 'ring',
  ),
  _JumpStyle(
    shape: 'hex',
    top: Color(0xFFEFE3CF),
    left: Color(0xFFCDBB97),
    right: Color(0xFFBCA883),
    pat: 'inset',
  ),
];

const _JumpStyle _musicStyle = _JumpStyle(
  shape: 'cyl',
  top: Color(0xFF6B4A38),
  left: Color(0xFF543A2B),
  right: Color(0xFF5E4130),
  pat: 'none',
);
const _JumpStyle _manholeStyle = _JumpStyle(
  shape: 'cyl',
  top: Color(0xFF8C8578),
  left: Color(0xFF6E695E),
  right: Color(0xFF7B7568),
  pat: 'none',
);

// 花纹用色（web 里是 rgba 字符串）
const Color _dk = Color(0x292A211C); // rgba(42,33,28,.16)
const Color _edge2 = Color(0x332A211C); // rgba(42,33,28,.2)
const Color _dark18 = Color(0x2E2A211C); // rgba(42,33,28,.18)
const Color _dotDark15 = Color(0x262A211C); // rgba(42,33,28,.15)
const Color _white55 = Color(0x8CF4F1ED); // rgba(244,241,237,.55)
const Color _white25 = Color(0x40F4F1ED);
const Color _white20 = Color(0x33F4F1ED);

/// 首屏参考图反解出的初始台面（唯一目标截图 _tmp/ref/games/gjump-m-l.png）
List<_JumpBlock> _previewBlocks() => [
  _JumpBlock(x: 0, y: 0, w: 56, h: 34, style: _jumpStyles[5]), // 窗格
  _JumpBlock(x: 132, y: 0, w: 46, h: 35, style: _jumpStyles[0]), // 素纸
  _JumpBlock(x: 132, y: 120, w: 34, h: 40, style: _jumpStyles[4]), // 木箱
];

// ---------------------------------------------------------------------------
// 页面逻辑（玩法 / 计分 / 最高分 / 提交分数，保留原有接口）
// ---------------------------------------------------------------------------

class _Fly {
  _Fly({
    required this.t0,
    required this.t,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.h0,
    required this.h1,
    required this.arc,
  });
  final double t0, t, x0, y0, x1, y1, h0, h1, arc;
}

class _Fall {
  _Fall({required this.t0, required this.z});
  final double t0;
  double z;
  double rot = 0;
  double vz = 0;
}

/// 画布每帧读取的可变快照。
///
/// 游戏逻辑更新它并推进 [ValueNotifier]，CustomPainter 直接重绘；
/// HUD / 页面只在落点、开始蓄力、结算等离散事件时 setState。
class _JumpFrameData {
  List<_JumpBlock> blocks = const [];
  int cur = 0;
  double playerX = 0;
  double playerY = 0;
  double playerZ = 0;
  double groundH = 0;
  double pieceScaleX = 1;
  double pieceScaleY = 1;
  double pieceRot = 0;
  double cam = 0;
  double camX = 0;
  double power = 0;
  bool charging = false;
  bool stayOn = false;
  double stayProgress = 0;
  List<_JumpFloat> floats = const [];
  List<_JumpParticle> particles = const [];
}

class _GameJumpPageState extends State<GameJumpPage>
    with SingleTickerProviderStateMixin {
  final math.Random _rnd = math.Random();
  final Stopwatch _clock = Stopwatch()..start();
  final ValueNotifier<String> _progress = ValueNotifier<String>('分数 0');
  late final Ticker _ticker;
  bool _tickerReady = false;
  Duration _lastElapsed = Duration.zero;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final _JumpFrameData _scene = _JumpFrameData();

  List<_JumpBlock> _blocks = [];
  int _cur = 0;
  double _px = 0;
  double _py = 0;
  double _z = 0;
  double _cam = 0;
  double _camTo = 0;
  double _camX = 0;
  double _camXTo = 0;
  double _power = 0;
  double _chargeT0 = 0;
  double _chargeBeepAcc = 0;
  String _state = 'ready'; // ready / charge / fly / fall / over
  _Fly? _fly;
  _Fall? _fall;
  double _landT = 0;
  bool _stayOn = false;
  double _stayT0 = 0;
  final List<_JumpFloat> _floats = [];
  final List<_JumpParticle> _parts = [];
  bool _over = false;
  bool _improved = false;
  bool _hintOn = true;
  int _score = 0;
  int _best = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _axis = 0;
  _JumpStyle? _lastStyle;

  double get _now => _clock.elapsedMilliseconds.toDouble();

  @override
  void initState() {
    super.initState();
    GameSfx.soundsEnabled = true; // v1.6.0：仅刹车与跳一跳保留音效
    _newGame();
    // 用 Choreographer 驱动的 Ticker 取代 16ms 定时器：60Hz 设备跑 60fps，
    // 120Hz 设备直接跑 120fps，且与屏幕 vsync 对齐，不会出现半帧抖动。
    _ticker = createTicker(_onFrame)..start();
    _tickerReady = true;
  }

  @override
  void dispose() {
    _ticker.dispose();
    GameSfx.soundsEnabled = false;
    _progress.dispose();
    _frame.dispose();
    super.dispose();
  }

  _JumpStyle _pickStyle() {
    _JumpStyle s;
    do {
      s = _jumpStyles[_rnd.nextInt(_jumpStyles.length)];
    } while (_lastStyle != null && identical(s, _lastStyle));
    _lastStyle = s;
    return s;
  }

  void _genNext() {
    final prev = _blocks.last;
    final w = 34 + _rnd.nextDouble() * 28;
    var d = 96 + _rnd.nextDouble() * 150;
    if (d < prev.w + w + 10) d = prev.w + w + 10;
    final roll = _rnd.nextDouble();
    String? special;
    if (roll < .09) {
      special = 'music';
    } else if (roll < .17) {
      special = 'manhole';
    }
    final st = _pickStyle();
    _blocks.add(
      _JumpBlock(
        x: prev.x + (_axis == 0 ? d : 0),
        y: prev.y + (_axis == 1 ? d : 0),
        w: w,
        h: 24 + _rnd.nextDouble() * 22,
        style: st,
        special: special,
        ax: _axis,
      ),
    );
    _axis = 1 - _axis;
  }

  void _newGame() {
    final st0 = _pickStyle();
    _blocks = [_JumpBlock(x: 0, y: 0, w: 56, h: 34, style: st0)];
    _cur = 0;
    _score = 0;
    _combo = 0;
    _maxCombo = 0;
    _over = false;
    _improved = false;
    _px = 0;
    _py = 0;
    _z = _blocks[0].h;
    _cam = 0;
    _camTo = 0;
    _camX = 0;
    _camXTo = 0;
    _power = 0;
    _fly = null;
    _fall = null;
    _landT = 0;
    _stayOn = false;
    _floats.clear();
    _parts.clear();
    _state = 'ready';
    _hintOn = true;
    _genNext();
    _genNext();
    _progress.value = '分数 0';
    if (mounted) setState(() {});
    if (_tickerReady && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  bool _hit(_JumpBlock b) {
    final dx = (_px - b.x).abs();
    final dy = (_py - b.y).abs();
    if (b.cyl) return math.sqrt(dx * dx + dy * dy) <= b.w + 4;
    return math.max(dx, dy) <= b.w + 4;
  }

  bool _centerHit(_JumpBlock b) {
    final dx = (_px - b.x).abs();
    final dy = (_py - b.y).abs();
    if (b.cyl) return math.sqrt(dx * dx + dy * dy) <= b.w * .38;
    return math.max(dx, dy) <= b.w * .38;
  }

  void _landOn(int idx) {
    final b = _blocks[idx];
    final m = b.w - 3;
    _px = math.max(b.x - m, math.min(b.x + m, _px));
    _py = math.max(b.y - m, math.min(b.y + m, _py));
    _z = b.h;
    _cur = idx;
    _landT = _now;
    _camTo = b.x + b.y;
    _camXTo = b.x - b.y;
    while (_blocks.length < idx + 2) {
      _genNext();
    }
    if (b.special != null && !b.gotBonus) {
      _stayOn = true;
      _stayT0 = _now;
    } else {
      _stayOn = false;
    }
    _state = 'ready';
  }

  void _addFloat(String text, bool big) {
    final p = _proj(_px, _py, _z + 46);
    _floats.add(_JumpFloat(x: p.dx, y: p.dy, text: text, big: big));
    if (_floats.length > 8) _floats.removeAt(0);
  }

  void _burst(int n) {
    final p = _proj(_px, _py, _z + 8);
    const cols = [
      Color(0xFFFE923B),
      Color(0xFFFFC46B),
      Color(0xFFF4F1ED),
      Color(0xFFE8B98A),
    ];
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final v = .06 + _rnd.nextDouble() * .16;
      _parts.add(
        _JumpParticle(
          x: p.dx,
          y: p.dy,
          vx: math.cos(a) * v,
          vy: math.sin(a) * v - .12,
          r: 2 + _rnd.nextDouble() * 2.4,
          color: cols[i % cols.length],
        ),
      );
    }
    if (_parts.length > 120) _parts.removeRange(0, _parts.length - 120);
  }

  Future<void> _save() async {
    await context.app.saveLocalBest('jump', _score);
    await context.app.submitScore('jump', _score);
  }

  void _end() {
    if (_over) return;
    _over = true;
    _state = 'over';
    GameSfx.lose();
    _improved = _score > _best;
    if (_improved) _best = _score;
    _save();
    _ticker.stop();
    _lastElapsed = Duration.zero;
    if (mounted) setState(() {});
  }

  void _land() {
    final n1 = _cur + 1 < _blocks.length ? _blocks[_cur + 1] : null;
    final n2 = _cur + 2 < _blocks.length ? _blocks[_cur + 2] : null;
    if (n1 != null && _hit(n1)) {
      if (_centerHit(n1)) {
        _combo++;
        if (_combo > _maxCombo) _maxCombo = _combo;
        final gain = 2 * _combo;
        _score += gain;
        _addFloat('+$gain${_combo > 1 ? ' 连击' : ' 完美'}', true);
        _burst(10);
        GameSfx.match();
      } else {
        _combo = 0;
        _score += 1;
        _addFloat('+1', false);
        GameSfx.eat();
      }
      _landOn(_cur + 1);
      _progress.value = '分数 $_score';
      setState(() {});
      return;
    }
    if (n2 != null && _hit(n2)) {
      _combo = 0;
      _score += 1;
      _addFloat('+1', false);
      GameSfx.eat();
      _landOn(_cur + 2);
      _progress.value = '分数 $_score';
      setState(() {});
      return;
    }
    final b = _blocks[_cur];
    if (_hit(b)) {
      _combo = 0;
      _landOn(_cur);
      setState(() {});
      return;
    }
    _fall = _Fall(t0: _now, z: _z);
    _state = 'fall';
  }

  void _pressDown() {
    if (_over || _state != 'ready') return;
    _chargeBeepAcc = 60; // 按下立即响第一声
    setState(() {
      _state = 'charge';
      _chargeT0 = _now;
      _power = 0;
      _hintOn = false;
    });
  }

  void _pressUp() {
    if (_state != 'charge') return;
    final p = math.min(1.0, (_now - _chargeT0) / _chargeMs);
    final b = _blocks[_cur];
    if (_cur + 1 >= _blocks.length) return;
    final nb = _blocks[_cur + 1];
    final dist = _minD + p * (_maxD - _minD);
    setState(() {
      _fly = _Fly(
        t0: _now,
        t: 460 + dist * .42,
        x0: _px,
        y0: _py,
        x1: _px + (nb.ax == 0 ? dist : 0),
        y1: _py + (nb.ax == 1 ? dist : 0),
        h0: b.h,
        h1: nb.h,
        arc: 86 + dist * .34,
      );
      _state = 'fly';
    });
  }

  void _onFrame(Duration elapsed) {
    if (!mounted) return;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000.0;
    _lastElapsed = elapsed;
    if (dt <= 0) dt = 16;
    dt = dt.clamp(1.0, 50.0);
    final now = _now;
    if (_cur > 4) {
      final cut = _cur - 4;
      _blocks.removeRange(0, cut);
      _cur -= cut;
    }
    final camK = math.min(1.0, dt * .0075);
    _cam += (_camTo - _cam) * camK;
    _camX += (_camXTo - _camX) * camK;

    if (_state == 'charge') {
      _power = math.min(1.0, (now - _chargeT0) / _chargeMs);
      // v1.6.0：蓄力声音提示 —— 音高随力度上行的节拍音（每 70ms 一格），
      // 松手起跳即停；web 端按住时的 tick 提示同思路。
      _chargeBeepAcc += dt;
      if (_chargeBeepAcc >= 70) {
        _chargeBeepAcc = 0;
        unawaited(
          GameSfx.tone(
            freq: 300 + 620 * _power,
            dur: 0.045,
            type: 'square',
            vol: 0.055 + 0.045 * _power,
          ),
        );
      }
    } else if (_state == 'fly') {
      final f = _fly!;
      final k = (now - f.t0) / f.t;
      if (k >= 1) {
        _px = f.x1;
        _py = f.y1;
        _land();
      } else {
        _px = f.x0 + (f.x1 - f.x0) * k;
        _py = f.y0 + (f.y1 - f.y0) * k;
        _z = f.h0 + (f.h1 - f.h0) * k + f.arc * 4 * k * (1 - k);
      }
    } else if (_state == 'fall') {
      final f = _fall!;
      final k = (now - f.t0) / 900;
      if (k >= 1) {
        _fall = null;
        _end();
      } else {
        f.vz += .0011 * dt;
        f.z -= f.vz * dt;
        f.rot = math.min(1.3, k * 1.6);
        _z = f.z;
      }
    } else if (_state == 'ready' && _stayOn) {
      final b = _blocks[_cur];
      if (b.special == null || b.gotBonus) {
        _stayOn = false;
      } else if (now - _stayT0 >= 2000) {
        b.gotBonus = true;
        _stayOn = false;
        final gain = b.special == 'music' ? 30 : 5;
        _score += gain;
        _addFloat('+$gain${b.special == 'music' ? ' ♪' : ''}', true);
        _burst(14);
        _progress.value = '分数 $_score';
        if (mounted) setState(() {});
      }
    }

    for (var i = _floats.length - 1; i >= 0; i--) {
      final f = _floats[i];
      f.life -= dt / 950;
      f.y -= dt * .055;
      if (f.life <= 0) _floats.removeAt(i);
    }
    for (var i = _parts.length - 1; i >= 0; i--) {
      final f = _parts[i];
      f.life -= dt / 820;
      f.x += f.vx * dt;
      f.y += f.vy * dt;
      f.vy += .00052 * dt;
      if (f.life <= 0) _parts.removeAt(i);
    }
    _syncScene(now);
    _frame.value++;
  }

  /// 把当前物理/动画参数写入画布快照。只推进 [_frame]，不重建整页。
  void _syncScene(double now) {
    final b = _blocks.isEmpty ? null : _blocks[_cur];
    var sx = 1.0;
    var sy = 1.0;
    var z = _z;
    if (_state == 'charge') {
      sy = 1 - .42 * _power;
      sx = 1 + .28 * _power;
    } else if (_landT > 0 && now - _landT < 170) {
      final lk = 1 - (now - _landT) / 170;
      sy = 1 - .16 * lk;
      sx = 1 + .11 * lk;
    } else if (_state == 'ready') {
      z += 1.5 + math.sin(now * .004) * 1.5;
    }
    var groundH = b?.h ?? 0;
    if (_state == 'fly' && _fly != null) {
      final f = _fly!;
      final k = math.min(1.0, (now - f.t0) / f.t);
      groundH = f.h0 + (f.h1 - f.h0) * k;
    }
    _scene
      ..blocks = _blocks
      ..cur = _cur
      ..playerX = _px
      ..playerY = _py
      ..playerZ = z
      ..groundH = groundH
      ..pieceScaleX = sx
      ..pieceScaleY = sy
      ..pieceRot = _state == 'fall' && _fall != null ? _fall!.rot : 0
      ..cam = _cam
      ..camX = _camX
      ..power = _power
      ..charging = _state == 'charge'
      ..stayOn = _stayOn
      ..stayProgress = _stayOn ? math.min(1.0, (now - _stayT0) / 2000) : 0
      ..floats = _floats
      ..particles = _parts;
  }

  Offset _proj(double x, double y, double z) {
    // 运行期投影按 360×566 基准近似（飘字起点用，最终由 painter 精确绘制）
    const cw = 360.0;
    const ch = 566.0;
    const anchorY = ch * .66;
    const sc = 360.0 / 700;
    return Offset(
      cw * .5 + ((x - y) - _camX) * _ix * sc,
      anchorY + (_cam - (x + y)) * _iy * sc - z,
    );
  }

  @override
  Widget build(BuildContext context) {
    final best = math.max(_best, context.app.localBest('jump'));
    _syncScene(_now);
    return GameJumpView(
      score: _score,
      best: best,
      frameData: _scene,
      sceneRepaint: _frame,
      hintOn: _hintOn,
      overlayVisible: _over,
      overlayScore: _score,
      overlayMaxCombo: _maxCombo,
      overlayImproved: _improved,
      liveProgress: _progress,
      onPressDown: _pressDown,
      onPressUp: _pressUp,
      onNew: _newGame,
      onRank: () => showGameRank(context, game: 'jump', title: '跳一跳'),
      onRetry: _newGame,
    );
  }
}

// ---------------------------------------------------------------------------
// 纯视觉层
// ---------------------------------------------------------------------------

class GameJumpView extends StatelessWidget {
  const GameJumpView({
    super.key,
    required this.score,
    required this.best,
    this.blocks = const [],
    this.cur = 0,
    this.playerX = 0,
    this.playerY = 0,
    this.playerZ = 0,
    this.groundH = 0,
    this.pieceScaleX = 1,
    this.pieceScaleY = 1,
    this.pieceRot = 0,
    this.cam = 0,
    this.camX = 0,
    this.power = 0,
    this.charging = false,
    this.stayOn = false,
    this.stayProgress = 0,
    this.floats = const [],
    this.particles = const [],
    this.frameData,
    this.sceneRepaint,
    this.hintOn = true,
    this.overlayVisible = false,
    this.overlayScore = 0,
    this.overlayMaxCombo = 0,
    this.overlayImproved = false,
    this.liveProgress,
    this.onPressDown,
    this.onPressUp,
    this.onNew,
    this.onRank,
    this.onRetry,
  });

  /// golden 预览：参考图首屏（分数 0 / 三个台面 / 棋子站立 / cam=0）
  factory GameJumpView.preview() => GameJumpView(
    score: 0,
    best: 0,
    blocks: _previewBlocks(),
    cur: 0,
    playerZ: 35.5,
    groundH: 34,
  );

  final int score;
  final int best;
  final List<_JumpBlock> blocks;
  final int cur;
  final double playerX;
  final double playerY;
  final double playerZ;
  final double groundH;
  final double pieceScaleX;
  final double pieceScaleY;
  final double pieceRot;
  final double cam;
  final double camX;
  final double power;
  final bool charging;
  final bool stayOn;
  final double stayProgress;
  final List<_JumpFloat> floats;
  final List<_JumpParticle> particles;

  /// 运行时画布快照；为空时（golden / preview）由上面的静态参数生成。
  final _JumpFrameData? frameData;
  final Listenable? sceneRepaint;
  final bool hintOn;
  final bool overlayVisible;
  final int overlayScore;
  final int overlayMaxCombo;
  final bool overlayImproved;
  final ValueNotifier<String>? liveProgress;
  final VoidCallback? onPressDown;
  final VoidCallback? onPressUp;
  final VoidCallback? onNew;
  final VoidCallback? onRank;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hud = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GameScorePill(label: '分数', value: '$score'),
        const SizedBox(width: 9),
        GameScorePill(label: '最高分', value: '$best'),
        const SizedBox(width: 9),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GameActionButton(
              label: '新游戏',
              icon: GameIcons.reset,
              primary: true,
              height: 56.64,
              onTap: onNew,
            ),
            const SizedBox(width: 8),
            GameActionButton(
              label: '排行榜',
              icon: GameIcons.trophy,
              height: 56.64,
              onTap: onRank,
            ),
          ],
        ),
      ],
    );

    final board = CssShadowLayer(
      radius: 14,
      shadows: const [
        CssShadowSpec(color: Color(0x0E5A4A2C), offset: Offset(0, 1), blur: 2),
        CssShadowSpec(
          color: Color(0x4D5A4A2C),
          offset: Offset(0, 8),
          blur: 20,
          spread: -12,
        ),
      ],
      child: Container(
        width: double.infinity,
        height: 568,
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: overlayVisible
                    ? null
                    : (_) => onPressDown?.call(),
                onPointerUp: overlayVisible ? null : (_) => onPressUp?.call(),
                onPointerCancel: overlayVisible
                    ? null
                    : (_) => onPressUp?.call(),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _JumpPainter(
                      frameData ??
                          (_JumpFrameData()
                            ..blocks = blocks
                            ..cur = cur
                            ..playerX = playerX
                            ..playerY = playerY
                            ..playerZ = playerZ
                            ..groundH = groundH
                            ..pieceScaleX = pieceScaleX
                            ..pieceScaleY = pieceScaleY
                            ..pieceRot = pieceRot
                            ..cam = cam
                            ..camX = camX
                            ..power = power
                            ..charging = charging
                            ..stayOn = stayOn
                            ..stayProgress = stayProgress
                            ..floats = floats
                            ..particles = particles),
                      repaint: sceneRepaint,
                    ),
                  ),
                ),
              ),
            ),
            if (hintOn)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: IgnorePointer(
                  child: Center(child: _JumpHint(c: c)),
                ),
              ),
            if (overlayVisible)
              Positioned.fill(
                child: _JumpOverlay(
                  score: overlayScore,
                  maxCombo: overlayMaxCombo,
                  improved: overlayImproved,
                  onRetry: onRetry,
                ),
              ),
          ],
        ),
      ),
    );

    return GameScaffold(
      gameKey: 'gjump',
      title: '跳一跳',
      hud: hud,
      boardGap: 18,
      board: board,
      liveProgress: liveProgress,
    );
  }
}

/// `.gjump-hint`：163.062×33.797，纸底 + line-2 边 + r99 + 前置 6px 橙点
class _JumpHint extends StatelessWidget {
  const _JumpHint({required this.c});
  final CitroColors c;

  @override
  Widget build(BuildContext context) {
    return CssShadowLayer(
      radius: 99,
      shadows: const [
        CssShadowSpec(color: Color(0x0E5A4A2C), offset: Offset(0, 1), blur: 2),
        CssShadowSpec(
          color: Color(0x4D5A4A2C),
          offset: Offset(0, 8),
          blur: 20,
          spread: -12,
        ),
      ],
      child: Container(
        width: 163.062,
        height: 33.797,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.line2),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                '按住蓄力 · 松手起跳',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontFamily: AppFonts.noto,
                  fontFamilyFallback: AppFonts.bodyFallback,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.65,
                  letterSpacing: .6,
                  color: c.ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.gjump-overlay`：360×566 rgba(246,239,223,.93) + r22 + 竖向居中 gap10
class _JumpOverlay extends StatelessWidget {
  const _JumpOverlay({
    required this.score,
    required this.maxCombo,
    required this.improved,
    this.onRetry,
  });

  final int score;
  final int maxCombo;
  final bool improved;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xEDF6EFDF),
        border: Border.all(color: const Color(0x262E2C22)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '游戏结束',
            style: TextStyle(
              fontFamily: AppFonts.kalam,
              fontFamilyFallback: AppFonts.fallback,
              fontSize: 22,
              fontWeight: FontWeight.w400,
              height: 36.3 / 22,
              letterSpacing: 1.32,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '本局得分 ',
                    style: TextStyle(color: c.ink2, fontSize: 13, height: 1.7),
                  ),
                  TextSpan(
                    text: '$score',
                    style: const TextStyle(
                      color: Color(0xFFE8C87E),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.7,
                    ),
                  ),
                  TextSpan(
                    text: ' · 最高连击 ×$maxCombo${improved ? '\n新纪录诞生！' : ''}',
                    style: TextStyle(color: c.ink2, fontSize: 13, height: 1.7),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontFamilyFallback: AppFonts.bodyFallback,
              ),
            ),
          ),
          const SizedBox(height: 10),
          GameActionButton(label: '再来一局', primary: true, onTap: onRetry),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// canvas 绘制（逐函数对应 index.html gjumpDraw*）
// ---------------------------------------------------------------------------

class _JumpPainter extends CustomPainter {
  _JumpPainter(this.data, {Listenable? repaint}) : super(repaint: repaint);

  final _JumpFrameData data;

  List<_JumpBlock> get blocks => data.blocks;
  int get cur => data.cur;
  double get playerX => data.playerX;
  double get playerY => data.playerY;
  double get playerZ => data.playerZ;
  double get groundH => data.groundH;
  double get pieceScaleX => data.pieceScaleX;
  double get pieceScaleY => data.pieceScaleY;
  double get pieceRot => data.pieceRot;
  double get cam => data.cam;
  double get camX => data.camX;
  double get power => data.power;
  bool get charging => data.charging;
  bool get stayOn => data.stayOn;
  double get stayProgress => data.stayProgress;
  List<_JumpFloat> get floats => data.floats;
  List<_JumpParticle> get particles => data.particles;

  double _cw = 0;
  double _ch = 0;
  double _sc = 1;
  double _anchorY = 0;

  @override
  void paint(Canvas canvas, Size size) {
    _cw = size.width;
    _ch = size.height;
    _sc = math.min(1.0, _cw / 700);
    if (_ch < 400) _sc *= .88;
    _anchorY = _ch * .66;

    final arr = List<_JumpBlock>.of(blocks)
      ..sort((a, b) => (b.x + b.y).compareTo(a.x + a.y));
    for (final b in arr) {
      final p = _proj(b.x, b.y, b.h);
      if (p.dy > _ch + 140 || p.dy < -140) continue;
      if (p.dx < -180 || p.dx > _cw + 180) continue;
      _drawBlock(canvas, b);
    }
    if (stayOn) _drawStay(canvas);
    if (charging) _drawChargeRing(canvas);
    _drawPiece(canvas);
    _drawFx(canvas);
  }

  Offset _proj(double x, double y, double z) => Offset(
    _cw * .5 + ((x - y) - camX) * _ix * _sc,
    _anchorY + (cam - (x + y)) * _iy * _sc - z,
  );

  // ---- 基础图元 ----

  void _quadFill(
    Canvas canvas,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
    double z,
    Color fill,
  ) {
    final p1 = _proj(x1, y1, z);
    final p2 = _proj(x2, y2, z);
    final p3 = _proj(x3, y3, z);
    final p4 = _proj(x4, y4, z);
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy)
        ..close(),
      Paint()..color = fill,
    );
  }

  void _quadStroke(
    Canvas canvas,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    double x4,
    double y4,
    double z,
    Color stroke,
    double lw,
  ) {
    final p1 = _proj(x1, y1, z);
    final p2 = _proj(x2, y2, z);
    final p3 = _proj(x3, y3, z);
    final p4 = _proj(x4, y4, z);
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy)
        ..close(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw
        ..color = stroke,
    );
  }

  Rect _isoRect(double x, double y, double z, double r) {
    final p = _proj(x, y, z);
    final rx = r * 1.414 * _ix * _sc;
    final ry = r * 1.414 * _iy * _sc;
    return Rect.fromCenter(center: p, width: rx * 2, height: ry * 2);
  }

  void _isoRing(
    Canvas canvas,
    double x,
    double y,
    double z,
    double r,
    Color stroke,
    double lw,
  ) {
    canvas.drawOval(
      _isoRect(x, y, z, r),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw
        ..color = stroke,
    );
  }

  void _isoArc(
    Canvas canvas,
    double x,
    double y,
    double z,
    double r,
    Color stroke,
    double lw,
  ) {
    canvas.drawArc(
      _isoRect(x, y, z, r),
      0,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw
        ..color = stroke,
    );
  }

  void _isoDot(
    Canvas canvas,
    double x,
    double y,
    double z,
    double r,
    Color fill,
  ) {
    canvas.drawOval(_isoRect(x, y, z, r), Paint()..color = fill);
  }

  Path _hexPath(double x, double y, double z, double r) {
    final path = Path();
    for (var k = 0; k < 6; k++) {
      final a = math.pi / 6 + k * math.pi / 3;
      final p = _proj(x + r * math.cos(a), y + r * math.sin(a), z);
      if (k == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
  }

  // ---- 台面 ----

  void _drawBox(Canvas canvas, _JumpBlock b, _JumpStyle st) {
    final w = b.w;
    final t1 = _proj(b.x - w, b.y - w, b.h);
    final t2 = _proj(b.x + w, b.y - w, b.h);
    final t3 = _proj(b.x + w, b.y + w, b.h);
    final t4 = _proj(b.x - w, b.y + w, b.h);
    final f1 = _proj(b.x - w, b.y - w, 0);
    final r1 = _proj(b.x + w, b.y - w, 0);
    final l1 = _proj(b.x - w, b.y + w, 0);
    canvas.drawPath(
      Path()
        ..moveTo(t1.dx, t1.dy)
        ..lineTo(t2.dx, t2.dy)
        ..lineTo(r1.dx, r1.dy)
        ..lineTo(f1.dx, f1.dy)
        ..close(),
      Paint()..color = st.right,
    );
    canvas.drawPath(
      Path()
        ..moveTo(t1.dx, t1.dy)
        ..lineTo(t4.dx, t4.dy)
        ..lineTo(l1.dx, l1.dy)
        ..lineTo(f1.dx, f1.dy)
        ..close(),
      Paint()..color = st.left,
    );
    canvas.drawPath(
      Path()
        ..moveTo(t1.dx, t1.dy)
        ..lineTo(t2.dx, t2.dy)
        ..lineTo(t3.dx, t3.dy)
        ..lineTo(t4.dx, t4.dy)
        ..close(),
      Paint()..color = st.top,
    );
  }

  void _drawCyl(Canvas canvas, _JumpBlock b, _JumpStyle st, double topScale) {
    final w = b.w;
    final tr = w * topScale;
    final rx = tr * 1.414 * _ix * _sc;
    final ry = tr * 1.414 * _iy * _sc;
    final brx = w * 1.414 * _ix * _sc;
    final bry = w * 1.414 * _iy * _sc;
    final tc = _proj(b.x, b.y, b.h);
    final bc = _proj(b.x, b.y, 0);
    final side = Path()
      ..moveTo(tc.dx - rx, tc.dy)
      ..lineTo(bc.dx - brx, bc.dy)
      ..arcTo(
        Rect.fromCenter(center: bc, width: brx * 2, height: bry * 2),
        math.pi,
        -math.pi,
        false,
      )
      ..lineTo(tc.dx + rx, tc.dy)
      ..close();
    canvas.drawPath(side, Paint()..color = st.left);
    canvas.drawOval(
      Rect.fromCenter(center: tc, width: rx * 2, height: ry * 2),
      Paint()..color = st.top,
    );
  }

  void _drawHex(Canvas canvas, _JumpBlock b, _JumpStyle st) {
    final w = b.w;
    final t = <Offset>[];
    final bt = <Offset>[];
    for (var k = 0; k < 6; k++) {
      final a = math.pi / 6 + k * math.pi / 3;
      t.add(_proj(b.x + w * math.cos(a), b.y + w * math.sin(a), b.h));
      bt.add(_proj(b.x + w * math.cos(a), b.y + w * math.sin(a), 0));
    }
    final c = _proj(b.x, b.y, b.h);
    for (var k = 0; k < 6; k++) {
      final k2 = (k + 1) % 6;
      if ((t[k].dy + t[k2].dy) / 2 > c.dy + .5) {
        canvas.drawPath(
          Path()
            ..moveTo(t[k].dx, t[k].dy)
            ..lineTo(t[k2].dx, t[k2].dy)
            ..lineTo(bt[k2].dx, bt[k2].dy)
            ..lineTo(bt[k].dx, bt[k].dy)
            ..close(),
          Paint()..color = (k % 2 == 1) ? st.left : st.right,
        );
      }
    }
    canvas.drawPath(_hexPath(b.x, b.y, b.h, w), Paint()..color = st.top);
  }

  void _drawPattern(Canvas canvas, _JumpBlock b, _JumpStyle st) {
    final x = b.x, y = b.y, w = b.w, h = b.h;
    final ac = st.ac ?? const Color(0x402A211C);
    switch (st.pat) {
      case 'inset':
        if (st.shape == 'box') {
          _quadStroke(
            canvas,
            x - w * .68,
            y - w * .68,
            x + w * .68,
            y - w * .68,
            x + w * .68,
            y + w * .68,
            x - w * .68,
            y + w * .68,
            h,
            _dk,
            2,
          );
        } else if (st.shape == 'hex') {
          canvas.drawPath(
            _hexPath(x, y, h, w * .66),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = _dk,
          );
        } else {
          _isoRing(canvas, x, y, h, w * .66, _dk, 2);
        }
        break;
      case 'checker':
        final c = w * .30;
        _quadFill(
          canvas,
          x - w * .5 - c,
          y - w * .5 - c,
          x - w * .5 + c,
          y - w * .5 - c,
          x - w * .5 + c,
          y - w * .5 + c,
          x - w * .5 - c,
          y - w * .5 + c,
          h,
          ac,
        );
        _quadFill(
          canvas,
          x + w * .5 - c,
          y + w * .5 - c,
          x + w * .5 + c,
          y + w * .5 - c,
          x + w * .5 + c,
          y + w * .5 + c,
          x + w * .5 - c,
          y + w * .5 + c,
          h,
          ac,
        );
        break;
      case 'rubik':
        final cs = w * .27;
        final off = w * .63;
        for (var i = -1; i <= 1; i++) {
          for (var j = -1; j <= 1; j++) {
            final f = (i == 0 && j == 0)
                ? const Color(0xFFFE923B)
                : (((i + j) % 2 == 0) ? _white55 : _dark18);
            _quadFill(
              canvas,
              x + i * off - cs,
              y + j * off - cs,
              x + i * off + cs,
              y + j * off - cs,
              x + i * off + cs,
              y + j * off + cs,
              x + i * off - cs,
              y + j * off + cs,
              h,
              f,
            );
          }
        }
        break;
      case 'ribbon':
        _quadFill(
          canvas,
          x - w,
          y - w * .13,
          x + w,
          y - w * .13,
          x + w,
          y + w * .13,
          x - w,
          y + w * .13,
          h,
          ac,
        );
        _quadFill(
          canvas,
          x - w * .13,
          y - w,
          x + w * .13,
          y - w,
          x + w * .13,
          y + w,
          x - w * .13,
          y + w,
          h,
          ac,
        );
        _isoDot(canvas, x, y, h, w * .10, const Color(0xFFF4F1ED));
        break;
      case 'wood':
        _quadFill(
          canvas,
          x - w * .36,
          y - w,
          x - w * .28,
          y - w,
          x - w * .28,
          y + w,
          x - w * .36,
          y + w,
          h,
          _dk,
        );
        _quadFill(
          canvas,
          x + w * .28,
          y - w,
          x + w * .36,
          y - w,
          x + w * .36,
          y + w,
          x + w * .28,
          y + w,
          h,
          _dk,
        );
        _quadStroke(
          canvas,
          x - w * .82,
          y - w * .82,
          x + w * .82,
          y - w * .82,
          x + w * .82,
          y + w * .82,
          x - w * .82,
          y + w * .82,
          h,
          _edge2,
          2,
        );
        break;
      case 'grid':
        _quadFill(
          canvas,
          x - w,
          y - w * .55,
          x + w,
          y - w * .55,
          x + w,
          y - w * .47,
          x - w,
          y - w * .47,
          h,
          _dk,
        );
        _quadFill(
          canvas,
          x - w,
          y + w * .47,
          x + w,
          y + w * .47,
          x + w,
          y + w * .55,
          x - w,
          y + w * .55,
          h,
          _dk,
        );
        _quadFill(
          canvas,
          x - w * .55,
          y - w,
          x - w * .47,
          y - w,
          x - w * .47,
          y + w,
          x - w * .55,
          y + w,
          h,
          _dk,
        );
        _quadFill(
          canvas,
          x + w * .47,
          y - w,
          x + w * .55,
          y - w,
          x + w * .55,
          y + w,
          x + w * .47,
          y + w,
          h,
          _dk,
        );
        break;
      case 'dots':
        _isoDot(canvas, x, y, h, w * .10, ac);
        _isoDot(canvas, x - w * .45, y - w * .45, h, w * .09, ac);
        _isoDot(canvas, x + w * .45, y - w * .45, h, w * .09, ac);
        _isoDot(canvas, x - w * .45, y + w * .45, h, w * .09, ac);
        _isoDot(canvas, x + w * .45, y + w * .45, h, w * .09, ac);
        break;
      case 'ring':
        final k = st.shape == 'cone' ? .58 : 1.0;
        _isoRing(canvas, x, y, h, w * .62 * k, _dark18, 2.5);
        _isoRing(canvas, x, y, h, w * .30 * k, _dotDark15, 2);
        break;
      case 'lantern':
        _isoArc(canvas, x, y, h * .66, w * 1.01, st.ac!, 3);
        _isoArc(canvas, x, y, h * .18, w * 1.01, st.ac!, 3);
        break;
      case 'floral':
        _isoRing(canvas, x, y, h, w * .42, st.ac!, 2);
        _isoDot(canvas, x, y, h, w * .08, st.ac!);
        _isoDot(canvas, x - w * .45, y, h, w * .07, st.ac!);
        _isoDot(canvas, x + w * .45, y, h, w * .07, st.ac!);
        _isoDot(canvas, x, y - w * .45, h, w * .07, st.ac!);
        _isoDot(canvas, x, y + w * .45, h, w * .07, st.ac!);
        break;
    }
  }

  void _drawBlock(Canvas canvas, _JumpBlock b) {
    if (b.special == 'music') {
      _drawCyl(canvas, b, _musicStyle, 1);
      _isoRing(canvas, b.x, b.y, b.h, b.w * .62, _white25, 2);
      _isoRing(canvas, b.x, b.y, b.h, b.w * .34, _white20, 2);
      _isoDot(canvas, b.x, b.y, b.h, b.w * .13, const Color(0xFFFE923B));
      return;
    }
    if (b.special == 'manhole') {
      _drawCyl(canvas, b, _manholeStyle, 1);
      _isoRing(canvas, b.x, b.y, b.h, b.w * .66, const Color(0x592A211C), 2.5);
      _isoRing(canvas, b.x, b.y, b.h, b.w * .30, const Color(0x4D2A211C), 2);
      return;
    }
    final st = b.style;
    switch (st.shape) {
      case 'box':
        _drawBox(canvas, b, st);
        break;
      case 'cyl':
        _drawCyl(canvas, b, st, 1);
        break;
      case 'cone':
        _drawCyl(canvas, b, st, .58);
        break;
      default:
        _drawHex(canvas, b, st);
    }
    _drawPattern(canvas, b, st);
  }

  void _drawStay(Canvas canvas) {
    if (cur < 0 || cur >= blocks.length) return;
    final b = blocks[cur];
    if (b.special == null || b.gotBonus) return;
    final rect = _isoRect(playerX, playerY, b.h, b.w * .8);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      stayProgress * math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFE923B),
    );
  }

  void _drawChargeRing(Canvas canvas) {
    if (cur < 0 || cur >= blocks.length) return;
    final b = blocks[cur];
    final rr = (b.w * .5 + power * b.w * .95) * 1.414 * _ix * _sc;
    final rr2 = rr * (_iy / _ix);
    final p = _proj(playerX, playerY, b.h);
    final rect = Rect.fromCenter(center: p, width: rr * 2, height: rr2 * 2);
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Color.fromRGBO(254, 146, 59, .30 + .45 * power),
    );
    canvas.drawOval(
      Rect.fromCenter(center: p, width: rr * 2 * .72, height: rr2 * 2 * .72),
      Paint()..color = const Color(0x14FE923B),
    );
  }

  void _drawPiece(Canvas canvas) {
    final p0 = _proj(playerX, playerY, groundH);
    final shK = math.max(.4, 1 - (playerZ - groundH) / 320);
    final e = .6 + .4 * shK;
    canvas.drawOval(
      Rect.fromCenter(
        center: p0,
        width: 17 * _sc * e * 2,
        height: 6.5 * _sc * e * 2,
      ),
      Paint()..color = Color.fromRGBO(15, 9, 6, .30 * shK),
    );

    final p = _proj(playerX, playerY, playerZ);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    if (pieceRot != 0) canvas.rotate(pieceRot);
    canvas.scale(pieceScaleX * _sc, pieceScaleY * _sc);
    final body = Paint()..color = const Color(0xFF453154);
    canvas.drawPath(
      Path()
        ..moveTo(-11, 1)
        ..cubicTo(-12, -10, -7, -17, -4.5, -21)
        ..lineTo(4.5, -21)
        ..cubicTo(7, -17, 12, -10, 11, 1)
        ..quadraticBezierTo(0, 5.5, -11, 1)
        ..close(),
      body,
    );
    canvas.drawCircle(const Offset(0, -26.5), 8.6, body);
    canvas.save();
    canvas.translate(-2.8, -29.5);
    canvas.rotate(-.5);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 6.4, height: 4.2),
      Paint()..color = const Color(0x21FFFFFF),
    );
    canvas.restore();
    canvas.save();
    canvas.translate(-4.5, -9);
    canvas.rotate(.12);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 6, height: 14),
      Paint()..color = const Color(0x0FFFFFFF),
    );
    canvas.restore();
    canvas.restore();
  }

  void _drawFx(Canvas canvas) {
    for (final f in particles) {
      final a = _clamp01(f.life);
      canvas.drawCircle(
        Offset(f.x, f.y),
        f.r,
        Paint()..color = f.color.withValues(alpha: a),
      );
    }
    for (final f in floats) {
      final a = _clamp01(f.life * 1.4);
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            fontFamily: AppFonts.noto,
            fontFamilyFallback: AppFonts.bodyFallback,
            fontSize: f.big ? 18 : 14,
            fontWeight: FontWeight.w700,
            color: (f.big ? const Color(0xFFE8C87E) : const Color(0xFFF4F1ED))
                .withValues(alpha: a),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(f.x - tp.width / 2, f.y - tp.height * .82);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _JumpPainter old) => true;
}
