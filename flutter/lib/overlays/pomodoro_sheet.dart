import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_keys.dart';
import '../services/pomodoro.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
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
    bg: dark ? const Color(0xFF191F1C) : const Color(0xFFF5F3EE),
    bg2: dark ? const Color(0xFF141A17) : const Color(0xFFEFECE4),
    surface: dark ? const Color(0xFF242D27) : const Color(0xFFFFFFFF),
    surface2: dark ? const Color(0xFF2C362E) : const Color(0xFFF7F5EF),
    paperLine: dark ? const Color(0xFF37433A) : const Color(0xFFEFEDE6),
    ink: dark ? const Color(0xFFE5EBDE) : const Color(0xFF2C2C2C),
    ink2: dark ? const Color(0xFFCFD8C9) : const Color(0xFF4A4A4A),
    inkSoft: dark ? const Color(0xFFA8B5A6) : const Color(0xFF8A8A8A),
    line: dark ? const Color(0xFF37433A) : const Color(0xFFE8E6E1),
    line2: dark ? const Color(0xFF465248) : const Color(0xFFD9DFD6),
    accent: dark ? const Color(0xFFAAC4A2) : const Color(0xFF4F6957),
    accent2: dark ? const Color(0xFF8FAF86) : const Color(0xFF3E5747),
    accentInk: dark ? const Color(0xFFC8DCC0) : const Color(0xFF3E5747),
    accentLt: dark ? const Color(0xFFC8DCC0) : const Color(0xFF7C9B79),
    mintSoft: dark ? const Color(0x33354B39) : const Color(0xFFE8EDE3),
    mintLine: dark ? const Color(0x38C9D3B2) : const Color(0xFFD7DED2),
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
      transitionDuration: CitroMotion.modal,
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
            opacity: CurvedAnimation(
              parent: anim,
              curve: CitroMotion.easeOut,
              reverseCurve: CitroMotion.exit,
            ),
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
              Text(title, style: context.heading(size: 24, color: c.ink)),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: context.body(size: 13, color: c.inkSoft, height: 1.65),
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
                    weight: FontWeight.w700,
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
                      size: 14,
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
                  style: context.body(size: 13, color: c.inkSoft),
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
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _downAt = e.position,
      onPointerUp: _onPointerUp,
      child: SizedBox.expand(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16 + MediaQuery.paddingOf(context).top,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Container(
              key: _cardKey,
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              child: const PomodoroCard(),
            ),
          ),
        ),
      ),
    );
  }
}

/// 专注面板：既是弹层内容，也能直接嵌进听隅的「专注」页。
///
/// 页面里听隅使用自己的浅绿主题、没有 CitroSkin，因此可以通过 [colors]
/// 注入配色；不传时回退到当前 Citro 主题。
class PomodoroCard extends StatefulWidget {
  const PomodoroCard({
    super.key,
    this.colors,
    this.showHeader = true,
    this.showClose = true,
    this.showLongSlider = true,
    this.minHeight = 0,
  });

  final CitroColors? colors;
  final bool showHeader;
  final bool showClose;
  final bool showLongSlider;
  final double minHeight;

  @override
  State<PomodoroCard> createState() => _PomodoroCardState();
}

class _PomodoroCardState extends State<PomodoroCard> {
  CitroColors _colorsOf(BuildContext context) => widget.colors ?? context.c;

