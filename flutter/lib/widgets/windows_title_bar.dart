import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'paper.dart';

/// 无边框窗口的悬浮窗控：不再占用标题栏高度，直接浮在内容右上角。
///
/// 默认半透明、鼠标移入后完全显形，避免遮住页面内容。
class CitroWindowControls extends StatefulWidget {
  const CitroWindowControls({super.key});

  @override
  State<CitroWindowControls> createState() => _CitroWindowControlsState();
}

class _CitroWindowControlsState extends State<CitroWindowControls>
    with WindowListener {
  bool _maximized = false;
  bool _fullScreen = false;
  bool _hovered = false;
  Brightness? _nativeBrightness;
  Color? _nativeBackground;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refreshWindowState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshWindowState() async {
    try {
      final maximized = await windowManager.isMaximized();
      final fullScreen = await windowManager.isFullScreen();
      if (!mounted) return;
      if (maximized != _maximized || fullScreen != _fullScreen) {
        setState(() {
          _maximized = maximized;
          _fullScreen = fullScreen;
        });
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _fullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _fullScreen = false);
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  void _syncNativeTheme(Brightness brightness, Color background) {
    if (_nativeBrightness == brightness && _nativeBackground == background) {
      return;
    }
    _nativeBrightness = brightness;
    _nativeBackground = background;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await windowManager.setBrightness(brightness);
        await windowManager.setBackgroundColor(background);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final brightness = Theme.of(context).brightness;
    _syncNativeTheme(brightness, c.surface);
    if (_fullScreen) return const SizedBox.shrink();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        opacity: _hovered ? 1 : .55,
        duration: CitroMotion.hover,
        curve: CitroMotion.easeColor,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _WindowControl(
              label: '最小化',
              icon: AppIcons.minus,
              onTap: () => windowManager.minimize(),
            ),
            _WindowControl(
              label: _maximized ? '还原' : '最大化',
              icon: _maximized ? AppIcons.restore : AppIcons.maximize,
              onTap: _toggleMaximize,
            ),
            _WindowControl(
              label: '关闭',
              icon: AppIcons.close,
              destructive: true,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowControl extends StatefulWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;
  final bool destructive;

  const _WindowControl({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  @override
  State<_WindowControl> createState() => _WindowControlState();
}

class _WindowControlState extends State<_WindowControl> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final close = widget.destructive;
    final restColor = close
        ? c.stamp.withAlpha(c.dark ? 92 : 30)
        : c.surface.withAlpha(c.dark ? 190 : 220);
    final restBorder = close ? c.stamp.withAlpha(60) : c.line;
    final hoverColor = close ? c.stamp : c.hl.withAlpha(c.dark ? 42 : 145);
    final hoverBorder = close ? c.stamp : c.accent.withAlpha(110);
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          // Windows 标题栏按钮的原生高度是 32pt：视觉 28pt，命中区 32pt。
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: AnimatedScale(
                scale: _down && !CitroMotion.reduced(context) ? .94 : 1,
                duration: CitroMotion.press,
                curve: CitroMotion.easeOut,
                child: AnimatedContainer(
                  duration: CitroMotion.hover,
                  curve: CitroMotion.easeColor,
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _hover ? hoverColor : restColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _hover ? hoverBorder : restBorder,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: c.ink.withAlpha(c.dark ? 40 : 18),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: _hover ? 1 : 0),
                      duration: CitroMotion.press,
                      curve: CitroMotion.easeOut,
                      builder: (context, t, _) => AppIcon(
                        strokeSvg(widget.icon, width: 2),
                        size: 13,
                        color: Color.lerp(
                          close ? c.stamp : c.ink2,
                          close ? Colors.white : c.accentInk,
                          t,
                        )!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
