import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
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

const List<_PengColorPair> _pengColors = [
  _PengColorPair(Color(0xFFE8A0B4), Color(0xFFC4768D)),
  _PengColorPair(Color(0xFF9EC3C9), Color(0xFF6C98A0)),
  _PengColorPair(Color(0xFFE8C97E), Color(0xFFBB9C50)),
  _PengColorPair(Color(0xFFA8C6A0), Color(0xFF789D6F)),
  _PengColorPair(Color(0xFFC9B2E0), Color(0xFF9B82BD)),
  _PengColorPair(Color(0xFFF4B183), Color(0xFFCB8454)),
];

// light 调色板（web gpengPalette light 分支）
const Color _wallColor = Color(0xAD4A3A22); // rgba(74,58,34,.68)
const Color _gapDotColor = Color(0xF2C45E16); // rgba(196,94,22,.95)
const Color _dangerRgb = Color(0xFFC62E24); // rgba(198,46,36,x)
const Color _dangerInk = Color(0xFFB5392B);
const Color _floatInk = Color(0xFF8A5A12);
const Color _timebarBg = Color(0xFFE4DCC9); // var(--line)
const Color _timebarFill = Color(0xFFF2A43C); // var(--accent)

const double _cardRadius = 14;

/// web 暗角 = createRadialGradient(中心, r0=30 → 外半径 max(w,h)*0.8，
/// rgba(255,255,255,.34) → rgba(120,86,48,.12)) 叠加在卡片底色 #FFFDF8 上。
///
/// Flutter 的 shader 渐变与 Chrome 的取整方式不同（Skia 截断、Chrome 四舍五入），
/// 整卡会系统性偏 1。这里不用 shader，而是从 web 参考图按半径统计出每个 1px
/// 环带的众数颜色（已含合成结果），再从外到内画不透明实心圆盘：像素距离 d
/// 最终取 LUT[ceil(d)] 的颜色，与 Chrome 的最终像素值一致。
const List<int> _vignetteLut = [
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFEFA,
  0xFFFFFDF9,
  0xFFFFFDF9,
  0xFFFFFEF9,
  0xFFFFFDF9,
  0xFFFEFDF9,
  0xFFFEFDF8,
  0xFFFEFCF8,
  0xFFFEFCF8,
  0xFFFEFDF8,
  0xFFFEFCF8,
  0xFFFDFCF8,
  0xFFFDFCF7,
  0xFFFDFBF7,
  0xFFFDFCF7,
  0xFFFDFCF7,
  0xFFFDFBF7,
  0xFFFCFBF6,
  0xFFFCFBF6,
  0xFFFCFAF6,
  0xFFFCFBF6,
  0xFFFCFBF6,
  0xFFFCFAF5,
  0xFFFCFAF5,
  0xFFFBFAF5,
  0xFFFBFAF5,
  0xFFFCFAF5,
  0xFFFBF9F4,
  0xFFFBF9F4,
  0xFFFBF9F4,
  0xFFFBF9F3,
  0xFFFBF9F4,
  0xFFFBF9F4,
  0xFFFBF8F3,
  0xFFFAF8F3,
  0xFFFAF8F3,
  0xFFFAF8F2,
  0xFFFAF8F3,
  0xFFFAF8F2,
  0xFFFAF8F2,
  0xFFFAF7F2,
  0xFFF9F7F1,
  0xFFF9F7F1,
  0xFFFAF7F2,
  0xFFF9F7F1,
  0xFFF9F7F1,
  0xFFF9F6F1,
  0xFFF8F6F0,
  0xFFF9F6F0,
  0xFFF9F6F0,
  0xFFF9F6F0,
  0xFFF8F6F0,
  0xFFF8F5EF,
  0xFFF8F5EF,
  0xFFF8F5EF,
  0xFFF8F5EF,
  0xFFF8F5EF,
  0xFFF8F5EF,
  0xFFF7F4EE,
  0xFFF7F4EE,
  0xFFF8F5EE,
  0xFFF7F5EE,
  0xFFF7F4EE,
  0xFFF7F4EE,
  0xFFF7F4ED,
  0xFFF7F4ED,
  0xFFF7F4EE,
  0xFFF7F4ED,
  0xFFF6F3ED,
  0xFFF6F3ED,
  0xFFF6F3EC,
  0xFFF6F3ED,
  0xFFF6F3ED,
  0xFFF6F3EC,
  0xFFF6F2EC,
  0xFFF6F2EC,
  0xFFF5F2EB,
  0xFFF6F2EC,
  0xFFF6F2EC,
  0xFFF5F2EB,
  0xFFF5F2EB,
  0xFFF5F1EB,
  0xFFF5F1EB,
  0xFFF5F2EB,
  0xFFF5F2EB,
  0xFFF5F1EA,
  0xFFF5F1EA,
  0xFFF4F1EA,
  0xFFF5F1EA,
  0xFFF5F1EA,
  0xFFF4F1EA,
  0xFFF4F0E9,
  0xFFF4F0E9,
  0xFFF4F0E9,
  0xFFF4F0E9,
  0xFFF4F0E9,
  0xFFF4F0E9,
  0xFFF4F0E9,
  0xFFF3EFE8,
  0xFFF3F0E8,
  0xFFF4F0E9,
  0xFFF4F0E8,
  0xFFF3EFE8,
  0xFFF3EFE8,
  0xFFF3EFE7,
  0xFFF3EFE8,
  0xFFF3EFE8,
  0xFFF3EFE8,
  0xFFF3EFE7,
  0xFFF3EEE7,
  0xFFF2EEE7,
  0xFFF3EFE7,
  0xFFF3EFE7,
  0xFFF3EEE7,
  0xFFF2EEE6,
  0xFFF2EEE6,
  0xFFF2EEE6,
  0xFFF2EEE6,
  0xFFF2EEE6,
  0xFFF2EEE6,
  0xFFF2EDE6,
  0xFFF2EDE5,
  0xFFF2EDE5,
  0xFFF2EDE5,
  0xFFF2EDE5,
  0xFFF2EDE5,
  0xFFF1EDE5,
  0xFFF1ECE5,
  0xFFF1ECE5,
  0xFFF1ECE5,
  0xFFF1ECE5,
  0xFFF1ECE4,
  0xFFF1ECE4,
  0xFFF1ECE4,
  0xFFF1ECE4,
  0xFFF1ECE4,
  0xFFF1ECE4,
  0xFFF1ECE4,
  0xFFF1ECE4,
  0xFFF1EBE4,
  0xFFF1EBE4,
  0xFFF0EBE3,
  0xFFF0EBE3,
  0xFFF0EBE3,
  0xFFF0EBE3,
  0xFFF0EBE3,
  0xFFF0EBE3,
  0xFFF0EBE3,
  0xFFF0EBE3,
  0xFFF0EAE3,
  0xFFF0EAE3,
  0xFFF0EAE3,
  0xFFF0EAE3,
  0xFFF0EAE3,
  0xFFF0EAE2,
  0xFFEFE9E2,
  0xFFEFE9E2,
  0xFFF0EAE3,
  0xFFF0EAE2,
  0xFFEFEAE2,
  0xFFEFE9E2,
  0xFFEFE9E2,
  0xFFEFE9E2,
  0xFFEFEAE2,
  0xFFEFE9E2,
  0xFFEFE9E2,
  0xFFEFE9E1,
  0xFFEFE9E1,
  0xFFEFE9E1,
  0xFFEFE9E2,
  0xFFEFE9E1,
  0xFFEFE9E1,
  0xFFEFE8E1,
  0xFFEEE8E1,
  0xFFEFE9E1,
  0xFFEFE9E1,
  0xFFEFE9E1,
  0xFFEEE8E1,
  0xFFEEE8E0,
  0xFFEEE8E1,
  0xFFEFE9E1,
  0xFFEFE8E1,
  0xFFEEE8E1,
  0xFFEEE8E0,
  0xFFEEE8E0,
  0xFFEEE8E0,
  0xFFEFE8E0,
  0xFFEEE8DF,
  0xFFEEE8DF,
  0xFFEEE8DF,
  0xFFEEE7DF,
  0xFFEEE8DF,
  0xFFEEE8DF,
  0xFFEEE8DF,
  0xFFEEE8DF,
  0xFFEEE7DF,
  0xFFEEE7DE,
  0xFFEEE8DF,
  0xFFEEE8DF,
  0xFFEEE8DF,
  0xFFEEE7DE,
  0xFFEDE7DE,
  0xFFEEE7DF,
  0xFFEEE8DF,
  0xFFEEE7DF,
  0xFFEEE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEEE7DF,
  0xFFEEE7DF,
  0xFFEEE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEEE7DE,
  0xFFEEE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEEE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE6DD,
  0xFFEEE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE6DD,
  0xFFEDE6DD,
  0xFFEEE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE6DD,
  0xFFEDE6DD,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE6DD,
  0xFFEDE6DD,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DD,
  0xFFEDE6DD,
  0xFFEDE6DD,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE6DD,
  0xFFEDE6DD,
  0xFFEDE6DD,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE6DD,
  0xFFEDE6DD,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE6DD,
  0xFFEDE6DD,
  0xFFEEE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEEE7DE,
  0xFFEEE7DE,
  0xFFEDE7DE,
  0xFFEDE7DE,
  0xFFEEE7DE,
  0xFFEEE7DE,
  0xFFEEE7DE,
  0xFFEEE7DE,
  0xFFEEE7DE,
  0xFFEEE8DE,
  0xFFEEE8DE,
];

