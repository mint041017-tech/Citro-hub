import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app_keys.dart';
import 'windows_title_bar.dart';

/// Windows 桌面壳：完全无边框窗口 + iPad 内容区。
///
/// TitleBarStyle.hidden 去掉原生标题栏，保留 DWM 圆角/阴影；四周缩放由 DragToResizeArea 补齐。
class CitroDesktopShell {
  static bool get enabled => Platform.isWindows;

  static const double titleBarHeight = 38;

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
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setMinimumSize(const Size(780, 560));
  }

  static Widget wrap(BuildContext context, Widget child) {
    if (!enabled) return child;
    return DragToResizeArea(
      resizeEdgeSize: 6,
      child: Column(
        children: [
          // 标题栏在 Navigator 之外，必须给一个 Material 祖先，
          // 否则会继承 MaterialApp 的黄色双下划线兜底文本样式。
          const RepaintBoundary(
            child: Material(
              type: MaterialType.transparency,
              child: CitroWindowTitleBar(height: titleBarHeight),
            ),
          ),
          Expanded(child: _DesktopShortcuts(child: child)),
        ],
      ),
    );
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
