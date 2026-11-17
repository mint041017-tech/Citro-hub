import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'game_identity.dart';
import 'game_ui.dart';

// ---------------------------------------------------------------------------
// 常量与数据（对应 web index.html gpeng 常量）
// ---------------------------------------------------------------------------

const double _gapDeg0 = 58; // 初始缺口宽度（度）
const double _gapDeg = 48; // 新增缺口宽度（度）
const int _gapMax = 4; // 缺口上限
const double _addGapEvery = 12; // 每 12 秒加缺口
const double _gapWarn = 3; // 新增缺口前 3 秒预警
const double _bouncePts = 2;
const double _timePts = 10;
const double _randSpread = math.pi / 12;
const double _shakeMax = 14;
const double _barFull = 90; // 时间条 90 秒满

class _PengColorPair {
  const _PengColorPair(this.f, this.d);
  final Color f;
  final Color d;
}

/// 淘气小球调色板：全部由游戏身份派生（固定颜色，不随主题切换）。
class PengPalette {
  const PengPalette({
    required this.balls,
    required this.wall,
    required this.gapDot,
    required this.danger,
    required this.dangerInk,
    required this.floatInk,
    required this.timebarBg,
    required this.timebarFill,
    required this.vignetteCenter,
    required this.vignetteEdge,
  });

  final List<_PengColorPair> balls;
  final Color wall;
  final Color gapDot;
  final Color danger;
  final Color dangerInk;
  final Color floatInk;
  final Color timebarBg;
  final Color timebarFill;
  final Color vignetteCenter;
  final Color vignetteEdge;
}

PengPalette pengPalette(GameIdentity identity, CitroColors c) {
  final balls = <_PengColorPair>[
    // 墙改 identity.deep 后，球的亮端统一避开墙色（paper / soft / mix 浅端），
    // 暗端用 deep / primary / ink 保持体积感，球贴墙时亮端仍可读。
    _PengColorPair(GameIdentity.paper, identity.deep),
    _PengColorPair(identity.soft, identity.primary),
    _PengColorPair(GameIdentity.paper, identity.primary),
    _PengColorPair(
      Color.lerp(identity.primary, GameIdentity.paper, .5)!,
      identity.deep,
    ),
    _PengColorPair(identity.soft, identity.ink),
    _PengColorPair(
      Color.lerp(identity.primary, GameIdentity.paper, .5)!,
      identity.primary,
    ),
  ];
  return PengPalette(
    balls: balls,
    wall: identity.deep,
    // 墙改成 deep 后，缺口端点圆点要用浅端才压得住（deep 圆点会融进墙里）。
    gapDot: GameIdentity.paper,
    danger: c.danger,
    dangerInk: c.stamp,
    floatInk: identity.primaryInk,
    timebarBg: identity.primary.withAlpha(40),
    timebarFill: identity.primary,
    vignetteCenter: GameIdentity.paper.withAlpha(70),
    vignetteEdge: identity.deep.withAlpha(30),
  );
}

const double _cardRadius = 24;

/// 暗角：直接画 shader 径向渐变（中心柔光 → 边缘轻压暗），
/// 不再走多层 LUT / ImageFiltered。颜色由身份色派生。
void _paintVignette(Canvas canvas, Size size, PengPalette palette) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.1),
        // RadialGradient.radius 是「最短边的分数」，不是像素：写像素值会让
        // 半径变成十万级，暗角永不出现、整块棋盘被均匀罩一层 paper α70。
        radius: 0.72,
        colors: [palette.vignetteCenter, palette.vignetteEdge],
        stops: const [0, 1],
      ).createShader(Offset.zero & size),
  );
}

double _normA(double a) {
  var t = a % (math.pi * 2);
  if (t < 0) t += math.pi * 2;
  return t;
}

double _deltaA(double d) {
  var x = d;
  while (x > math.pi) {
    x -= math.pi * 2;
  }
  while (x < -math.pi) {
    x += math.pi * 2;
  }
  return x;
}

class _PengGap {
  _PengGap(this.a, this.w, this.born);
  double a;
  double w;
  double born;
}

class _PengBall {
  _PengBall({
    required this.x,
    required this.y,
    required this.r,
    required this.vx,
    required this.vy,
    required this.color,
  });
  double x;
  double y;
  double r;
  double vx;
  double vy;
  final _PengColorPair color;
}

class _PengPart {
  _PengPart({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.life,
    required this.color,
  });
  double x;
  double y;
  double vx;
  double vy;
  double r;
  double life;
  final Color color;
}

class _PengFloat {
  _PengFloat({
    required this.text,
    required this.x,
    required this.y,
    required this.big,
    required this.color,
  });
  final String text;
  double x;
  double y;
  double life = 1;
  final bool big;
  final Color color;
}

