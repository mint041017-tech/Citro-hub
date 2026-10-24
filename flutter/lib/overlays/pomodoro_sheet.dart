import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/pomodoro.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/browser_effects.dart';
import '../widgets/paper.dart';

Future<void> showPomodoroOverlay(BuildContext context) async {
  PomodoroState.instance.init();
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
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
              begin: .92,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
            child: const Material(
              type: MaterialType.transparency,
              child: _PomodoroDialog(),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PomodoroDialog extends StatefulWidget {
  const _PomodoroDialog();

  @override
  State<_PomodoroDialog> createState() => _PomodoroDialogState();
}

class _PomodoroDialogState extends State<_PomodoroDialog> {
  final GlobalKey _cardKey = GlobalKey();
  Offset? _downAt;

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

  @override
  Widget build(BuildContext context) {
    final c = context.c;
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: c.dark
                      ? [const Color(0xFF2C2720), const Color(0xFF201D18)]
                      : [const Color(0xFFF8F2E5), const Color(0xFFEADDC7)],
                ),
                borderRadius: BorderRadius.circular(24),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: ListenableBuilder(
                      listenable: PomodoroState.instance,
                      builder: (context, _) {
                        final state = PomodoroState.instance;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Text(
                                '番茄钟',
                                style: context.heading(size: 25, color: c.ink),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _tabs(context, state),
                            if (state.mode == 'long' && !state.running) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Text(
                                    '长休时长',
                                    style: context.body(
                                      size: 11.5,
                                      color: c.inkSoft,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${state.longMinutes} 分钟',
                                    style: context.body(
                                      size: 11.5,
                                      weight: FontWeight.w700,
                                      color: c.accentInk,
                                    ),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16,
                                  ),
                                  activeTrackColor: c.accent,
                                  inactiveTrackColor: c.line2,
                                  thumbColor: c.accent,
                                ),
                                child: Slider(
                                  value: state.longMinutes.toDouble(),
                                  min: 15,
                                  max: 30,
                                  divisions: 15,
                                  label: '${state.longMinutes} 分钟',
                                  onChanged: (v) =>
                                      state.setLongMinutes(v.round()),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Center(child: _ring(context, state)),
                            const SizedBox(height: 14),
                            _actions(context, state),
                            const SizedBox(height: 16),
                            _tomatoes(context, state),
                            const SizedBox(height: 5),
                            Text(
                              '今日已完成 ${state.todayCount} 个番茄 · 关闭后计时继续',
                              textAlign: TextAlign.center,
                              style: context.body(size: 11, color: c.inkSoft),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Pressable(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c.ink.withAlpha(10),
                          shape: BoxShape.circle,
                          border: Border.all(color: c.line.withAlpha(120)),
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

  Widget _tabs(BuildContext context, PomodoroState state) {
    final c = context.c;
    final items = [
      ('focus', '专注 25′'),
      ('short', '短休 5′'),
      ('long', '长休 ${state.longMinutes}′'),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.dark ? const Color(0x12FFFFFF) : const Color(0x0D23211C),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line.withAlpha(150)),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: GestureDetector(
                onTap: () => state.switchMode(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 34,
                  decoration: BoxDecoration(
                    color: state.mode == item.$1
                        ? c.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: state.mode == item.$1
                        ? CitroColors.shadows.note(c)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      item.$2,
                      style: context.display(
                        size: 14,
                        weight: FontWeight.w700,
                        color: state.mode == item.$1
                            ? const Color(0xFF2E2C22)
                            : c.inkSoft,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ring(BuildContext context, PomodoroState state) {
    final c = context.c;
    return SizedBox(
      width: 216,
      height: 216,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(216, 216),
            painter: _RingPainter(
              progress: state.progress,
              track: c.dark ? const Color(0x1FFFFFFF) : const Color(0x1A4A3A22),
              color: c.accent,
              color2: c.accent2,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.timeText,
                style: context.display(
                  size: 54,
                  weight: FontWeight.w700,
                  color: c.ink,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                state.notice ?? state.modeLabel,
                style: context.body(size: 12, color: c.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, PomodoroState state) {
    final c = context.c;
    final label = state.running
        ? '暂停'
        : (state.remain < state.total && state.remain > 0 && !state.done
              ? '继续'
              : state.startLabel);
    return Row(
      children: [
        Expanded(
          child: Pressable(
            onTap: state.toggle,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: CitroColors.shadows.note(c),
              ),
              child: Center(
                child: Text(
                  label,
                  style: context.body(
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: const Color(0xFF2E2C22),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Pressable(
          onTap: state.reset,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.surface2.withAlpha(c.dark ? 30 : 190),
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
            child: Center(
              child: AppIcon(
                strokeSvg(AppIcons.refresh, width: 2),
                size: 18,
                color: c.inkSoft,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tomatoes(BuildContext context, PomodoroState state) {
    final c = context.c;
    if (state.todayCount <= 0) {
      return Text(
        '还没有番茄，专注一个试试',
        textAlign: TextAlign.center,
        style: context.body(size: 11.5, color: c.inkSoft),
      );
    }
    final shown = math.min(state.todayCount, 8);
    return Text(
      '${List.filled(shown, '🍅').join(' ')}${state.todayCount > 8 ? '  ×${state.todayCount}' : ''}',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 19, height: 1.2),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color color;
  final Color color2;

  _RingPainter({
    required this.progress,
    required this.track,
    required this.color,
    required this.color2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = track,
    );
    if (progress <= 0) return;
    final shader = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: math.pi * 3 / 2,
      colors: [color, color2, color],
    ).createShader(rect);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.color != color ||
      old.color2 != color2;
}
