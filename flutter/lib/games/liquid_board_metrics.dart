import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 咕噜果冻铺各端共享的棋盘视口尺寸。
///
/// 游戏内罐子按 WebView/iframe 的 innerWidth/innerHeight 布局，所以同一窗口
/// 尺寸下 Web / Windows / Android 必须拿到相同视口，罐子才会一样大。
///
/// 尺寸只从**内容区约束**推导（[boardSizeFor]），不读整屏尺寸：
/// GameScaffold 的 board 槽位把棋盘放进滚动区，只有宽度有界、高度无界，
/// 所以高度按宽度折算；手机紧凑壳的棋盘在 Expanded 里，宽高都有界，
/// 就直接用可用高度，绝不撑破父级。
class LiquidBoardMetrics {
  const LiquidBoardMetrics._();

  static const double maxBoardWidth = 430;
  static const double maxBoardHeight = 720;
  static const double minBoardHeight = 360;
  static const double sidePad = 14;

  /// 高度折算比例：430 宽 → 645 高，接近原版手机视口的竖屏比例。
  static const double boardHeightRatio = 1.5;

  /// 与 GameScaffold 顶栏 / GameLiveBar / 操作按钮保持同源。
  ///
  /// 保留给下面这套按整屏尺寸折算的旧算法，新代码请用 [boardSizeFor]。
  static const double headHeight = 64;
  static const double liveBarHeight = 44.7 + 12;
  static const double actionReserve = 42 + 12;
  static const double edgePad = 8;

  /// 可用宽度 → 棋盘宽度（封顶 [maxBoardWidth]）。
  static double boardWidth(double availableWidth) =>
      math.max(0, math.min(availableWidth, maxBoardWidth));

  /// 内容区约束 → 棋盘高度。
  ///
  /// [maxHeight] 有界（紧凑壳的 Expanded）时按可用高度收，最多 [maxBoardHeight]；
  /// 无界（GameScaffold 的滚动 board 区）时按宽度折算，夹在可玩区间内。
  static double boardHeightFor({
    required double width,
    double maxHeight = double.infinity,
  }) {
    if (maxHeight.isFinite) {
      return math.max(0, math.min(maxHeight, maxBoardHeight));
    }
    return _clampHeight(width * boardHeightRatio);
  }

  /// 内容区约束 → 棋盘视口尺寸。两维都来自父级 [LayoutBuilder] 的 constraints。
  static Size boardSizeFor({
    required double maxWidth,
    double maxHeight = double.infinity,
  }) {
    final w = boardWidth(maxWidth);
    return Size(w, boardHeightFor(width: w, maxHeight: maxHeight));
  }

  /// 标准 GameScaffold 的旧算法：按整屏尺寸扣掉顶栏 / 正在玩 / 操作行。
  ///
  /// 保留给 `test/liquid_board_metrics_test.dart`；页面不要再用它——
  /// 整屏尺寸在横屏 / 带侧栏时算出来的高度会裁掉棋盘。
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

  /// 手机紧凑壳（竖屏）的旧算法：虽然本壳没有操作按钮，也预留同样高度，
  /// 让同尺寸窗口下与 Web 的棋盘子寸严格一致。
  ///
  /// 保留给 `test/liquid_board_metrics_test.dart`；页面改用 [boardSizeFor]。
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
