import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 咕噜果冻铺各端共享的棋盘视口尺寸。
///
/// 游戏内罐子按 WebView/iframe 的 innerWidth/innerHeight 布局，所以同一窗口
/// 尺寸下 Web / Windows / Android 必须拿到相同视口，罐子才会一样大。
class LiquidBoardMetrics {
  const LiquidBoardMetrics._();

  static const double maxBoardWidth = 430;
  static const double maxBoardHeight = 720;
  static const double minBoardHeight = 360;
  static const double sidePad = 14;

  /// 与 GameScaffold 顶栏 / GameLiveBar / 操作按钮保持同源。
  static const double headHeight = 64;
  static const double liveBarHeight = 44.7 + 12;
  static const double actionReserve = 42 + 12;
  static const double edgePad = 8;

  static double boardWidth(double availableWidth) =>
      math.max(0, math.min(availableWidth, maxBoardWidth));

  /// 标准 GameScaffold：横屏没有顶栏和「正在玩」条，竖屏两者都占高。
  static double standardBoardHeight(Size screen, EdgeInsets safe) {
    final landscape = screen.width > screen.height;
    final chrome = landscape
        ? safe.top + edgePad + actionReserve + edgePad
        : safe.top +
              headHeight +
              liveBarHeight +
              safe.bottom +
              edgePad +
              actionReserve +
              edgePad;
    return _clampHeight(screen.height - chrome);
  }

  /// 手机紧凑壳（竖屏）：虽然本壳没有操作按钮，也预留同样高度，
  /// 让同尺寸窗口下与 Web 的棋盘子寸严格一致。
  static double compactBoardHeight(Size screen, EdgeInsets safe) {
    final chrome =
        safe.top +
        headHeight +
        liveBarHeight +
        safe.bottom +
        edgePad +
        actionReserve +
        edgePad;
    return _clampHeight(screen.height - chrome);
  }

  static double _clampHeight(double value) =>
      value.clamp(minBoardHeight, maxBoardHeight).toDouble();
}
