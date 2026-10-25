import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';
import 'paper.dart';

/// 无边框窗口的自绘标题栏：左侧手账品牌，中间可拖拽，右侧窗口三键。
class CitroWindowTitleBar extends StatefulWidget {
  final double height;

  const CitroWindowTitleBar({super.key, this.height = 38});

  @override
  State<CitroWindowTitleBar> createState() => _CitroWindowTitleBarState();
}

class _CitroWindowTitleBarState extends State<CitroWindowTitleBar>
    with WindowListener {
  bool _maximized = false;
  bool _fullScreen = false;
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
    return SizedBox(
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DragToMoveArea(
                child: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Text(
                          'Citro',
                          style: context.display(
                            size: 15,
                            color: c.ink2,
                            letterSpacing: .3,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 4),
                            Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                color: c.inkSoft.withAlpha(90),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
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
            const SizedBox(width: 10),
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

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final close = widget.destructive;
    final restColor = close ? c.stamp.withAlpha(c.dark ? 30 : 14) : c.surface2;
    final restBorder = close ? c.stamp.withAlpha(60) : c.line;
    final hoverColor = close ? c.stamp : c.hl.withAlpha(c.dark ? 42 : 145);
    final hoverBorder = close ? c.stamp : c.accent.withAlpha(110);
    final iconColor = _hover
        ? (close ? Colors.white : c.accentInk)
        : (close ? c.stamp : c.ink2);
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(left: 6, top: 5, bottom: 5),
            decoration: BoxDecoration(
              color: _hover ? hoverColor : restColor,
              shape: BoxShape.circle,
              border: Border.all(color: _hover ? hoverBorder : restBorder),
              boxShadow: [
                BoxShadow(
                  color: c.ink.withAlpha(c.dark ? 34 : 12),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: AppIcon(
                strokeSvg(widget.icon, width: 2),
                size: 13,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
