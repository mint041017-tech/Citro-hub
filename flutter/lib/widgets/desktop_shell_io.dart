import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app_keys.dart';
import '../theme/motion.dart';
import 'windows_title_bar.dart';

/// Windows 桌面壳：完全无边框窗口 + iPad 内容区。
///
/// TitleBarStyle.hidden 去掉原生标题栏，保留 DWM 圆角/阴影；四周缩放由 DragToResizeArea 补齐。
/// 窗口三键不再占一条标题栏，而是悬浮在内容右上角；顶部只留一条窄拖拽区。
class CitroDesktopShell {
  static bool get enabled => Platform.isWindows;

  /// 顶部安全留白：让页面 SafeArea 自动避开悬浮窗控。
  static const double titleBarHeight = 30;

  /// 悬浮窗控（三枚 26px 圆钮 + 间距 + 右边距）占用的宽度。
  static const double windowControlsWidth = 118;

  /// 顶栏内容需要避让的窗控宽度：只有 Windows 悬浮窗控占位，手机/平板等
  /// 其他运行在 io 平台的端不应预留这段空白，否则右上角的控件会离屏幕边缘很远。
  static double get windowControlsInset => enabled ? windowControlsWidth : 0;

  static final _lifecycle = _WindowLifecycle();
  static bool _hooked = false;

  static Future<void> init() async {
    if (!enabled) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1200, 720),
      minimumSize: Size(780, 560),
      center: true,
      backgroundColor: Color(0xFFFBF7EC),
      title: 'Citro',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      // 先透明再显示，随后用约 160ms 淡入，避免窗口"啪"地出现。
      try {
        await windowManager.setOpacity(0);
      } catch (_) {}
      await windowManager.show();
      await windowManager.focus();
      unawaited(_fadeOpacity(from: 0, to: 1, durationMs: 160));
    });
    await windowManager.setMinimumSize(const Size(780, 560));
    if (!_hooked) {
      _hooked = true;
      try {
        await windowManager.setPreventClose(true);
        windowManager.addListener(_lifecycle);
      } catch (_) {}
    }
  }

  static Future<void> _fadeOpacity({
    required double from,
    required double to,
    required int durationMs,
  }) async {
    const frameMs = 16;
    final steps = (durationMs / frameMs).ceil().clamp(1, 60);
    try {
      for (var i = 1; i <= steps; i++) {
        // 用 ease-out 收尾：开头快、结尾稳，避免窗口透明度线性变化显得生硬。
        final t = CitroMotion.easeOut.transform(i / steps);
        await windowManager.setOpacity(from + (to - from) * t);
        await Future<void>.delayed(const Duration(milliseconds: frameMs));
      }
      await windowManager.setOpacity(to);
    } catch (_) {}
  }

  static Widget wrap(BuildContext context, Widget child) {
    if (!enabled) return child;
    final media = MediaQuery.maybeOf(context);
    final content = media == null
        ? child
        : MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(
                top: media.padding.top > titleBarHeight
                    ? media.padding.top
                    : titleBarHeight,
              ),
            ),
            child: child,
          );
    return DragToResizeArea(
      resizeEdgeSize: 6,
      child: Stack(
        children: [
          Positioned.fill(child: _DesktopShortcuts(child: content)),
          // 顶部窄拖拽带：双击还原/最大化，右侧为悬浮窗控让位。
          const Positioned(
            top: 0,
            left: 0,
            right: windowControlsWidth,
            height: titleBarHeight,
            child: _WindowDragArea(),
          ),
          // 窗控在 Navigator 之外，必须给一个 Material 祖先，
          // 否则会继承 MaterialApp 的黄色双下划线兜底文本样式。
          const Positioned(
            top: 4,
            right: 10,
            child: RepaintBoundary(
              child: Material(
                type: MaterialType.transparency,
                child: CitroWindowControls(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部透明拖拽带：拖动移动窗口，双击在最大化/还原之间切换。
///
/// 外层 opaque 命中测试只是为了挡住下方页面点击，双击/拖动由 DragToMoveArea 处理。
class _WindowDragArea extends StatelessWidget {
  const _WindowDragArea();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: const MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: DragToMoveArea(child: SizedBox.expand()),
      ),
    );
  }
}

class _WindowLifecycle with WindowListener {
  bool _closing = false;

  @override
  void onWindowClose() {
    unawaited(_close());
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await CitroDesktopShell._fadeOpacity(from: 1, to: 0, durationMs: 120);
    try {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (_) {}
  }
}

class _DesktopShortcuts extends StatelessWidget {
  final Widget child;

  const _DesktopShortcuts({required this.child});

  void _back() {
    final nav = citroNavigatorKey.currentState;
    if (nav != null && nav.canPop()) nav.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _back,
        const SingleActivator(LogicalKeyboardKey.browserBack): _back,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
      },
      child: child,
    );
  }
}