/// 画布每帧读取的可变快照。逻辑层更新后推进 ValueNotifier，
/// 只让 CustomPainter 重绘，不重建 HUD / 页面。
class _PengFrameData {
  double phi = 0;
  List<_PengGap> gaps = const [];
  List<_PengBall> balls = const [];
  List<_PengPart> parts = const [];
  List<_PengFloat> floats = const [];
  double shake = 0;
  double nowMs = 0;
  String state = 'ready';
  double addGapT = 0;
}

/// 圆形场地几何（对应 web gpengLayout）。
class _PengLayout {
  const _PengLayout(this.cw, this.ch);
  final double cw;
  final double ch;

  double get sc => math.max(0.78, math.min(1.0, math.min(cw / 640, ch / 460)));
  double get speedScale => (cw / 360 * 0.78).clamp(0.78, 2.4);
  double get cx => cw / 2;
  double get cy => ch / 2;
  double get radius => math.min(cw, ch) / 2 - (11 * sc / 2 + _shakeMax / 2 + 3);
}

// ---------------------------------------------------------------------------
// 页面（玩法 / 状态）
// ---------------------------------------------------------------------------

class GamePengPage extends StatefulWidget {
  const GamePengPage({super.key});
  @override
  State<GamePengPage> createState() => _GamePengPageState();
}

