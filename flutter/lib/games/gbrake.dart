import 'dart:async';
import 'dart:math' as math;
import 'dart:ui'
    as ui
    show
        FontFeature,
        ParagraphBuilder,
        ParagraphConstraints,
        ParagraphStyle,
        TextStyle;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'game_ui.dart';
import 'gbrake_scene.dart';

// ---------------------------------------------------------------------------
// 极限刹车（gbrake）· web 页 #gbrakePage 的 Flutter 复刻
//
// v1.5.9：3D 场景重写为与 web 原版同源的透视投影渲染器（黄昏天光 / 分段雾化
// 路面 / 路灯与护栏 / 2600m 水马路障 / 低多边形黑色 SUV 车模 / 撞击翻滚），
// 物理常量与计分公式与 web GB_* 完全一致（得分 = 初速度² ÷ 刹停用时）。
// 菜单卡 / 结算卡 / HUD 版式沿用 v1.5.8 已逐像素对齐的实现。
// ---------------------------------------------------------------------------

// v1.6.3：全套改用原版 shache.org 的暗玻璃 + 金字配色
// （--ink #f5efe6 / --gold #d8c39a / --gold-strong #f1dcae / --glass / --line）。
const Color _ink = Color(0xFFF5EFE6);
const Color _ink2 = Color(0xC7F5EFE6);
const Color _inkSoft = Color(0x8CF5EFE6);
const Color _accent = Color(0xFFD8C39A); // --gold
const Color _accent2 = Color(0xFFC9A86C);
const Color _accentInk = Color(0xFFF1DCAE); // --gold-strong
const Color _surface2 = Color(0x14FFFFFF); // rgba(255,255,255,.08)
const Color _line = Color(0x33D8C39A); // rgba(216,195,154,.28)
const Color _line2 = Color(0x47D8C39A);
const Color _mint = Color(0xFF5FE0A0); // --ok
const Color _mintInk = Color(0xFF5FE0A0);
const Color _mintSoft = Color(0x1F5FE0A0);
const Color _mintLine = Color(0x4D5FE0A0);
const Color _fail = Color(0xFFFF4B3A); // --danger
const Color _onAccent = Color(0xFF20170C);

/// 场景黑底 / 暗色玻璃
const Color _sceneBlack = Color(0xFF120D10);
const Color _cream = Color(0xFFF5EFE6);
const Color _paper = Color(0xCC151012); // 面板：#100c0e 89%

const double _stageH = 470;
const double _stageRadius = 14;
const double _panelRadius = 16;

class GameBrakePage extends StatefulWidget {
  const GameBrakePage({super.key});

  @override
  State<GameBrakePage> createState() => _GameBrakePageState();
}

