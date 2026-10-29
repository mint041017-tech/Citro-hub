import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_keys.dart';
import '../data/cards.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
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
    final image = Image.network(
      card.url,
      fit: fit,
      cacheWidth: cacheWidth?.round(),
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          child: child,
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _CardImagePlaceholder();
      },
      errorBuilder: (_, __, ___) => const _CardImagePlaceholder(),
    );
    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}

class _CardImagePlaceholder extends StatelessWidget {
  const _CardImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A2F24), Color(0xFF241D17)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_awesome_outlined,
          size: 18,
          color: Colors.white.withAlpha(90),
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.accent, c.accent2],
                ),
                boxShadow: CitroColors.shadows.note(c),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.sparkle, width: 2),
                  size: 26,
                  color: const Color(0xFF2E2C22),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('完成 7 局游戏', style: ctx.heading(size: 21)),
            const SizedBox(height: 6),
            Text(
              '获得一次卡面抽取机会，现在翻开一张吗？\n当前待抽 $credits 次',
              textAlign: TextAlign.center,
              style: ctx.body(size: 12, color: c.inkSoft, height: 1.6),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '稍后再抽',
                    outlined: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
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
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '收下卡面',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
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
    );
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
    _flip.animateTo(1, curve: Curves.easeInOutCubic).then((_) {
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
    Future<void>.delayed(const Duration(milliseconds: 160), () {
      if (ctx.mounted) unawaited(showCardDrawOverlay(ctx));
    });
  }

  @override
  Widget build(BuildContext context) {
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
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.12),
                  radius: 1.05,
                  colors: [
                    Color(0xFF5B4226),
                    Color(0xFF2C241C),
                    Color(0xFF16120F),
                  ],
                  stops: [0, .52, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _glow,
              builder: (context, _) => CustomPaint(
                painter: _HaloPainter(
                  t: _glow.value,
                  color: const Color(0xFFF2A43C),
                ),
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
                            color: Colors.black.withAlpha(80),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withAlpha(40)),
                          ),
                          child: Center(
                            child: AppIcon(
                              strokeSvg(AppIcons.close, width: 2),
                              size: 17,
                              color: Colors.white.withAlpha(220),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                  Text(
                    _revealed ? '卡面已收下' : '卡面抽取',
                    style: context.display(
                      size: 13,
                      weight: FontWeight.w700,
                      color: Colors.white.withAlpha(190),
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: Listenable.merge([_intro, _flip]),
                    builder: (context, _) {
                      final e = Curves.easeOutBack.transform(
                        _intro.value.clamp(0.0, 1.0),
                      );
                      final angle = _flip.value * math.pi;
                      final front = angle > math.pi / 2;
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
                              child: SizedBox(
                                width: cardW,
                                height: cardH,
                                child: front
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
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  AnimatedOpacity(
                    opacity: _revealed ? 1 : 0,
                    duration: const Duration(milliseconds: 360),
                    child: Column(
                      children: [
                        Text(
                          widget.card.categoryName,
                          style: context.body(
                            size: 11,
                            weight: FontWeight.w700,
                            color: const Color(0xFFF2A43C),
                            letterSpacing: 2.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.wasOwned ? '这张之前已经收集过' : '已收入卡面收藏',
                          style: context.body(
                            size: 12,
                            color: Colors.white.withAlpha(185),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (AppState.instance.cardCredits > 0) ...[
                              Pressable(
                                onTap: _again,
                                child: Container(
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(24),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.white.withAlpha(70),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '再抽一次 (${AppState.instance.cardCredits})',
                                      style: context.body(
                                        size: 12,
                                        weight: FontWeight.w600,
                                        color: Colors.white.withAlpha(230),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Pressable(
                              onTap: () => Navigator.of(context).maybePop(),
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFF2C46B), Color(0xFFE79A3C)],
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x66E79A3C),
                                      blurRadius: 18,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    '收下卡面',
                                    style: context.body(
                                      size: 12.5,
                                      weight: FontWeight.w800,
                                      color: const Color(0xFF2E2C22),
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
                    const SizedBox(height: 12),
                    Text(
                      '轻点卡背翻开',
                      style: context.body(
                        size: 11,
                        color: Colors.white.withAlpha(150),
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _burst,
                builder: (context, _) {
                  if (!_revealed || _burst.value == 0) {
                    return const SizedBox.shrink();
                  }
                  return CustomPaint(
                    painter: _BurstPainter(
                      t: _burst.value,
                      origin: Offset(size.width / 2, size.height * .46),
                    ),
                  );
                },
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4C3721), Color(0xFF241A12)],
        ),
        border: Border.all(color: const Color(0x66F2C46B), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0xCC000000),
            blurRadius: 50,
            offset: Offset(0, 26),
          ),
          BoxShadow(
            color: Color(0x66F2A43C),
            blurRadius: 40,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: CustomPaint(
                painter: _BackPatternPainter(
                  color: const Color(0xFFF2C46B).withAlpha(26),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0x4DF2C46B)),
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
                    border: Border.all(color: const Color(0x66F2C46B)),
                    gradient: const RadialGradient(
                      colors: [Color(0x33F2C46B), Color(0x00F2C46B)],
                    ),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/images/logo.webp',
                      width: 54,
                      cacheWidth: 108,
                      opacity: const AlwaysStoppedAnimation(.82),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'CITRO',
                  style: context.display(
                    size: 20,
                    weight: FontWeight.w700,
                    color: const Color(0xFFF2C46B).withAlpha(220),
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CARD COLLECTION',
                  style: context.body(
                    size: 7.5,
                    weight: FontWeight.w700,
                    color: const Color(0xFFF2C46B).withAlpha(140),
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
                size: 9,
                weight: FontWeight.w700,
                color: const Color(0xFFF2C46B).withAlpha(150),
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xA6F2C46B), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0xCC000000),
            blurRadius: 52,
            offset: Offset(0, 28),
          ),
          BoxShadow(
            color: Color(0x80F2A43C),
            blurRadius: 46,
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CardFaceImage(
              card: card,
              cacheWidth: 900,
              borderRadius: BorderRadius.zero,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x00000000), Color(0x99000000)],
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
                      style: context.display(
                        size: 17,
                        weight: FontWeight.w700,
                        color: Colors.white.withAlpha(235),
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(90),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.white.withAlpha(60)),
                    ),
                    child: Text(
                      '#${card.label}',
                      style: context.body(
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: Colors.white.withAlpha(210),
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
  _HaloPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .46);
    final radius = math.min(size.width, size.height) * .46;
    final paint = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      paint
        ..color = color.withAlpha(((1 - p) * 30).round())
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, radius * (.42 + .55 * p), paint);
    }
    final ray = Paint()
      ..color = color.withAlpha(22)
      ..strokeWidth = 1.4;
    for (var i = 0; i < 18; i++) {
      final angle = i * math.pi * 2 / 18 + t * math.pi / 9;
      final inner = radius * (.5 + .02 * math.sin(t * math.pi * 2 + i));
      final outer = radius * (.74 + .04 * math.sin(t * math.pi * 2 + i * 1.7));
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * inner,
        center + Offset(math.cos(angle), math.sin(angle)) * outer,
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HaloPainter old) =>
      old.t != t || old.color != color;
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
  _BurstPainter({required this.t, required this.origin});

  final double t;
  final Offset origin;

  static const _colors = [
    Color(0xFFF2C46B),
    Color(0xFFF2A43C),
    Color(0xFFE0796A),
    Color(0xFFC9D3B2),
    Color(0xFFFFF4DC),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
    final fade = (1 - t).clamp(0.0, 1.0);
    if (fade <= 0) return;
    for (var i = 0; i < 46; i++) {
      final angle = i * 2.399963 + (i % 5) * .13;
      final speed = 120 + (i * 37 % 190);
      final dist = speed * eased;
      final gravity = 150 * eased * eased;
      final p = origin +
          Offset(math.cos(angle), math.sin(angle) * .82) * dist +
          Offset(0, gravity);
      final paint = Paint()
        ..color = _colors[i % _colors.length].withAlpha((235 * fade).round());
      final radius = (i % 3 == 0 ? 3.2 : 2.0) * (0.6 + .4 * fade);
      if (i % 4 == 0) {
        canvas.drawRect(
          Rect.fromCenter(center: p, width: radius * 3, height: radius * 1.3),
          paint,
        );
      } else {
        canvas.drawCircle(p, radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) =>
      old.t != t || old.origin != origin;
}