class _GamePengPageState extends State<GamePengPage>
    with SingleTickerProviderStateMixin {
  final math.Random _rnd = math.Random();
  final Stopwatch _clock = Stopwatch()..start();
  final ValueNotifier<String> _progress = ValueNotifier<String>('得分 0');
  CitroColors _colors = CitroColors.light;
  GameIdentity _identity = identityOf('gpeng');

  late final Ticker _ticker;
  bool _tickerReady = false;
  Duration _lastElapsed = Duration.zero;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final ValueNotifier<double> _barProgress = ValueNotifier<double>(0);
  final _PengFrameData _scene = _PengFrameData();
  int _shownScore = -1;
  int _shownTime = -1;
  _PengLayout _layout = const _PengLayout(360, 436.875);

  String _state = 'ready';
  int _score = 0;
  int _best = 0;
  int _bounces = 0;
  double _elapsed = 0;
  double _addGapT = 0;
  double _shake = 0;

  double _phi = 0;
  double _omega = 0;
  bool _dragging = false;
  double _lastA = 0;
  double _lastX = 0;
  int _lastT = 0;

  final List<_PengGap> _gaps = [];
  final List<_PengBall> _balls = [];
  final List<_PengPart> _parts = [];
  final List<_PengFloat> _floats = [];

  bool _hintOn = true;
  bool _overlayVisible = false;
  bool _improved = false;
  int _overSecs = 0;
  int _overBounces = 0;
  int _overScore = 0;

  @override
  void initState() {
    super.initState();
    _newGame(auto: false);
    _ticker = createTicker(_onFrame)..start();
    _tickerReady = true;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _progress.dispose();
    _frame.dispose();
    _barProgress.dispose();
    super.dispose();
  }

  void _newGame({required bool auto}) {
    _state = auto ? 'play' : 'ready';
    _score = 0;
    _bounces = 0;
    _elapsed = 0;
    _addGapT = 0;
    _shake = 0;
    _balls.clear();
    _parts.clear();
    _floats.clear();
    _phi = 0;
    _omega = 0;
    _dragging = false;
    _overlayVisible = false;
    _improved = false;
    _hintOn = !auto;
    _progress.value = '得分 0';
    final now = _clock.elapsedMilliseconds.toDouble();
    final a0 = _rnd.nextDouble() * math.pi * 2;
    final w0 = _gapDeg0 * math.pi / 180;
    _gaps
      ..clear()
      ..add(_PengGap(a0, w0, now))
      ..add(_PengGap(a0 + math.pi, w0, now));
    _spawnBall();
    _shownScore = 0;
    _shownTime = 0;
    _barProgress.value = 0;
    _syncScene(now);
    setState(() {});
    if (_tickerReady && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  double get _ballSpeed =>
      (320 + 280 * math.min(1.0, _elapsed / 55)) * _layout.speedScale;

  void _spawnBall() {
    final a = _rnd.nextDouble() * math.pi * 2;
    final sp = _ballSpeed;
    final palette = pengPalette(_identity, _colors).balls;
    _balls.add(
      _PengBall(
        x: _layout.cx,
        y: _layout.cy,
        r: (11 + _rnd.nextDouble() * 3) * _layout.sc,
        vx: math.cos(a) * sp,
        vy: math.sin(a) * sp,
        color: palette[_rnd.nextInt(palette.length)],
      ),
    );
  }

  double _gapWidth(_PengGap g, double now) {
    final grow = math.min(1.0, math.max(0.0, (now - g.born) / 600));
    return g.w * math.max(0.06, grow);
  }

  bool _inGap(double theta, double now) {
    for (final g in _gaps) {
      final ws = _normA(g.a + _phi);
      final we = ws + _gapWidth(g, now);
      if (we > math.pi * 2) {
        if (theta >= ws || theta <= we - math.pi * 2) return true;
      } else if (theta >= ws && theta <= we) {
        return true;
      }
    }
    return false;
  }

  /// 找最大空弧的中点（确定性放置新缺口）；放不下返回 null。
  double? _gapPickAngle(List<_PengGap> gaps, double width) {
    if (gaps.length >= _gapMax) return null;
    final cs = gaps.map((g) => _normA(g.a)).toList()..sort();
    var best = -1.0;
    var bestI = -1;
    for (var i = 0; i < cs.length; i++) {
      final next = i == cs.length - 1 ? cs[0] + math.pi * 2 : cs[i + 1];
      final d = next - cs[i];
      if (d > best) {
        best = d;
        bestI = i;
      }
    }
    if (bestI < 0) return null;
    var wMax = 0.0;
    for (final g in gaps) {
      wMax = math.max(wMax, g.w);
    }
    final need = width + wMax + 0.1;
    if (best < need) return null;
    return _normA(cs[bestI] + best / 2);
  }

  void _addGap(double now) {
    final a = _gapPickAngle(_gaps, _gapDeg * math.pi / 180);
    if (a == null) return;
    _gaps.add(_PengGap(a, _gapDeg * math.pi / 180, now));
    _addFloat(
      '新缺口！',
      _layout.cx,
      _layout.cy - _layout.radius * 0.5,
      big: true,
      color: pengPalette(_identity, _colors).dangerInk,
    );
    GameSfx.warn();
  }

  void _onFrame(Duration elapsed) {
    if (!mounted) return;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000.0;
    _lastElapsed = elapsed;
    if (dt <= 0) dt = 16;
    dt = dt.clamp(1.0, 60.0);
    final now = _clock.elapsedMilliseconds.toDouble();
    _update(dt, now);
    _syncScene(now);
    _barProgress.value = math.min(1.0, _elapsed / _barFull);
    _frame.value++;
    // 数字 HUD 只在秒数/分数变化时重建，120Hz 的球与边框只走画布重绘。
    final hudTime = _elapsed.floor();
    if (hudTime != _shownTime || _score != _shownScore) {
      _shownTime = hudTime;
      _shownScore = _score;
      setState(() {});
    }
  }

  void _syncScene(double now) {
    _scene
      ..phi = _phi
      ..gaps = _gaps
      ..balls = _balls
      ..parts = _parts
      ..floats = _floats
      ..shake = _shake
      ..nowMs = now
      ..state = _state
      ..addGapT = _addGapT;
  }

  void _update(double dt, double now) {
    final dtSec = dt / 1000;
    // 粒子 / 飘字 / 抖动
    for (var i = _parts.length - 1; i >= 0; i--) {
      final p = _parts[i];
      p.life -= dtSec;
      if (p.life <= 0) {
        _parts.removeAt(i);
        continue;
      }
      p.vy += 380 * dtSec;
      p.x += p.vx * dtSec;
      p.y += p.vy * dtSec;
    }
    for (var i = _floats.length - 1; i >= 0; i--) {
      final f = _floats[i];
      f.life -= dt / 900;
      if (f.life <= 0) {
        _floats.removeAt(i);
        continue;
      }
      f.y -= 42 * dtSec;
    }
    _shake *= math.exp(-dt / 1000 * 7);
    if (_shake < 0.2) _shake = 0;
    if (_state == 'over') return;
    // 圆环惯性
    if (!_dragging) {
      _phi += _omega * dtSec;
      _omega *= math.exp(-dtSec * 2.2);
      if (_omega.abs() < 0.02) _omega = 0;
    }
    final steps = dt > 25 ? 2 : 1;
    for (var s = 0; s < steps; s++) {
      _physics(dt / steps, now);
      if (_state == 'over') break;
    }
    if (_state != 'play') return;
    _elapsed += dtSec;
    _score =
        _elapsed.floor() * _timePts.toInt() + _bounces * _bouncePts.toInt();
    _progress.value = '得分 $_score';
    if (_balls.isNotEmpty) {
      final b = _balls.first;
      final sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (sp > 0.001) {
        final target = _ballSpeed;
        final ns = sp + (target - sp) * math.min(1.0, dtSec * 0.9);
        final k = ns / sp;
        b.vx *= k;
        b.vy *= k;
      }
    }
    _addGapT += dt;
    if (_addGapT >= _addGapEvery * 1000) {
      _addGapT = 0;
      _addGap(now);
    }
  }

  void _physics(double dt, double now) {
    if (_balls.isEmpty) return;
    final b = _balls.first;
    final dtSec = dt / 1000;
    b.x += b.vx * dtSec;
    b.y += b.vy * dtSec;
    final dx = b.x - _layout.cx;
    final dy = b.y - _layout.cy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0.001) return;
    final lim = _layout.radius - b.r;
    if (dist < lim) return;
    final nx = dx / dist;
    final ny = dy / dist;
    final vr = b.vx * nx + b.vy * ny;
    if (vr <= 0) return;
    final th = _normA(math.atan2(dy, dx));
    if (_inGap(th, now) && _state == 'play') {
      _escape(b);
      return;
    }
    final sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    final baseA = math.atan2(b.vy - 2 * vr * ny, b.vx - 2 * vr * nx);
    var na = baseA + (_rnd.nextDouble() * 2 - 1) * _randSpread;
    final inA = math.atan2(-ny, -nx);
    final dA = _deltaA(na - inA);
    final dLim = math.pi / 2 - 0.06;
    if (dA > dLim) {
      na = inA + dLim;
    } else if (dA < -dLim) {
      na = inA - dLim;
    }
    b.vx = math.cos(na) * sp;
    b.vy = math.sin(na) * sp;
    b.x = _layout.cx + nx * lim;
    b.y = _layout.cy + ny * lim;
    if (_state == 'play') _bounceFx(b.x, b.y);
  }

  void _bounceFx(double x, double y) {
    _bounces++;
    _score += _bouncePts.toInt();
    _burst(x, y, _identity.primary, 8);
    _addFloat('+2', x, y - 16 * _layout.sc, color: pengPalette(_identity, _colors).floatInk);
    _shake = math.min(8, _shake + 2);
    GameSfx.bounce();
  }

  void _escape(_PengBall b) {
    _burst(b.x, b.y, _identity.deep, 16);
    _shake = _shakeMax;
    GameSfx.lose();
    _addFloat(
      '球飞出去了！',
      _layout.cx,
      _layout.cy - _layout.radius * 0.5,
      big: true,
      color: pengPalette(_identity, _colors).dangerInk,
    );
    _end();
  }

  void _burst(double x, double y, Color color, int n) {
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final sp = (40 + _rnd.nextDouble() * 180) * _layout.sc;
      _parts.add(
        _PengPart(
          x: x,
          y: y,
          vx: math.cos(a) * sp,
          vy: math.sin(a) * sp,
          r: (1.6 + _rnd.nextDouble() * 2.4) * _layout.sc,
          life: 0.5 + _rnd.nextDouble() * 0.35,
          color: color,
        ),
      );
    }
  }

  void _addFloat(
    String text,
    double x,
    double y, {
    bool big = false,
    Color? color,
  }) {
    color ??= pengPalette(_identity, _colors).floatInk;
    _floats.add(_PengFloat(text: text, x: x, y: y, big: big, color: color));
  }

  Future<void> _end() async {
    if (_state == 'over') return;
    final best = context.app.localBest('peng');
    _state = 'over';
    _overlayVisible = true;
    _hintOn = false;
    _overSecs = _elapsed.floor();
    _overBounces = _bounces;
    _overScore = _score;
    _improved = _score > best;
    if (_improved) _best = _score;
    _ticker.stop();
    _lastElapsed = Duration.zero;
    _syncScene(_clock.elapsedMilliseconds.toDouble());
    setState(() {});
    await context.app.saveLocalBest('peng', _score);
    await context.app.submitScore('peng', _score);
    if (mounted) setState(() {});
  }

  void _press(Offset pos) {
    if (_state == 'over') return;
    if (_state == 'ready') {
      setState(() {
        _state = 'play';
        _hintOn = false;
      });
    }
    _dragging = true;
    _lastA = math.atan2(pos.dy - _layout.cy, pos.dx - _layout.cx);
    _lastX = pos.dx;
    _lastT = _clock.elapsedMilliseconds;
    _omega = 0;
  }

  void _move(Offset pos) {
    if (!_dragging) return;
    final now = _clock.elapsedMilliseconds;
    final dtm = math.max(1, now - _lastT);
    final x = pos.dx - _layout.cx;
    final y = pos.dy - _layout.cy;
    double dphi;
    if (math.sqrt(x * x + y * y) > 70 * _layout.sc) {
      final a = math.atan2(y, x);
      dphi = _deltaA(a - _lastA);
      _lastA = a;
    } else {
      dphi = (pos.dx - _lastX) * 0.008;
    }
    _phi += dphi;
    final inst = dphi / (dtm / 1000);
    _omega = _omega * 0.6 + inst.clamp(-7.0, 7.0) * 0.4;
    _lastX = pos.dx;
    _lastT = now;
    // 拖拽只改棋盘姿态：推画布重绘，不重建整页。
    _syncScene(now.toDouble());
    _frame.value++;
  }

  void _release() {
    _dragging = false;
  }

  void _syncLayout(double boardWidth, double boardHeight) {
    final l = _PengLayout(
      math.max(160.0, boardWidth - 2),
      math.max(160.0, boardHeight - 2),
    );
    if ((l.cw - _layout.cw).abs() < 0.01 && (l.ch - _layout.ch).abs() < 0.01) {
      return;
    }
    _layout = l;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_state == 'ready') {
        _newGame(auto: false);
      } else if (_state != 'over') {
        for (final b in _balls) {
          final dx = b.x - _layout.cx;
          final dy = b.y - _layout.cy;
          final d = math.sqrt(dx * dx + dy * dy);
          final lim = _layout.radius - b.r;
          if (d > lim && d > 0) {
            b.x = _layout.cx + dx / d * lim;
            b.y = _layout.cy + dy / d * lim;
          }
        }
        _syncScene(_clock.elapsedMilliseconds.toDouble());
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _colors = context.c;
    _identity = GameIdentityScope.of(context);
    final best = math.max(_best, context.app.localBest('peng'));
    return GamePengView(
      score: _score,
      best: best,
      time: _elapsed.floor(),
      timeProgress: math.min(1.0, _elapsed / _barFull),
      frameData: _scene,
      sceneRepaint: _frame,
      barProgress: _barProgress,
      hintOn: _hintOn,
      overlayVisible: _overlayVisible,
      overlaySecs: _overSecs,
      overlayBounces: _overBounces,
      overlayScore: _overScore,
      overlayImproved: _improved,
      liveProgress: _progress,
      onPointerDown: _press,
      onPointerMove: _move,
      onPointerUp: _release,
      onNew: () => _newGame(auto: true),
      onRank: () => showGameRank(context, game: 'peng', title: '淘气小球'),
      onRetry: () => _newGame(auto: true),
      onBoardSize: (size) => _syncLayout(size.width, size.height),
    );
  }
}

