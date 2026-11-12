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
/// 同样先按宽度折算，再用可用高度收底，绝不撑破父级。
class LiquidBoardMetrics {
  const LiquidBoardMetrics._();

  static const double maxBoardWidth = 430;
  static const double maxBoardHeight = 720;
  static const double minBoardHeight = 360;

  /// 高度折算比例：430 宽 → 645 高，接近原版手机视口的竖屏比例。
  static const double boardHeightRatio = 1.5;

  /// 可用宽度 → 棋盘宽度（封顶 [maxBoardWidth]）。
  static double boardWidth(double availableWidth) =>
      math.max(0, math.min(availableWidth, maxBoardWidth));

  /// 内容区约束 → 棋盘高度。
  ///
  /// 先按宽度折算（[boardHeightRatio]，夹在可玩区间内）；[maxHeight] 有界时
  /// 再按可用高度收底，绝不撑破父级。Web 与紧凑壳因此共用同一套宽度折算，
  /// 同一窗口拿到相同视口。
  static double boardHeightFor({
    required double width,
    double maxHeight = double.infinity,
  }) {
    final byWidth = _clampHeight(width * boardHeightRatio);
    if (!maxHeight.isFinite) return byWidth;
    return math.max(0, math.min(byWidth, maxHeight));
  }

  /// 内容区约束 → 棋盘视口尺寸。两维都来自父级 [LayoutBuilder] 的 constraints。
  static Size boardSizeFor({
    required double maxWidth,
    double maxHeight = double.infinity,
  }) {
    final w = boardWidth(maxWidth);
    return Size(w, boardHeightFor(width: w, maxHeight: maxHeight));
  }

  static double _clampHeight(double value) =>
      value.clamp(minBoardHeight, maxBoardHeight).toDouble();
}
