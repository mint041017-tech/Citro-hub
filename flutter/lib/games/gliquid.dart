import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../services/game_sfx.dart';
import '../services/refresh_rate.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/paper.dart';
import 'game_ui.dart'
    show
        GameActionButton,
        GameIcons,
        GameScaffold,
        GameScorePill,
        GameTape,
        showGameRank;
import 'gliquid_game.dart';
import 'gliquid_physics.dart';
import 'gliquid_sfx.dart';

const Color _ink = Color(0xFF26313F);
const Color _cream = Color(0xFFFFFAF0);
const Color _paper = Color(0xFFF5ECDB);
const Color _coral = Color(0xFFD9584A);
const Color _coralLt = Color(0xFFFF7B67);
const Color _mint = Color(0xFFA9E5C8);
const Color _lineSoft = Color(0x2E26313F);

class _LiquidPalette {
  const _LiquidPalette._();

  static const List<Color> _fills = [
    Color(0xFFA9ECCB),
    Color(0xFFA9D8FF),
    Color(0xFFCBB8FF),
    Color(0xFFFFC3D6),
    Color(0xFFFFB08C),
    Color(0xFFFFDD7F),
    Color(0xFFC9EA7C),
    Color(0xFF86E6DC),
    Color(0xFFFF9FC3),
    Color(0xFFB7A3FF),
    Color(0xFFA9D98B),
    Color(0xFFFFD36E),
  ];

  static const List<Color> _edges = [
    Color(0xFF2F7C62),
    Color(0xFF346A9C),
    Color(0xFF6B50A8),
    Color(0xFFAB4F72),
    Color(0xFFA95835),
    Color(0xFF98701A),
    Color(0xFF66821F),
    Color(0xFF2F7F78),
    Color(0xFFA73963),
    Color(0xFF5E4A99),
    Color(0xFF5B7A2C),
    Color(0xFFA66A00),
  ];

  static Color fill(int level) {
    if (level <= _fills.length) return _fills[level - 1];
    final hue = ((level - 13) * 47.0 + 266) % 360;
    return HSLColor.fromAHSL(1, hue, 0.58, 0.76).toColor();
  }

  static Color edge(int level) {
    if (level <= _edges.length) return _edges[level - 1];
    final hue = ((level - 13) * 47.0 + 266) % 360;
    return HSLColor.fromAHSL(1, hue, 0.62, 0.38).toColor();
  }

  static Color lighten(Color color, double amount) =>
      Color.lerp(color, Colors.white, amount)!;

  static Color darken(Color color, double amount) =>
      Color.lerp(color, Colors.black, amount)!;

  static Color rainbow(int level, double t) {
    final base = HSLColor.fromColor(fill(level));
    final hue = (base.hue + t * 300) % 360;
    return HSLColor.fromAHSL(1, hue, 0.7, 0.78).toColor();
  }
}

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);

class _Repaint extends ChangeNotifier {
  void tick() => notifyListeners();
}

class GameLiquidPage extends StatefulWidget {
  const GameLiquidPage({super.key});

  @override
  State<GameLiquidPage> createState() => _GameLiquidPageState();
}

class _GameLiquidPageState extends State<GameLiquidPage>
    with SingleTickerProviderStateMixin {
  final _repaint = _Repaint();
  final _focus = FocusNode(debugLabel: 'liquid-2048');
  LiquidGame? _game;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  Size _lastSize = Size.zero;

  int _best = 0;
  bool _newBest = false;
  bool _submitted = false;
  int _lastScore = -1;
  int _lastQueueSig = -1;
  LiquidPhase? _lastPhase;
  bool _lastHint = false;
  String? _toast;
  Timer? _toastTimer;
  final ValueNotifier<String> _liveProgressNotifier = ValueNotifier('');
  @override
  void initState() {
    super.initState();
    _best = AppState.instance.localBest('liquid');
    // v1.6.0 起音效默认关闭（只有跳一跳/刹车开着），液体游戏在这里打开。
    GameSfx.soundsEnabled = true;
    unawaited(GameSfx.warmup());
    RefreshRate.acquire();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final topInset = 96 + MediaQuery.paddingOf(context).top;
    if (_game == null) {
      _game = LiquidGame(
        layout: LiquidLayout.compute(
          size.width,
          size.height,
          topInset: topInset,
        ),
      );
      _lastSize = size;
      _ticker = createTicker(_tick)..start();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    } else if (size != _lastSize) {
      _lastSize = size;
      _game!.resize(
        LiquidLayout.compute(size.width, size.height, topInset: topInset),
      );
    }
  }

  void _tick(Duration elapsed) {
    final game = _game;
    if (game == null) return;

    var dt = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.05) dt = 1 / 60;

    game.step(dt);
    _repaint.tick();
    _consumeEvents(game.drainEvents());

    final queueSig = game.queue
        .take(3)
        .fold<int>(0, (sum, level) => sum * 31 + level);
    final phaseChanged = game.phase != _lastPhase;
    if (game.score != _lastScore ||
        queueSig != _lastQueueSig ||
        game.hintVisible != _lastHint ||
        phaseChanged) {
      _lastScore = game.score;
      _lastQueueSig = queueSig;
      _lastHint = game.hintVisible;
      _lastPhase = game.phase;
      _liveProgressNotifier.value = _liveProgress;
      if (mounted) setState(() {});
    }

    if (phaseChanged && game.phase == LiquidPhase.over) {
      _finishRound(game);
    }
  }

  void _consumeEvents(List<LiquidEvent> events) {
    for (final event in events) {
      switch (event.type) {
        case LiquidEventType.shoot:
          LiquidSfx.shoot(event.power);
        case LiquidEventType.merge:
          LiquidSfx.merge(event.level, event.combo);
        case LiquidEventType.warn:
          LiquidSfx.warn();
        case LiquidEventType.overflow:
          LiquidSfx.over();
        case LiquidEventType.tierUp:
        case LiquidEventType.unlock:
          if (event.message != null) _showToast(event.message!);
          LiquidSfx.pop();
        case LiquidEventType.start:
          LiquidSfx.start();
        case LiquidEventType.over:
          break;
      }
    }
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      setState(() => _toast = null);
    });
  }

  void _finishRound(LiquidGame game) {
    if (_submitted) return;
    _submitted = true;
    final previousBest = _best;
    final isNewBest = game.score > previousBest;
    _best = math.max(_best, game.score);
    unawaited(AppState.instance.saveLocalBest('liquid', game.score));
    unawaited(AppState.instance.submitScore('liquid', game.score));
    if (mounted) setState(() => _newBest = isNewBest);
  }

  void _start() {
    final game = _game;
    if (game == null) return;
    game.start();
    _focus.requestFocus();
    setState(() {});
  }

  void _restart({bool demo = false}) {
    final game = _game;
    if (game == null) return;
    _submitted = false;
    _newBest = false;
    _toast = null;
    _toastTimer?.cancel();
    game.reset(demo: demo);
    if (!demo) game.start();
    _lastScore = -1;
    _lastQueueSig = -1;
    _lastPhase = null;
    _lastHint = game.hintVisible;
    _focus.requestFocus();
    setState(() {});
  }

  void _onPointerDown(PointerDownEvent event) {
    final game = _game;
    if (game == null || !game.isPlaying) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryButton) {
      return;
    }
    _focus.requestFocus();
    game.setAimFromPoint(event.localPosition.dx, event.localPosition.dy);
    game.beginCharge();
  }

  void _onPointerMove(PointerMoveEvent event) {
    final game = _game;
    if (game == null || !game.isPlaying) return;
    game.setAimFromPoint(event.localPosition.dx, event.localPosition.dy);
  }

  void _onPointerUp(PointerUpEvent event) {
    _game?.releaseShot();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _game?.cancelCharge();
  }

  void _onHover(PointerHoverEvent event) {
    final game = _game;
    if (game == null || !game.isPlaying) return;
    game.setAimFromPoint(event.localPosition.dx, event.localPosition.dy);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final game = _game;
    if (game == null) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.space) {
        if (game.isPlaying) game.beginCharge();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.keyA) {
        game.nudgeAim(-0.06);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.keyD) {
        game.nudgeAim(0.06);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyR) {
        _restart();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        if (game.phase == LiquidPhase.intro) {
          _start();
          return KeyEventResult.handled;
        }
        if (game.phase == LiquidPhase.over) {
          _restart();
          return KeyEventResult.handled;
        }
      }
    } else if (event is KeyUpEvent && key == LogicalKeyboardKey.space) {
      if (game.charging) game.releaseShot();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _liveProgress {
    final game = _game;
    if (game == null) return '';
    final maxValue = LiquidLevels.valueForLevel(math.max(1, game.maxLevel));
    return '得分 ${LiquidGame.formatScore(game.score)} · 最大 '
        '${LiquidGame.formatBlobValue(maxValue)}';
  }

  @override
  void dispose() {
    GameSfx.soundsEnabled = false;
    _liveProgressNotifier.dispose();
    _ticker?.dispose();
    _toastTimer?.cancel();
    _focus.dispose();
    _repaint.dispose();
    RefreshRate.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    if (game == null) {
      return const Scaffold(backgroundColor: _paper, body: SizedBox.shrink());
    }
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GameScaffold(
          gameKey: 'gliquid',
          title: '咕噜果冻铺',
          rankGame: 'liquid',
          showLive: true,
          liveProgress: _liveProgressNotifier,
          onBack: () => popOrHome(context),
          pills: [
            GameScorePill(label: '分数', value: LiquidGame.formatScore(game.score)),
            GameScorePill(
              label: '最高分',
              value: LiquidGame.formatScore(math.max(_best, game.score)),
            ),
            GameScorePill(
              label: '接下来',
              value: game.queue
                  .skip(1)
                  .take(3)
                  .map((l) => LiquidGame.formatBlobValue(
                        LiquidLevels.valueForLevel(l),
                      ))
                  .join('·'),
              minWidth: 96,
            ),
          ],
          actions: [
            GameActionButton(
              label: '重开',
              icon: GameIcons.refresh,
              onTap: () => _restart(),
            ),
            GameActionButton(
              label: '排行榜',
              icon: GameIcons.trophy,
              onTap: () => showGameRank(
                context,
                game: 'liquid',
                title: '咕噜果冻铺',
              ),
            ),
          ],
          boardGap: 12,
          board: LayoutBuilder(
            builder: (context, cons) {
              final media = MediaQuery.sizeOf(context);
              final avail = cons.maxWidth.isFinite ? cons.maxWidth : 760.0;
              final wide = media.width >= 1100 && media.width > media.height;
              final boardW = math.min(avail, 430.0);
              // 竖屏时让整页放得下，避免拖动瞄准时把页面也一起滚了。
              final boardH = wide
                  ? math.min(760.0, math.max(440.0, media.height - 240))
                  : math.min(620.0, math.max(460.0, media.height - 350));
              return SizedBox(
                width: boardW,
                height: boardH,
                child: GameLiquidView(
                  game: game,
                  repaint: _repaint,
                  best: _best,
                  newBest: _newBest,
                  toast: _toast,
                  onBack: () => popOrHome(context),
                  onStart: _start,
                  onRestart: () => _restart(),
                  onHome: () => _restart(demo: true),
                  onRank: () => showGameRank(
                    context,
                    game: 'liquid',
                    title: '咕噜果冻铺',
                  ),
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  onHover: _onHover,
                  chrome: false,
                ),
              );
            },
          ),
        ),
    );
  }
}