// ---------------------------------------------------------------------------
// 纯视觉层
// ---------------------------------------------------------------------------

class GamePengView extends StatelessWidget {
  const GamePengView({
    super.key,
    required this.score,
    required this.best,
    this.time = 0,
    this.timeProgress = 0,
    this.phi = 0,
    this.gaps = const [],
    this.balls = const [],
    this.parts = const [],
    this.floats = const [],
    this.frameData,
    this.sceneRepaint,
    this.barProgress,
    this.shake = 0,
    this.nowMs = 0,
    this.state = 'ready',
    this.addGapT = 0,
    this.hintOn = true,
    this.overlayVisible = false,
    this.overlaySecs = 0,
    this.overlayBounces = 0,
    this.overlayScore = 0,
    this.overlayImproved = false,
    this.liveProgress,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onNew,
    this.onRank,
    this.onRetry,
    this.onBoardSize,
    this.identity,
  });

  /// golden 预览：参考图首屏（ready 态 / 两个 58° 缺口 / 粉色小球 / 时间条 0）
  factory GamePengView.preview() => GamePengView(
    score: 0,
    best: 0,
    time: 0,
    phi: 0,
    nowMs: 0,
    identity: identityOf('gpeng'),
    gaps: [
      _PengGap(0.0593, 1.01229, -100000),
      _PengGap(0.0593 + math.pi, 1.01229, -100000),
    ],
    balls: [
      _PengBall(
        x: 232.5,
        y: 104.1,
        r: 9.3,
        vx: 108.0,
        vy: 225.0,
        color: pengPalette(identityOf('gpeng'), CitroColors.light).balls[0],
      ),
    ],
  );

