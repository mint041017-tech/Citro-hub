import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/cards.dart';
import '../data/fortunes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
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
    transitionDuration: CitroMotion.sheet,
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
          opacity: CurvedAnimation(
            parent: anim,
            curve: CitroMotion.easeOut,
            reverseCurve: CitroMotion.exit,
          ),
          child: ScaleTransition(
            scale: Tween(
              begin: .92,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim, curve: CitroMotion.settle)),
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
          ? [const Color(0xFF312A21), const Color(0xFF1A1611)]
          : [const Color(0xFFFFFBF2), const Color(0xFFF1E3CD)],
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
                                decoration: BoxDecoration(
                                  gradient: frontGradient,
                                ),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: -34,
                                      top: -46,
                                      child: IgnorePointer(
                                        child: Container(
                                          width: 190,
                                          height: 190,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: RadialGradient(
                                              colors: [
                                                c.accent.withAlpha(
                                                  c.dark ? 26 : 34,
                                                ),
                                                c.accent.withAlpha(0),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: Padding(
                                          padding: const EdgeInsets.all(9),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              border: Border.all(
                                                color: c.accent.withAlpha(
                                                  c.dark ? 42 : 70,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        22,
                                        30,
                                        22,
                                        18,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
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
                                              Text(
                                                festId != null
                                                    ? '${festivalName(festId)}特别签'
                                                    : '今日打卡',
                                                style: context.heading(
                                                  size: 14,
                                                  color: c.accentInk,
                                                  letterSpacing: .8,
                                                ),
                                              ),
                                              const SizedBox(width: 9),
                                              Expanded(
                                                child: Container(
                                                  height: 1,
                                                  color: c.accent.withAlpha(58),
                                                ),
                                              ),
                                              const SizedBox(width: 9),
                                              Text(
                                                'DAILY DRAW',
                                                style: context.body(
                                                  size: 7.5,
                                                  weight: FontWeight.w700,
                                                  color: c.inkSoft,
                                                  letterSpacing: 1.7,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .end,
                                                      children: [
                                                        Text(
                                                          '${today.day}',
                                                          style: context
                                                              .display(
                                                                size: 56,
                                                                color:
                                                                    c.accentInk,
                                                                height: .95,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                bottom: 7,
                                                              ),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Text(
                                                                '${today.year} / ${today.month.toString().padLeft(2, '0')}',
                                                                style: context.body(
                                                                  size: 10.5,
                                                                  color:
                                                                      c.inkSoft,
                                                                  letterSpacing:
                                                                      1.1,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 2,
                                                              ),
                                                              Text(
                                                                weekdayChinese(
                                                                  today,
                                                                ),
                                                                style: context
                                                                    .heading(
                                                                      size: 15,
                                                                      color: c
                                                                          .ink2,
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 9),
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
                                                          size: 10,
                                                          color: c.inkSoft,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              _catSticker(context, catIndex),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          AnimatedOpacity(
                                            opacity: loading ? 0 : 1,
                                            duration: const Duration(
                                              milliseconds: 380,
                                            ),
                                            child: AnimatedScale(
                                              scale: loading ? .97 : 1,
                                              duration: const Duration(
                                                milliseconds: 380,
                                              ),
                                              curve: Curves.easeOut,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      14,
                                                      15,
                                                      14,
                                                      15,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: c.surface.withAlpha(
                                                    c.dark ? 26 : 148,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  border: Border.all(
                                                    color: c.accent.withAlpha(
                                                      c.dark ? 40 : 58,
                                                    ),
                                                  ),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Color(0x0F5A4A2C),
                                                      blurRadius: 12,
                                                      offset: Offset(0, 5),
                                                    ),
                                                  ],
                                                ),
                                                child: loading
                                                    ? const SizedBox(
                                                        height: 168,
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
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              _fortuneSeal(
                                                                context,
                                                                fortune.lv,
                                                              ),
                                                              const SizedBox(
                                                                width: 14,
                                                              ),
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .stretch,
                                                                  children: [
                                                                    Text(
                                                                      fortune
                                                                          .name,
                                                                      textAlign:
                                                                          TextAlign
                                                                              .center,
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                      style: context.display(
                                                                        size:
                                                                            23,
                                                                        weight:
                                                                            FontWeight.w700,
                                                                        color: c
                                                                            .ink,
                                                                        letterSpacing:
                                                                            3.4,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      height: 6,
                                                                    ),
                                                                    Container(
                                                                      padding: const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            12,
                                                                        vertical:
                                                                            9,
                                                                      ),
                                                                      decoration: BoxDecoration(
                                                                        color: c.accent.withAlpha(
                                                                          c.dark
                                                                              ? 14
                                                                              : 18,
                                                                        ),
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              12,
                                                                            ),
                                                                        border: Border.all(
                                                                          color: c
                                                                              .accent
                                                                              .withAlpha(
                                                                                48,
                                                                              ),
                                                                        ),
                                                                      ),
                                                                      child: Column(
                                                                        children: [
                                                                          for (final line
                                                                              in fortune.poem)
                                                                            Text(
                                                                              line,
                                                                              textAlign: TextAlign.center,
                                                                              style: context.display(
                                                                                size: 13.5,
                                                                                weight: FontWeight.w600,
                                                                                color: c.ink,
                                                                                height: 1.75,
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
                                                          const SizedBox(
                                                            height: 12,
                                                          ),
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child: Container(
                                                                  height: 1,
                                                                  color: c.line2
                                                                      .withAlpha(
                                                                        120,
                                                                      ),
                                                                ),
                                                              ),
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          8,
                                                                    ),
                                                                child: Text(
                                                                  '✦',
                                                                  style: context
                                                                      .body(
                                                                        size: 9,
                                                                        color: c
                                                                            .accentInk,
                                                                      ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child: Container(
                                                                  height: 1,
                                                                  color: c.line2
                                                                      .withAlpha(
                                                                        120,
                                                                      ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                            height: 10,
                                                          ),
                                                          Text(
                                                            fortune.desc,
                                                            textAlign: TextAlign
                                                                .center,
                                                            style: context.body(
                                                              size: 12.5,
                                                              color: c.ink2,
                                                              height: 1.65,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 12,
                                                          ),
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child: _yiJi(
                                                                  context,
                                                                  '宜',
                                                                  fortune.yi,
                                                                  good: true,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Expanded(
                                                                child: _yiJi(
                                                                  context,
                                                                  '忌',
                                                                  fortune.ji,
                                                                  good: false,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                            ),
                                          ),
                                          if (!loading &&
                                              isBad &&
                                              festId == null) ...[
                                            const SizedBox(height: 12),
                                            _transferBox(context, state),
                                          ],
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.fromLTRB(
                                              11,
                                              8,
                                              11,
                                              8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.dark
                                                  ? const Color(0x0FFFFFFF)
                                                  : const Color(0x0A5A4A2C),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: c.line2.withAlpha(90),
                                              ),
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
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    state.checkinStreak > 0
                                                        ? '连续打卡 ${state.checkinStreak} 天 · 明日再来'
                                                        : '明天再来抽一签',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: context.body(
                                                      size: 10.5,
                                                      color: c.inkSoft,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    _card == null
                                                        ? '轻点翻看卡面'
                                                        : '轻点翻看 · ${_card!.categoryName}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.right,
                                                    style: context.body(
                                                      size: 9.5,
                                                      color: c.inkSoft
                                                          .withAlpha(170),
                                                      letterSpacing: .2,
                                                    ),
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
                              ),
                            ),
                            builder: (context, child) {
                              final t = _flip.value;
                              final angle = t * math.pi;
                              final showFront = angle > math.pi / 2;
                              final pulse = math.sin(
                                math.pi * t.clamp(0.0, 1.0),
                              );
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
                                border: Border.all(
                                  color: Colors.white.withAlpha(80),
                                ),
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

  Widget _catSticker(BuildContext context, int catIndex) {
    final c = context.c;
    final size = MediaQuery.sizeOf(context).width < 380 ? 78.0 : 92.0;
    return Transform.rotate(
      angle: 2.6 * math.pi / 180,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.noteY,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.accent.withAlpha(86)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A3A2812),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/images/cats/${23757 + catIndex}.webp',
            fit: BoxFit.contain,
            cacheWidth: 288,
          ),
        ),
      ),
    );
  }

  Widget _fortuneSeal(BuildContext context, String level) {
    final c = context.c;
    final stamp = c.stamp;
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [stamp, Color.lerp(stamp, Colors.black, .16)!],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: stamp.withAlpha(58),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0x66FFF6E4)),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '今日签',
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontFamilyFallback: AppFonts.bodyFallback,
                      fontSize: 8.5,
                      letterSpacing: 2,
                      color: Color(0xCCFFF6E4),
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      level,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: AppFonts.zcool,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Color(0xFFFFF7E8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _yiJi(
    BuildContext context,
    String mark,
    String text, {
    required bool good,
  }) {
    final c = context.c;
    final tone = good ? c.mintInk : c.stamp;
    final bg = good
        ? (c.dark ? const Color(0x1AC9D3B2) : const Color(0xFFEAF2E3))
        : (c.dark ? const Color(0x14E0796A) : const Color(0xFFFBE9E4));
    final border = good
        ? c.mintLine
        : (c.dark ? const Color(0x33E0796A) : const Color(0xFFF0D2C8));
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: good
                  ? c.mintSoft
                  : (c.dark
                        ? const Color(0x33E0796A)
                        : const Color(0xFFF5DCD4)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              mark,
              style: context.body(
                size: 10,
                weight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: context.body(size: 11, color: tone, height: 1.4),
            ),
          ),
        ],
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
        colors: [color.withAlpha(34), color.withAlpha(12), color.withAlpha(0)],
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