class _GameBrakePageState extends State<GameBrakePage>
    with SingleTickerProviderStateMixin {
  late final BrakeWorld world;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  bool muted = false;

  String toast = '';
  bool toastAlert = false;
  Timer? toastTimer;

  // 结算展示数据（onFinish 时定格）
  String resultTitle = '';
  String resultSub = '';
  bool resultOk = false;
  int resultScore = 0;
  double resultV0 = 0;
  double resultTime = 0;
  double resultDist = 0;
  int resultForce = 0;
  bool hadPowerCut = false;

  int best = 0;
  bool submitted = false;

  final _progress = ValueNotifier<String>('待开始');
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  double _lastHudMs = 0;
  BrakePhase _lastPhase = BrakePhase.idle;

  @override
  void initState() {
    super.initState();
    GameSfx.soundsEnabled = true; // v1.6.0：仅刹车与跳一跳保留音效
    world = BrakeWorld();
    _wireWorld();
    best = AppState.instance.localBest('brake');
    unawaited(
      GameSfx.loadMuted().then((_) {
        if (mounted) setState(() => muted = GameSfx.muted);
      }),
    );
    _ticker = createTicker(_onTick)..start();
  }

  void _wireWorld() {
    world.onToast = (text, {bool alert = false, double dur = 1.4}) {
      if (!mounted) return;
      toastTimer?.cancel();
      if (text.isEmpty) {
        setState(() {
          toast = '';
          toastAlert = false;
        });
        return;
      }
      setState(() {
        toast = text;
        toastAlert = alert;
      });
      toastTimer = Timer(Duration(milliseconds: (dur * 1000).round()), () {
        if (mounted) setState(() => toast = '');
      });
    };
    world.onCountTone = () {
      GameSfx.tone(freq: 660, dur: 0.12, vol: 0.16);
      GameSfx.vibrate(GameVibe.tick);
    };
    world.onGoTone = () => GameSfx.tone(freq: 1320, dur: 0.22, vol: 0.2);
    world.onPressedTone = () {
      GameSfx.tone(freq: 180, dur: 0.09, vol: 0.16, slide: 120);
      GameSfx.vibrate(GameVibe.medium);
    };
    world.onCrashStart = (kind) {
      GameSfx.crash(heavy: kind == 'break');
      unawaited(GameSfx.engineStop());
      unawaited(GameSfx.tireSet(0));
    };
    world.onSucceedTone = () {
      GameSfx.win();
      unawaited(GameSfx.engineStop());
      unawaited(GameSfx.tireSet(0));
    };
    world.onFinish = () {
      unawaited(GameSfx.engineStop());
      unawaited(GameSfx.tireSet(0));
      final ok = world.crashKind.isEmpty;
      resultOk = ok;
      resultScore = world.score;
      resultV0 = world.powerCut ? world.bvKmh : 0;
      resultTime = world.bt;
      resultDist = world.powerCut ? math.max(0, world.z - world.bz) : world.z;
      resultForce = world.maxForce.round();
      hadPowerCut = world.powerCut;
      resultTitle = ok
          ? '刹停成功'
          : (world.crashKind == 'break' ? '刹车踏板断裂' : '撞上路障');
      resultSub = ok
          ? '稳稳停住，V800 毫发无损'
          : (world.crashKind == 'break'
                ? '踏板力度达到 1612 N，整车失控翻滚飞出'
                : '没能在路障前刹停，再果断一点');
      if (ok && world.score > 0) {
        if (world.score > best) {
          best = world.score;
          AppState.instance.saveLocalBest('brake', best);
        }
        if (!submitted) {
          submitted = true;
          AppState.instance.submitScore('brake', world.score);
        }
      }
      _progress.value = ok ? '本局 ${world.score} 分' : '挑战失败';
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _ticker.dispose();
    toastTimer?.cancel();
    _progress.dispose();
    _frame.dispose();
    GameSfx.soundsEnabled = false;
    unawaited(GameSfx.engineStop());
    unawaited(GameSfx.disposeLoops());
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt > 0.1) dt = 0.1;
    world.acc += dt;
    world.snapshotFrame();
    var steps = 0;
    while (world.acc >= 1 / 60 && steps < 5) {
      world.step(1 / 60);
      world.acc -= 1 / 60;
      steps++;
    }
    world.render(dt, true);

    // 引擎 / 轮胎持续音（web gbEngineSet / gbNoiseSet）
    if (world.phase == BrakePhase.accel ||
        (world.phase == BrakePhase.brake && world.v > 1)) {
      unawaited(GameSfx.engineStart());
      unawaited(GameSfx.engineSet(math.min(1, world.v / gbVref), true));
      unawaited(GameSfx.tireStart());
      unawaited(
        GameSfx.tireSet(
          (world.powerCut && world.v > 3)
              ? math.min(0.16, math.pow(world.force / gbBreak, 1.6) * 0.16)
              : 0,
        ),
      );
    }

    if (world.phase == BrakePhase.accel) {
      _progress.value = '加速中 ${world.speedKmh.round()} km/h';
    } else if (world.phase == BrakePhase.brake) {
      _progress.value = '刹停中 ${world.speedKmh.round()} km/h';
    } else if (world.phase == BrakePhase.stop ||
        world.phase == BrakePhase.crash) {
      _progress.value = '本局 ${world.score} 分';
    } else if (world.phase == BrakePhase.idle) {
      _progress.value = '待开始';
    }
    // 3D 场景自己按 vsync 重绘（120Hz）；HUD 数字降到 ~30Hz 重建，
    // 菜单/结算态 4Hz 足够，避免每帧重建整页。
    _frame.value++;
    final nowMs = elapsed.inMicroseconds / 1000.0;
    final phase = world.phase;
    final active =
        phase == BrakePhase.count ||
        phase == BrakePhase.accel ||
        phase == BrakePhase.brake ||
        phase == BrakePhase.crash;
    final interval = active ? 33.0 : 250.0;
    if (phase != _lastPhase || nowMs - _lastHudMs >= interval) {
      _lastPhase = phase;
      _lastHudMs = nowMs;
      if (mounted) setState(() {});
    }
  }

  void _start() {
    GameSfx.tap();
    submitted = false;
    unawaited(GameSfx.engineStart());
    world.start();
    setState(() {});
  }

  void _press() => world.press();

  void _release() => world.release();

  Future<void> _toggleMute() async {
    muted = !muted;
    await GameSfx.setMuted(muted);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GameBrakeView(
      world: world,
      sceneRepaint: _frame,
      muted: muted,
      toast: toast,
      toastAlert: toastAlert,
      resultTitle: resultTitle,
      resultSub: resultSub,
      resultOk: resultOk,
      resultScore: resultScore,
      resultV0: resultV0,
      resultTime: resultTime,
      resultDist: resultDist,
      resultForce: resultForce,
      hadPowerCut: hadPowerCut,
      best: best,
      score: world.score,
      liveProgress: _progress,
      onStart: _start,
      onRetry: _start,
      onPress: _press,
      onRelease: _release,
      onToggleMute: _toggleMute,
      onRank: () => showGameRank(context, game: 'brake', title: '极限刹车'),
    );
  }
}

// ---------------------------------------------------------------------------
// 纯视觉层
// ---------------------------------------------------------------------------

class GameBrakeView extends StatelessWidget {
  const GameBrakeView({
    super.key,
    this.world,
    this.sceneRepaint,
    this.muted = false,
    this.toast = '',
    this.toastAlert = false,
    this.resultTitle = '刹停成功',
    this.resultSub = '稳稳停住，V800 毫发无损',
    this.resultOk = true,
    this.resultScore = 0,
    this.resultV0 = 0,
    this.resultTime = 0,
    this.resultDist = 0,
    this.resultForce = 0,
    this.hadPowerCut = false,
    this.score = 0,
    this.best = 0,
    this.liveProgress,
    this.onStart,
    this.onRetry,
    this.onPress,
    this.onRelease,
    this.onToggleMute,
    this.onRank,
  });

  /// 菜单态展示用世界（golden 渲染默认 orbit 相机静止帧）。
  final BrakeWorld? world;