class GameLiquidView extends StatelessWidget {
  const GameLiquidView({
    super.key,
    required this.game,
    required this.best,
    this.repaint,
    this.newBest = false,
    this.toast,
    this.onBack,
    this.onStart,
    this.onRestart,
    this.onHome,
    this.onRank,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this.onHover,
    this.interactive = true,
    this.chrome = true,
  });

  final LiquidGame game;
  final Listenable? repaint;
  final int best;
  final bool newBest;
  final String? toast;
  final VoidCallback? onBack;
  final VoidCallback? onStart;
  final VoidCallback? onRestart;
  final VoidCallback? onHome;
  final VoidCallback? onRank;
  final void Function(PointerDownEvent)? onPointerDown;
  final void Function(PointerMoveEvent)? onPointerMove;
  final void Function(PointerUpEvent)? onPointerUp;
  final void Function(PointerCancelEvent)? onPointerCancel;
  final void Function(PointerHoverEvent)? onHover;
  final bool interactive;

  /// false = 作为 GameScaffold 的 board 使用：不画页面背景和自定义 HUD，
  /// 标题/分数/排行榜/正在玩全部交给标准骨架，保持和其他游戏一致。
  final bool chrome;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final topInset = chrome
            ? 96 + MediaQuery.paddingOf(context).top
            : 14.0;
        if ((size.width - game.layout.width).abs() > 0.5 ||
            (size.height - game.layout.height).abs() > 0.5) {
          game.resize(
            LiquidLayout.compute(size.width, size.height, topInset: topInset),
          );
        }

        Widget stage = RepaintBoundary(
          child: CustomPaint(
            painter: _LiquidStagePainter(game: game, repaint: repaint),
            isComplex: true,
            willChange: true,
          ),
        );

        if (interactive) {
          stage = Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: onPointerDown,
            onPointerMove: onPointerMove,
            onPointerUp: onPointerUp,
            onPointerCancel: onPointerCancel,
            child: MouseRegion(
              cursor: SystemMouseCursors.precise,
              onHover: onHover,
              child: stage,
            ),
          );
        }

        final hudTop = chrome
            ? MediaQuery.paddingOf(context).top + 6
            : 6.0;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final hudScale = screenWidth >= 1100
            ? 1.18
            : screenWidth >= 760
            ? 1.08
            : 1.0;
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.08,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (chrome)
                const RepaintBoundary(
                  child: CustomPaint(
                    painter: _LiquidBackdropPainter(),
                    isComplex: true,
                    willChange: false,
                  ),
                ),
              stage,
              if (chrome)
                Positioned(
                  left: 0,
                  right: 0,
                  top: hudTop,
                  child: Transform.scale(
                    scale: hudScale,
                    alignment: Alignment.topCenter,
                    child: _LiquidHud(game: game, best: best),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 14,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: game.hintVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 260),
                    child: const Center(child: _LiquidHint()),
                  ),
                ),
              ),
              if (toast != null)
                Positioned(
                  left: 12,
                  right: 12,
                  top: hudTop + 92 * hudScale,
                  child: IgnorePointer(
                    child: Center(child: _LiquidToast(text: toast!)),
                  ),
                ),
              if (game.phase == LiquidPhase.intro)
                Positioned.fill(
                  child: _IntroOverlay(
                    game: game,
                    best: best,
                    repaint: repaint,
                    onStart: onStart,
                  ),
                ),
              if (game.phase == LiquidPhase.over)
                Positioned.fill(
                  child: _EndOverlay(
                    game: game,
                    best: best,
                    newBest: newBest,
                    onRestart: onRestart,
                    onHome: onHome,
                    onRank: onRank,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LiquidHud extends StatelessWidget {
  const _LiquidHud({required this.game, required this.best});

  final LiquidGame game;
  final int best;

  @override
  Widget build(BuildContext context) {
    final next = game.queue.skip(1).take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LiquidBrand(),
          const SizedBox(height: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _LiquidScoreCard(
                    score: game.score,
                    best: math.max(best, game.score),
                  ),
                ),
                const SizedBox(width: 8),
                _LiquidNextCard(next: next),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiquidBrand extends StatelessWidget {
  const _LiquidBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 20,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                bottom: 1,
                child: _dot(10, const Color(0xFFA9ECCB)),
              ),
              Positioned(
                left: 9,
                bottom: 4,
                child: _dot(12, const Color(0xFFFFC3D6)),
              ),
              Positioned(
                left: 19,
                bottom: 2,
                child: _dot(9, const Color(0xFFFFDD7F)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '咕噜果冻铺',
          style: TextStyle(
            fontFamily: AppFonts.zcool,
            fontFamilyFallback: AppFonts.bodyFallback,
            fontSize: 17,
            height: 1.1,
            letterSpacing: 1.2,
            color: _ink,
          ),
        ),
      ],
    );
  }

  Widget _dot(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: _ink.withValues(alpha: 0.7), width: 1),
    ),
  );
}

class _LiquidScoreCard extends StatelessWidget {
  const _LiquidScoreCard({required this.score, required this.best});

  final int score;
  final int best;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: _cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _ink.withValues(alpha: 0.82), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F26313F),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: '得分',
              value: LiquidGame.formatScore(score),
              bumpKey: score,
            ),
          ),
          SizedBox(
            width: 12,
            height: 28,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 2,
                    height: 2,
                    margin: const EdgeInsets.symmetric(vertical: 1.6),
                    decoration: BoxDecoration(
                      color: _ink.withValues(alpha: 0.28),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _Stat(label: '最佳', value: LiquidGame.formatScore(best)),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.bumpKey});

  final String label;
  final String value;
  final int? bumpKey;

  @override
  Widget build(BuildContext context) {
    Widget number = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: TextStyle(
        fontFamily: AppFonts.kalam,
        fontFamilyFallback: AppFonts.fallback,
        fontSize: 20,
        height: 1.05,
        color: _ink,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      ),
    );
    if (bumpKey != null && bumpKey! > 0) {
      number = TweenAnimationBuilder<double>(
        key: ValueKey(bumpKey),
        tween: Tween(begin: 1.16, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (_, scale, child) => Transform.scale(
          scale: scale,
          alignment: Alignment.centerLeft,
          child: child,
        ),
        child: number,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.noto,
            fontFamilyFallback: AppFonts.bodyFallback,
            fontSize: 8.5,
            height: 1,
            letterSpacing: 0.8,
            color: _ink.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 2),
        number,
      ],
    );
  }
}

class _LiquidNextCard extends StatelessWidget {
  const _LiquidNextCard({required this.next});

  final List<int> next;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
      decoration: BoxDecoration(
        color: _cream.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _ink.withValues(alpha: 0.45), width: 1.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '接下来',
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 8.5,
              letterSpacing: 0.6,
              color: _ink.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 7),
          for (var i = 0; i < next.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _NextChip(level: next[i]),
          ],
        ],
      ),
    );
  }
}

class _NextChip extends StatelessWidget {
  const _NextChip({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final fill = _LiquidPalette.fill(level);
    final edge = _LiquidPalette.edge(level);
    return Container(
      height: 26,
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: edge, width: 1.1),
      ),
      alignment: Alignment.center,
      child: Text(
        LiquidGame.formatBlobValue(LiquidLevels.valueForLevel(level)),
        style: TextStyle(
          fontFamily: AppFonts.noto,
          fontFamilyFallback: AppFonts.bodyFallback,
          fontWeight: FontWeight.w800,
          fontSize: 8.5,
          height: 1,
          color: _ink,
        ),
      ),
    );
  }
}