  @override
  Widget build(BuildContext context) {
    final c = _colorsOf(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(minHeight: widget.minHeight),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.line2),
        boxShadow: [
          BoxShadow(
            color: c.dark ? const Color(0x66000000) : const Color(0x1F6E5030),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: ListenableBuilder(
          listenable: PomodoroState.instance,
          builder: (context, _) {
            final state = PomodoroState.instance;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showHeader) ...[
                  _header(context, state),
                  const SizedBox(height: 16),
                ],
                _tabs(context, state),
                if (widget.showLongSlider &&
                    state.mode == 'long' &&
                    !state.running) ...[
                  const SizedBox(height: 12),
                  _longSlider(context, state),
                ],
                const SizedBox(height: 18),
                Center(child: _ring(context, state)),
                const SizedBox(height: 18),
                _cycleRow(context, state),
                const SizedBox(height: 18),
                _actions(context, state),
                const SizedBox(height: 14),
                Text(
                  state.running ? '通知栏常驻倒计时 · 到点会弹窗提醒' : '关闭窗口后计时继续 · 到点会提醒你',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: c.inkSoft, height: 1.6),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _phaseColor(CitroColors c, String mode) => switch (mode) {
    'short' => c.dark ? const Color(0xFFD3B77E) : const Color(0xFFB08245),
    'long' => c.dark ? const Color(0xFFA3C0C3) : const Color(0xFF5D7B80),
    _ => c.accent,
  };

  String _phaseLabel(String mode) => switch (mode) {
    'short' => '短休息',
    'long' => '长休息',
    _ => '专注',
  };

  String _phaseHint(String mode) => switch (mode) {
    'short' => '起身走走，看看远处。',
    'long' => '这次多歇一会儿，别急着回来。',
    _ => '把眼前这一件事，做完就好。',
  };

  String _statusLabel(PomodoroState state) {
    if (state.done) return '${_phaseLabel(state.mode)}完成';
    if (state.running) return '${_phaseLabel(state.mode)}中';
    if (state.remain < state.total) return '已暂停';
    return '准备开始';
  }

  Color _onAccent(CitroColors c) => c.accent.computeLuminance() > .55
      ? const Color(0xFF1B2A1E)
      : const Color(0xFFFFFDF8);

  Widget _header(BuildContext context, PomodoroState state) {
    final c = _colorsOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '番茄钟',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '一段一段地做，把心放回此刻。',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: c.accent.withAlpha(c.dark ? 34 : 22),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.spa_outlined, size: 13, color: c.accentInk),
              const SizedBox(width: 5),
              Text(
                '今日 ${state.todayMinutes} 分钟',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.accentInk,
                ),
              ),
            ],
          ),
        ),
        if (widget.showClose) ...[
          const SizedBox(width: 6),
          _PomodoroPressScale(
            scale: .92,
            child: Material(
              color: c.ink.withAlpha(10),
              shape: CircleBorder(
                side: BorderSide(color: c.line.withAlpha(110)),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).pop(),
                child: SizedBox(
                  width: 30,
                  height: 30,
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
          ),
        ],
      ],
    );
  }

  Widget _tabs(BuildContext context, PomodoroState state) {
    final items = [
      ('focus', '专注', Icons.center_focus_strong_outlined),
      ('short', '短休息', Icons.local_cafe_outlined),
      ('long', '长休息', Icons.nightlight_outlined),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _tab(context, state, items[i])),
        ],
      ],
    );
  }

  Widget _tab(
    BuildContext context,
    PomodoroState state,
    (String, String, IconData) item,
  ) {
    final c = _colorsOf(context);
    final selected = state.mode == item.$1;
    final color = _phaseColor(c, item.$1);
    return _PomodoroPressScale(
      child: Material(
        color: selected
            ? color.withAlpha(c.dark ? 56 : 30)
            : c.surface2.withAlpha(c.dark ? 50 : 120),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(
            color: selected ? color.withAlpha(140) : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => state.switchMode(item.$1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$3, size: 18, color: selected ? color : c.inkSoft),
                const SizedBox(height: 4),
                Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? color : c.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _longSlider(BuildContext context, PomodoroState state) {
    final c = _colorsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('长休时长', style: TextStyle(fontSize: 12, color: c.inkSoft)),
            const Spacer(),
            Text(
              '${state.longMinutes} 分钟',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.accentInk,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
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
    final c = _colorsOf(context);
    final color = _phaseColor(c, state.mode);
    final dimension = math
        .min(MediaQuery.sizeOf(context).width - 170, 280.0)
        .clamp(210.0, 280.0)
        .toDouble();
    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: state.progress),
            duration: const Duration(milliseconds: 980),
            curve: Curves.linear,
            builder: (context, value, _) => CustomPaint(
              size: Size.square(dimension),
              painter: _PomoRingPainter(
                progress: value,
                color: color,
                track: c.line2.withValues(alpha: .8),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.timeText,
                style: TextStyle(
                  fontSize: dimension * .225,
                  height: 1.05,
                  fontWeight: FontWeight.w400,
                  letterSpacing: .5,
                  color: c.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: state.running ? color : c.inkSoft,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusLabel(state),
                    style: TextStyle(
                      fontSize: 13,
                      color: c.inkSoft,
                      letterSpacing: .4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _phaseHint(state.mode),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.inkSoft, height: 1.6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cycleRow(BuildContext context, PomodoroState state) {
    final c = _colorsOf(context);
    final color = _phaseColor(c, state.mode);
    final doneInCycle = state.todayCount % 4;
    final active = state.mode == 'focus' && !state.done;
    final current = state.mode == 'long' ? 4 : doneInCycle + 1;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 4; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(right: 5),
                width: i == doneInCycle && active ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i < doneInCycle
                      ? color
                      : i == doneInCycle && active
                      ? color.withAlpha(90)
                      : c.line2,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
          ],
        ),
        Text(
          '第 $current / 4 轮',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: c.inkSoft,
          ),
        ),
        if (state.todayCount > 0)
          Text(
            '今日完成 ${state.todayCount} 次',
            style: TextStyle(fontSize: 12, color: c.inkSoft),
          ),
      ],
    );
  }

  Widget _actions(BuildContext context, PomodoroState state) {
    final c = _colorsOf(context);
    final icon = state.running ? Icons.pause_rounded : Icons.play_arrow_rounded;
    final label = state.running
        ? '暂停一下'
        : (state.remain < state.total && state.remain > 0 && !state.done
              ? '继续'
              : state.startLabel);
    return Row(
      children: [
        _roundButton(
          context,
          icon: Icons.replay_rounded,
          tooltip: '重新开始本阶段',
          onTap: state.reset,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 56,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: _onAccent(c),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: state.toggle,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(icon, key: ValueKey(icon), size: 22),
              ),
              label: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, .25),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _roundButton(
          context,
          icon: Icons.skip_next_rounded,
          tooltip: '跳过本阶段',
          onTap: () => _skip(state),
        ),
      ],
    );
  }

  Widget _roundButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final c = _colorsOf(context);
    return _PomodoroPressScale(
      scale: .92,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: c.surface2.withAlpha(c.dark ? 40 : 200),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.line2),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, size: 22, color: c.inkSoft),
            ),
          ),
        ),
      ),
    );
  }

  void _skip(PomodoroState state) {
    state.switchMode(state.mode == 'focus' ? 'short' : 'focus');
  }
}

