import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_keys.dart';
import '../services/pomodoro.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/browser_effects.dart';
import '../widgets/paper.dart';

Future<void> showPomodoroOverlay(
  BuildContext context, {
  CitroColors? colors,
  bool nook = false,
}) async {
  PomodoroState.instance.ensureInit();
  PomodoroState.instance.nookUi = nook;
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
            child: Theme(
              data: colors == null
                  ? Theme.of(ctx)
                  : Theme.of(ctx).copyWith(extensions: [CitroSkin(colors)]),
              child: Material(
                type: MaterialType.transparency,
                child: _PomodoroDialog(nook: nook),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

CitroColors _nookColors(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = dark ? CitroColors.darkColors : CitroColors.light;
  return base.copyWith(
    accent: dark ? const Color(0xFFAAC4A2) : const Color(0xFF4F6957),
    accent2: dark ? const Color(0xFF8FAF86) : const Color(0xFF3E5747),
    accentInk: dark ? const Color(0xFFC8DCC0) : const Color(0xFF3E5747),
    accentLt: dark ? const Color(0xFFC8DCC0) : const Color(0xFF7C9B79),
    hl: dark ? const Color(0x33AAC4A2) : const Color(0x8FE4EADD),
    hlInk: dark ? const Color(0x57AAC4A2) : const Color(0x9E4F6957),
  );
}

/// 全局监听番茄钟到点事件，在任何页面都能弹出完成提示。
class PomodoroDoneWatcher extends StatefulWidget {
  const PomodoroDoneWatcher({super.key});

  @override
  State<PomodoroDoneWatcher> createState() => _PomodoroDoneWatcherState();
}

class _PomodoroDoneWatcherState extends State<PomodoroDoneWatcher> {
  @override
  void initState() {
    super.initState();
    PomodoroState.instance.finished.addListener(_onFinished);
  }

  @override
  void dispose() {
    PomodoroState.instance.finished.removeListener(_onFinished);
    super.dispose();
  }

  void _onFinished() {
    final state = PomodoroState.instance;
    final nextMode = state.finished.value;
    if (nextMode == null) return;
    state.finished.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _present(nextMode));
    // 静止页面可能没有下一帧，只登记 post-frame 回调会一直等不到。
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _present(String nextMode) async {
    if (!mounted) return;
    final ctx = citroNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      PomodoroState.instance.settleFinished();
      return;
    }
    await showGeneralDialog<void>(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: '稍后',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (dialogCtx, anim, _, __) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(dialogCtx).maybePop(),
              child: CitroBackdropBlur(
                sigma: 14,
                child: Container(color: const Color(0x9923211C)),
              ),
            ),
          ),
          FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: .9, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
              ),
              child: Theme(
                data: PomodoroState.instance.nookUi
                    ? Theme.of(dialogCtx).copyWith(
                        extensions: [CitroSkin(_nookColors(dialogCtx))],
                      )
                    : Theme.of(dialogCtx),
                // Overlay 路由没有 Scaffold 的文字样式，缺 Material 会继承红字黄双下划线。
                child: Material(
                  type: MaterialType.transparency,
                  child: _PomodoroDoneDialog(nextMode: nextMode),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    PomodoroState.instance.settleFinished();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PomodoroDoneDialog extends StatelessWidget {
  const _PomodoroDoneDialog({required this.nextMode});
  final String nextMode;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final toFocus = nextMode == 'focus';
    final title = toFocus ? '休息结束' : '专注完成';
    final subtitle = toFocus
        ? '把心收回来，继续下一轮专注。'
        : (nextMode == 'long' ? '已经攒够一轮番茄，好好长休一会儿。' : '站起来走两步，喝口水，看看远处。');
    final action = toFocus ? '继续专注' : (nextMode == 'long' ? '开始长休' : '开始短休');
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          22,
          16 + MediaQuery.paddingOf(context).top,
          22,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: c.dark
                  ? [const Color(0xFF2C2720), const Color(0xFF201D18)]
                  : [const Color(0xFFFBF6EA), const Color(0xFFEDE0CA)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: c.accent.withAlpha(c.dark ? 70 : 60)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x306E5030),
                blurRadius: 50,
                offset: Offset(0, 22),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c.accent.withAlpha(c.dark ? 70 : 52),
                      c.accent.withAlpha(0),
                    ],
                  ),
                ),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.accent.withAlpha(c.dark ? 54 : 30),
                    border: Border.all(color: c.accent.withAlpha(120)),
                  ),
                  child: Text(
                    toFocus ? '🌿' : '🍅',
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(title, style: context.heading(size: 25, color: c.ink)),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: context.body(size: 12.5, color: c.inkSoft, height: 1.65),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: c.accent.withAlpha(c.dark ? 30 : 22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '今日已完成 ${PomodoroState.instance.todayCount} 颗番茄',
                  style: context.body(
                    size: 11,
                    weight: FontWeight.w600,
                    color: c.accentInk,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Pressable(
                onTap: () {
                  PomodoroState.instance.beginNext(startNow: true);
                  Navigator.of(context).maybePop();
                },
                child: Container(
                  height: 48,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.accent, c.accent2]),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: CitroColors.shadows.note(c),
                  ),
                  child: Text(
                    action,
                    style: context.body(
                      size: 14.5,
                      weight: FontWeight.w700,
                      color: const Color(0xFF2E2C22),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(
                  '稍后再说',
                  style: context.body(size: 12.5, color: c.inkSoft),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PomodoroDialog extends StatefulWidget {
  const _PomodoroDialog({this.nook = false});

  final bool nook;

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
              constraints: const BoxConstraints(maxWidth: 420),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: c.dark
                      ? (widget.nook
                            ? [const Color(0xFF202B23), const Color(0xFF161F19)]
                            : [
                                const Color(0xFF2C2720),
                                const Color(0xFF201D18),
                              ])
                      : (widget.nook
                            ? [const Color(0xFFF4F7EF), const Color(0xFFE3EADA)]
                            : [
                                const Color(0xFFFAF4E7),
                                const Color(0xFFE9DBC4),
                              ]),
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: c.line.withAlpha(c.dark ? 66 : 90)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2E6E5030),
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
                children: [
                  Positioned(
                    top: -46,
                    right: -34,
                    child: _glow(c.accent, 158, c.dark ? .2 : .16),
                  ),
                  Positioned(
                    bottom: -70,
                    left: -50,
                    child: _glow(c.accent2, 180, c.dark ? .16 : .12),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: ListenableBuilder(
                      listenable: PomodoroState.instance,
                      builder: (context, _) {
                        final state = PomodoroState.instance;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _header(context, state),
                            const SizedBox(height: 14),
                            _tabs(context, state),
                            if (state.mode == 'long' && !state.running) ...[
                              const SizedBox(height: 12),
                              _longSlider(context, state),
                            ],
                            const SizedBox(height: 14),
                            Center(child: _ring(context, state)),
                            const SizedBox(height: 16),
                            _actions(context, state),
                            const SizedBox(height: 14),
                            _today(context, state),
                            const SizedBox(height: 8),
                            Text(
                              state.running
                                  ? '通知栏常驻倒计时 · 到点会弹窗提醒'
                                  : '关闭窗口后计时继续 · 到点会提醒你',
                              textAlign: TextAlign.center,
                              style: context.body(size: 10.5, color: c.inkSoft),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Pressable(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c.ink.withAlpha(10),
                          shape: BoxShape.circle,
                          border: Border.all(color: c.line.withAlpha(110)),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.close, width: 2),
                            size: 13,
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

  Widget _glow(Color color, double size, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withAlpha((alpha * 255).round()),
              color.withAlpha(0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, PomodoroState state) {
    final c = context.c;
    final subtitle = state.running
        ? '还剩 ${state.timeText} · 先专注这一件事'
        : state.done
        ? '这一轮结束了，准备下一轮'
        : switch (state.mode) {
            'short' => '休息 ${state.total ~/ 60} 分钟 · 离开屏幕远眺',
            'long' => '长休 ${state.total ~/ 60} 分钟 · 好好放松',
            _ => '专注 25 分钟 · 一次只做一件事',
          };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('番茄钟', style: context.heading(size: 22, color: c.ink)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: 10.8, color: c.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(width: 30),
      ],
    );
  }

  Widget _tabs(BuildContext context, PomodoroState state) {
    final c = context.c;
    final items = [
      ('focus', '专注 25′', Icons.center_focus_strong_rounded),
      ('short', '短休 5′', Icons.coffee_rounded),
      ('long', '长休 ${state.longMinutes}′', Icons.nightlight_round),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.dark ? const Color(0x12FFFFFF) : const Color(0x0D23211C),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line.withAlpha(140)),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: GestureDetector(
                onTap: () => state.switchMode(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 36,
                  decoration: BoxDecoration(
                    color: state.mode == item.$1
                        ? c.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: state.mode == item.$1
                        ? CitroColors.shadows.note(c)
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.$3,
                        size: 14,
                        color: state.mode == item.$1
                            ? const Color(0xFF2E2C22)
                            : c.inkSoft,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.$2,
                        style: context.display(
                          size: 13.5,
                          weight: FontWeight.w700,
                          color: state.mode == item.$1
                              ? const Color(0xFF2E2C22)
                              : c.inkSoft,
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

  Widget _longSlider(BuildContext context, PomodoroState state) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('长休时长', style: context.body(size: 11.5, color: c.inkSoft)),
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
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
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
            onChanged: (v) => state.setLongMinutes(v.round()),
          ),
        ),
      ],
    );
  }

  Widget _ring(BuildContext context, PomodoroState state) {
    final c = context.c;
    return SizedBox(
      width: 230,
      height: 230,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(230, 230),
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
                  size: 60,
                  weight: FontWeight.w700,
                  color: c.ink,
                  height: 1.02,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: c.accent.withAlpha(c.dark ? 34 : 20),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  state.notice ?? state.modeLabel,
                  style: context.body(
                    size: 11,
                    weight: FontWeight.w600,
                    color: c.accentInk,
                  ),
                ),
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
        ? '暂停一下'
        : (state.remain < state.total && state.remain > 0 && !state.done
              ? '继续'
              : state.startLabel);
    return Row(
      children: [
        Expanded(
          child: Pressable(
            onTap: state.toggle,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.accent, c.accent2]),
                borderRadius: BorderRadius.circular(999),
                boxShadow: CitroColors.shadows.note(c),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    state.running
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 21,
                    color: const Color(0xFF2E2C22),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: context.body(
                      size: 14.5,
                      weight: FontWeight.w700,
                      color: const Color(0xFF2E2C22),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Pressable(
          onTap: state.reset,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: c.surface2.withAlpha(c.dark ? 40 : 200),
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

  Widget _today(BuildContext context, PomodoroState state) {
    final c = context.c;
    final shown = math.min(state.todayCount, 8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.surface.withAlpha(c.dark ? 26 : 150),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line.withAlpha(110)),
      ),
      child: Row(
        children: [
          Text(
            '今日番茄',
            style: context.body(
              size: 11,
              weight: FontWeight.w600,
              color: c.inkSoft,
            ),
          ),
          const Spacer(),
          if (state.todayCount <= 0)
            Text('还没有，先专注一颗', style: context.body(size: 10.5, color: c.inkSoft))
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < shown; i++)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Text('🍅', style: TextStyle(fontSize: 13)),
                  ),
                if (state.todayCount > shown)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '×${state.todayCount}',
                      style: context.body(
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: c.accentInk,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
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
    final radius = math.min(size.width, size.height) / 2 - 16;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (var i = 0; i < 12; i++) {
      final angle = -math.pi / 2 + i * math.pi / 6;
      final inner = radius + 8;
      final outer = radius + (i % 3 == 0 ? 14 : 11);
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        Paint()
          ..color = track
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = track,
    );
    if (progress <= 0) return;
    final shader = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: math.pi * 3 / 2,
      colors: [color, color2, color],
    ).createShader(rect);
    final sweep = math.pi * 2 * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..color = color.withAlpha(30)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 9),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
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
