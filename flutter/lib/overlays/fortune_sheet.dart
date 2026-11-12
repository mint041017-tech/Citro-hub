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
import '../widgets/modal.dart';

Future<void> showFortuneOverlay(BuildContext context) async {
  await showCitroGeneralDialog(
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
              child: Container(color: ctx.c.scrim),
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
  static final _cardRadius = BorderRadius.all(Radius.circular(CitroColors.radii.card));
  // 翻面：压到 560ms（原 900ms 是「拖沓」的主因）。曲线用强 ease-out 起步，
  // 比 easeInOut 的起步更有「被弹起来」的仪式感。
  static const _flipDuration = Duration(milliseconds: 560);
  static const Curve _flipCurve = CitroMotion.easeOut;
  // 入场 460ms（原 980ms）：位移/缩放/旋转用强 ease-out，fade 单独再提前，
  // 两层叠出「落得稳、亮得快」的节奏。
  static const _entranceDuration = Duration(milliseconds: 460);
  // 循环光晕放慢一倍：它只是氛围底，不该抢翻面的戏。
  static const _auraDuration = Duration(seconds: 10);
  // 揭晓（翻面落定）：星尘 / 边缘高光 / 逐行浮现 / 收尾共用一条时间轴。
  static const Duration _revealDuration = Duration(milliseconds: 1080);
  // 各段在时间轴上的起点，越靠后越有「一层层揭开」的层次。
  static const Duration _atSeal = Duration(milliseconds: 60);
  static const Duration _atName = Duration(milliseconds: 170);
  static const Duration _atPoem = Duration(milliseconds: 250);
  static const Duration _atPoemLine = Duration(milliseconds: 80);
  static const Duration _atDesc = Duration(milliseconds: 400);
  static const Duration _atYiJi = Duration(milliseconds: 480);

  final GlobalKey _cardKey = GlobalKey();
  Offset? _downAt;
  int? idx;
  bool loading = true;

  late final AnimationController _flip;
  late final AnimationController _entrance;
  late final AnimationController _aura;
  late final AnimationController _reveal;
  CardFace? _card;
  Timer? _introTimer;
  Timer? _revealTimer;
  bool _frontUp = false;
  bool _flipBusy = false;
  bool _transferBusy = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(vsync: this, duration: _flipDuration, value: 0);
    _entrance = AnimationController(
      vsync: this,
      duration: _entranceDuration,
    )..forward();
    _aura = AnimationController(vsync: this, duration: _auraDuration)..forward();
    // 揭晓进度：t = 已进行的时间 / 总时长。星尘 / 逐行浮现 / 收尾共用一个
    // ticker，省掉多条 AnimatedBuilder 各算一遍时间。
    _reveal = AnimationController(
      vsync: this,
      duration: _revealDuration,
      value: 1,
    );
    _load();
    _loadCard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reduced) {
        _flip.value = 1;
        _frontUp = true;
        return;
      }
      // 卡背先停一会儿让用户看清「今天要翻什么」，再翻开（原来 240ms 太短，
      // 看起来像直接翻；也不能长到拖沓）。
      _introTimer = Timer(const Duration(milliseconds: 680), _flipToFront);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery 依赖要在 didChangeDependencies 里读，initState 里读会抛
    // 「dependOnInheritedWidgetOfExactType() was called before initState() finished」。
    _reduced = CitroMotion.reduced(context);
  }

  Future<void> _loadCard() async {
    final card = await AppState.instance.ensureTodayCard();
    if (!mounted) return;
    setState(() => _card = card);
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _revealTimer?.cancel();
    _flip.dispose();
    _entrance.dispose();
    _aura.dispose();
    _reveal.dispose();
    super.dispose();
  }

  void _flipToFront({bool withReveal = true}) {
    _introTimer?.cancel();
    if (!mounted || _flipBusy || _frontUp) return;
    _flipBusy = true;
    HapticFeedback.lightImpact();
    // 揭晓比翻面晚 240ms 起：翻面将落未落时星尘先亮，文字随后一层层揭开，
    // 两段叠在一起更密实；同时压掉「翻完了才开始」的空等。
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      if (withReveal && !_reduced && !loading) _reveal.forward(from: 0);
    });
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
    // 返回卡背时把没放完的揭晓收掉，避免下次翻开时停在半截。
    _revealTimer?.cancel();
    _reveal.stop();
    _reveal.value = 1;
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
      // 留一点时间让用户看到新卡背，再翻开新签。
      await Future<void>.delayed(const Duration(milliseconds: 120));
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
        color: c.accentLt.withAlpha(c.dark ? 44 : 170),
        borderRadius: BorderRadius.circular(CitroColors.radii.small),
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
                    borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                  ),
                  child: Text(
                    '待使用',
                    style: context.body(
                      size: CitroType.micro,
                      weight: CitroType.medium,
                      color: c.onAccent,
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
            style: context.body(size: 11, color: c.inkSoft, height: 1.45),
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
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
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
                          color: ready ? c.onAccent : c.accentInk,
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
                            : (ready ? c.onAccent : c.accentInk),
                      ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: context.body(
                        size: CitroType.small,
                        weight: CitroType.medium,
                        color: used
                            ? c.inkSoft
                            : (ready ? c.onAccent : c.accentInk),
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
          ? [c.surface2, c.bg2]
          : [c.surface, c.tintYellow],
    );

    // 揭晓时的「星尘」粒子要能跑出卡片圆角，所以单独一层画在整张卡之上。
    final sparkles = _RevealSparkles(controller: _reveal, color: c.accent);

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
                final t = CitroMotion.easeOut.transform(
                  _entrance.value.clamp(0.0, 1.0),
                );
                final fade = Curves.easeOut.transform(
                  (_entrance.value * 1.8).clamp(0.0, 1.0),
                );
                return Opacity(
                  opacity: fade,
                  child: Transform.translate(
                    offset: Offset(0, 56 * (1 - t)),
                    child: Transform.rotate(
                      angle: -.035 * (1 - t),
                      child: Transform.scale(
                        scale: .88 + .12 * t,
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
                      // 光晕图案固定不变，只做旋转 + 呼吸缩放：整层只栅格化一次，
                      // 不用每帧重画 24 条射线 + 16 个粒子（原来是 5s 无限 repeat
                      // 且每帧重绘整块区域，是打卡动画卡顿的主因）。
                      child: RepaintBoundary(
                        // 亮度压在低位，避免盖过翻面和星尘。
                        child: AnimatedBuilder(
                          animation: _aura,
                          builder: (context, child) {
                            final t = _aura.value;
                            // 揭晓的瞬间光晕亮一下，平时保持很淡的呼吸。
                            final boost = math.sin(
                              math.pi * _reveal.value.clamp(0.0, 1.0),
                            );
                            return Opacity(
                              opacity: .34 + .16 * boost,
                              child: Transform.rotate(
                                angle: t * math.pi * 2 / 24,
                                child: Transform.scale(
                                  scale: .96 + .04 * math.sin(t * math.pi * 2),
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: CustomPaint(
                            painter: _FortuneAuraPainter(color: c.accent),
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
                      boxShadow: [
                        BoxShadow(
                          color: c.dark
                              ? const Color(0x66000000)
                              : const Color(0x24000000),
                          blurRadius: 60,
                          offset: const Offset(0, 24),
                        ),
                        BoxShadow(
                          color: c.dark
                              ? const Color(0x40000000)
                              : const Color(0x1A000000),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
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
                                          padding: const EdgeInsets.all(10),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    CitroColors.radii.inner,
                                                  ),
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
                                              const SizedBox(width: 8),
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
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Container(
                                                  height: 1,
                                                  color: c.accent.withAlpha(58),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                'DAILY DRAW',
                                                style: context.body(
                                                  size: 9,
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
                                                                bottom: 8,
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
                                                                  size: 11,
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
                                                    const SizedBox(height: 10),
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
                                          _RevealItem(
                                            controller: _reveal,
                                            child: AnimatedOpacity(
                                              opacity: loading ? 0 : 1,
                                              duration: const Duration(
                                                milliseconds: 220,
                                              ),
                                              child: AnimatedScale(
                                                scale: loading ? .98 : 1,
                                                duration: const Duration(
                                                  milliseconds: 220,
                                                ),
                                                curve: Curves.easeOut,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        14,
                                                        16,
                                                        14,
                                                        16,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: c.surface.withAlpha(
                                                      c.dark ? 26 : 148,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          CitroColors.radii.inner,
                                                        ),
                                                    border: Border.all(
                                                      color: c.accent.withAlpha(
                                                        c.dark ? 40 : 58,
                                                      ),
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: c.dark
                                                            ? const Color(
                                                                0x33000000,
                                                              )
                                                            : const Color(
                                                                0x0F000000,
                                                              ),
                                                        blurRadius: 12,
                                                        offset: const Offset(0, 5),
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
                                                              _StampIn(
                                                                controller:
                                                                    _reveal,
                                                                at: _atSeal,
                                                                child:
                                                                    _fortuneSeal(
                                                                  context,
                                                                  fortune.lv,
                                                                ),
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
                                                                    // 签名用「从左往右写出来」的擦除式揭示，
                                                                    // 比单纯淡入更像落笔。
                                                                    _WritingReveal(
                                                                      controller:
                                                                          _reveal,
                                                                      at: _atName,
                                                                      color: c
                                                                          .ink,
                                                                      child:
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
                                                                              24,
                                                                          weight:
                                                                              FontWeight.w700,
                                                                          color: c
                                                                              .ink,
                                                                          letterSpacing:
                                                                              3.4,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      height: 6,
                                                                    ),
                                                                    _RevealItem(
                                                                      controller:
                                                                          _reveal,
                                                                      at: _atPoem,
                                                                      child:
                                                                          Container(
                                                                        padding: const EdgeInsets.symmetric(
                                                                          horizontal:
                                                                              12,
                                                                          vertical:
                                                                              10,
                                                                        ),
                                                                        decoration: BoxDecoration(
                                                                          color: c.accent.withAlpha(
                                                                            c.dark
                                                                                ? 14
                                                                                : 18,
                                                                          ),
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                            CitroColors.radii.small,
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
                                                                            for (var i = 0;
                                                                                i < fortune.poem.length;
                                                                                i++)
                                                                              _RevealItem(
                                                                                controller:
                                                                                    _reveal,
                                                                                at: _atPoem +
                                                                                    _atPoemLine *
                                                                                        i,
                                                                                rise: 6,
                                                                                child: Text(
                                                                                  fortune
                                                                                      .poem[i],
                                                                                  textAlign:
                                                                                      TextAlign.center,
                                                                                  style: context.display(
                                                                                    size: 14,
                                                                                    weight: FontWeight.w700,
                                                                                    color: c.ink,
                                                                                    height: 1.75,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                          ],
                                                                        ),
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
                                                          _RevealItem(
                                                            controller: _reveal,
                                                            at: _atDesc,
                                                            rise: 8,
                                                            child: Text(
                                                              fortune.desc,
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: context.body(
                                                                size: 13,
                                                                color: c.ink2,
                                                                height: 1.65,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 12,
                                                          ),
                                                          _RevealItem(
                                                            controller: _reveal,
                                                            at: _atYiJi,
                                                            child: Row(
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
                                                          ),
                                                        ],
                                                      ),
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
                                              12,
                                              8,
                                              12,
                                              8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.surface2,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    CitroColors.radii.small,
                                                  ),
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
                                                      size: 11,
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
                                                      size: 10,
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
                        // 翻面落定的瞬间：沿卡片内圈扫过一圈高光。
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ClipRRect(
                              borderRadius: _cardRadius,
                              child: _RevealEdge(
                                controller: _reveal,
                                color: c.accent,
                              ),
                            ),
                          ),
                        ),
                        // 星尘可以跑出圆角，所以放在 ClipRRect 之外。
                        Positioned.fill(
                          child: IgnorePointer(child: sparkles),
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
                                color: c.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.line),
                                boxShadow: CitroColors.shadows.sm(c),
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
          color: c.tintYellow,
          borderRadius: BorderRadius.circular(CitroColors.radii.card),
          border: Border.all(color: c.accent.withAlpha(86)),
          boxShadow: CitroColors.shadows.sm(c),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
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
          colors: [stamp, Color.lerp(stamp, c.ink, .16)!],
        ),
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
        boxShadow: CitroColors.shadows.sm(c),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CitroColors.radii.inner - 1),
                  border: Border.all(color: Colors.white.withAlpha(180)),
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
                  Text(
                    '今日签',
                    style: context.body(
                      size: CitroType.micro,
                      weight: CitroType.medium,
                      // 棕底配白字，深青在棕上几乎看不见。
                      color: Colors.white.withAlpha(230),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      level,
                      maxLines: 1,
                      style: context.heading(
                        size: CitroType.titleLg,
                        color: Colors.white,
                        letterSpacing: 1,
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
    final bg = good ? c.mintSoft : c.dangerSoft;
    final border = good ? c.mintLine : c.danger.withAlpha(90);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CitroColors.radii.small),
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
              color: good ? c.surface : c.dangerSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              mark,
              style: context.body(
                size: CitroType.micro,
                weight: CitroType.medium,
                color: tone,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              text,
              style: context.body(
                size: CitroType.small,
                color: tone,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBack(BuildContext context) {
    final c = context.c;
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
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.surface2, c.bg2],
                ),
              ),
            ),
          // 照片上的暗角只用于保证文字可读，属图片叠加层，不走 token。
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x4D000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x66000000),
                ],
                stops: [0, .2, .72, 1],
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(CitroColors.radii.card - 1),
                  border: Border.all(color: c.accentLt, width: 1),
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 13,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.scrim,
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              ),
              child: Text(
                '轻点翻开',
                style: context.body(
                  size: CitroType.small,
                  weight: CitroType.medium,
                  color: c.surface,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: c.scrim,
                  borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                ),
                child: Text(
                  '${card.categoryName} · ${card.label}',
                  style: context.body(
                    size: CitroType.micro,
                    weight: CitroType.medium,
                    color: c.surface,
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
        bg = c.accentLt.withAlpha(c.dark ? 60 : 140);
        fg = c.accentInk;
        border = c.accent.withAlpha(120);
        break;
      case 'term':
        bg = c.mintSoft;
        fg = c.mintInk;
        border = c.mintLine;
        break;
      default:
        bg = c.surface2;
        fg = c.ink2;
        border = c.line;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CitroColors.radii.xs),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: context.body(size: CitroType.small, color: fg),
      ),
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
  _FortuneAuraPainter({required this.color});

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
      final angle = i * math.pi * 2 / 24;
      final pulse = .5 + .5 * math.sin(i * .9);
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
      final phase = i / 16;
      final angle = i * 2.399;
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
  bool shouldRepaint(covariant _FortuneAuraPainter old) => old.color != color;
}

/// 翻面时扫过卡面的一道暖光；只在动画期间显形。
///
/// 主体是一条亮芯 + 一条更宽更淡的尾迹，比单条光带更有「扫过去」的层次。
class _FlipShine extends StatelessWidget {
  final AnimationController controller;

  const _FlipShine({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
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
                  // 宽尾迹：先于亮芯半步，把卡面「铺亮」。
                  Positioned(
                    top: -h * .45,
                    bottom: -h * .45,
                    left: (-1.2 + 2.2 * (t * .94).clamp(0.0, 1.0)) * w,
                    width: w * .58,
                    child: Transform.rotate(
                      angle: -.3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              c.surface.withAlpha(0),
                              c.surface.withAlpha(58),
                              c.surface.withAlpha(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -h * .45,
                    bottom: -h * .45,
                    left: (-1.1 + 2.2 * t) * w,
                    width: w * .34,
                    child: Transform.rotate(
                      angle: -.3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              c.surface.withAlpha(0),
                              c.surface.withAlpha(150),
                              c.surface.withAlpha(0),
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

// -----------------------------------------------------------------------------
// 揭晓序列（翻面落定后的那 1 秒）
// -----------------------------------------------------------------------------

/// 揭晓序列里每个片段的时间窗与曲线（文件级，供 _RevealItem / _WritingReveal 等私有组件用）。
const Duration _revealWindow = Duration(milliseconds: 420);
const Curve _revealCurve = Curves.easeOutCubic;

/// 时间轴上某一点的进度：`[at, at + window]` 映射到 0 → 1。
double _revealLocal(
  AnimationController controller,
  Duration at,
  Duration window,
) {
  final total = controller.duration?.inMicroseconds ?? 0;
  if (total <= 0) return 1;
  return ((controller.value * total - at.inMicroseconds) /
          window.inMicroseconds)
      .clamp(0.0, 1.0);
}

/// 揭晓序列的基本单位：在 [at] 处淡入 + 上浮（可选缩放）。
///
/// 动画结束后直接返回原 child，不再包一层 Opacity/Transform，
/// 静止时不产生额外的合成层。
class _RevealItem extends StatelessWidget {
  const _RevealItem({
    required this.controller,
    required this.child,
    this.at = Duration.zero,
    this.rise = 10,
    this.scale = 1,
  });

  final AnimationController controller;
  final Widget child;
  final Duration at;
  final double rise;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = _revealLocal(controller, at, _revealWindow);
        if (t >= 1) return child;
        final e = _revealCurve.transform(t);
        return Opacity(
          opacity: e,
          child: Transform.translate(
            offset: Offset(0, rise * (1 - e)),
            child: scale == 1
                ? child
                : Transform.scale(
                    scale: scale + (1 - scale) * e,
                    child: child,
                  ),
          ),
        );
      },
    );
  }
}

/// 签名（运势名）的「书写」揭示：从左往右把字擦出来，边缘留一段软过渡。
///
/// 用 ShaderMask 做纯绘制层的揭示，不动布局——不像改 letterSpacing 那样
/// 每帧重排文字。
class _WritingReveal extends StatelessWidget {
  const _WritingReveal({
    required this.controller,
    required this.child,
    required this.color,
    this.at = Duration.zero,
  });

  final AnimationController controller;
  final Widget child;
  final Color color;
  final Duration at;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = _revealLocal(controller, at, _revealWindow);
        if (t >= 1) return child;
        final soft = math.min(.14, t);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [color, color, color.withAlpha(0), color.withAlpha(0)],
            stops: [0, (t - soft).clamp(0.0, 1.0), t, 1],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

/// 印章落下：先放大微旋，落定时回稳，同时向外推一圈墨晕。
class _StampIn extends StatelessWidget {
  const _StampIn({
    required this.controller,
    required this.child,
    this.at = Duration.zero,
  });

  final AnimationController controller;
  final Widget child;
  final Duration at;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = _revealLocal(controller, at, _revealWindow);
        if (t >= 1) return child;
        final e = Curves.easeOut.transform(t);
        final settle = Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
        return SizedBox(
          width: 78,
          height: 78,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 墨晕：随落章向外扩并淡出。
              Positioned(
                left: 5,
                right: 5,
                top: 5,
                bottom: 5,
                child: Opacity(
                  opacity: (1 - e) * .45,
                  child: Transform.scale(
                    scale: .82 + .5 * e,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: c.stamp.withAlpha(150)),
                      ),
                    ),
                  ),
                ),
              ),
              Opacity(
                opacity: math.min(1.0, t * 2.4),
                child: Transform.rotate(
                  angle: .07 * (1 - e),
                  child: Transform.scale(scale: 1.3 - .3 * settle, child: child),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 翻面落定时绕卡内圈扫过的一束光：转一圈即收，不循环。
class _RevealEdge extends StatelessWidget {
  const _RevealEdge({required this.controller, required this.color});

  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value.clamp(0.0, 1.0);
        if (t <= 0 || t >= 1) return const SizedBox.shrink();
        // 只扫前 62%，剩下时间留给星尘和文字。
        final sweep = Curves.easeOut.transform((t / .62).clamp(0.0, 1.0));
        final fade = math.sin(math.pi * t.clamp(0.0, 1.0));
        return Opacity(
          opacity: fade * .55,
          child: Transform.rotate(
            angle: sweep * math.pi * 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: SweepGradient(
                  colors: [
                    color.withAlpha(0),
                    color.withAlpha(0),
                    color.withAlpha(215),
                    color.withAlpha(0),
                    color.withAlpha(0),
                  ],
                  stops: const [0, .38, .5, .62, 1],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 揭晓瞬间从卡心炸开的星尘。
///
/// 粒子位置/大小在构造时一次性算好，paint 里只做画圆和画线，
/// 没有随机数、没有路径分配，也没有模糊。
class _RevealSparkles extends StatelessWidget {
  const _RevealSparkles({required this.controller, required this.color});

  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _SparklePainter(
              progress: controller.value.clamp(0.0, 1.0),
              color: color,
            ),
          );
        },
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const _count = 18;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) * .46;
    // 星尘只在揭示的前 3/4 时间内活跃。
    final window = (progress / .75).clamp(0.0, 1.0);
    if (window >= 1) return;
    for (var i = 0; i < _count; i++) {
      // 黄金角分布，疏密均匀又不呆板。
      final angle = i * 2.39996 + .35;
      final dist = maxR * (.3 + .7 * ((i * 37) % 100) / 100);
      final ease = Curves.easeOutCubic.transform(window);
      final p = center +
          Offset(math.cos(angle), math.sin(angle)) * dist * ease;
      // 错峰闪烁：每颗粒子在自己那段时间里亮起再暗下去。
      final local = ((window - (i % 5) * .06) / .62).clamp(0.0, 1.0);
      final twinkle = math.sin(math.pi * local);
      if (twinkle <= 0) continue;
      final r = 1.1 + 2.4 * ((i * 53) % 100) / 100;
      canvas.drawCircle(
        p,
        r * (.6 + .4 * twinkle),
        Paint()..color = color.withAlpha((235 * twinkle).round()),
      );
      // 四角星芒：只给靠外的几颗，避免整片都是十字。
      if (i % 3 == 0) {
        final ray = r * 3.1 * twinkle;
        final paint = Paint()
          ..color = color.withAlpha((150 * twinkle).round())
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          p - Offset(ray, 0),
          p + Offset(ray, 0),
          paint,
        );
        canvas.drawLine(
          p - Offset(0, ray),
          p + Offset(0, ray),
          paint,
        );
      }
    }
    // 卡心一闪而过的亮斑，把视线先聚到签名上。
    final core = math.sin(math.pi * (window / .34).clamp(0.0, 1.0));
    if (core > 0) {
      canvas.drawCircle(
        center,
        maxR * .34 * core,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withAlpha((70 * core).round()),
              color.withAlpha(0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: maxR * .34)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) =>
      old.progress != progress || old.color != color;
}
