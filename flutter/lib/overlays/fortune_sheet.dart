import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fortunes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/lunar.dart';
import '../widgets/browser_effects.dart';
import '../widgets/paper.dart';

Future<void> showFortuneOverlay(BuildContext context) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(ctx).maybePop(),
            child: CitroBackdropBlur(
              sigma: 14,
              child: Container(color: const Color(0x8A23211C)),
            ),
          ),
        ),
        FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(
              begin: .9,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
            child: const Material(
              type: MaterialType.transparency,
              child: _FortuneDialog(),
            ),
          ),
        ),
      ],
    ),
  );
}

class _FortuneDialog extends StatefulWidget {
  const _FortuneDialog();
  @override
  State<_FortuneDialog> createState() => _FortuneDialogState();
}

class _FortuneDialogState extends State<_FortuneDialog>
    with SingleTickerProviderStateMixin {
  static const _cardRadius = BorderRadius.all(Radius.circular(24));
  static const _flipDuration = Duration(milliseconds: 900);
  static const _flipCurve = Cubic(.22, 1.12, .32, 1);

  final GlobalKey _cardKey = GlobalKey();
  Offset? _downAt;
  int? idx;
  bool loading = true;

  late final AnimationController _flip;
  late final int _backIndex;
  Timer? _introTimer;
  bool _frontUp = false;
  bool _flipBusy = false;

  String get _backAsset =>
      'assets/card/card_${(_backIndex + 1).toString().padLeft(2, '0')}.webp';

  /// 一年内 12 张卡背打乱后按天轮换：每天稳定随机、相邻日不重复。
  static int _backIndexFor(DateTime d) {
    final order = List<int>.generate(12, (i) => i);
    var seed = (d.year * 92821 + 17) & 0x7fffffff;
    int next() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed;
    }

    for (var i = order.length - 1; i > 0; i--) {
      final j = next() % (i + 1);
      final tmp = order[i];
      order[i] = order[j];
      order[j] = tmp;
    }
    final day = d.difference(DateTime(d.year, 1, 1)).inDays;
    return order[day % order.length];
  }

  @override
  void initState() {
    super.initState();
    _backIndex = _backIndexFor(DateTime.now());
    _flip = AnimationController(vsync: this, duration: _flipDuration, value: 0);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        precacheImage(AssetImage(_backAsset), context).catchError((_) {}),
      );
      _introTimer = Timer(const Duration(seconds: 1), _flipToFront);
    });
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _flip.dispose();
    super.dispose();
  }

  void _flipToFront() {
    _introTimer?.cancel();
    if (!mounted || _flipBusy || _frontUp) return;
    _flipBusy = true;
    HapticFeedback.lightImpact();
    _flip.animateTo(1, duration: _flipDuration, curve: _flipCurve).then((_) {
      if (!mounted) return;
      setState(() {
        _frontUp = true;
        _flipBusy = false;
      });
    });
  }

  Future<void> _flipToBack() async {
    if (!mounted || _flipBusy || !_frontUp) return;
    _flipBusy = true;
    HapticFeedback.selectionClick();
    await _flip.animateTo(0, duration: _flipDuration, curve: _flipCurve);
    if (!mounted) return;
    setState(() {
      _frontUp = false;
      _flipBusy = false;
    });
  }

  void _onCardTap() {
    if (!_frontUp) {
      if (!_flipBusy) _flipToFront();
      return;
    }
    unawaited(_flipToBack());
  }

  void _onPointerUp(PointerUpEvent event) {
    final down = _downAt;
    _downAt = null;
    if (down == null) return;
    if ((event.position - down).distance > 14) return;
    final box = _cardKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.contains(event.position)) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.maybePop();
  }

  Future<void> _load() async {
    final state = AppState.instance;
    final existing = state.todayFortuneIdx;
    if (existing != null) {
      setState(() {
        idx = existing;
        loading = false;
      });
      return;
    }
    try {
      final i = await state.drawFortuneIdx();
      if (mounted) {
        setState(() {
          idx = i;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          idx = 0;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = context.app;
    final today = DateTime.now();
    final fortune = kFortunes[(idx ?? 0) % kFortunes.length];
    final festId = festivalIdOf(today);
    final term = termToday(today);
    final at = termAt(today);
    final lu = lunarOf(today);
    final nt = nextTerm(today);
    final catIndex = _catIndex('${today.year}-${today.month}-${today.day}');
    final tags = <Widget>[];
    if (festId != null) {
      tags.add(_tag(context, festivalName(festId), type: 'fest'));
    }
    if (term != null) {
      tags.add(_tag(context, '$term · 今日交节', type: 'term'));
    } else if (at != null) {
      final md = kTermDays[at.year]!.substring(at.index * 4, at.index * 4 + 4);
      final start = DateTime(
        at.year,
        int.parse(md.substring(0, 2)),
        int.parse(md.substring(2, 4)),
      );
      final days = dayDiff(start, today) + 1;
      if (festId == null)
        tags.add(_tag(context, '${at.name} · 第 $days 天', type: 'term'));
    }
    if (lu != null) tags.add(_tag(context, lu.name, type: 'lunar'));

    final back = _buildBack(context);
    final frontGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: c.dark
          ? [const Color(0xFF2C2720), const Color(0xFF201D18)]
          : [const Color(0xFFF5F0E6), const Color(0xFFE8DCC8)],
    );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _downAt = e.position,
      onPointerUp: _onPointerUp,
      child: SizedBox.expand(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              16 + MediaQuery.paddingOf(context).top,
              20,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Container(
              key: _cardKey,
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                borderRadius: _cardRadius,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x246E5030),
                    blurRadius: 60,
                    offset: Offset(0, 24),
                  ),
                  BoxShadow(
                    color: Color(0x1A6E5030),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onCardTap,
                    child: AnimatedBuilder(
                      animation: _flip,
                      child: ClipRRect(
                        borderRadius: _cardRadius,
                        child: DecoratedBox(
                          decoration: BoxDecoration(gradient: frontGradient),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 30, 20, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            festId != null
                                                ? '${festivalName(festId)}特别签'
                                                : '今日打卡',
                                            style: context.display(
                                              size: 24,
                                              weight: FontWeight.w700,
                                              color: c.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                '${today.day}',
                                                style: context.display(
                                                  size: 52,
                                                  weight: FontWeight.w400,
                                                  color: c.accentInk,
                                                  height: 1,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 5,
                                                ),
                                                child: Text(
                                                  '${today.year}年${today.month}月 · ${weekdayChinese(today)}',
                                                  style: context.body(
                                                    size: 12,
                                                    color: c.ink2,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 5,
                                            children: tags,
                                          ),
                                          if (nt != null) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              '距 ${_termName(nt)} ${dayDiff(today, nt)} 天',
                                              style: context.body(
                                                size: 10.5,
                                                color: c.inkSoft,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Transform.rotate(
                                      angle: 3 * math.pi / 180,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          top: 22,
                                          right: 3,
                                        ),
                                        child: Image.asset(
                                          'assets/images/cats/${23757 + catIndex}.webp',
                                          width: 96,
                                          height: 96,
                                          fit: BoxFit.contain,
                                          cacheWidth: 288,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                AnimatedOpacity(
                                  opacity: loading ? 0 : 1,
                                  duration: const Duration(milliseconds: 380),
                                  child: AnimatedScale(
                                    scale: loading ? .96 : 1,
                                    duration: const Duration(milliseconds: 380),
                                    curve: Curves.easeOut,
                                    child: Container(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        16,
                                        16,
                                        14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c.dark
                                            ? const Color(0x0DFFFFFF)
                                            : const Color(0x0D23211C),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: c.dark
                                              ? const Color(0x14FFF6E4)
                                              : const Color(0x1423211C),
                                        ),
                                      ),
                                      child: loading
                                          ? const SizedBox(
                                              height: 160,
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            )
                                          : Column(
                                              children: [
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Expanded(
                                                      flex: 4,
                                                      child: FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: ShaderMask(
                                                          shaderCallback: (rect) =>
                                                              LinearGradient(
                                                                colors: [
                                                                  c.accent,
                                                                  c.accent2,
                                                                ],
                                                                begin: Alignment
                                                                    .topLeft,
                                                                end: Alignment
                                                                    .bottomRight,
                                                              ).createShader(
                                                                rect,
                                                              ),
                                                          child: Text(
                                                            fortune.lv,
                                                            textAlign: TextAlign
                                                                .center,
                                                            maxLines: 1,
                                                            style: context
                                                                .display(
                                                                  size: 46,
                                                                  weight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: Colors
                                                                      .white,
                                                                  height: 1.05,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      flex: 5,
                                                      child: Column(
                                                        children: [
                                                          Text(
                                                            fortune.name,
                                                            style: context
                                                                .display(
                                                                  size: 21,
                                                                  weight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: c.ink,
                                                                  letterSpacing:
                                                                      2.2,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 8,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              gradient: LinearGradient(
                                                                begin: Alignment
                                                                    .topCenter,
                                                                end: Alignment
                                                                    .bottomCenter,
                                                                colors: [
                                                                  const Color(
                                                                    0x1AB8924A,
                                                                  ),
                                                                  const Color(
                                                                    0x0AB8924A,
                                                                  ),
                                                                ],
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                              border: Border.all(
                                                                color:
                                                                    const Color(
                                                                      0x38B8924A,
                                                                    ),
                                                              ),
                                                            ),
                                                            child: Column(
                                                              children: [
                                                                for (final line
                                                                    in fortune
                                                                        .poem)
                                                                  Text(
                                                                    line,
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    style: context.display(
                                                                      size:
                                                                          13.5,
                                                                      weight: FontWeight
                                                                          .w600,
                                                                      color:
                                                                          c.ink,
                                                                      height:
                                                                          1.7,
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  fortune.desc,
                                                  textAlign: TextAlign.center,
                                                  style: context.body(
                                                    size: 12.5,
                                                    color: c.ink2,
                                                    height: 1.55,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 10,
                                                              vertical: 8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: c.dark
                                                              ? const Color(
                                                                  0x1AC9D3B2,
                                                                )
                                                              : const Color(
                                                                  0xFFEAF2E3,
                                                                ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                          border: Border.all(
                                                            color: c.mintLine,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        4,
                                                                    vertical: 1,
                                                                  ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                    color: c
                                                                        .mintSoft,
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          4,
                                                                        ),
                                                                  ),
                                                              child: Text(
                                                                '宜',
                                                                style: context.body(
                                                                  size: 10,
                                                                  weight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color:
                                                                      c.mintInk,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                fortune.yi,
                                                                style: context
                                                                    .body(
                                                                      size:
                                                                          11.5,
                                                                      color: c
                                                                          .mintInk,
                                                                      height:
                                                                          1.35,
                                                                    ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 10,
                                                              vertical: 8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: c.dark
                                                              ? const Color(
                                                                  0x14E0796A,
                                                                )
                                                              : const Color(
                                                                  0xFFFBE9E4,
                                                                ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                          border: Border.all(
                                                            color: c.dark
                                                                ? const Color(
                                                                    0x33E0796A,
                                                                  )
                                                                : const Color(
                                                                    0xFFF0D2C8,
                                                                  ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        4,
                                                                    vertical: 1,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: c.dark
                                                                    ? const Color(
                                                                        0x33E0796A,
                                                                      )
                                                                    : const Color(
                                                                        0xFFF5DCD4,
                                                                      ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      4,
                                                                    ),
                                                              ),
                                                              child: Text(
                                                                '忌',
                                                                style: context.body(
                                                                  size: 10,
                                                                  weight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color:
                                                                      c.stamp,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                fortune.ji,
                                                                style: context
                                                                    .body(
                                                                      size:
                                                                          11.5,
                                                                      color: c
                                                                          .stamp,
                                                                      height:
                                                                          1.35,
                                                                    ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      state.checkinStreak > 0
                                          ? '连续打卡 ${state.checkinStreak} 天 · 明日再来'
                                          : '明天再来抽一签',
                                      style: context.body(
                                        size: 11,
                                        color: c.inkSoft,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '轻点卡片 · 翻看卡背',
                                  textAlign: TextAlign.center,
                                  style: context.body(
                                    size: 10,
                                    color: c.inkSoft.withAlpha(170),
                                    letterSpacing: .3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      builder: (context, child) {
                        final t = _flip.value;
                        final angle = t * math.pi;
                        final showFront = angle > math.pi / 2;
                        final pulse = math.sin(math.pi * t.clamp(0.0, 1.0));
                        final scale = 1 - .035 * pulse;
                        return Transform.translate(
                          offset: Offset(0, -6 * pulse),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, .0014)
                              ..rotateY(angle)
                              ..scaleByDouble(scale, scale, 1, 1),
                            child: Stack(
                              children: [
                                Opacity(
                                  opacity: showFront ? 1 : 0,
                                  child: IgnorePointer(
                                    ignoring: !showFront,
                                    child: Transform(
                                      alignment: Alignment.center,
                                      transform: showFront
                                          ? Matrix4.rotationY(math.pi)
                                          : Matrix4.identity(),
                                      child: child,
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Opacity(
                                    opacity: showFront ? 0 : 1,
                                    child: IgnorePointer(
                                      ignoring: showFront,
                                      child: back,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: _cardRadius,
                        child: _FlipShine(controller: _flip),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Pressable(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c.surface.withAlpha(235),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withAlpha(80)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x38000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.close, width: 2),
                            size: 14,
                            color: c.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBack(BuildContext context) {
    return ClipRRect(
      borderRadius: _cardRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _backAsset,
            fit: BoxFit.cover,
            alignment: const Alignment(0, .3),
            cacheWidth: 1200,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3A2B1E), Color(0xFF221811)],
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x4D140F0A),
                  Color(0x00140F0A),
                  Color(0x00140F0A),
                  Color(0x66140F0A),
                ],
                stops: [0, .2, .72, 1],
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: const Color(0x73FFF4DC), width: 1),
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 13,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0x59000000),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Text(
                '轻点翻开',
                style: context.body(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: const Color(0xE6FFF6E4),
                  letterSpacing: 1.4,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, String text, {required String type}) {
    final c = context.c;
    final Color bg;
    final Color fg;
    final Color border;
    switch (type) {
      case 'fest':
        bg = c.dark ? c.hl : const Color(0x21F2A43C);
        fg = c.accentInk;
        border = const Color(0x38F2A43C);
        break;
      case 'term':
        bg = c.mintSoft;
        fg = c.mintInk;
        border = c.mintLine;
        break;
      default:
        bg = c.dark ? c.hl : const Color(0x0D23211C);
        fg = c.ink2;
        border = c.line;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(text, style: context.body(size: 10.5, color: fg)),
    );
  }

  String _termName(DateTime d) {
    final t = termAt(d);
    if (t == null) return '';
    final md = kTermDays[t.year]!.substring(t.index * 4, t.index * 4 + 4);
    return md ==
            '${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'
        ? t.name
        : t.name;
  }

  int _catIndex(String key) {
    var h = 2166136261;
    for (final code in key.codeUnits) {
      h ^= code;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return h % 9;
  }
}

/// 翻面时扫过卡面的一道暖光；只在动画期间显形。
class _FlipShine extends StatelessWidget {
  final AnimationController controller;

  const _FlipShine({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isAnimating) return const SizedBox.shrink();
        final t = controller.value.clamp(0.0, 1.0);
        final opacity = math.sin(math.pi * t) * .9;
        if (opacity <= .01) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return Opacity(
              opacity: opacity,
              child: Stack(
                children: [
                  Positioned(
                    top: -h * .45,
                    bottom: -h * .45,
                    left: (-1.1 + 2.2 * t) * w,
                    width: w * .42,
                    child: Transform.rotate(
                      angle: -.3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white.withAlpha(0),
                              Colors.white.withAlpha(125),
                              Colors.white.withAlpha(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