void _paintVignette(Canvas canvas, Size size) {
  final cx = size.width / 2;
  final cy = size.height * 0.42;
  final maxR = math.sqrt(
    math.pow(math.max(cx, size.width - cx), 2) +
        math.pow(math.max(cy, size.height - cy), 2),
  );
  final paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = false;
  final top = math.min(maxR.ceil(), _vignetteLut.length - 1);
  for (var r = top; r >= 0; r--) {
    paint.color = Color(_vignetteLut[r]);
    canvas.drawCircle(Offset(cx, cy), r.toDouble(), paint);
  }
}

// 暗角是纯静态的 400 层圆环。旧实现每帧重画 400 个圆（120Hz 下 4.8 万次/秒），
// 这里按“逻辑尺寸 × DPR”离屏烘焙一次，之后每帧只 drawImage。
ui.Image? _vignetteImage;
Size _vignetteLogicalSize = Size.zero;
double _vignetteDpr = 0;

ui.Image _cachedVignette(Size size) {
  final views = ui.PlatformDispatcher.instance.views;
  final dpr = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
  if (_vignetteImage != null &&
      _vignetteLogicalSize == size &&
      _vignetteDpr == dpr) {
    return _vignetteImage!;
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(dpr);
  _paintVignette(canvas, size);
  final picture = recorder.endRecording();
  final w = math.max(1, (size.width * dpr).ceil());
  final h = math.max(1, (size.height * dpr).ceil());
  final image = picture.toImageSync(w, h);
  picture.dispose();
  _vignetteImage = image;
  _vignetteLogicalSize = size;
  _vignetteDpr = dpr;
  return image;
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
    _balls.add(
      _PengBall(
        x: _layout.cx,
        y: _layout.cy,
        r: (11 + _rnd.nextDouble() * 3) * _layout.sc,
        vx: math.cos(a) * sp,
        vy: math.sin(a) * sp,
        color: _pengColors[_rnd.nextInt(_pengColors.length)],
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
      color: _dangerInk,
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
    _burst(x, y, const Color(0xFFFFC48A), 8);
    _addFloat('+2', x, y - 16 * _layout.sc, color: _floatInk);
    _shake = math.min(8, _shake + 2);
    GameSfx.bounce();
  }

  void _escape(_PengBall b) {
    _burst(b.x, b.y, const Color(0xFFF07B6A), 16);
    _shake = _shakeMax;
    GameSfx.lose();
    _addFloat(
      '球飞出去了！',
      _layout.cx,
      _layout.cy - _layout.radius * 0.5,
      big: true,
      color: _dangerInk,
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
    Color color = _floatInk,
  }) {
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
  });

  /// golden 预览：参考图首屏（ready 态 / 两个 58° 缺口 / 粉色小球 / 时间条 0）
  factory GamePengView.preview() => GamePengView(
    score: 0,
    best: 0,
    time: 0,
    phi: 0,
    nowMs: 0,
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
        color: _pengColors[0],
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

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final board = LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final availableW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : screen.width - 30;
        final side = math.min(availableW, math.max(300.0, screen.height - 260));
        onBoardSize?.call(Size(side, side));
        return Center(
          child: CssShadowLayer(
            radius: _cardRadius,
            shadows: const [
              CssShadowSpec(
                color: Color(0x0E5A4A2C),
                offset: Offset(0, 1),
                blur: 2,
              ),
              CssShadowSpec(
                color: Color(0x4D5A4A2C),
                offset: Offset(0, 8),
                blur: 20,
                spread: -12,
              ),
            ],
            child: Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                color: c.surface2,
                border: Border.all(color: c.line),
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
                              danger: c.dark
                                  ? _dangerRgb
                                  : const Color(0xFFFF3B30),
                              showVignette:
                                  MediaQuery.sizeOf(context).width < 900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: SizedBox(
                        height: 3,
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: ColoredBox(color: _timebarBg),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: barProgress == null
                                  ? FractionallySizedBox(
                                      widthFactor: timeProgress
                                          .clamp(0.0, 1.0)
                                          .toDouble(),
                                      heightFactor: 1,
                                      child: const ColoredBox(
                                        color: _timebarFill,
                                      ),
                                    )
                                  : ValueListenableBuilder<double>(
                                      valueListenable: barProgress!,
                                      builder: (_, v, __) =>
                                          FractionallySizedBox(
                                            widthFactor: v
                                                .clamp(0.0, 1.0)
                                                .toDouble(),
                                            heightFactor: 1,
                                            child: const ColoredBox(
                                              color: _timebarFill,
                                            ),
                                          ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (hintOn)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 11.745,
                      child: IgnorePointer(
                        child: Center(child: _PengHint(c: c)),
                      ),
                    ),
                  if (overlayVisible)
                    Positioned.fill(
                      child: _PengOverlay(
                        secs: overlaySecs,
                        bounces: overlayBounces,
                        score: overlayScore,
                        improved: overlayImproved,
                        onRetry: onRetry,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // HUD 三粒 pill 在 web 中是定宽（62 / 63.0469 / 62），kit 的内容自适应宽度
    // 会让整组窄 ~1px，这里用 SizedBox 显式定宽还原；kit 在传 hud 时忽略
    // pills/actions，所以按钮行也一并放进 hud。
    final hud = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 三个 pill 总宽 205.047，居中后左缘落在 92.4765（小数坐标）→ Skia
        // 会把 1px 边框摊成 2px 抗锯齿；左移 0.4765 对齐到整像素 92，与
        // Chrome 的边框吸附一致。
        Transform.translate(
          offset: const Offset(-0.4765, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 62,
                child: GameScorePill(label: '分数', value: '$score'),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 63.047,
                child: GameScorePill(label: '最高分', value: '$best'),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 62,
                child: GameScorePill(label: '时间', value: '$time'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GameActionButton(
              label: '新游戏',
              icon: GameIcons.reset,
              primary: true,
              onTap: onNew,
            ),
            const SizedBox(width: 8),
            GameActionButton(
              label: '排行榜',
              icon: GameIcons.trophy,
              onTap: onRank,
            ),
          ],
        ),
      ],
    );

    return GameScaffold(
      gameKey: 'gpeng',
      title: '淘气小球',
      hud: hud,
      boardGap: 18,
      board: board,
      liveProgress: liveProgress,
    );
  }
}

/// `.gpeng-hint`：188.25×33.797，纸底 + line-2 边 + r99 + 前置 6px 橙点
class _PengHint extends StatelessWidget {
  const _PengHint({required this.c});
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
        // web computed 188.25×33.797；水平保持原值（文本 x 已与 web 对齐），
        // 高度取整到 34 并把底边对齐整像素，让上下 1px 边框像 Chrome 一样清晰。
        width: 188.25,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.line2),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFF2A43C),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                '按住拖动 · 旋转边框守球',
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                  fontFamily: AppFonts.noto,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.65,
                  letterSpacing: 0.6,
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

/// `.gpeng-overlay`：rgba(252,248,240,.94) + 1px 边 + r22 + gap10
class _PengOverlay extends StatelessWidget {
  const _PengOverlay({
    required this.secs,
    required this.bounces,
    required this.score,
    required this.improved,
    required this.onRetry,
  });
  final int secs;
  final int bounces;
  final int score;
  final bool improved;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF0FCF8F0),
        border: Border.all(color: const Color(0x292E2C22)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '球飞出去了！',
            style: TextStyle(
              fontFamily: AppFonts.kalam,
              fontSize: 22,
              height: 36.3 / 22,
              letterSpacing: 1.32,
              color: context.c.ink,
            ),
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
                    style: const TextStyle(
                      color: _floatInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' 秒 · 反弹 $bounces 次 · 得分 '),
                  TextSpan(
                    text: '$score',
                    style: const TextStyle(
                      color: _floatInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (improved) const TextSpan(text: '\n新纪录诞生！'),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontSize: 13,
                height: 22.1 / 13,
                color: context.c.ink2,
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
    required this.danger,
    this.showVignette = true,
  }) : super(repaint: repaint);

  final _PengFrameData data;
  final bool showVignette;

  double get phi => data.phi;
  List<_PengGap> get gaps => data.gaps;
  List<_PengBall> get balls => data.balls;
  List<_PengPart> get parts => data.parts;
  List<_PengFloat> get floats => data.floats;
  double get shake => data.shake;
  double get nowMs => data.nowMs;
  String get state => data.state;
  double get addGapT => data.addGapT;

  /// 快消失预警色（浅色主题用 web 的亮红 255,59,48，深色用暗红）。
  final Color danger;

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

    if (showVignette) {
      final vig = _cachedVignette(size);
      canvas.drawImageRect(
        vig,
        Rect.fromLTWH(0, 0, vig.width.toDouble(), vig.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.low,
      );
    }

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
            fontFamily: AppFonts.noto,
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
      ..color = _wallColor;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < ivs.length; i++) {
      final cur = ivs[i];
      final s2 = cur.s + cur.w;
      final e2 = i + 1 < ivs.length ? ivs[i + 1].s : ivs[0].s + math.pi * 2;
      if (e2 > s2 + 0.02) {
        canvas.drawArc(rect, s2, e2 - s2, false, wall);
      }
    }
    // 缺口两端橙色圆点
    final dot = Paint()..color = _gapDotColor;
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
      ..color = danger.withValues(alpha: al * 0.75)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * sc);
    canvas.drawArc(rect, s, w, false, glow);
    final solid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5 * sc
      ..strokeCap = StrokeCap.butt
      ..color = danger.withValues(alpha: math.min(1.0, al + 0.2));
    canvas.drawArc(rect, s, w, false, solid);
    final dot = Paint()..color = danger.withValues(alpha: al);
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
      Paint()..color = const Color(0x57FFFFFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PengPainter old) => true;
}

Offset _gapPoint(Offset center, double radius, double t) =>
    Offset(center.dx + radius * math.cos(t), center.dy + radius * math.sin(t));