  /// 3D 场景的每帧重绘通知（画面不重建 widget）。
  final Listenable? sceneRepaint;
  final bool muted;
  final String toast;
  final bool toastAlert;
  final String resultTitle;
  final String resultSub;
  final bool resultOk;
  final int resultScore;
  final double resultV0;
  final double resultTime;
  final double resultDist;
  final int resultForce;
  final bool hadPowerCut;
  final int score;
  final int best;
  final ValueNotifier<String>? liveProgress;
  final VoidCallback? onStart;
  final VoidCallback? onRetry;
  final VoidCallback? onPress;
  final VoidCallback? onRelease;
  final VoidCallback? onToggleMute;
  final VoidCallback? onRank;

  BrakeWorld get w => world ?? BrakeWorld();

  bool get _inGame => w.phase != BrakePhase.idle && w.phase != BrakePhase.over;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = MediaQuery.sizeOf(context).width;
    final world = this.w;
    return GameScaffold(
      gameKey: 'gbrake',
      title: '极限刹车挑战',
      boardGap: 16,
      liveProgress: liveProgress,
      pills: [
        GameScorePill(label: '本局得分', value: '$score'),
        GameScorePill(label: '最高分', value: '$best'),
      ],
      actions: [
        GameActionButton(
          label: '开始挑战',
          icon: GameIcons.reset,
          primary: true,
          onTap: onStart,
        ),
        GameActionButton(label: '排行榜', icon: GameIcons.trophy, onTap: onRank),
      ],
      board: SizedBox(
        width: math.max(0.0, w - GameMetrics.sidePad * 2),
        height: _stageH,
        child: CssShadowLayer(
          radius: _stageRadius,
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
          child: SizedBox.expand(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _sceneBlack,
                borderRadius: BorderRadius.circular(_stageRadius),
                border: Border.all(color: c.line2),
              ),
              child: Listener(
                onPointerDown: _inGame ? (_) => onPress?.call() : null,
                onPointerUp: _inGame ? (_) => onRelease?.call() : null,
                onPointerCancel: _inGame ? (_) => onRelease?.call() : null,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: BrakeScenePainter(
                            world,
                            repaint: sceneRepaint,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _hudChip(
                        label: '制动计时',
                        value:
                            '${(world.bt > 0 ? world.bt : 0).toStringAsFixed(3)}s',
                        width: 67.7,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: _hudChip(
                        label: '距路障',
                        value: '${world.distToBarrier.round()}m',
                        width: 69.88,
                      ),
                    ),
                    if (_inGame) ...[
                      Positioned(
                        left: 93.6,
                        top: 356.33,
                        width: 172.8,
                        height: 103.67,
                        child: _speedo(world),
                      ),
                      _forceGauge(world),
                      _pedal(world),
                    ],
                    if (world.phase == BrakePhase.count &&
                        world.countText.isNotEmpty)
                      Center(
                        child: Text(
                          world.countText,
                          style: const TextStyle(
                            fontFamily: AppFonts.kalam,
                            fontSize: 88,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 4,
                            color: Color(0xFFF1DCAE),
                            shadows: [
                              Shadow(color: Color(0xB3F1DCAE), blurRadius: 36),
                            ],
                          ),
                        ),
                      ),
                    if (world.phase == BrakePhase.idle) _menu(),
                    if (world.phase == BrakePhase.over) _result(),
                    if (toast.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 74,
                        child: Center(child: _toast(toast, alert: toastAlert)),
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

  Widget _hudChip({
    required String label,
    required String value,
    required double width,
  }) {
    return Container(
      width: width,
      height: 54.25,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A3C301A),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 10,
              height: 1.65,
              letterSpacing: 0.8,
              color: _inkSoft,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 15,
              height: 1.65,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: _accentInk,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedo(BrakeWorld world) {
    final ready = world.speedKmh >= gbMinKmh;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _SpeedoPainter(kmh: world.speedKmh, ready: ready),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 58.67,
          height: 43,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${world.speedKmh.round()}',
                style: const TextStyle(
                  fontFamily: AppFonts.kalam,
                  fontSize: 30,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                  color: _cream,
                  shadows: [Shadow(color: Color(0xCC0B0A0F), blurRadius: 10)],
                ),
              ),
              Text(
                'km/h',
                style: const TextStyle(
                  fontFamily: AppFonts.noto,
                  fontFamilyFallback: AppFonts.bodyFallback,
                  fontSize: 11,
                  height: 1.05,
                  letterSpacing: 0,
                  color: Color(0xA8F6EFE3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _forceGauge(BrakeWorld world) {
    final ratio = (world.force / gbFmax).clamp(0.0, 1.0);
    final danger = world.force > gbBreak * 0.85;
    return Positioned(
      left: 12,
      top: 128,
      width: 70,
      height: 212,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '踏板力度',
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 11,
              height: 1.65,
              letterSpacing: 0,
              color: Color(0xB8F6EFE3),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 160,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0x80101014),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: const Color(0x38F6EFE3)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x59000000),
                          blurRadius: 6,
                          spreadRadius: 1,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 3,
                  bottom: 2,
                  width: 14,
                  height: math.max(0.0, 156 * ratio),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: const LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xFFD2482F), Color(0xFFF2A43C), _mint],
                        stops: [0, 0.46, 1],
                      ),
                      boxShadow: const [
                        BoxShadow(color: Color(0x73F5A233), blurRadius: 14),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 12.47,
                  child: Container(
                    width: 30,
                    height: 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6A4D),
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: const [
                        BoxShadow(color: Color(0x99FF6A4D), blurRadius: 8),
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  left: 34,
                  top: 6,
                  child: Text(
                    '1612N',
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontFamilyFallback: AppFonts.bodyFallback,
                      fontSize: 10,
                      height: 1.2,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w700,
                      color: Color(0xCCF6EFE3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${world.force.round()} N',
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 13,
              height: 1.3,
              letterSpacing: 0,
              fontWeight: FontWeight.w700,
              color: danger ? const Color(0xFFFF4B3A) : _cream,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pedal(BrakeWorld world) {
    final kmh = world.speedKmh;
    final can =
        (world.phase == BrakePhase.accel || world.phase == BrakePhase.brake) &&
        (world.powerCut || kmh >= gbMinKmh);
    final pressed = world.pressed;
    final label = world.phase == BrakePhase.brake
        ? '按住加力'
        : (can ? '踩刹车!' : '刹车');
    return Positioned(
      right: 12,
      bottom: 12,
      child: GestureDetector(
        onTapDown: can ? (_) => onPress?.call() : null,
        onTapUp: (_) => onRelease?.call(),
        onTapCancel: () => onRelease?.call(),
        child: PinchPedal(
          label: label,
          ready: can && !pressed,
          pressed: pressed,
          disabled: !can,
        ),
      ),
    );
  }

  // ----------------------------- 开始卡片 -----------------------------

  Widget _menu() {
    return Positioned(
      left: 11,
      top: 77.84,
      width: 338,
      height: 378.16,
      child: _paperPanel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 36.28, child: _brandLine()),
              const SizedBox(height: 4),
              SizedBox(
                height: 36.3,
                child: Center(
                  child: Transform.translate(
                    // web 上 h2 的 font-family 以 Kalam 为首选（中文回退 ZCOOL），
                    // 基线比 Flutter 垂直居中高约 4px，这里做等价位移。
                    offset: const Offset(-1, -5),
                    child: const Text(
                      '极限刹车挑战',
                      style: TextStyle(
                        fontFamily: AppFonts.zcool,
                        fontFamilyFallback: AppFonts.fallback,
                        fontSize: 22,
                        height: 1.65,
                        letterSpacing: 1.32,
                        color: _accentInk,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _mintSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _mintLine),
                  ),
                  child: const Text(
                    '越快踩，越快停。别把刹车踏板踩断。',
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontFamilyFallback: AppFonts.bodyFallback,
                      fontSize: 13,
                      height: 1.65,
                      letterSpacing: 0,
                      color: _mintInk,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _rulesCard(),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: _orangeButton(
                        '开始挑战',
                        onTap: onStart,
                        primary: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _orangeButton(
                        muted ? '音效：关' : '音效：开',
                        onTap: onToggleMute,
                        primary: false,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const SizedBox(
                height: 18.14,
                child: Center(
                  child: Text(
                    '按住屏幕任意位置或右下角按钮踩刹车',
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontFamilyFallback: AppFonts.bodyFallback,
                      fontSize: 11,
                      height: 1.65,
                      letterSpacing: 0,
                      color: _inkSoft,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 品牌行：web 该行是 text-align center 的 inline 内容（6px 圆点 + 8px 间距 + 文字），
  // 且「款 / 造」两个字不在 App 内置 Noto 子集里（web 用系统 Noto Sans SC），
  // 这里用内嵌字形轮廓绘制这两个字，其余仍用 TextSpan 排版。
  Widget _brandLine() {
    const double lineHeight = 18.15;
    const double advance = 13.86;
    const brandStyle = TextStyle(
      fontFamily: AppFonts.noto,
      fontFamilyFallback: AppFonts.bodyFallback,
      fontSize: 11,
      height: 1.65,
      letterSpacing: 2.86,
      fontWeight: FontWeight.w700,
      color: _accentInk,
    );
    Widget glyph(String ch, String data) => SizedBox(
      width: advance,
      height: lineHeight,
      child: CustomPaint(
        painter: _InkGlyphPainter(data: data, fontSize: 11, color: _accentInk),
      ),
    );
    return Text.rich(
      TextSpan(
        style: brandStyle,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(
              width: 14,
              height: lineHeight,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6.1),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const TextSpan(text: '新'),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: glyph('款', _kGlyphKuan),
          ),
          const TextSpan(text: '也被OTA了？没关系，我们一年能'),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: glyph('造', _kGlyphZao),
          ),
          const TextSpan(text: '三'),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: glyph('款', _kGlyphKuan),
          ),
          const TextSpan(text: '\n车'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _rulesCard() {
    final base = TextStyle(
      fontFamily: AppFonts.noto,
      fontFamilyFallback: AppFonts.bodyFallback,
      fontSize: 12.5,
      height: 1.6,
      letterSpacing: 0,
      color: _ink2,
    );
    const bold = TextStyle(
      fontFamily: AppFonts.noto,
      fontFamilyFallback: AppFonts.bodyFallback,
      fontSize: 12.5,
      height: 1.6,
      letterSpacing: 0,
      fontWeight: FontWeight.w700,
      color: _accentInk,
    );
    const boldBad = TextStyle(
      fontFamily: AppFonts.noto,
      fontFamilyFallback: AppFonts.bodyFallback,
      fontSize: 12.5,
      height: 1.6,
      letterSpacing: 0,
      fontWeight: FontWeight.w700,
      color: _fail,
    );
    final rules = <List<TextSpan>>[
      [
        TextSpan(text: '车辆自动全力加速，', style: base),
        const TextSpan(text: '100 km/h', style: bold),
        TextSpan(text: ' 后才能踩刹车', style: base),
      ],
      [
        TextSpan(text: '一踩下刹车，动力立即切断；', style: base),
        const TextSpan(text: '按得越久，力度越大', style: bold),
      ],
      [
        TextSpan(text: '力度达到 ', style: base),
        const TextSpan(text: '1612 N', style: boldBad),
        TextSpan(text: ' 刹车踏板断裂，整车翻滚失败', style: base),
      ],
      [TextSpan(text: '得分 = 刹车初速度² ÷ 刹停用时，越高越好', style: base)],
      [
        TextSpan(text: '路障在 ', style: base),
        const TextSpan(text: '2600 m', style: bold),
        TextSpan(text: ' 外 —— 刹得越晚分越高，刹不停就撞上', style: base),
      ],
    ];
    return Container(
      height: 160,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final spans in rules)
            Text.rich(
              TextSpan(
                style: base,
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: SizedBox(
                      width: 16,
                      height: 20,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 1.2, top: 7.4),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: _RuleDiamond(),
                        ),
                      ),
                    ),
                  ),
                  ...spans,
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _paperPanel({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(_panelRadius),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F5A4A2C),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: Color(0x6B5A4A2C),
            offset: Offset(0, 22),
            blurRadius: 48,
            spreadRadius: -24,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_panelRadius),
        child: Stack(
          children: [
            Positioned(
              left: 47,
              right: 47,
              top: 0,
              child: Container(
                height: 1,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x00F2A43C),
                      Color(0xFFF2A43C),
                      Color(0x00F2A43C),
                    ],
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }

  Widget _orangeButton(
    String label, {
    VoidCallback? onTap,
    required bool primary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 2,
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: primary ? _accent2 : _line2,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: primary ? _accent : _surface2,
                borderRadius: BorderRadius.circular(999),
                border: primary ? null : Border.all(color: _line2),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppFonts.noto,
                    fontFamilyFallback: AppFonts.bodyFallback,
                    fontSize: 14,
                    height: 1.2,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w700,
                    color: primary ? _onAccent : _ink2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toast(String text, {bool alert = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: alert ? const Color(0xD9C81E14) : const Color(0xD91B1712),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: alert ? const Color(0xCCFF7864) : const Color(0x33F6EFE3),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppFonts.noto,
          fontFamilyFallback: AppFonts.bodyFallback,
          fontSize: alert ? 14 : 12,
          height: 1.35,
          letterSpacing: 0,
          fontWeight: alert ? FontWeight.w700 : FontWeight.w400,
          color: _cream,
        ),
      ),
    );
  }

  // ----------------------------- 结算卡片 -----------------------------

  Widget _result() {
    // v1.6.1：结算卡整体在场景内水平 + 垂直居中（用户反馈「结算页不是
    // 居中显示」；原定位沿用 web 的贴顶布局）。
    return Positioned.fill(
      child: Center(
        child: SizedBox(
          width: 338,
          height: 444.4,
          child: _paperPanel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 36.3,
                    child: Center(
                      child: Text(
                        resultTitle,
                        style: TextStyle(
                          fontFamily: AppFonts.zcool,
                          fontFamilyFallback: AppFonts.fallback,
                          fontSize: 22,
                          height: 1.65,
                          letterSpacing: 1.1,
                          color: resultOk ? _mintInk : _fail,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 19.8,
                    child: Center(
                      child: Text(
                        resultSub,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: AppFonts.noto,
                          fontFamilyFallback: AppFonts.bodyFallback,
                          fontSize: 12,
                          height: 1.65,
                          letterSpacing: 0,
                          color: _ink2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _statsGrid(),
                  const SizedBox(height: 6),
                  _chartBox(),
                  const SizedBox(height: 6),
                  _scoreBox(),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: _orangeButton('再来一次', onTap: onRetry, primary: true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statsGrid() {
    final items = <(String, String)>[
      ('刹车初速度 (km/h)', hadPowerCut ? resultV0.toStringAsFixed(1) : '未踩刹车'),
      ('刹停用时 (s)', hadPowerCut ? resultTime.toStringAsFixed(3) : '—'),
      ('制动距离 (m)', resultDist.toStringAsFixed(1)),
      ('最大踏板力 (N)', '$resultForce'),
    ];
    return SizedBox(
      height: 120.84,
      child: Column(
        children: [
          for (var row = 0; row < 2; row++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  top: row == 0 ? 0 : 3,
                  bottom: row == 0 ? 3 : 0,
                ),
                child: Row(
                  children: [
                    for (var col = 0; col < 2; col++) ...[
                      if (col == 1) const SizedBox(width: 6),
                      Expanded(child: _statCell(items[row * 2 + col])),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statCell((String, String) item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.$1,
            style: const TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 10,
              height: 1.65,
              letterSpacing: 0,
              color: _inkSoft,
            ),
          ),
          Text(
            item.$2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 14.5,
              height: 1.65,
              letterSpacing: 0,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartBox() {
    return Container(
      height: 104.14,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF111113), Color(0xFF121214)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1AFFF8EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: 18.14,
            child: Row(
              children: [
                Text(
                  '制动过程',
                  style: TextStyle(
                    fontFamily: AppFonts.noto,
                    fontFamilyFallback: AppFonts.bodyFallback,
                    fontSize: 11,
                    height: 1.65,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w700,
                    color: _cream,
                  ),
                ),
                Spacer(),
                Text('车速 km/h', style: _legendStyle),
                SizedBox(width: 8),
                Text('踏板力 N', style: _legendStyle),
                SizedBox(width: 8),
                Text('断裂极限', style: _legendStyle),
              ],
            ),
          ),
          Expanded(
            child: CustomPaint(
              painter: _ChartPainter(
                samples: w.samples,
                total: w.bt,
                vmax: math.max(60, w.bvKmh),
                failed: w.crashKind.isNotEmpty,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreBox() {
    return Container(
      height: 64.33,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '得分',
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 11,
              height: 1.5,
              letterSpacing: 0,
              color: _inkSoft,
            ),
          ),
          // 得分滚动：0 → 终值（easeOutCubic 0.9s，web 结算高光时刻）
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: resultScore.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(
              v.round().toString(),
              style: const TextStyle(
                fontFamily: AppFonts.kalam,
                fontSize: 28,
                height: 1.65,
                letterSpacing: 0.56,
                fontWeight: FontWeight.w700,
                color: _accentInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const TextStyle _legendStyle = TextStyle(
  fontFamily: AppFonts.noto,
  fontFamilyFallback: AppFonts.bodyFallback,
  fontSize: 9.5,
  height: 1.2,
  letterSpacing: 0,
  color: Color(0xFF76715E),
);

/// 右下角圆形刹车踏板：ready 红底脉冲 / 按下缩小 / 禁用半透明（web .gb-pedal）。
class PinchPedal extends StatelessWidget {
  const PinchPedal({
    super.key,
    this.opacity = 0.55,
    this.label = '刹车',
    this.ready = false,
    this.pressed = false,
    this.disabled = false,
  });

  final double opacity;
  final String label;
  final bool ready;
  final bool pressed;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    Widget pedal = Container(
      width: 81.89,
      height: 81.89,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ready
            ? const RadialGradient(
                center: Alignment(-0.3, -0.4),
                radius: 0.9,
                colors: [Color(0xFFFF6A52), Color(0xFFB3140B)],
                stops: [0, 0.7],
              )
            : const RadialGradient(
                center: Alignment(-0.3, -0.4),
                radius: 0.9,
                colors: [Color(0x29F6EFE3), Color(0x0DF6EFE3)],
                stops: [0, 0.7],
              ),
        border: Border.all(
          color: ready ? const Color(0xE6FF5A46) : const Color(0x47F6EFE3),
          width: 3,
        ),
        boxShadow: ready
            ? [
                BoxShadow(
                  color: const Color(0xFFFF3B26)
                      .withValues(alpha: pressed ? 0.55 : 0.28),
                  blurRadius: pressed ? 44 : 30,
                  spreadRadius: pressed ? 9 : 5,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Container(
                  width: 4,
                  height: 10.6,
                  decoration: BoxDecoration(
                    color: ready
                        ? const Color(0xF2FFFFFF)
                        : const Color(0x8CF6EFE3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 16,
              height: 1.2,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: ready
                  ? Colors.white.withValues(alpha: 0.92)
                  : const Color(0x8CF6EFE3),
            ),
          ),
        ],
      ),
    );
    if (pressed) {
      pedal = Transform.scale(scale: 0.92, child: pedal);
    }
    return Opacity(
      opacity: disabled ? 0.5 : opacity.clamp(0.55, 1.0),
      child: pedal,
    );
  }
}

// ---------------------------------------------------------------------------
// 速度表（web .gb-speedo：金色半圆弧 + 100km/h 门槛刻度 + 白色指针 + 就绪变绿）
// ---------------------------------------------------------------------------

class _SpeedoPainter extends CustomPainter {
  _SpeedoPainter({required this.kmh, required this.ready});

  final double kmh;
  final bool ready;

  static const double _s = 0.864; // 200x120 → 172.8x103.67

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(100 * _s, 110 * _s);
    final r = 80 * _s;
    final rect = Rect.fromCircle(center: center, radius: r);

    // 轨道（var(--gp-glass) 半透明白）
    final track = Paint()
      ..color = const Color(0x2EF6EFE3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.64
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, track);

    // 进度弧：金色 #D8C39A，≥100km/h 后变薄荷绿 #5FE0A0（web .arc.ready）
    final frac = (kmh / 260).clamp(0.0, 1.0);
    if (frac > 0.001) {
      final arcColor = ready
          ? const Color(0xFF5FE0A0)
          : const Color(0xFFD8C39A);
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ready ? 4 : 3)
        ..color = arcColor.withValues(alpha: ready ? 0.55 : 0.35);
      final progress = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.64
        ..strokeCap = StrokeCap.round
        ..color = arcColor;
      final sweep = math.pi * frac;
      canvas.drawArc(rect, math.pi, sweep, false, glow);
      canvas.drawArc(rect, math.pi, sweep, false, progress);
    }

    // 刻度：每 50 一小格 / 每 100 一大格，100 km/h（刹车门槛）金色
    for (var tv = 0; tv <= 260; tv += 50) {
      final angle = math.pi * (1 - tv / 260);
      final major = tv % 100 == 0;
      final gate = tv == 100;
      final r0 = (major ? 66.0 : 71.0) * _s;
      final r1 = 78.0 * _s;
      final p = Paint()
        ..color = gate
            ? const Color(0xFFD8C39A)
            : Color.fromRGBO(245, 239, 230, major ? 0.5 : 0.26)
        ..strokeWidth = gate ? 2.4 : (major ? 2 : 1.3)
        ..strokeCap = StrokeCap.round;
      final dir = Offset(math.cos(angle), -math.sin(angle));
      canvas.drawLine(center + dir * r0, center + dir * r1, p);
    }

    // 白色指针（web #gbrakeMark：74 → 96）
    final ang = math.pi * (1 - (kmh / 260).clamp(0.0, 1.0));
    final dir = Offset(math.cos(ang), -math.sin(ang));
    final mark = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawLine(center + dir * 74 * _s, center + dir * 96 * _s, mark);
  }

  @override
  bool shouldRepaint(covariant _SpeedoPainter old) =>
      old.kmh != kmh || old.ready != ready;
}

/// 制动曲线（web gbrakeDrawChart：渐变填充 + 双色描线 + 断裂极限虚线 + 终点标记）
class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.samples,
    required this.total,
    required this.vmax,
    required this.failed,
  });

  final List<List<double>> samples;
  final double total;
  final double vmax;
  final bool failed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const pad = 4.0;
    final iw = w - pad * 2;
    final ih = h - pad * 2;
    final grid = Paint()
      ..color = const Color(0x1AFFF8EA)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = pad + ih * i / 4;
      canvas.drawLine(Offset(pad, y), Offset(w - pad, y), grid);
    }
    // 断裂极限（1612 / 1715）红色虚线 + 标注
    final limY = pad + ih * (1 - gbBreak / gbFmax);
    final lim = Paint()
      ..color = const Color(0xCCFF3B30)
      ..strokeWidth = 1.4;
    for (var x = pad; x < w - pad; x += 7) {
      canvas.drawLine(
        Offset(x, limY),
        Offset(math.min(x + 4, w - pad), limY),
        lim,
      );
    }
    _label(
      canvas,
      '1612 N',
      Offset(w - pad - 2, limY - 2),
      const Color(0xCCFF3B30),
    );

    if (samples.length < 2) {
      _label(
        canvas,
        '本局没有制动数据',
        Offset(w / 2, h / 2),
        const Color(0x73F5EFE6),
        fontSize: 12,
        center: true,
      );
      return;
    }
    final n = samples.length;
    double xOf(int i) =>
        pad + iw * (samples[i][0] / (total <= 0 ? 1 : total)).clamp(0.0, 1.0);
    double yForce(int i) =>
        pad + ih * (1 - (samples[i][2] / gbFmax).clamp(0.0, 1.0));
    double ySpeed(int i) =>
        pad + ih * (1 - (samples[i][1] / vmax).clamp(0.0, 1.0));

    // 渐变填充（曲线下 55%→00）
    void fill(double Function(int) yOfFn, Color color) {
      final path = Path()..moveTo(pad, pad + ih);
      for (var i = 0; i < n; i++) {
        path.lineTo(xOf(i), yOfFn(i));
      }
      path.lineTo(xOf(n - 1), pad + ih);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.33), color.withValues(alpha: 0)],
          ).createShader(Rect.fromLTRB(0, pad, w, pad + ih)),
      );
    }

    fill(yForce, const Color(0xFFFF6A3D));
    fill(ySpeed, const Color(0xFFF1DCAE));

    // 车速（金）
    _polyline(canvas, n, xOf, ySpeed, const Color(0xFFF1DCAE), 2.2);
    // 踏板力（橙）
    _polyline(canvas, n, xOf, yForce, const Color(0xFFFF6A3D), 1.8);

    // 终点标记：成功绿点 / 失败红叉
    final ex = xOf(n - 1);
    if (failed) {
      final ey = yForce(n - 1);
      final x = Paint()
        ..color = const Color(0xFFFF3B30)
        ..strokeWidth = 2.2;
      canvas.drawLine(Offset(ex - 5, ey - 5), Offset(ex + 5, ey + 5), x);
      canvas.drawLine(Offset(ex + 5, ey - 5), Offset(ex - 5, ey + 5), x);
    } else {
      canvas.drawCircle(
        Offset(ex, pad + ih),
        3.5,
        Paint()..color = const Color(0xFF5FE0A0),
      );
    }
  }

  void _polyline(
    Canvas canvas,
    int n,
    double Function(int) xOf,
    double Function(int) yOf,
    Color color,
    double width,
  ) {
    final path = Path();
    for (var i = 0; i < n; i++) {
      if (i == 0) {
        path.moveTo(xOf(i), yOf(i));
      } else {
        path.lineTo(xOf(i), yOf(i));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    double fontSize = 10,
    bool center = false,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: fontSize,
              fontFamily: AppFonts.noto,
              textAlign: center ? TextAlign.center : TextAlign.right,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: fontSize,
              fontFamily: AppFonts.noto,
            ),
          )
          ..addText(text);
    final para = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 200));
    final dx = center
        ? at.dx - para.maxIntrinsicWidth / 2
        : at.dx - para.maxIntrinsicWidth;
    canvas.drawParagraph(para, Offset(dx, at.dy - para.height));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.samples.length != samples.length || old.failed != failed;
}

// ---------------------------------------------------------------------------
// 品牌行内嵌字形
//
// App 内置的 noto-sc-*-app.otf 是子集字体，缺「款 / 造」两字（web 端由系统
// Noto Sans SC 渲染）。这里从 web 实际加载的 fonts/noto-sans-sc-700-sub.woff2
// 提取轮廓（unitsPerEm = 1000，坐标已转为 y 向下、相对基线），在 Canvas 上
// 直接绘制，保证品牌行文案与参考图一致。
// ---------------------------------------------------------------------------

const String _kGlyphKuan =
    'M656 -494L770 -494L770 -444Q770 -390 763.5 -323.5Q757 -257 737 -184.5Q717 -112 676 -41Q635 30 566 93Q556 80 540.5 64.5Q525 49 507.5 34.5Q490 20 475 11Q538 -43 574.5 -103.5Q611 -164 628 -225.5Q645 -287 650.5 -344Q656 -401 656 -447ZM762 -373Q778 -295 806 -224.5Q834 -154 877 -99.5Q920 -45 981 -14Q967 -2 952 15.5Q937 33 923 52Q909 71 900 88Q834 46 788.5 -20Q743 -86 714 -171.5Q685 -257 666 -356ZM43 -769L512 -769L512 -671L43 -671ZM29 -333L524 -333L524 -235L29 -235ZM68 -621L490 -621L490 -524L68 -524ZM74 -477L484 -477L484 -380L74 -380ZM224 -291L336 -291L336 -23Q336 14 328.5 36.5Q321 59 296 71Q272 84 241 87Q210 90 168 90Q165 66 155.5 37Q146 8 136 -14Q160 -13 181.5 -13Q203 -13 211 -13Q224 -13 224 -25ZM223 -843L335 -843L335 -557L223 -557ZM93 -216L191 -193Q176 -138 154 -79.5Q132 -21 111 20Q95 10 66.5 -2Q38 -14 19 -20Q41 -59 61 -112.5Q81 -166 93 -216ZM364 -183L453 -218Q466 -193 478.5 -165.5Q491 -138 502 -111Q513 -84 518 -63L424 -23Q419 -44 409 -71.5Q399 -99 387.5 -128.5Q376 -158 364 -183ZM602 -669L884 -669L884 -560L602 -560ZM583 -848L700 -832Q688 -741 668.5 -654.5Q649 -568 622 -493.5Q595 -419 560 -362Q550 -372 532 -386Q514 -400 495 -413.5Q476 -427 462 -435Q496 -483 519.5 -549Q543 -615 558.5 -691.5Q574 -768 583 -848ZM853 -669L870 -669L889 -674L971 -651Q962 -602 949.5 -550Q937 -498 923.5 -450Q910 -402 897 -365L800 -394Q810 -427 820 -471Q830 -515 838.5 -562Q847 -609 853 -651Z';

const String _kGlyphZao =
    'M441 -736L915 -736L915 -635L441 -635ZM310 -551L957 -551L957 -450L310 -450ZM413 -840L524 -816Q504 -740 470 -669Q436 -598 398 -550Q386 -560 367.5 -570Q349 -580 330 -590.5Q311 -601 297 -606Q336 -649 366 -712Q396 -775 413 -840ZM579 -850L698 -850L698 -483L579 -483ZM47 -752L136 -817Q164 -794 193.5 -766.5Q223 -739 249 -711Q275 -683 290 -660L195 -587Q182 -611 157 -640Q132 -669 103 -698.5Q74 -728 47 -752ZM272 -464L272 -84L157 -84L157 -353L43 -353L43 -464ZM493 -293L493 -193L767 -193L767 -293ZM381 -389L886 -389L886 -98L381 -98ZM234 -122Q255 -122 275 -107Q295 -92 329 -72Q375 -45 440.5 -38Q506 -31 586 -31Q626 -31 677.5 -32Q729 -33 784 -36Q839 -39 890.5 -44Q942 -49 982 -55Q977 -40 969 -18Q961 4 956 26Q951 48 950 63Q916 65 870 67Q824 69 773 70.5Q722 72 672.5 73Q623 74 582 74Q491 74 428 64.5Q365 55 316 28Q289 11 267.5 -5Q246 -21 232 -21Q217 -21 196 -4.5Q175 12 153 37Q131 62 109 90L37 -15Q86 -61 139.5 -91.5Q193 -122 234 -122Z';

/// 规则卡的 ◆ 项目符号（内置字体缺 U+25C6，用旋转方块等价绘制）。
class _RuleDiamond extends StatelessWidget {
  const _RuleDiamond();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: 4.6,
        height: 4.6,
        decoration: BoxDecoration(
          color: _accent2,
          borderRadius: BorderRadius.circular(0.7),
        ),
      ),
    );
  }
}

/// 把 M/L/Q/C/Z 路径字符串画成一个字（字号 = fontSize）。
class _InkGlyphPainter extends CustomPainter {
  const _InkGlyphPainter({
    required this.data,
    required this.fontSize,
    required this.color,
  });

  final String data;
  final double fontSize;
  final Color color;

  static final Map<String, Path> _cache = <String, Path>{};

  static Path _parse(String src) {
    final Path path = Path();
    final List<String> parts = src.split(RegExp(r'(?=[MLQCZ])'));
    for (final String seg in parts) {
      if (seg.isEmpty) continue;
      final String cmd = seg[0];
      final String rest = seg.substring(1).trim();
      if (rest.isEmpty) {
        if (cmd == 'Z') path.close();
        continue;
      }
      final List<double> n = rest.split(' ').map(double.parse).toList();
      switch (cmd) {
        case 'M':
          path.moveTo(n[0], n[1]);
          break;
        case 'L':
          path.lineTo(n[0], n[1]);
          break;
        case 'Q':
          path.quadraticBezierTo(n[0], n[1], n[2], n[3]);
          break;
        case 'C':
          path.cubicTo(n[0], n[1], n[2], n[3], n[4], n[5]);
          break;
        default:
          path.close();
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = _cache.putIfAbsent(data, () => _parse(data));
    canvas.save();
    canvas.translate(0, fontSize * 1.213);
    canvas.scale(fontSize / 1000);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InkGlyphPainter old) =>
      old.data != data || old.fontSize != fontSize || old.color != color;
}