/// 只做按压缩放，不接管点击，避免和外层 InkWell 重复触发。
class _PomodoroPressScale extends StatefulWidget {
  const _PomodoroPressScale({required this.child, this.scale = .96});

  final Widget child;
  final double scale;

  @override
  State<_PomodoroPressScale> createState() => _PomodoroPressScaleState();
}

class _PomodoroPressScaleState extends State<_PomodoroPressScale> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !reduce ? widget.scale : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _PomoRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  const _PomoRingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 9;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = track,
    );

    final tick = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = track;
    for (var i = 0; i < 60; i++) {
      final angle = i * math.pi / 30 - math.pi / 2;
      final long = i % 5 == 0;
      final start = radius + 11;
      final end = start + (long ? 5 : 2.5);
      canvas.drawLine(
        center + Offset(math.cos(angle) * start, math.sin(angle) * start),
        center + Offset(math.cos(angle) * end, math.sin(angle) * end),
        tick,
      );
    }

    if (progress <= .0005) return;
    final sweep = math.pi * 2 * progress.clamp(0.0, 1.0);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 13
      ..color = color.withValues(alpha: .16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, glow);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 7
        ..color = color,
    );
    final angle = -math.pi / 2 + sweep;
    canvas.drawCircle(
      center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
      5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _PomoRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}
