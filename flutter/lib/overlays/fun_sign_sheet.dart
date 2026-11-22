import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fun_signs.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

/// 打开「趣签筒」：不算命、不看吉凶，可反复摇。
///
/// 和每日运签（`showFortuneOverlay`）互不打扰：
/// 运签一天一支、带宜忌与转运；趣签纯本地文案，摇多少次都行。
Future<void> showFunSignSheet(BuildContext context) {
  return showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withAlpha(60),
    builder: (_) => const _FunSignSheet(),
  );
}

class _FunSignSheet extends StatefulWidget {
  const _FunSignSheet();

  @override
  State<_FunSignSheet> createState() => _FunSignSheetState();
}

class _FunSignSheetState extends State<_FunSignSheet>
    with SingleTickerProviderStateMixin {
  FunSign _sign = funSignOfDay(DateTime.now());
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _reroll() {
    if (_shake.isAnimating) return;
    HapticFeedback.selectionClick();
    setState(() => _sign = randomFunSign(avoidId: _sign.id));
    _shake.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: c.line2.withAlpha(110), width: .6),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: c.inkSoft.withAlpha(110),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.casino_outlined, size: 16, color: c.accent),
                    const SizedBox(width: 6),
                    Text('趣签筒', style: context.heading(size: 16, color: c.ink)),
                    const Spacer(),
                    CitroChip(
                      '$kFunSignCount 支 · ${kFunSignKinds.length} 种',
                      background: c.tintYellow.withAlpha(150),
                      borderColor: c.line2.withAlpha(120),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '这一筒不算命，只负责好玩。想看今天顺不顺，还是回上面那支运签。',
                  style: context.body(
                    size: 11.5,
                    color: c.inkSoft,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) {
                    final t = _shake.value;
                    final dx = t == 0 ? 0.0 : 5 * (1 - t) * _wave(t);
                    final rot = t == 0 ? 0.0 : .012 * (1 - t) * _wave(t);
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: Transform.rotate(angle: rot, child: child),
                    );
                  },
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: CitroMotion.easeOut,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: CitroMotion.easeOut,
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: _signCard(context, key: ValueKey(_sign.id)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: CitroButton(
                        label: '再摇一签',
                        icon: Icon(
                          Icons.casino_outlined,
                          size: 16,
                          color: c.surface,
                        ),
                        style: CitroButtonStyle.primary,
                        onPressed: _reroll,
                      ),
                    ),
                    const SizedBox(width: 10),
                    CitroButton(
                      label: '收好',
                      style: CitroButtonStyle.ghost,
                      width: 74,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 0→1 的一段来回摆动，两端归零，避免摇完停在偏位。
  double _wave(double t) => math.sin(math.pi * 4 * t);

  Widget _signCard(BuildContext context, {required Key key}) {
    final c = context.c;
    return Container(
      key: key,
      constraints: const BoxConstraints(minHeight: 208),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: c.tintYellow,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: c.accent.withAlpha(55), width: .8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.accent.withAlpha(90), width: .7),
                ),
                child: Text(
                  _sign.kind,
                  style: context.body(
                    size: 10.5,
                    color: c.accentInk,
                    letterSpacing: .3,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Citro 趣签',
                style: context.body(
                  size: 10,
                  color: c.inkSoft.withAlpha(170),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _sign.name,
            style: context.display(size: 28, color: c.ink, height: 1.1),
          ),
          const SizedBox(height: 8),
          Text(
            _sign.poem1,
            style: context.hand(size: 15, color: c.ink2, height: 1.7),
          ),
          Text(
            _sign.poem2,
            style: context.hand(size: 15, color: c.ink2, height: 1.7),
          ),
          const SizedBox(height: 8),
          Text(
            _sign.note,
            style: context.body(size: 12.5, color: c.ink2, height: 1.6),
          ),
          const SizedBox(height: 10),
          _row(context, '宜', _sign.yi, c.mintSoft, true),
          const SizedBox(height: 4),
          _row(context, '忌', _sign.ji, c.surface, false),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String tag,
    String text,
    Color tagBg,
    bool good,
  ) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tagBg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: (good ? c.mintInk : c.dangerSoft).withAlpha(90),
              width: .6,
            ),
          ),
          child: Text(
            tag,
            style: context.body(
              size: 10,
              color: good ? c.mintInk : c.ink2,
              weight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: context.body(size: 12, color: c.ink2, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