  final int score;
  final int best;
  final int time;
  final double timeProgress;
  final double phi;
  final List<_PengGap> gaps;
  final List<_PengBall> balls;
  final List<_PengPart> parts;
  final List<_PengFloat> floats;
  final _PengFrameData? frameData;
  final Listenable? sceneRepaint;
  final ValueNotifier<double>? barProgress;
  final double shake;
  final double nowMs;
  final String state;
  final double addGapT;
  final bool hintOn;
  final bool overlayVisible;
  final int overlaySecs;
  final int overlayBounces;
  final int overlayScore;
  final bool overlayImproved;
  final ValueNotifier<String>? liveProgress;
  final void Function(Offset local)? onPointerDown;
  final void Function(Offset local)? onPointerMove;
  final VoidCallback? onPointerUp;
  final VoidCallback? onNew;
  final VoidCallback? onRank;
  final VoidCallback? onRetry;
  final ValueChanged<Size>? onBoardSize;

  /// 游戏身份；缺省从 [GameIdentityScope] 取（预览 / 测试直接指定）。
  final GameIdentity? identity;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final id = identity ?? GameIdentityScope.of(context);
    final board = LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
        const double hintH = 34.0;
        const double gap = 8.0;
        // 棋盘尺寸只吃内容区约束：圆形场地按内容宽算（正方形卡，圆填满宽度），
        // 不再读 MediaQuery；高度不够时交给外层 SingleChildScrollView 滚动。
        final h = constraints.maxHeight.isFinite
            ? math.max(160.0, constraints.maxHeight - hintH - gap)
            : w;
        onBoardSize?.call(Size(w, h));
        final palette = pengPalette(id, c);
        return Center(
          child: SizedBox(
            width: w,
            height: h + gap + hintH,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: w,
                  height: h,
                  child: _boardCard(context, c, id, palette, w, h),
                ),
                const SizedBox(height: gap),
                IgnorePointer(
                  child: Center(
                    child: _PengHint(identity: id, active: hintOn, height: hintH),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    // HUD 三粒 pill 在 web 中是定宽（62 / 63.0469 / 62），kit 的内容自适应宽度
    // 会让整组窄 ~1px，这里用 SizedBox 显式定宽还原。
    final hud = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 三个 pill 总宽 205.047，居中后左缘落在 92.4765（小数坐标）→ Skia
        // 会把 1px 边框摊成 2px 抗锯齿；左移 0.4765 对齐到整像素 92，与
        // Chrome 的边框吸附一致。
        Transform.translate(
          offset: const Offset(-0.4765, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 62,
                child: GameScorePill(label: '分数', value: '$score'),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 63.047,
                child: GameScorePill(label: '最高分', value: '$best'),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 62,
                child: GameScorePill(label: '时间', value: '$time'),
              ),
            ],
          ),
        ),
      ],
    );

    return GameScaffold(
      gameKey: 'gpeng',
      title: '淘气小球',
      hud: hud,
      hudStats: [
        GameHudStat('分数', '$score'),
        GameHudStat('最高分', '$best'),
        GameHudStat('时间', '$time'),
      ],
      actions: [
        GameActionButton(
          label: '新游戏',
          icon: GameIcons.reset,
          primary: true,
          onTap: onNew,
        ),
        GameActionButton(label: '排行榜', icon: GameIcons.trophy, onTap: onRank),
      ],
      boardGap: 18,
      board: board,
      liveProgress: liveProgress,
    );
  }

  /// 棋盘卡：底座用身份色 soft + primary 边框，时间条 7px 带秒数。
  Widget _boardCard(
    BuildContext context,
    CitroColors c,
    GameIdentity id,
    PengPalette palette,
    double w,
    double h,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: CitroColors.shadows.card(c),
      ),
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: id.soft,
          border: Border.all(color: id.primary.withAlpha(150)),
          borderRadius: BorderRadius.circular(_cardRadius),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: overlayVisible
                    ? null
                    : (e) => onPointerDown?.call(e.localPosition),
                onPointerMove: overlayVisible
                    ? null
                    : (e) => onPointerMove?.call(e.localPosition),
                onPointerUp: overlayVisible
                    ? null
                    : (_) => onPointerUp?.call(),
                onPointerCancel: overlayVisible
                    ? null
                    : (_) => onPointerUp?.call(),
                child: ClipRect(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _PengPainter(
                        frameData ??
                            (_PengFrameData()
                              ..phi = phi
                              ..gaps = gaps
                              ..balls = balls
                              ..parts = parts
                              ..floats = floats
                              ..shake = shake
                              ..nowMs = nowMs
                              ..state = state
                              ..addGapT = addGapT),
                        repaint: sceneRepaint,
                        palette: palette,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 时间条：加粗到 7px。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: SizedBox(
                  height: 7,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(color: palette.timebarBg),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: barProgress == null
                            ? FractionallySizedBox(
                                widthFactor: timeProgress
                                    .clamp(0.0, 1.0)
                                    .toDouble(),
                                heightFactor: 1,
                                child: ColoredBox(
                                  color: palette.timebarFill,
                                ),
                              )
                            : ValueListenableBuilder<double>(
                                valueListenable: barProgress!,
                                builder: (_, v, __) => FractionallySizedBox(
                                  widthFactor: v
                                      .clamp(0.0, 1.0)
                                      .toDouble(),
                                  heightFactor: 1,
                                  child: ColoredBox(
                                    color: palette.timebarFill,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 秒数：时间条右下。
            Positioned(
              top: 10,
              right: 10,
              child: IgnorePointer(
                child: Text(
                  '$time',
                  style: context.body(
                    size: CitroType.micro,
                    weight: CitroType.strong,
                    color: id.primaryInk,
                  ),
                ),
              ),
            ),
            if (overlayVisible)
              Positioned.fill(
                child: _PengOverlay(
                  secs: overlaySecs,
                  bounces: overlayBounces,
                  score: overlayScore,
                  improved: overlayImproved,
                  identity: id,
                  onRetry: onRetry,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 提示胶囊：纸底 + 身份色描边 + 前置圆点，移到棋盘外常驻。
class _PengHint extends StatelessWidget {
  const _PengHint({
    required this.identity,
    required this.active,
    this.height = 34,
  });

  final GameIdentity identity;
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: identity.primary.withAlpha(70)),
        borderRadius: BorderRadius.circular(CitroColors.radii.button),
        boxShadow: CitroColors.shadows.card(c),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? identity.primary : identity.deep.withAlpha(120),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '按住拖动 · 旋转边框守球',
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: context.body(
                size: CitroType.caption,
                weight: CitroType.strong,
                color: c.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.gpeng-overlay`：rgba(252,248,240,.94) + 1px 边 + r22 + gap10
class _PengOverlay extends StatelessWidget {
  const _PengOverlay({
    required this.secs,
    required this.bounces,
    required this.score,
    required this.improved,
    required this.identity,
    required this.onRetry,
  });
  final int secs;
  final int bounces;
  final int score;
  final bool improved;
  final GameIdentity identity;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final id = identity;
    // 浮层是 c.surface（暗色下深面）：primaryInk 只有约 3.0:1，
    // 暗色主题改用 onDark()。
    final overlayInk = c.dark ? id.onDark() : id.primaryInk;
    return Container(
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.96),
        border: Border.all(color: id.primary.withAlpha(70)),
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '球飞出去了！',
            style: context.heading(size: CitroType.subtitle, color: c.ink),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '坚持了 '),
                  TextSpan(
                    text: '$secs',
                    style: TextStyle(
                      color: overlayInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: ' 秒 · 反弹 '),
                  TextSpan(
                    text: '$bounces',
                    style: TextStyle(
                      color: overlayInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: ' 次 · 得分 '),
                  TextSpan(
                    text: '$score',
                    style: TextStyle(
                      color: overlayInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (improved) const TextSpan(text: '· 新纪录诞生！'),
                ],
              ),
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: c.ink2),
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
// 画布
// ---------------------------------------------------------------------------

class _GapIv {
  const _GapIv(this.s, this.w);
  final double s;
  final double w;
}

class _PengPainter extends CustomPainter {
  _PengPainter(
    this.data, {
    Listenable? repaint,
    required this.palette,
  }) : super(repaint: repaint);

  final _PengFrameData data;
  final PengPalette palette;

  double get phi => data.phi;
  List<_PengGap> get gaps => data.gaps;
  List<_PengBall> get balls => data.balls;
  List<_PengPart> get parts => data.parts;
  List<_PengFloat> get floats => data.floats;
  double get shake => data.shake;
  double get nowMs => data.nowMs;
  String get state => data.state;
  double get addGapT => data.addGapT;


  @override
  void paint(Canvas canvas, Size size) {
    final sc = math.max(
      0.78,
      math.min(1.0, math.min(size.width / 640, size.height / 460)),
    );
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(size.width, size.height) / 2 - (11 * sc / 2 + 10);
    final center = Offset(cx, cy);

    if (shake > 0.2) {
      final lim = math.max(
        0.0,
        math.min(size.width, size.height) / 2 - radius - 8,
      );
      final sx = (nowMs * 0.9).remainder(1).abs() * 2 - 1;
      final sy = ((nowMs * 0.7) + 0.5).remainder(1).abs() * 2 - 1;
      canvas.save();
      canvas.translate(
        math.max(-lim, math.min(lim, sx * shake * 0.5)),
        math.max(-lim, math.min(lim, sy * shake * 0.5)),
      );
    }

    _paintVignette(canvas, size, palette);

    _drawWalls(canvas, center, radius, sc);
    _drawGapWarn(canvas, center, radius, sc);

    for (final b in balls) {
      _drawBall(canvas, b);
    }

    for (final p in parts) {
      final a = (p.life / 0.85).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.r,
        Paint()..color = p.color.withValues(alpha: p.color.a * a),
      );
    }

    for (final f in floats) {
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            fontFamily: AppFonts.rounded,
            fontSize: f.big ? 17 : 13.5,
            fontWeight: FontWeight.w700,
            color: f.color.withValues(
              alpha: f.color.a * f.life.clamp(0.0, 1.0),
            ),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(f.x - tp.width / 2, f.y - tp.height / 2));
    }

    if (shake > 0.2) canvas.restore();
  }

  double _gapWidth(_PengGap g) {
    final grow = math.min(1.0, math.max(0.0, (nowMs - g.born) / 600));
    return g.w * math.max(0.06, grow);
  }

  void _drawWalls(Canvas canvas, Offset center, double radius, double sc) {
    if (gaps.isEmpty) return;
    final ivs = <_GapIv>[];
    for (final g in gaps) {
      ivs.add(_GapIv(_normA(g.a + phi), _gapWidth(g)));
    }
    ivs.sort((a, b) => a.s.compareTo(b.s));
    final wall = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11 * sc
      ..strokeCap = StrokeCap.butt
      ..color = palette.wall;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < ivs.length; i++) {
      final cur = ivs[i];
      final s2 = cur.s + cur.w;
      final e2 = i + 1 < ivs.length ? ivs[i + 1].s : ivs[0].s + math.pi * 2;
      if (e2 > s2 + 0.02) {
        canvas.drawArc(rect, s2, e2 - s2, false, wall);
      }
    }
    // 缺口两端身份色圆点
    final dot = Paint()..color = palette.gapDot;
    for (final iv in ivs) {
      for (final t in [iv.s, iv.s + iv.w]) {
        canvas.drawCircle(_gapPoint(center, radius, t), 2.8 * sc, dot);
      }
    }
  }

  void _drawGapWarn(Canvas canvas, Offset center, double radius, double sc) {
    if (state != 'play' || gaps.length >= _gapMax) return;
    final remain = _addGapEvery * 1000 - addGapT;
    if (remain <= 0 || remain > _gapWarn * 1000) return;
    final a = _pickAngle(_gapDeg * math.pi / 180);
    if (a == null) return;
    final s = _normA(a + phi);
    final w = _gapDeg * math.pi / 180;
    final t = (_gapWarn * 1000 - remain) / (_gapWarn * 1000);
    final blink = 0.5 + 0.5 * (math.sin(nowMs / 220)).abs();
    // 2026-10-23：红色预警不够显眼（用户反馈）。整体提高不透明度下限、
    // 加粗一圈发光描边，并在内圈再补一条不模糊的实线，浅色纸底上也清晰。
    final al = ((0.45 + 0.55 * t) * (0.55 + 0.45 * blink)).clamp(0.0, 1.0);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13 * sc
      ..strokeCap = StrokeCap.butt
      ..color = palette.danger.withValues(alpha: al * 0.75)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * sc);
    canvas.drawArc(rect, s, w, false, glow);
    final solid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5 * sc
      ..strokeCap = StrokeCap.butt
      ..color = palette.danger.withValues(alpha: math.min(1.0, al + 0.2));
    canvas.drawArc(rect, s, w, false, solid);
    final dot = Paint()..color = palette.danger.withValues(alpha: al);
    for (final q in [s, s + w]) {
      canvas.drawCircle(
        Offset(
          center.dx + radius * math.cos(q),
          center.dy + radius * math.sin(q),
        ),
        3.4 * sc,
        dot,
      );
    }
  }

  double? _pickAngle(double width) {
    if (gaps.length >= _gapMax) return null;
    final cs = gaps.map((g) => _normA(g.a)).toList()..sort();
    var best = -1.0;
    var bestI = -1;
    for (var i = 0; i < cs.length; i++) {
      final next = i == cs.length - 1 ? cs[0] + math.pi * 2 : cs[i + 1];
      final d = next - cs[i];
      if (d > best) {
        best = d;
        bestI = i;
      }
    }
    if (bestI < 0) return null;
    var wMax = 0.0;
    for (final g in gaps) {
      wMax = math.max(wMax, g.w);
    }
    final need = width + wMax + 0.1;
    if (best < need) return null;
    return _normA(cs[bestI] + best / 2);
  }

  void _drawBall(Canvas canvas, _PengBall b) {
    final center = Offset(b.x, b.y);
    // 拖影
    final speed = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    if (speed > 0.001) {
      canvas.drawLine(
        Offset(b.x - b.vx * 0.05, b.y - b.vy * 0.05),
        center,
        Paint()
          ..color = b.color.f.withValues(alpha: 0.22)
          ..strokeWidth = b.r * 0.9
          ..strokeCap = StrokeCap.round,
      );
    }
    // 径向渐变球体
    final shader = ui.Gradient.radial(
      center,
      b.r,
      [b.color.f, b.color.d],
      const [0.0, 1.0],
      TileMode.clamp,
      null,
      Offset(b.x - b.r * 0.35, b.y - b.r * 0.42),
      b.r * 0.12,
    );
    canvas.drawCircle(center, b.r, Paint()..shader = shader);
    // 高光
    canvas.save();
    canvas.translate(b.x - b.r * 0.32, b.y - b.r * 0.42);
    canvas.rotate(-0.6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: b.r * 0.6,
        height: b.r * 0.36,
      ),
      Paint()..color = GameIdentity.paper.withAlpha(150),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PengPainter old) => true;
}

Offset _gapPoint(Offset center, double radius, double t) =>
    Offset(center.dx + radius * math.cos(t), center.dy + radius * math.sin(t));