class _LiquidHint extends StatelessWidget {
  const _LiquidHint();

  @override
  Widget build(BuildContext context) {
    final desktop =
        !kIsWeb && (Theme.of(context).platform == TargetPlatform.windows);
    final text = desktop ? '按住蓄力 · ← → 微调 · 空格或松开出手' : '按住蓄力 · 拖动瞄准 · 松开出手';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: _cream.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _ink.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: _coralLt,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 10.5,
              letterSpacing: 0.3,
              color: _ink.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiquidToast extends StatelessWidget {
  const _LiquidToast({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3326313F),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppFonts.noto,
          fontFamilyFallback: AppFonts.bodyFallback,
          fontSize: 11,
          height: 1.35,
          letterSpacing: 0.2,
          color: _cream,
        ),
      ),
    );
  }
}

class _IntroOverlay extends StatelessWidget {
  const _IntroOverlay({
    required this.game,
    required this.best,
    this.repaint,
    this.onStart,
  });

  final LiquidGame game;
  final int best;
  final Listenable? repaint;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return _OverlayVeil(
      child: _PaperDialog(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SOFT LIQUID MERGE · 软体合并',
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontFamilyFallback: AppFonts.bodyFallback,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
                color: _ink.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 6),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 2,
                  right: 58,
                  bottom: 6,
                  height: 16,
                  child: Transform.rotate(
                    angle: -0.025,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: _mint,
                        borderRadius: BorderRadius.all(Radius.circular(7)),
                      ),
                    ),
                  ),
                ),
                Text(
                  '咕噜果冻铺',
                  style: TextStyle(
                    fontFamily: AppFonts.zcool,
                    fontFamilyFallback: AppFonts.bodyFallback,
                    fontSize: 36,
                    height: 1.12,
                    letterSpacing: 2,
                    color: _ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 82,
                  height: 82,
                  child: CustomPaint(
                    painter: _MascotPainter(game: game, repaint: repaint),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '把软乎乎的一团投进罐子。\n相同数字会流到一起，\n数字没有上限。',
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontFamilyFallback: AppFonts.bodyFallback,
                      fontSize: 12,
                      height: 1.65,
                      color: _ink.withValues(alpha: 0.82),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Expanded(
                  child: _HowTo(step: '1', title: '瞄准', caption: '拖动 / ← →'),
                ),
                Expanded(
                  child: _HowTo(step: '2', title: '蓄力', caption: '按住不放'),
                ),
                Expanded(
                  child: _HowTo(step: '3', title: '投下', caption: '松开出手'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PaperButton(
              label: '开张营业',
              trailing: '→',
              primary: true,
              onTap: onStart,
            ),
            const SizedBox(height: 10),
            Text(
              '没有倒计时，慢慢玩。果冻溢出罐口才打烊。'
              '${best > 0 ? '  本机最佳 ${LiquidGame.formatScore(best)}' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontFamilyFallback: AppFonts.bodyFallback,
                fontSize: 9,
                height: 1.5,
                letterSpacing: 0.2,
                color: _ink.withValues(alpha: 0.58),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowTo extends StatelessWidget {
  const _HowTo({
    required this.step,
    required this.title,
    required this.caption,
  });

  final String step;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _mint.withValues(alpha: 0.8),
            shape: BoxShape.circle,
            border: Border.all(color: _ink.withValues(alpha: 0.6), width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: TextStyle(
              fontFamily: AppFonts.kalam,
              fontFamilyFallback: AppFonts.fallback,
              fontSize: 12,
              height: 1,
              color: _ink,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          title,
          style: TextStyle(
            fontFamily: AppFonts.noto,
            fontFamilyFallback: AppFonts.bodyFallback,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          caption,
          style: TextStyle(
            fontFamily: AppFonts.noto,
            fontFamilyFallback: AppFonts.bodyFallback,
            fontSize: 8.5,
            color: _ink.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _EndOverlay extends StatelessWidget {
  const _EndOverlay({
    required this.game,
    required this.best,
    required this.newBest,
    this.onRestart,
    this.onHome,
    this.onRank,
  });

  final LiquidGame game;
  final int best;
  final bool newBest;
  final VoidCallback? onRestart;
  final VoidCallback? onHome;
  final VoidCallback? onRank;

  @override
  Widget build(BuildContext context) {
    final maxValue = LiquidLevels.valueForLevel(game.maxLevel);
    final nextValue = LiquidLevels.valueForLevel(game.maxLevel + 1);
    final maxFill = _LiquidPalette.fill(game.maxLevel);
    final maxEdge = _LiquidPalette.edge(game.maxLevel);
    return _OverlayVeil(
      child: _PaperDialog(
        width: 352,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "TODAY'S JAR",
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontFamilyFallback: AppFonts.bodyFallback,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                      color: _ink.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                if (newBest)
                  Transform.rotate(
                    angle: 0.045,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _coral,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '新的本机纪录',
                        style: TextStyle(
                          fontFamily: AppFonts.noto,
                          fontFamilyFallback: AppFonts.bodyFallback,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: _cream,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '罐口溢出来啦',
              style: TextStyle(
                fontFamily: AppFonts.zcool,
                fontFamilyFallback: AppFonts.bodyFallback,
                fontSize: 32,
                height: 1.15,
                letterSpacing: 1.8,
                color: _ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              newBest ? '刷新了本机纪录，这罐果冻很争气。' : '罐口溢出来了，这罐就打烊。',
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontFamilyFallback: AppFonts.bodyFallback,
                fontSize: 10.5,
                color: _ink.withValues(alpha: 0.66),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '本局得分',
                        style: TextStyle(
                          fontFamily: AppFonts.noto,
                          fontFamilyFallback: AppFonts.bodyFallback,
                          fontSize: 9,
                          letterSpacing: 0.6,
                          color: _ink.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        LiquidGame.formatScore(game.score),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: AppFonts.kalam,
                          fontFamilyFallback: AppFonts.fallback,
                          fontSize: 36,
                          height: 1,
                          color: _ink,
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _EndStat(
                        label: '最大果冻',
                        value: LiquidGame.formatBlobValue(maxValue),
                        dot: maxFill,
                        dotEdge: maxEdge,
                      ),
                      const SizedBox(height: 5),
                      _EndStat(label: '投出次数', value: '${game.shots}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _paper.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _lineSoft),
              ),
              child: Row(
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.trophy, width: 2, color: '#26313F'),
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '本机最佳 ${LiquidGame.formatScore(best)}',
                      style: TextStyle(
                        fontFamily: AppFonts.noto,
                        fontFamilyFallback: AppFonts.bodyFallback,
                        fontSize: 9.5,
                        color: _ink.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                  Text(
                    '下一站 ${LiquidGame.formatBlobValue(nextValue)}',
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontFamilyFallback: AppFonts.bodyFallback,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: maxEdge,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _PaperButton(
              label: '再来一罐',
              trailing: '→',
              primary: true,
              onTap: onRestart,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _PaperButton(
                    label: '排行榜',
                    onTap: onRank,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PaperButton(
                    label: '回看玩法',
                    onTap: onHome,
                    compact: true,
                    outlined: true,
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

class _EndStat extends StatelessWidget {
  const _EndStat({
    required this.label,
    required this.value,
    this.dot,
    this.dotEdge,
  });

  final String label;
  final String value;
  final Color? dot;
  final Color? dotEdge;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (dot != null) ...[
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
              border: Border.all(color: dotEdge ?? _ink, width: 1),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.noto,
            fontFamilyFallback: AppFonts.bodyFallback,
            fontSize: 9,
            color: _ink.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppFonts.kalam,
            fontFamilyFallback: AppFonts.fallback,
            fontSize: 15,
            color: _ink,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _OverlayVeil extends StatelessWidget {
  const _OverlayVeil({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = _dialogScale(context);
    return ColoredBox(
      color: _paper.withValues(alpha: 0.78),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Transform.scale(scale: scale, child: child),
          ),
        ),
      ),
    );
  }
}

double _dialogScale(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 1100) return 1.16;
  if (width >= 760) return 1.06;
  return 1.0;
}

class _PaperDialog extends StatelessWidget {
  const _PaperDialog({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: _cream,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _ink, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2626313F),
                  blurRadius: 22,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: child,
          ),
          Positioned(
            top: -8,
            left: 28,
            child: GameTape(
              width: 84,
              height: 22,
              color: const Color(0xB8FFD696),
              angle: -3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperButton extends StatelessWidget {
  const _PaperButton({
    required this.label,
    this.trailing,
    this.onTap,
    this.primary = false,
    this.outlined = false,
    this.compact = false,
  });

  final String label;
  final String? trailing;
  final VoidCallback? onTap;
  final bool primary;
  final bool outlined;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? _cream : _ink;
    final background = primary
        ? _ink
        : outlined
        ? Colors.transparent
        : _paper.withValues(alpha: 0.9);
    return Pressable(
      onTap: onTap,
      child: Container(
        height: compact ? 38 : 48,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(compact ? 12 : 15),
          border: Border.all(
            color: primary
                ? _ink
                : _ink.withValues(alpha: outlined ? 0.5 : 0.8),
            width: primary ? 2 : 1.3,
          ),
          boxShadow: primary
              ? const [
                  BoxShadow(color: _coral, offset: Offset(0, 4), blurRadius: 0),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.zcool,
                fontFamilyFallback: AppFonts.bodyFallback,
                fontSize: compact ? 12 : 16,
                letterSpacing: 1,
                color: foreground,
              ),
            ),
            if (trailing != null && !compact) ...[
              const SizedBox(width: 7),
              Text(
                trailing!,
                style: TextStyle(
                  fontFamily: AppFonts.noto,
                  fontSize: compact ? 11 : 15,
                  color: foreground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   液体渲染
   ============================================================ */

class _LiquidBackdropPainter extends CustomPainter {
  const _LiquidBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = _paper);

    var paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.12, size.height * 0.08),
        math.max(size.width, size.height) * 0.58,
        [
          const Color(0x66A9E5C8),
          const Color(0x14A9E5C8),
          const Color(0x00A9E5C8),
        ],
        [0, 0.6, 1],
      );
    canvas.drawRect(rect, paint);

    paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.92, size.height * 0.92),
        math.max(size.width, size.height) * 0.48,
        [
          const Color(0x29FF7B67),
          const Color(0x0AFF7B67),
          const Color(0x00FF7B67),
        ],
        [0, 0.65, 1],
      );
    canvas.drawRect(rect, paint);

    final random = math.Random(24681357);
    final dotPaint = Paint()..color = _ink.withValues(alpha: 0.05);
    for (var y = 18.0; y < size.height; y += 24) {
      for (var x = 16.0; x < size.width; x += 24) {
        if (random.nextDouble() < 0.52) continue;
        canvas.drawCircle(
          Offset(x + random.nextDouble() * 3, y + random.nextDouble() * 3),
          1.05,
          dotPaint,
        );
      }
    }

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _ink.withValues(alpha: 0.12);
    _drawDashedArc(
      canvas,
      Rect.fromCircle(
        center: Offset(size.width / 2, size.height * 0.28),
        radius: math.min(size.width * 0.43, 420),
      ),
      math.pi * 0.08,
      math.pi * 0.9,
      arcPaint,
    );

    final starPaint = Paint()..color = _ink.withValues(alpha: 0.17);
    for (var i = 0; i < 9; i++) {
      final x = size.width * (0.06 + random.nextDouble() * 0.88);
      final y = size.height * (0.08 + random.nextDouble() * 0.55);
      if ((x - size.width / 2).abs() < math.min(size.width * 0.42, 380) &&
          y > size.height * 0.2) {
        continue;
      }
      canvas.drawPath(
        _starPath(Offset(x, y), 2 + random.nextDouble() * 4),
        starPaint,
      );
    }

    final doodlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = _ink.withValues(alpha: 0.09);
    for (var i = 0; i < 3; i++) {
      final x = size.width * (0.05 + random.nextDouble() * 0.2);
      final y = size.height * (0.2 + random.nextDouble() * 0.4);
      final path = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + 18, y - 8, x + 34, y + 4);
      canvas.drawPath(path, doodlePaint);
    }
  }

  void _drawDashedArc(
    Canvas canvas,
    Rect rect,
    double start,
    double sweep,
    Paint paint,
  ) {
    const segments = 22;
    for (var i = 0; i < segments; i += 2) {
      final a0 = start + sweep * (i / segments);
      final a1 = start + sweep * ((i + 1) / segments);
      canvas.drawArc(rect, a0, a1 - a0, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidBackdropPainter oldDelegate) => false;
}

class _LiquidStagePainter extends CustomPainter {
  _LiquidStagePainter({required this.game, super.repaint});

  final LiquidGame game;
  final math.Random _shakeRng = math.Random();

  @override
  void paint(Canvas canvas, Size size) {
    final layout = game.layout;
    canvas.save();
    if (game.shake > 0.2) {
      // 原版是逐帧 rand(-shake, shake) 的随机抖动，不是平滑正弦。
      canvas.translate(
        (_shakeRng.nextDouble() * 2 - 1) * game.shake,
        (_shakeRng.nextDouble() * 2 - 1) * game.shake,
      );
    }

    _drawShelf(canvas, layout);
    _drawJarBack(canvas, layout);
    _drawGhosts(canvas);
    _drawBlobs(canvas);
    _drawEffects(canvas);
    _drawJarFront(canvas, layout);
    _drawOverflow(canvas, layout);
    _drawLauncher(canvas, layout);
    _drawFloats(canvas);
    canvas.restore();
  }

  void _drawShelf(Canvas canvas, LiquidLayout layout) {
    final center = Offset(layout.cx, layout.floorY + 12);
    final shadow = Paint()
      ..shader = ui.Gradient.radial(
        center,
        layout.jarW * 0.56,
        [
          const Color(0x2626313F),
          const Color(0x0D26313F),
          const Color(0x0026313F),
        ],
        [0, 0.7, 1],
      );
    canvas.save();
    canvas.translate(0, 0);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: layout.jarW * 1.08, height: 36),
      shadow,
    );
    canvas.restore();

    final shelfY = layout.floorY + 3;
    final shelfPad = math.min(54.0, layout.jarW * 0.09);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        layout.jarX0 - shelfPad,
        shelfY,
        layout.jarW + shelfPad * 2,
        10,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xB3DECBB0));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _ink.withValues(alpha: 0.24),
    );
    final topRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        layout.jarX0 - shelfPad,
        shelfY - 2,
        layout.jarW + shelfPad * 2,
        4,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(topRect, Paint()..color = const Color(0xE6F6EDDD));
    canvas.drawRRect(
      topRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _ink.withValues(alpha: 0.2),
    );
  }

  Path _jarPath(LiquidLayout layout, {bool close = true}) {
    final r = math.min(26.0, layout.jarW * 0.08);
    final path = Path()
      ..moveTo(layout.jarX0, layout.jarTop)
      ..lineTo(layout.jarX0, layout.floorY - r)
      ..quadraticBezierTo(
        layout.jarX0,
        layout.floorY,
        layout.jarX0 + r,
        layout.floorY,
      )
      ..lineTo(layout.jarX1 - r, layout.floorY)
      ..quadraticBezierTo(
        layout.jarX1,
        layout.floorY,
        layout.jarX1,
        layout.floorY - r,
      )
      ..lineTo(layout.jarX1, layout.jarTop);
    if (close) path.close();
    return path;
  }

  void _drawJarBack(Canvas canvas, LiquidLayout layout) {
    final path = _jarPath(layout);
    final glass = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, layout.jarTop),
        Offset(0, layout.floorY),
        [
          Colors.white.withValues(alpha: 0.2),
          Colors.white.withValues(alpha: 0.05),
          const Color(0x24BEE0D3),
        ],
        [0, 0.45, 1],
      );
    canvas.drawPath(path, glass);

    final floorShade = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, layout.floorY - 42),
        Offset(0, layout.floorY),
        [const Color(0x0026313F), const Color(0x1326313F)],
      );
    canvas.drawRect(
      Rect.fromLTWH(layout.jarX0, layout.floorY - 42, layout.jarW, 42),
      floorShade,
    );

    final tickPaint = Paint()
      ..color = _ink.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = layout.jarTop + layout.jarH * (i / 4);
      canvas.drawLine(
        Offset(layout.jarX0 + 16, y),
        Offset(layout.jarX0 + 34, y),
        tickPaint,
      );
      _drawText(
        canvas,
        '${i * 25}',
        Offset(layout.jarX0 + 39, y),
        fontSize: 8,
        color: _ink.withValues(alpha: 0.24),
        weight: FontWeight.w600,
        align: TextAlign.left,
        centerVertically: true,
      );
    }

    final rimShade = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, layout.jarTop),
        Offset(0, layout.jarTop + 34),
        [const Color(0x1426313F), const Color(0x0026313F)],
      );
    canvas.drawRect(
      Rect.fromLTWH(layout.jarX0, layout.jarTop, layout.jarW, 34),
      rimShade,
    );
  }

  void _drawJarFront(Canvas canvas, LiquidLayout layout) {
    final path = _jarPath(layout);

    canvas.save();
    canvas.clipPath(path);
    final sheen = Paint()
      ..shader = ui.Gradient.linear(
        Offset(layout.jarX0, layout.jarTop),
        Offset(layout.jarX1, layout.floorY),
        [
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.07),
        ],
        [0, 0.2, 0.78, 1],
      );
    canvas.drawRect(
      Rect.fromLTWH(layout.jarX0, layout.jarTop, layout.jarW, layout.jarH),
      sheen,
    );

    final streak = Path()
      ..moveTo(layout.jarX0 + layout.jarW * 0.13, layout.jarTop)
      ..lineTo(layout.jarX0 + layout.jarW * 0.23, layout.jarTop)
      ..lineTo(layout.jarX0 + layout.jarW * 0.01, layout.floorY)
      ..lineTo(layout.jarX0 - layout.jarW * 0.07, layout.floorY)
      ..close();
    canvas.drawPath(
      streak,
      Paint()..color = Colors.white.withValues(alpha: 0.1),
    );

    canvas.drawLine(
      Offset(layout.jarX0 + 10, layout.jarTop + 28),
      Offset(layout.jarX0 + 10, layout.floorY - 24),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.4,
    );
    canvas.restore();

    final outline = _jarPath(layout, close: false);
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = _ink,
    );
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.7),
    );

    const lip = 9.0;
    final lipPath = Path()
      ..moveTo(layout.jarX0 - lip, layout.jarTop)
      ..quadraticBezierTo(
        layout.jarX0 + 2,
        layout.jarTop - 5,
        layout.jarX0 + lip + 4,
        layout.jarTop,
      )
      ..moveTo(layout.jarX1 + lip, layout.jarTop)
      ..quadraticBezierTo(
        layout.jarX1 - 2,
        layout.jarTop - 5,
        layout.jarX1 - lip - 4,
        layout.jarTop,
      );
    canvas.drawPath(
      lipPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = _ink,
    );

    final sparkle = Paint()..color = Colors.white.withValues(alpha: 0.65);
    canvas.save();
    canvas.translate(layout.jarX0 + 13, layout.jarTop + 18);
    canvas.rotate(-0.3);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 4.4, height: 10),
      sparkle,
    );
    canvas.restore();
    canvas.save();
    canvas.translate(layout.jarX1 - 17, layout.jarTop + 46);
    canvas.rotate(0.2);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 2.8, height: 6.4),
      sparkle,
    );
    canvas.restore();

    if (layout.width - layout.jarX1 > 90) {
      _drawJarTag(canvas, layout);
    }
  }

  void _drawJarTag(Canvas canvas, LiquidLayout layout) {
    final x = layout.jarX1 + 8;
    final y = layout.jarTop + 54;
    final thread = Path()
      ..moveTo(layout.jarX1 - 2, layout.jarTop + 32)
      ..quadraticBezierTo(x + 2, y - 14, x + 15, y + 2);
    canvas.drawPath(
      thread,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _ink.withValues(alpha: 0.5),
    );

    canvas.save();
    canvas.translate(x + 24, y + 6);
    canvas.rotate(0.1);
    final tag = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-22, -14, 48, 30),
      const Radius.circular(5),
    );
    canvas.drawRRect(tag, Paint()..color = _cream);
    canvas.drawRRect(
      tag,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _ink,
    );
    _drawText(
      canvas,
      'NO. 6',
      const Offset(2, -3),
      fontSize: 8,
      color: _ink,
      weight: FontWeight.w800,
      centerVertically: true,
    );
    canvas.drawLine(
      const Offset(-13, 5),
      const Offset(15, 5),
      Paint()
        ..color = _ink.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
    _drawText(
      canvas,
      'LIQUID 2048+',
      const Offset(1, 11),
      fontSize: 6,
      color: _ink.withValues(alpha: 0.55),
      weight: FontWeight.w600,
      centerVertically: true,
    );
    canvas.restore();
  }

  void _drawBlobs(Canvas canvas) {
    final blobs = List<SoftBlob>.of(game.blobs)
      ..sort((a, b) => b.radius.compareTo(a.radius));
    for (final blob in blobs) {
      if (blob.cx < -blob.radius * 2 ||
          blob.cx > game.layout.width + blob.radius * 2) {
        continue;
      }
      _drawBlob(canvas, blob);
    }
  }

  void _drawBlob(Canvas canvas, SoftBlob blob) {
    final poly = blob.boundaryPoints();
    final points = _flowPoints(
      poly,
      blob.cx,
      blob.cy,
      blob.radius,
      blob.wobblePhase,
      blob.averageVx(),
      blob.averageVy(),
    );
    var scale = 1.0;
    if (blob.visualPop > 0) {
      final t = 1 - blob.visualPop / 0.34;
      scale = 1 + math.sin(t * math.pi) * 0.035;
    }
    final tilt = _clamp(blob.averageVx() / 2600, -0.12, 0.12);
    final healthy = blob.area / blob.targetArea > 0.45;
    _drawLiquid(
      canvas,
      points: points,
      cx: blob.cx,
      cy: blob.cy,
      radius: blob.radius,
      level: blob.level,
      seed: blob.faceSeed,
      blink: blob.blinkFor > 0,
      tilt: tilt,
      scale: scale,
      showFace: healthy,
      showNumber: healthy,
      shadow: true,
    );
  }

  List<Offset> _flowPoints(
    List<Vec2> poly,
    double cx,
    double cy,
    double radius,
    double phase,
    double vx,
    double vy,
  ) {
    final sizeFactor = _clamp(radius / 45.0, 0.9, 1.0);
    final ripple = _clamp(radius * 0.15, 2.4, 8.0) * sizeFactor;
    final speed = math.sqrt(vx * vx + vy * vy);
    final stretch = speed > 20 ? _clamp(speed / 8000, 0.0, 0.1) : 0.0;
    final ux = speed > 0.001 ? vx / speed : 0.0;
    final uy = speed > 0.001 ? vy / speed : 0.0;
    final points = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i];
      final dx = p.x - cx;
      final dy = p.y - cy;
      final d = math.sqrt(dx * dx + dy * dy);
      final safe = d == 0 ? 1.0 : d;
      final k = i / poly.length * math.pi * 2;
      final wave =
          (math.sin(game.time * 2.6 + k + phase) * 0.5 +
              math.sin(game.time * 1.4 - k * 1.6 + phase * 1.7) * 0.24) *
          ripple;
      final breath = math.sin(game.time * 1.55 + phase) * ripple * 0.25;
      final lobe =
          math.sin(k + game.time * 1.05 + phase) *
          math.sin(game.time * 0.9 + phase * 0.6) *
          ripple *
          0.4;
      var px = p.x + dx / safe * (wave + breath + lobe);
      var py = p.y + dy / safe * (wave + breath + lobe);
      if (stretch > 0) {
        final rx = px - cx;
        final ry = py - cy;
        final along = rx * ux + ry * uy;
        final perp = -rx * uy + ry * ux;
        final na = along * (1 + stretch);
        final np = perp * (1 - stretch * 0.65);
        px = cx + ux * na - uy * np;
        py = cy + uy * na + ux * np;
      }
      final shear = math.sin(game.time * 1.0 + phase) * radius * 0.045;
      px += shear * _clamp((cy - py) / radius, -1.0, 1.0);

      // 轮廓不许超过物理半径，保证画面零重叠。
      final ox = px - cx;
      final oy = py - cy;
      final od = math.sqrt(ox * ox + oy * oy);
      final cap = radius * 0.985;
      if (od > cap) {
        px = cx + ox / od * cap;
        py = cy + oy / od * cap;
      }
      points.add(Offset(px, py));
    }
    return points;
  }

  void _drawLiquid(
    Canvas canvas, {
    required List<Offset> points,
    required double cx,
    required double cy,
    required double radius,
    required int level,
    required double seed,
    bool blink = false,
    double tilt = 0,
    double scale = 1,
    bool showFace = true,
    bool showNumber = true,
    bool shadow = false,
    bool preview = false,
  }) {
    final fill = _LiquidPalette.fill(level);
    final edge = _LiquidPalette.edge(level);
    final shimmer = LiquidLevels.shimmerForLevel(level);
    final path = _smoothPath(_chaikin(points, 1));

    canvas.save();
    if (scale != 1) {
      canvas.translate(cx, cy);
      canvas.scale(scale, scale);
      canvas.translate(-cx, -cy);
    }

    if (shadow) {
      canvas.save();
      canvas.translate(0, math.max(2, radius * 0.09));
      canvas.drawPath(
        path,
        Paint()..color = _ink.withValues(alpha: preview ? 0.04 : 0.09),
      );
      canvas.restore();
    }

    final gradientColors = <Color>[];
    final stops = <double>[];
    if (shimmer) {
      for (var i = 0; i <= 4; i++) {
        gradientColors.add(
          _LiquidPalette.rainbow(level, i / 4).withValues(alpha: 0.96),
        );
        stops.add(i / 4);
      }
    } else {
      gradientColors.addAll([
        _LiquidPalette.lighten(fill, 0.38).withValues(alpha: 0.96),
        fill.withValues(alpha: 0.96),
        _LiquidPalette.darken(fill, 0.07).withValues(alpha: 0.96),
      ]);
      stops.addAll(const [0, 0.52, 1]);
    }
    final bodyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - radius, cy - radius * 0.95),
        Offset(cx + radius * 0.95, cy + radius),
        gradientColors,
        stops,
      );
    canvas.drawPath(path, bodyPaint);

    canvas.save();
    canvas.clipPath(path);

    final drift = math.sin(game.time * 0.65 + seed) * radius * 0.08;
    final glowRect = Rect.fromCircle(
      center: Offset(cx - radius * 0.36 + drift, cy - radius * 0.44),
      radius: radius * 1.15,
    );
    canvas.drawRect(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius * 1.4),
      Paint()
        ..shader = ui.Gradient.radial(
          glowRect.center,
          glowRect.width / 2,
          [
            Colors.white.withValues(alpha: 0.58),
            Colors.white.withValues(alpha: 0.15),
            Colors.white.withValues(alpha: 0),
          ],
          [0, 0.32, 1],
        ),
    );

    final causticX =
        cx + radius * (0.3 + math.sin(game.time * 0.9 + seed) * 0.11);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(causticX, cy - radius * 0.28),
        width: radius * 0.9,
        height: radius * 0.52,
      ),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(causticX, cy - radius * 0.28),
          radius * 0.45,
          [
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0),
          ],
        ),
    );

    final swirlAngle = game.time * 0.7 + seed;
    final swirlCenter = Offset(
      cx + math.cos(swirlAngle) * radius * 0.35,
      cy + math.sin(swirlAngle * 0.8) * radius * 0.3,
    );
    canvas.save();
    canvas.translate(swirlCenter.dx, swirlCenter.dy);
    canvas.rotate(game.time * 0.4 + seed);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 1.0,
        height: radius * 0.58,
      ),
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, radius * 0.55, [
          Colors.white.withValues(alpha: 0.34),
          Colors.white.withValues(alpha: 0),
        ]),
    );
    canvas.restore();

    final streakPhase = game.time * 0.8 + seed * 0.02;
    final streakRect = Rect.fromCenter(
      center: Offset(
        cx + math.sin(streakPhase) * radius * 0.04,
        cy - radius * 0.34,
      ),
      width: radius * 1.12,
      height: radius * 0.58,
    );
    canvas.drawArc(
      streakRect,
      math.pi * 1.04,
      math.pi * 0.42,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.8, radius * 0.032)
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.24),
    );

    void drawBand(double phase, Color color, double top, double amplitude) {
      final baseY = cy + radius * (top + math.sin(phase) * amplitude);
      final band = Path()..moveTo(cx - radius * 1.2, baseY);
      for (var i = 1; i <= 6; i++) {
        final x = cx - radius * 1.2 + radius * 2.4 * i / 6;
        band.lineTo(x, baseY + math.sin(phase + i * 0.85) * radius * 0.055);
      }
      band
        ..lineTo(cx + radius * 1.2, cy + radius * 1.3)
        ..lineTo(cx - radius * 1.2, cy + radius * 1.3)
        ..close();
      canvas.drawPath(band, Paint()..color = color);
    }

    drawBand(
      game.time * 1.15 + seed,
      Colors.white.withValues(alpha: 0.24),
      0.12,
      0.1,
    );
    drawBand(
      -game.time * 0.9 + seed * 1.4,
      _LiquidPalette.darken(fill, 0.12).withValues(alpha: 0.18),
      -0.02,
      0.08,
    );

    final depthColor = _LiquidPalette.darken(fill, 0.12);
    canvas.drawRect(
      Rect.fromLTWH(cx - radius, cy + radius * 0.15, radius * 2, radius * 0.85),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, cy + radius * 0.15),
          Offset(0, cy + radius),
          [depthColor.withValues(alpha: 0), depthColor.withValues(alpha: 0.16)],
        ),
    );

    final bottom = Paint()
      ..shader = ui.Gradient.linear(Offset(0, cy), Offset(0, cy + radius), [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: 0.12),
      ]);
    canvas.drawRect(Rect.fromLTWH(cx - radius, cy, radius * 2, radius), bottom);

    final meniscusY =
        cy - radius * (0.48 + math.sin(game.time * 1.0 + seed) * 0.04);
    final meniscus = Path()..moveTo(cx - radius * 0.85, meniscusY);
    for (var i = 1; i <= 4; i++) {
      final x = cx - radius * 0.85 + radius * 1.7 * i / 4;
      meniscus.lineTo(
        x,
        meniscusY + math.sin(game.time * 1.1 + i * 1.3 + seed) * radius * 0.035,
      );
    }
    canvas.drawPath(
      meniscus,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, radius * 0.03)
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.45),
    );

    final bubbleCount = 3 + (level >= 8 ? 1 : 0);
    for (var i = 0; i < bubbleCount; i++) {
      final travel =
          (game.time * (18 + i * 6) + seed * 9 + i * 27) % (radius * 1.25);
      final bx =
          cx + math.sin(seed + i * 2.1 + game.time * 0.55) * radius * 0.42;
      final by = cy + radius * 0.55 - travel;
      final br = radius * (0.05 + (i % 3) * 0.02);
      canvas.drawCircle(
        Offset(bx, by),
        br,
        Paint()..color = _cream.withValues(alpha: 0.42),
      );
      canvas.drawCircle(
        Offset(bx, by),
        br,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = edge.withValues(alpha: 0.24),
      );
      canvas.drawCircle(
        Offset(bx - br * 0.3, by - br * 0.3),
        br * 0.34,
        Paint()..color = Colors.white.withValues(alpha: 0.75),
      );
    }
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.4, radius * 0.08)
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.24),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _clamp(radius * 0.045, 1.2, 2.7)
        ..strokeJoin = StrokeJoin.round
        ..color = edge,
    );

    if (showFace && radius > 18) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(tilt);
      canvas.translate(-cx, -cy);
      _drawFace(canvas, cx, cy, radius, seed, blink);
      canvas.restore();
    }

    if (showNumber) {
      _drawNumber(
        canvas,
        cx,
        cy + (showFace && radius > 18 ? radius * 0.31 : 0),
        radius,
        LiquidLevels.valueForLevel(level),
        edge,
        showFace && radius > 18,
      );
    }

    if (level >= 7) {
      canvas.save();
      canvas.translate(cx + radius * 0.58, cy - radius * 0.58);
      canvas.rotate(-0.1);
      _drawStarFill(
        canvas,
        radius: math.max(2.5, radius * 0.09),
        fill: _cream.withValues(alpha: 0.94),
        stroke: edge,
      );
      if (level >= 10) {
        canvas.translate(-radius * 0.94, radius * 0.32);
        _drawStarFill(
          canvas,
          radius: math.max(1.8, radius * 0.055),
          fill: _cream.withValues(alpha: 0.8),
          stroke: edge,
        );
      }
      canvas.restore();
    }

    canvas.restore();
  }

  void _drawFace(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
    double seed,
    bool blink,
  ) {
    final eyeY = cy - radius * 0.28;
    final eyeX = radius * 0.22;
    final eyeR = math.max(1.8, radius * 0.075);
    final style = seed.floor() % 4;

    if (style != 2) {
      final blush = Paint()..color = _coralLt.withValues(alpha: 0.18);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx - radius * 0.38, cy - radius * 0.02),
          width: radius * 0.17,
          height: radius * 0.08,
        ),
        blush,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + radius * 0.38, cy - radius * 0.02),
          width: radius * 0.17,
          height: radius * 0.08,
        ),
        blush,
      );
    }

    final ink = Paint()..color = _ink;
    final glint = Paint()..color = Colors.white.withValues(alpha: 0.88);
    final lw = math.max(1.4, radius * 0.045);

    if (blink) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw
        ..strokeCap = StrokeCap.round
        ..color = _ink;
      for (final sign in [-1.0, 1.0]) {
        final x = cx + eyeX * sign;
        final path = Path()
          ..moveTo(x - eyeR * 1.3, eyeY)
          ..quadraticBezierTo(x, eyeY + eyeR * 1.15, x + eyeR * 1.3, eyeY);
        canvas.drawPath(path, stroke);
      }
      return;
    }

    if (style == 1) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw
        ..strokeCap = StrokeCap.round
        ..color = _ink;
      for (final sign in [-1.0, 1.0]) {
        final x = cx + eyeX * sign;
        final path = Path()
          ..moveTo(x - eyeR * 1.25, eyeY + eyeR * 0.2)
          ..quadraticBezierTo(
            x,
            eyeY - eyeR,
            x + eyeR * 1.25,
            eyeY + eyeR * 0.2,
          );
        canvas.drawPath(path, stroke);
      }
    } else if (style == 3) {
      canvas.drawCircle(Offset(cx - eyeX, eyeY), eyeR, ink);
      canvas.drawCircle(
        Offset(cx - eyeX + eyeR * 0.34, eyeY - eyeR * 0.34),
        eyeR * 0.3,
        glint,
      );
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw
        ..strokeCap = StrokeCap.round
        ..color = _ink;
      final x = cx + eyeX;
      canvas.drawPath(
        Path()
          ..moveTo(x - eyeR * 1.2, eyeY)
          ..quadraticBezierTo(x, eyeY + eyeR * 1.1, x + eyeR * 1.2, eyeY),
        stroke,
      );
    } else {
      for (final sign in [-1.0, 1.0]) {
        final center = Offset(cx + eyeX * sign, eyeY);
        canvas.drawCircle(center, eyeR * (style == 2 ? 1.35 : 1), ink);
        canvas.drawCircle(
          center + Offset(eyeR * 0.34, -eyeR * 0.34),
          eyeR * 0.32,
          glint,
        );
      }
    }

    final mouthPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lw
      ..strokeCap = StrokeCap.round
      ..color = _ink;
    if (style == 2) {
      canvas.drawCircle(
        Offset(cx, cy - radius * 0.02),
        radius * 0.055,
        Paint()..color = _ink,
      );
    } else {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(cx, cy - radius * 0.03),
          width: radius * 0.3,
          height: radius * 0.18,
        ),
        math.pi * 0.16,
        math.pi * 0.68,
        false,
        mouthPaint,
      );
    }
  }

  void _drawNumber(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
    int value,
    Color edge,
    bool belowFace,
  ) {
    final label = LiquidGame.formatBlobValue(value);
    var fontSize = radius * (belowFace ? 0.54 : 0.68);
    final maxWidth = radius * (belowFace ? 1.5 : 1.7);
    var painter = _textPainter(label, fontSize, _ink, FontWeight.w800);
    if (painter.width > maxWidth) {
      fontSize *= maxWidth / painter.width;
      painter = _textPainter(label, fontSize, _ink, FontWeight.w800);
    }
    final maxHeight = radius * (belowFace ? 0.46 : 0.62);
    if (painter.height > maxHeight) {
      fontSize *= maxHeight / painter.height;
      painter = _textPainter(label, fontSize, _ink, FontWeight.w800);
    }

    final center = Offset(cx, cy);
    if (belowFace) {
      final haloRect = Rect.fromCenter(
        center: center,
        width: radius * 1.42,
        height: radius * 0.58,
      );
      canvas.drawOval(
        haloRect,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            radius * 0.62,
            [
              _cream.withValues(alpha: 0.62),
              _cream.withValues(alpha: 0.18),
              _cream.withValues(alpha: 0),
            ],
            [0, 0.55, 1],
          ),
      );
    }

    final offset = Offset(
      center.dx - painter.width / 2,
      center.dy - painter.height / 2,
    );
    final stroke = _textPainter(
      label,
      fontSize,
      _cream.withValues(alpha: 0.8),
      FontWeight.w800,
      strokeWidth: math.max(2.5, fontSize * 0.2),
    );
    stroke.paint(canvas, offset);
    painter.paint(canvas, offset);
  }

  void _drawEffects(Canvas canvas) {
    for (final fx in game.effects) {
      final alpha = _clamp(fx.life / fx.maxLife, 0, 1);
      final color = fx.cream
          ? _cream
          : fx.kind == 0
          ? _LiquidPalette.edge(fx.level)
          : _LiquidPalette.fill(fx.level);
      if (fx.kind == 0) {
        canvas.drawCircle(
          Offset(fx.x, fx.y),
          math.max(0.1, fx.radius),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = fx.width
            ..color = color.withValues(alpha: alpha * 0.7),
        );
      } else {
        canvas.drawCircle(
          Offset(fx.x, fx.y),
          fx.size,
          Paint()..color = color.withValues(alpha: alpha),
        );
      }
    }
  }

  void _drawGhosts(Canvas canvas) {
    for (final ghost in game.ghosts) {
      final p = ghost.progress;
      final alpha = (1 - p).clamp(0.0, 1.0);
      final fill = _LiquidPalette.fill(ghost.level);
      final mid = Offset((ghost.ax + ghost.bx) / 2, (ghost.ay + ghost.by) / 2);
      final bridgeWidth =
          math.min(ghost.radiusA, ghost.radiusB) * 0.9 * (1 - p);
      if (bridgeWidth > 0.8) {
        canvas.drawLine(
          Offset(ghost.ax, ghost.ay),
          Offset(ghost.bx, ghost.by),
          Paint()
            ..color = fill.withValues(alpha: 0.34 * alpha)
            ..strokeWidth = bridgeWidth
            ..strokeCap = StrokeCap.round,
        );
      }
      for (var side = 0; side < 2; side++) {
        final points = side == 0 ? ghost.pointsA : ghost.pointsB;
        final origin = side == 0
            ? Offset(ghost.ax, ghost.ay)
            : Offset(ghost.bx, ghost.by);
        final target = Offset.lerp(origin, mid, p * 0.72)!;
        final scale = 1 - p * 0.35;
        final scaled = <Offset>[
          for (final point in points)
            Offset(
              target.dx + (point.x - origin.dx) * scale,
              target.dy + (point.y - origin.dy) * scale,
            ),
        ];
        canvas.drawPath(
          _smoothPath(scaled),
          Paint()..color = fill.withValues(alpha: 0.5 * alpha),
        );
      }
      canvas.drawCircle(
        mid,
        18 * (1 - p),
        Paint()
          ..shader = ui.Gradient.radial(mid, 18 * (1 - p), [
            fill.withValues(alpha: 0.55 * alpha),
            fill.withValues(alpha: 0),
          ]),
      );
    }
  }

  void _drawFloats(Canvas canvas) {
    for (final item in game.floats) {
      final t = 1 - item.life / item.maxLife;
      final alpha = _clamp(item.life / item.maxLife, 0, 1);
      final scale = t < 0.16 ? 0.6 + (t / 0.16) * 0.5 : 1 + (t - 0.16) * 0.14;
      final color = Color(item.color);
      final painter = _textPainter(
        item.text,
        item.size,
        color,
        FontWeight.w800,
      );
      final stroke = _textPainter(
        item.text,
        item.size,
        _cream.withValues(alpha: 0.78),
        FontWeight.w800,
        strokeWidth: 4,
      );
      canvas.save();
      canvas.translate(item.x, item.y);
      canvas.scale(scale, scale);
      final offset = Offset(-painter.width / 2, -painter.height / 2);
      canvas.saveLayer(
        Rect.fromCenter(
          center: Offset.zero,
          width: painter.width + 8,
          height: painter.height + 8,
        ),
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
      stroke.paint(canvas, offset);
      painter.paint(canvas, offset);
      canvas.restore();
      canvas.restore();
    }
  }

  void _drawOverflow(Canvas canvas, LiquidLayout layout) {
    if (game.overflowTime <= 0.04) return;
    final progress = _clamp(game.overflowTime / LiquidGame.overflowLimit, 0, 1);
    final pulse = 0.65 + math.sin(game.time * 8) * 0.2;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = _coral.withValues(alpha: 0.35 + progress * 0.45);
    final y = layout.dangerY;
    const dash = 5.0;
    for (var x = layout.jarX0 + 12; x < layout.jarX1 - 12; x += dash * 2) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, layout.jarX1 - 12), y),
        linePaint,
      );
    }

    _drawText(
      canvas,
      '满罐线',
      Offset(layout.jarX1 - 16, y - 5),
      fontSize: 9,
      color: _coral.withValues(alpha: pulse),
      weight: FontWeight.w700,
      align: TextAlign.right,
    );

    final remain = math.max(0, LiquidGame.overflowLimit - game.overflowTime);
    final text = remain > 0.1
        ? '罐子要满了 · ${remain.toStringAsFixed(1)}s'
        : '罐子要满了';
    final painter = _textPainter(text, 11, _coral, FontWeight.w700);
    final width = painter.width + 26;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(layout.cx - width / 2, y + 10, width, 26),
      const Radius.circular(13),
    );
    canvas.drawRRect(rect, Paint()..color = _cream.withValues(alpha: 0.95));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _coral.withValues(alpha: 0.55 + progress * 0.35),
    );
    painter.paint(
      canvas,
      Offset(layout.cx - painter.width / 2, y + 10 + (26 - painter.height) / 2),
    );

    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(layout.cx - width / 2 + 10, y + 40, width - 20, 3),
      const Radius.circular(2),
    );
    canvas.drawRRect(barRect, Paint()..color = _coral.withValues(alpha: 0.16));
    if (progress > 0) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          layout.cx - width / 2 + 10,
          y + 40,
          (width - 20) * progress,
          3,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(
        fillRect,
        Paint()..color = _coral.withValues(alpha: 0.78),
      );
    }
  }

  void _drawLauncher(Canvas canvas, LiquidLayout layout) {
    final level = game.queue.isEmpty ? 2 : game.queue.first;
    final radius = layout.levelRadius(level);
    final dirX = math.sin(game.aim);
    final dirY = math.cos(game.aim);
    final recoil = game.recoil * 6;
    final dist = layout.muzzle + radius * 0.12 - recoil;
    final mx = layout.launcherX + dirX * dist;
    final my = layout.launcherY + dirY * dist;

    _drawAimGuide(canvas, layout, mx, my, dirX, dirY, radius);

    final rail = Path()
      ..moveTo(layout.launcherX, math.max(12, layout.launcherY - 96))
      ..lineTo(layout.launcherX, layout.launcherY - 10);
    _drawDashedPath(canvas, rail, _ink.withValues(alpha: 0.28), 1.3, 2, 6);

    canvas.drawCircle(
      Offset(layout.launcherX, layout.launcherY - 6),
      6,
      Paint()..color = const Color(0xFFE8D6B9),
    );
    canvas.drawCircle(
      Offset(layout.launcherX, layout.launcherY - 6),
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = _ink,
    );

    canvas.save();
    canvas.translate(layout.launcherX, layout.launcherY);
    canvas.rotate(game.aim);
    final wobble = math.sin(game.time * 2.4) * 0.8;
    canvas.translate(0, -recoil * 0.4);

    final scoop = Path()
      ..moveTo(-17, -2)
      ..quadraticBezierTo(-15, 22, -10, 34 + wobble)
      ..lineTo(10, 34 + wobble)
      ..quadraticBezierTo(15, 22, 17, -2)
      ..quadraticBezierTo(0, -8, -17, -2)
      ..close();
    canvas.drawPath(scoop, Paint()..color = _cream);
    canvas.drawPath(
      scoop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = _ink,
    );

    final liquid = Path()
      ..moveTo(-12, 25 + wobble)
      ..lineTo(12, 25 + wobble)
      ..lineTo(8.5, 34 + wobble)
      ..lineTo(-8.5, 34 + wobble)
      ..close();
    canvas.drawPath(
      liquid,
      Paint()..color = _LiquidPalette.fill(level).withValues(alpha: 0.6),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-5, -4, 10, 8),
        const Radius.circular(3),
      ),
      Paint()..color = _ink,
    );
    final line = Path()
      ..moveTo(-10, 9)
      ..quadraticBezierTo(0, 13, 10, 9);
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _ink.withValues(alpha: 0.3),
    );
    canvas.restore();

    final pop = game.previewPop > 0
        ? 1 + math.sin((1 - game.previewPop / 0.24) * math.pi) * 0.09
        : 1.0;
    final previewScale = (game.charging ? 0.96 + game.power * 0.05 : 1.0) * pop;
    final previewPoints = _previewPoints(mx, my, radius, game.previewSeed);
    _drawLiquid(
      canvas,
      points: previewPoints,
      cx: mx,
      cy: my,
      radius: radius,
      level: level,
      seed: game.previewSeed,
      tilt: -game.aim * 0.05,
      scale: previewScale,
      showFace: true,
      shadow: false,
      preview: true,
    );

    if (game.charging || game.power > 0.02) {
      _drawChargeRing(canvas, mx, my, radius);
    }
  }

  List<Offset> _previewPoints(
    double cx,
    double cy,
    double radius,
    double seed,
  ) {
    const n = 18;
    final points = <Offset>[];
    final phase = seed * 0.7;
    for (var i = 0; i < n; i++) {
      final angle = i / n * math.pi * 2;
      final wobbleScale = _clamp(radius / 45.0, 0.85, 1.0);
      final wobble =
          1 +
          math.sin(game.time * 2.2 + i * 0.9 + phase) * 0.05 * wobbleScale +
          math.cos(game.time * 1.7 + i * 1.4 + phase) * 0.032 * wobbleScale;
      points.add(
        Offset(
          cx + math.cos(angle) * radius * wobble,
          cy + math.sin(angle) * radius * wobble,
        ),
      );
    }
    return points;
  }

  void _drawChargeRing(Canvas canvas, double mx, double my, double radius) {
    final ringR = radius + 7;
    const start = -math.pi / 2;
    final center = Offset(mx, my);
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _ink.withValues(alpha: 0.12),
    );
    final color = game.power >= 1 ? _coral : _coralLt;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringR),
      start,
      math.pi * 2 * math.max(0.04, game.power),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    if (game.power >= 1) {
      final pulse = 1 + math.sin(game.time * 9) * 0.06;
      canvas.drawCircle(
        center,
        ringR * pulse + 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _coralLt.withValues(alpha: 0.35),
      );
    }
    final angle = start + math.pi * 2 * game.power;
    final dot = Offset(
      mx + math.cos(angle) * ringR,
      my + math.sin(angle) * ringR,
    );
    canvas.drawCircle(dot, 3.2, Paint()..color = _cream);
    canvas.drawCircle(
      dot,
      3.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _coral,
    );
  }

  void _drawAimGuide(
    Canvas canvas,
    LiquidLayout layout,
    double fromX,
    double fromY,
    double dirX,
    double dirY,
    double radius,
  ) {
    final power = game.charging ? game.power : 0.55;
    final speed = layout.launchSpeed(power);
    var vx = dirX * speed;
    var vy = dirY * speed;
    final gravity = game.world.gravity;
    const dt = 1 / 40;
    var x = fromX;
    var y = fromY;
    final points = <Offset>[];
    final maxTime = game.charging ? 1.1 : 0.65;

    for (var t = 0.0; t < maxTime; t += dt) {
      vy += gravity * dt;
      x += vx * dt;
      y += vy * dt;
      if (x < layout.bounds.left + radius * 0.35 ||
          x > layout.bounds.right - radius * 0.35) {
        break;
      }
      if (y > layout.bounds.floor - radius * 0.25) break;
      points.add(Offset(x, y));
    }
    if (points.isEmpty) return;

    final alpha = game.charging ? 0.45 : 0.2;
    final step = math.max(1, points.length ~/ 11);
    for (var i = 0; i < points.length; i += step) {
      final t = i / points.length;
      canvas.drawCircle(
        points[i],
        _lerp(2.4, 1.2, t),
        Paint()..color = _ink.withValues(alpha: alpha * (1 - t * 0.8)),
      );
    }
    final last = points.last;
    _drawDashedCircle(
      canvas,
      last,
      math.max(5, radius * 0.28),
      _ink.withValues(alpha: alpha * 0.7),
      1.2,
    );
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Color color,
    double width,
    double dash,
    double gap,
  ) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, next),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..color = color,
        );
        distance = next + gap;
      }
    }
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double width,
  ) {
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    _drawDashedPath(canvas, path, color, width, 3, 4);
  }

  @override
  bool shouldRepaint(covariant _LiquidStagePainter oldDelegate) =>
      oldDelegate.game != game;
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({required this.game, super.repaint});

  final LiquidGame game;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 2;
    final radius = math.min(size.width, size.height) * 0.39;
    final points = <Offset>[];
    for (var i = 0; i < 18; i++) {
      final angle = i / 18 * math.pi * 2;
      final wobble =
          1 +
          math.sin(game.time * 2.1 + i * 0.85) * 0.042 +
          math.cos(game.time * 1.4 + i * 1.2) * 0.028;
      points.add(
        Offset(
          cx + math.cos(angle) * radius * wobble,
          cy + math.sin(angle) * radius * wobble,
        ),
      );
    }

    final fill = _LiquidPalette.fill(4);
    final edge = _LiquidPalette.edge(4);
    final path = _smoothPath(_chaikin(points, 1));
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius * 1.2);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [
            _LiquidPalette.lighten(fill, 0.38),
            fill,
            _LiquidPalette.darken(fill, 0.06),
          ],
          const [0, 0.52, 1],
        ),
    );
    canvas.save();
    canvas.clipPath(path);
    canvas.drawCircle(
      Offset(cx - radius * 0.3, cy - radius * 0.38),
      radius * 0.55,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx - radius * 0.3, cy - radius * 0.38),
          radius * 0.6,
          [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0),
          ],
        ),
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = edge,
    );

    final eyeY = cy - radius * 0.12;
    final eyeR = radius * 0.075;
    for (final sign in [-1.0, 1.0]) {
      final center = Offset(cx + radius * 0.22 * sign, eyeY);
      canvas.drawCircle(center, eyeR, Paint()..color = _ink);
      canvas.drawCircle(
        center + Offset(eyeR * 0.3, -eyeR * 0.3),
        eyeR * 0.3,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy + radius * 0.03),
        width: radius * 0.3,
        height: radius * 0.2,
      ),
      math.pi * 0.16,
      math.pi * 0.68,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, radius * 0.045)
        ..strokeCap = StrokeCap.round
        ..color = _ink,
    );
  }

  @override
  bool shouldRepaint(covariant _MascotPainter oldDelegate) =>
      oldDelegate.game != game;
}

