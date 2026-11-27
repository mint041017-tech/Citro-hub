import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_keys.dart';
import '../data/cards.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

/// 卡面网络图：带淡入与失败占位，列表里用小尺寸解码。
class CardFaceImage extends StatelessWidget {
  const CardFaceImage({
    super.key,
    required this.card,
    this.cacheWidth,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final CardFace card;
  final double? cacheWidth;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    // 卡面原图已打包进包内（assets/card/），直接读本地，不再走网络。
    final ImageFrameBuilder frameBuilder =
        (BuildContext context, Widget child, int? frame, bool sync) {
      if (sync) return child;
      return AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: child,
      );
    };
    final errorBuilder = (_, __, ___) => const _CardImagePlaceholder();
    final Image image;
    if (card.isAsset) {
      image = Image.asset(
        card.asset,
        fit: fit,
        cacheWidth: cacheWidth?.round(),
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        frameBuilder: frameBuilder,
        errorBuilder: errorBuilder,
      );
    } else {
      image = Image.network(
        card.url,
        fit: fit,
        cacheWidth: cacheWidth?.round(),
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        frameBuilder: frameBuilder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const _CardImagePlaceholder();
        },
        errorBuilder: errorBuilder,
      );
    }
    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}

class _CardImagePlaceholder extends StatelessWidget {
  const _CardImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface2),
      child: Center(
        child: AppIcon(
          strokeSvg(AppIcons.sparkle, width: 2),
          size: 20,
          color: c.inkSoft,
        ),
      ),
    );
  }
}

