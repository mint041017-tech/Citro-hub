import 'package:flutter/material.dart';

import '../app_keys.dart';
import '../services/cook_timer.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'timer_sheet.dart';

class TimerCapsuleOverlay extends StatefulWidget {
  const TimerCapsuleOverlay({super.key});

  @override
  State<TimerCapsuleOverlay> createState() => _TimerCapsuleOverlayState();
}

class _TimerCapsuleOverlayState extends State<TimerCapsuleOverlay> {
  /// 计时结束后胶囊要淡出，需要保留最后一帧内容，避免先被移除再消失。
  CookTick? _lastTick;

  @override
  void initState() {
    super.initState();
    CookTimer.instance.finished.addListener(_onFinished);
  }

  @override
  void dispose() {
    CookTimer.instance.finished.removeListener(_onFinished);
    super.dispose();
  }

  void _onFinished() {
    final label = CookTimer.instance.finished.value;
    if (label == null) return;
    CookTimer.instance.finished.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = citroNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      showCitroDialog(
        ctx,
        builder: (dialogCtx) => PaperDialog(
          showClose: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('⏰ 时间到', style: dialogCtx.heading(size: 24)),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: dialogCtx.body(size: 13, color: dialogCtx.c.inkSoft),
              ),
              const SizedBox(height: 16),
              AccentButton(text: '好', onTap: () => Navigator.pop(dialogCtx)),
            ],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        CookTimer.instance,
        AppState.instance.popupActiveNotifier,
      ]),
      builder: (context, _) {
        final tick = CookTimer.instance.tick;
        if (tick != null) _lastTick = tick;
        final current = tick ?? _lastTick;
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final visible =
            tick != null &&
            !keyboardOpen &&
            !AppState.instance.popupActiveNotifier.value;
        if (current == null) return const SizedBox.shrink();
        final c = context.c;
        final bg = c.dark ? c.surface2 : const Color(0xFF2E2A22);
        final fg = c.dark ? c.ink : const Color(0xFFFBF7EC);
        final reduce = CitroMotion.reduced(context);
        return Positioned(
          left: 14,
          bottom: MediaQuery.paddingOf(context).bottom + 76,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(-.04, .28),
              duration: reduce ? Duration.zero : CitroMotion.popover,
              curve: CitroMotion.easeOut,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: reduce ? Duration.zero : CitroMotion.toastReverse,
                curve: CitroMotion.easeColor,
                child: GestureDetector(
                  onTap: () {
                    final ctx = citroNavigatorKey.currentContext;
                    if (ctx != null) showTimerManageSheet(ctx);
                  },
                  child: Container(
                    height: 44,
                    constraints: const BoxConstraints(maxWidth: 238),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: c.accent.withAlpha(170),
                        width: 1.2,
                      ),
                      boxShadow: CitroColors.shadows.lg(c),
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(decoration: TextDecoration.none),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            strokeSvg(
                              '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
                              width: 2.2,
                            ),
                            size: 18,
                            color: c.accentLt,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            current.timeText,
                            style: context.display(
                              size: 18,
                              weight: FontWeight.w700,
                              color: c.accentLt,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 16,
                            color: fg.withAlpha(55),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              current.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.body(
                                size: 10,
                                color: fg.withAlpha(180),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