/* ============================================================
   绘制工具
   ============================================================ */

/// Chaikin 切角：把多边形的尖角磨圆，且结果永远在原多边形内部，
/// 配合“轮廓不超过物理半径”的钳制，保证视觉上不会互相侵入。
List<Offset> _chaikin(List<Offset> pts, int iterations) {
  if (pts.length < 3) return pts;
  var current = pts;
  for (var it = 0; it < iterations; it++) {
    final next = <Offset>[];
    for (var i = 0; i < current.length; i++) {
      final a = current[i];
      final b = current[(i + 1) % current.length];
      next.add(Offset(a.dx * 0.75 + b.dx * 0.25, a.dy * 0.75 + b.dy * 0.25));
      next.add(Offset(a.dx * 0.25 + b.dx * 0.75, a.dy * 0.25 + b.dy * 0.75));
    }
    current = next;
  }
  return current;
}

Path _smoothPath(List<Offset> points, {double tension = 0.65}) {
  final path = Path();
  if (points.length < 3) return path;
  final n = points.length;
  path.moveTo(points[0].dx, points[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = points[(i - 1 + n) % n];
    final p1 = points[i];
    final p2 = points[(i + 1) % n];
    final p3 = points[(i + 2) % n];
    final cp1x = p1.dx + ((p2.dx - p0.dx) / 6) * tension;
    final cp1y = p1.dy + ((p2.dy - p0.dy) / 6) * tension;
    final cp2x = p2.dx - ((p3.dx - p1.dx) / 6) * tension;
    final cp2y = p2.dy - ((p3.dy - p1.dy) / 6) * tension;
    path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
  }
  path.close();
  return path;
}

Path _starPath(Offset center, double radius) {
  final inner = radius * 0.4;
  final path = Path()
    ..moveTo(center.dx, center.dy - radius)
    ..lineTo(center.dx + inner * 0.62, center.dy - inner * 0.62)
    ..lineTo(center.dx + radius, center.dy)
    ..lineTo(center.dx + inner * 0.62, center.dy + inner * 0.62)
    ..lineTo(center.dx, center.dy + radius)
    ..lineTo(center.dx - inner * 0.62, center.dy + inner * 0.62)
    ..lineTo(center.dx - radius, center.dy)
    ..lineTo(center.dx - inner * 0.62, center.dy - inner * 0.62)
    ..close();
  return path;
}

void _drawStarFill(
  Canvas canvas, {
  required double radius,
  required Color fill,
  required Color stroke,
}) {
  final path = _starPath(Offset.zero, radius);
  canvas.drawPath(path, Paint()..color = fill);
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = stroke,
  );
}