/// 完成 7 局游戏后的轻量提示：立即抽或稍后从收藏库再抽。
Future<void> showCardDrawPrompt(
  BuildContext context, {
  required int credits,
}) async {
  final draw = await showCitroDialog<bool>(
    context,
    builder: (ctx) {
      final c = ctx.c;
      return PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.accentLt,
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.sparkle, width: 2),
                  size: 26,
                  color: c.accentInk,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            Text('完成 7 局游戏', style: ctx.heading(size: 20)),
            const SizedBox(height: AppSpacing.x1),
            Text(
              '获得一次卡面抽取机会，现在翻开一张吗？\n当前待抽 $credits 次',
              textAlign: TextAlign.center,
              style: ctx.body(
                size: CitroType.caption,
                color: c.inkSoft,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '稍后再抽',
                    outlined: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: AppSpacing.x1),
                Expanded(
                  child: AccentButton(
                    text: '立即抽卡',
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  if (draw == true && context.mounted) {
    await showCardDrawOverlay(context);
  }
}

/// 抽卡全屏动画；不传 [preset] 时消耗一次抽卡机会。
Future<void> showCardDrawOverlay(
  BuildContext context, {
  CardFace? preset,
}) async {
  final state = AppState.instance;
  CardFace? card = preset;
  var wasOwned = false;
  if (card == null) {
    final before = state.ownedCards;
    card = await state.drawCardFromCredit();
    if (card != null) wasOwned = before.contains(card.id);
  } else {
    wasOwned = state.ownedCards.contains(card.id);
  }
  if (!context.mounted) return;
  if (card == null) {
    AppToast.show(context, '还没有抽卡机会');
    return;
  }
  await showCitroGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '收下卡面',
    barrierColor: Colors.transparent,
    transitionDuration: CitroMotion.modal,
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) => FadeTransition(
      opacity: CurvedAnimation(
        parent: anim,
        curve: CitroMotion.easeOut,
        reverseCurve: CitroMotion.exit,
      ),
      child: _CardDrawDialog(card: card!, wasOwned: wasOwned),
    ),
  );
}

class _CardDrawDialog extends StatefulWidget {
  const _CardDrawDialog({required this.card, required this.wasOwned});

  final CardFace card;
  final bool wasOwned;

  @override
  State<_CardDrawDialog> createState() => _CardDrawDialogState();
}

class _CardDrawDialogState extends State<_CardDrawDialog>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _flip;
  late final AnimationController _glow;
  late final AnimationController _burst;
  bool _revealed = false;
  bool _flipping = false;
  // 翻面过中点后一次性切正/背面，避免每帧重建卡面子树。
  bool _showFront = false;
  Timer? _autoFlip;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..forward();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    )..addListener(_handleFlip);
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    HapticFeedback.mediumImpact();
    _autoFlip = Timer(const Duration(milliseconds: 1700), _reveal);
  }

  void _handleFlip() {
    final front = _flip.value > .5;
    if (front != _showFront && mounted) {
      setState(() => _showFront = front);
    }
  }

  @override
  void dispose() {
    _autoFlip?.cancel();
    _intro.dispose();
    _flip.dispose();
    _glow.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _reveal() {
    _autoFlip?.cancel();
    if (!mounted || _flipping || _revealed) return;
    _flipping = true;
    HapticFeedback.selectionClick();
    _flip.animateTo(1, curve: CitroMotion.easeInOut).then((_) {
      if (!mounted) return;
      setState(() {
        _revealed = true;
        _flipping = false;
      });
      HapticFeedback.heavyImpact();
      _burst.forward(from: 0);
    });
  }

  void _again() {
    final ctx = citroNavigatorKey.currentContext;
    Navigator.of(context).pop();
    if (ctx == null) return;
    // 等这一层退场结束再开下一层，别让两场淡入淡出叠在一起。
    Future<void>.delayed(CitroMotion.modalReverse, () {
      if (ctx.mounted) unawaited(showCardDrawOverlay(ctx));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = MediaQuery.sizeOf(context);
    final aspect = widget.card.aspect.clamp(.6, .85);
    final cardW = math.min(
      360.0,
      math.min(size.width * .78, math.max(190.0, (size.height - 310) * aspect)),
    );
    final cardH = cardW / aspect;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 抽卡是全屏沉浸时刻：浅色下用暖白聚光，深色下用近黑聚光，
          // 让卡面成为唯一视觉焦点（nosh 的「舞台」手法）。
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.12),
                  radius: 1.05,
                  colors: [
                    c.dark ? c.bg2 : c.surface,
                    c.dark ? c.bg : c.bg2,
                    c.dark ? c.bg : c.bg2,
                  ],
                  stops: const [0, .52, 1],
                ),
              ),
            ),
          ),
          // 光晕是静态图层，只旋转 + 轻微呼吸：不再每帧重绘整块屏幕，
          // 翻转时 GPU 只需重新合成一张已栅格化的贴图。
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _glow,
              builder: (context, child) {
                final center = Offset(size.width / 2, size.height * .46);
                final pulse = 1 + .04 * math.sin(_glow.value * math.pi * 2);
                return Transform.rotate(
                  origin: center,
                  angle: _glow.value * math.pi * 2,
                  child: Transform.scale(
                    origin: center,
                    scale: pulse,
                    child: child,
                  ),
                );
              },
              child: RepaintBoundary(
                child: CustomPaint(painter: _HaloPainter(color: c.accent)),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                      child: Pressable(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c.surface.withValues(alpha: c.surface.a * (180) / 255),
                            shape: BoxShape.circle,
                            border: Border.all(color: c.line),
                          ),
                          child: Center(
                            child: AppIcon(
                              strokeSvg(AppIcons.close, width: 2),
                              size: 18,
                              color: c.ink2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                  Text(
                    _revealed ? '卡面已收下' : '卡面抽取',
                    style: context.body(
                      size: CitroType.micro,
                      weight: CitroType.medium,
                      color: c.inkSoft,
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  // 卡面本体作为 child 传进去：动画每帧只更新外层 Transform，
                  // 不重建卡面（900px 图解码、背面图案、大模糊阴影），
                  // 翻转时才不会掉帧。正/背面只在过中点时切一次。
                  AnimatedBuilder(
                    animation: Listenable.merge([_intro, _flip]),
                    builder: (context, child) {
                      final e = CitroMotion.easeOut.transform(
                        _intro.value.clamp(0.0, 1.0),
                      );
                      final angle = _flip.value * math.pi;
                      return Transform.translate(
                        offset: Offset(0, 70 * (1 - e)),
                        child: Transform.scale(
                          scale: .78 + .22 * e,
                          child: Transform.rotate(
                            angle: -.075 * (1 - e),
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, .0015)
                                ..rotateY(angle),
                              child: child,
                            ),
                          ),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: cardW,
                      height: cardH,
                      child: _showFront
                          ? Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.rotationY(math.pi),
                              child: _CardFront(card: widget.card),
                            )
                          : GestureDetector(
                              onTap: _reveal,
                              child: _CardBack(card: widget.card),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  AnimatedOpacity(
                    opacity: _revealed ? 1 : 0,
                    duration: const Duration(milliseconds: 360),
                    child: Column(
                      children: [
                        Text(
                          widget.card.categoryName,
                          style: context.body(
                            size: CitroType.micro,
                            weight: CitroType.medium,
                            color: c.accentInk,
                            letterSpacing: 2.4,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          widget.wasOwned ? '这张之前已经收集过' : '已收入卡面收藏',
                          style: context.body(
                            size: CitroType.caption,
                            color: c.ink2,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (AppState.instance.cardCredits > 0) ...[
                              Pressable(
                                onTap: _again,
                                child: Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.surface,
                                    borderRadius: BorderRadius.circular(
                                      CitroColors.radii.chip,
                                    ),
                                    border: Border.all(color: c.line2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '再抽一次 (${AppState.instance.cardCredits})',
                                      style: context.body(
                                        size: CitroType.caption,
                                        weight: CitroType.medium,
                                        color: c.ink,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.x1),
                            ],
                            Pressable(
                              onTap: () => Navigator.of(context).maybePop(),
                              child: Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                decoration: BoxDecoration(
                                  color: c.accent,
                                  borderRadius: BorderRadius.circular(
                                    CitroColors.radii.chip,
                                  ),
                                  boxShadow: CitroColors.shadows.float(c),
                                ),
                                child: Center(
                                  child: Text(
                                    '收下卡面',
                                    style: context.body(
                                      size: CitroType.meta,
                                      weight: CitroType.medium,
                                      color: c.onAccent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!_revealed) ...[
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      '轻点卡背翻开',
                      style: context.body(
                        size: CitroType.small,
                        color: c.inkSoft,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
          if (_revealed)
            Positioned.fill(
              child: IgnorePointer(
                // painter 自带 repaint: _burst，动画每帧只重绘这一层；
                // 粒子参数在构造时算好，避免每帧新建 Paint/Color。
                child: CustomPaint(
                  painter: _BurstPainter(
                    animation: _burst,
                    origin: Offset(size.width / 2, size.height * .46),
                    colors: [
                      c.accent,
                      c.mint,
                      c.stamp,
                      c.accentLt,
                      c.surface,
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({required this.card});

  final CardFace card;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
        color: c.surface2,
        border: Border.all(color: c.accentLt, width: 1.2),
        boxShadow: CitroColors.shadows.card(c),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CitroColors.radii.card),
              child: CustomPaint(
                painter: _BackPatternPainter(
                  color: c.accent.withAlpha(28),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                border: Border.all(color: c.accentLt.withAlpha(120)),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.accentLt),
                    gradient: RadialGradient(
                      colors: [
                        c.accentLt.withAlpha(90),
                        c.accentLt.withAlpha(0),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/images/logo.webp',
                      width: 54,
                      cacheWidth: 108,
                      opacity: const AlwaysStoppedAnimation(.9),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  'CITRO',
                  style: context.heading(
                    size: CitroType.titleLg,
                    color: c.ink,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CARD COLLECTION',
                  style: context.body(
                    size: CitroType.micro,
                    weight: CitroType.medium,
                    color: c.inkSoft,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: 14,
            child: Text(
              card.categoryName,
              style: context.body(
                size: CitroType.micro,
                weight: CitroType.medium,
                color: c.inkSoft,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({required this.card});

  final CardFace card;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
        border: Border.all(color: c.accentLt, width: 1.4),
        boxShadow: CitroColors.shadows.card(c),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CitroColors.radii.card - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CardFaceImage(
              card: card,
              cacheWidth: 900,
              borderRadius: BorderRadius.zero,
            ),
            // 照片上的暗角只用于保证底部文字可读，属图片叠加层，不走 token。
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0x99000000),
                  ],
                  stops: [0, .62, 1],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      card.categoryName,
                      style: context.heading(
                        size: CitroType.bodyLg,
                        color: Colors.white,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(90),
                      borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                      border: Border.all(color: Colors.white.withAlpha(60)),
                    ),
                    child: Text(
                      '#${card.label}',
                      style: context.body(
                        size: CitroType.micro,
                        weight: CitroType.medium,
                        color: Colors.white.withAlpha(230),
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .46);
    final radius = math.min(size.width, size.height) * .46;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 3; i++) {
      ring.color = color.withAlpha(26 - i * 7);
      canvas.drawCircle(center, radius * (.42 + .16 * i), ring);
    }
    final ray = Paint()
      ..color = color.withAlpha(22)
      ..strokeWidth = 1.4;
    for (var i = 0; i < 18; i++) {
      final angle = i * math.pi * 2 / 18;
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * radius * .5,
        center + Offset(math.cos(angle), math.sin(angle)) * radius * .74,
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HaloPainter old) => old.color != color;
}

class _BackPatternPainter extends CustomPainter {
  _BackPatternPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const gap = 22.0;
    for (var x = -size.height; x < size.width + size.height; x += gap) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(x + size.height, 0),
        Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackPatternPainter old) => old.color != color;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.animation,
    required this.origin,
    required this.colors,
  })  : _angles = List<double>.generate(
          _count,
          (i) => i * 2.399963 + (i % 5) * .13,
        ),
        _speeds = List<double>.generate(
          _count,
          (i) => 120 + (i * 37 % 190),
        ),
        _radii = List<double>.generate(
          _count,
          (i) => i % 3 == 0 ? 3.2 : 2.0,
        ),
        super(repaint: animation);

  static const int _count = 46;

  final Animation<double> animation;
  final Offset origin;
  final List<Color> colors;
  final List<double> _angles;
  final List<double> _speeds;
  final List<double> _radii;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0) return;
    final eased = CitroMotion.easeOut.transform(t.clamp(0.0, 1.0));
    final fade = (1 - t).clamp(0.0, 1.0);
    if (fade <= 0) return;
    // 一个 Paint 复用到底，避免每帧给 46 个粒子各建一个。
    final paint = Paint();
    for (var i = 0; i < _count; i++) {
      final dist = _speeds[i] * eased;
      final gravity = 150 * eased * eased;
      final p = origin +
          Offset(math.cos(_angles[i]), math.sin(_angles[i]) * .82) * dist +
          Offset(0, gravity);
      paint.color = colors[i % colors.length].withAlpha((235 * fade).round());
      final radius = _radii[i] * (0.6 + .4 * fade);
      if (i % 4 == 0) {
        canvas.drawRect(
          Rect.fromCenter(
            center: p,
            width: radius * 3,
            height: radius * 1.3,
          ),
          paint,
        );
      } else {
        canvas.drawCircle(p, radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) =>
      old.origin != origin || old.colors != colors;
}
