import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/cards.dart';
import '../data/fortunes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/lunar.dart';
import '../widgets/browser_effects.dart';
import '../widgets/paper.dart';
import 'ai_chat.dart';
import 'card_draw.dart';

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
    with TickerProviderStateMixin {
  static const _cardRadius = BorderRadius.all(Radius.circular(24));
  static const _flipDuration = Duration(milliseconds: 900);
  static const _flipCurve = Cubic(.22, 1.12, .32, 1);

  final GlobalKey _cardKey = GlobalKey();
  Offset? _downAt;
  int? idx;
  bool loading = true;

  late final AnimationController _flip;
  late final AnimationController _entrance;
  late final AnimationController _aura;
  CardFace? _card;
  Timer? _introTimer;
  bool _frontUp = false;
  bool _flipBusy = false;
  bool _transferBusy = false;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(vsync: this, duration: _flipDuration, value: 0);
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    )..forward();
    _aura = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..forward();
    _load();
    _loadCard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _introTimer = Timer(const Duration(seconds: 1), _flipToFront);
    });
  }

  Future<void> _loadCard() async {
    final card = await AppState.instance.ensureTodayCard();
    if (!mounted) return;
    setState(() => _card = card);
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _flip.dispose();
    _entrance.dispose();
    _aura.dispose();
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

  Future<void> _openDeedChat() async {
    final state = AppState.instance;
    await showAiChat(
      context,
      goodDeed: true,
      onGoodDeed: () => unawaited(state.grantFortuneTransfer()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _useTransfer() async {
    if (_transferBusy) return;
    setState(() => _transferBusy = true);
    HapticFeedback.mediumImpact();
    if (_frontUp) await _flipToBack();
    final next = await AppState.instance.useFortuneTransfer();
    if (!mounted) return;
    if (next != null) {
      final card = await AppState.instance.redrawTodayCard();
      if (!mounted) return;
      setState(() {
        idx = next;
        if (card != null) _card = card;
      });
      // 留一点时间让用户看到卡背，再翻开新签。
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;
      _flipToFront();
      HapticFeedback.lightImpact();
    } else {
      _flipToFront();
      AppToast.show(context, '今天已经转运过了');
    }
    if (mounted) setState(() => _transferBusy = false);
  }

  Widget _transferBox(BuildContext context, AppState state) {
    final c = context.c;
    final used = state.fortuneTransferUsed;
    final ready = state.fortuneTransferReady;
    final label = used
        ? '今日转运已用 · 明天再来'
        : ready
        ? '转运 · 再抽一签'
        : '找 CiCi 分享好事 · 换一签';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.dark ? const Color(0x14F2A43C) : const Color(0xFFFFF4E3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.accent.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(
                strokeSvg(AppIcons.sparkle, width: 2),
                size: 14,
                color: c.accentInk,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '抽到下签了？还有一次转运机会',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: 11,
                    weight: FontWeight.w700,
                    color: c.accentInk,
                  ),
                ),
              ),
              if (ready) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '待使用',
                    style: context.body(
                      size: 9,
                      weight: FontWeight.w800,
                      color: const Color(0xFF2E2C22),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            used
                ? '今天的好运已经换过一次，剩下的交给明天。'
                : ready
                ? '好事已经分享给 CiCi，这一签可以重新抽。'
                : '跟 CiCi 说说今天做的一件好事，就能换一签。',
            style: context.body(size: 10.5, color: c.inkSoft, height: 1.45),
          ),
          const SizedBox(height: 8),
          Pressable(
            onTap: used || _transferBusy
                ? null
                : (ready ? _useTransfer : _openDeedChat),
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: used
                    ? c.surface2
                    : (ready ? c.accent : Colors.transparent),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: used
                      ? c.line
                      : (ready ? c.accent : c.accent.withAlpha(160)),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_transferBusy)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: ready ? const Color(0xFF2E2C22) : c.accentInk,
                        ),
                      )
                    else
                      AppIcon(
                        strokeSvg(
                          ready ? AppIcons.refresh : AppIcons.sparkle,
                          width: 2,
                        ),
                        size: 13,
                        color: used
                            ? c.inkSoft
                            : (ready ? const Color(0xFF2E2C22) : c.accentInk),
                      ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: context.body(
                        size: 11,
                        weight: FontWeight.w700,
                        color: used
                            ? c.inkSoft
                            : (ready ? const Color(0xFF2E2C22) : c.accentInk),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = context.app;
    final today = DateTime.now();
    final fortune = kFortunes[(idx ?? 0) % kFortunes.length];
    final isBad = fortune.lv == '下签' || fortune.lv == '下下签';
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
            child: AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) {
                final t = Curves.easeOutBack.transform(
                  _entrance.value.clamp(0.0, 1.0),
                );
                final fade = Curves.easeOut.transform(
                  (_entrance.value * 1.5).clamp(0.0, 1.0),
                );
                return Opacity(
                  opacity: fade,
                  child: Transform.translate(
                    offset: Offset(0, 92 * (1 - t)),
                    child: Transform.rotate(
                      angle: -.05 * (1 - t),
                      child: Transform.scale(
                        scale: .84 + .16 * t,
                        child: child,
                      ),
                    ),
                  ),
                );
              },
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: -40,
                    right: -40,
                    top: -40,
                    bottom: -40,
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _aura,
                        builder: (context, _) => CustomPaint(
                          painter: _FortuneAuraPainter(
                            t: _aura.value,
                            color: c.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
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
                                              Flexible(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.bottomLeft,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 5,
                                                        ),
                                                    child: Text(
                                                      '${today.year}年${today.month}月 · ${weekdayChinese(today)}',
                                                      maxLines: 1,
                                                      style: context.body(
                                                        size: 12,
                                                        color: c.ink2,
                                                      ),
                                                    ),
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
                                if (!loading && isBad && festId == null) ...[
                                  const SizedBox(height: 12),
                                  _transferBox(context, state),
                                ],
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
                                  _card == null
                                      ? '轻点卡片 · 翻看卡背'
                                      : '轻点卡片 · 翻看今日卡面 · ${_card!.categoryName}',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBack(BuildContext context) {
    final card = _card;
    return ClipRRect(
      borderRadius: _cardRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (card != null)
            CardFaceImage(
              card: card,
              fit: BoxFit.cover,
              cacheWidth: 1200,
              borderRadius: BorderRadius.zero,
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3A2B1E), Color(0xFF221811)],
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
          if (card != null)
            Positioned(
              right: 14,
              bottom: 13,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x73000000),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: const Color(0x2EFFF6E4)),
                ),
                child: Text(
                  '${card.categoryName} · ${card.label}',
                  style: context.body(
                    size: 9.5,
                    weight: FontWeight.w600,
                    color: const Color(0xD9FFF6E4),
                    letterSpacing: .8,
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

/// 打卡卡面出场时的暖色光晕：缓慢旋转的射线 + 呼吸光斑。
class _FortuneAuraPainter extends CustomPainter {
  _FortuneAuraPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .5);
    final radius = math.min(size.width, size.height) * .62;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withAlpha(34),
          color.withAlpha(12),
          color.withAlpha(0),
        ],
        stops: const [0, .55, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, glow);

    final ray = Paint()..strokeWidth = 1.2;
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi * 2 / 24 + t * math.pi * 2 / 24;
      final pulse = .5 + .5 * math.sin(t * math.pi * 2 + i * .9);
      ray.color = color.withAlpha((8 + 14 * pulse).round());
      final inner = radius * (.46 + .02 * pulse);
      final outer = radius * (.66 + .06 * pulse);
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * inner,
        center + Offset(math.cos(angle), math.sin(angle)) * outer,
        ray,
      );
    }
    for (var i = 0; i < 16; i++) {
      final phase = (t + i / 16) % 1;
      final angle = i * 2.399 + phase * math.pi * 2;
      final dist = radius * (.5 + .18 * phase);
      final p = center + Offset(math.cos(angle), math.sin(angle)) * dist;
      final fade = math.sin(phase * math.pi);
      canvas.drawCircle(
        p,
        1.2 + 1.6 * fade,
        Paint()..color = color.withAlpha((16 + 70 * fade).round()),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FortuneAuraPainter old) =>
      old.t != t || old.color != color;
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