final Map<String, TextPainter> _textCache = {};

TextPainter _textPainter(
  String text,
  double fontSize,
  Color color,
  FontWeight weight, {
  double? strokeWidth,
}) {
  final rounded = (fontSize * 10).round() / 10;
  final colorValue = color.toARGB32();
  final stroke = strokeWidth != null;
  final key =
      '$text|$rounded|$colorValue|${weight.value}|${strokeWidth?.toStringAsFixed(1)}';
  final cached = _textCache[key];
  if (cached != null) return cached;
  if (_textCache.length > 900) _textCache.clear();

  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: AppFonts.noto,
        fontFamilyFallback: AppFonts.bodyFallback,
        fontSize: rounded,
        height: 1,
        fontWeight: weight,
        color: stroke ? null : color,
        foreground: stroke
            ? (Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth
                ..strokeJoin = StrokeJoin.round
                ..color = color)
            : null,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  _textCache[key] = painter;
  return painter;
}

void _drawText(
  Canvas canvas,
  String text,
  Offset position, {
  required double fontSize,
  required Color color,
  FontWeight weight = FontWeight.w600,
  TextAlign align = TextAlign.center,
  bool centerVertically = false,
}) {
  final painter = _textPainter(text, fontSize, color, weight);
  var dx = position.dx;
  if (align == TextAlign.center) {
    dx -= painter.width / 2;
  } else if (align == TextAlign.right) {
    dx -= painter.width;
  }
  final dy = centerVertically ? position.dy - painter.height / 2 : position.dy;
  painter.paint(canvas, Offset(dx, dy));
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
