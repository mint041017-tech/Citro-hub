import 'package:flutter/widgets.dart';

/// 统一动效参数：曲线取 Emil Kowalski 的 UI 动效基准，
/// 时长控制在 300ms 以内，页面转场按端区分（桌面更短）。
class CitroMotion {
  CitroMotion._();

  /// 进场/退场：强 ease-out，cubic-bezier(0.23, 1, 0.32, 1)。
  static const Curve easeOut = Curves.easeOutQuint;

  /// 屏内移动/变形：cubic-bezier(0.77, 0, 0.175, 1)。
  static const Curve easeInOut = Curves.easeInOutQuart;

  /// 悬停、颜色变化。
  static const Curve easeColor = Curves.easeOutCubic;

  /// 抽屉式曲线，保留给底部弹层类交互。
  static const Curve drawer = Cubic(0.32, 0.72, 0, 1);

  static const Duration press = Duration(milliseconds: 150);
  static const Duration popover = Duration(milliseconds: 180);
  static const Duration modal = Duration(milliseconds: 220);
  static const Duration pageDesktop = Duration(milliseconds: 160);
  static const Duration pageDesktopReverse = Duration(milliseconds: 140);
  static const Duration pageTouch = Duration(milliseconds: 220);
  static const Duration pageTouchReverse = Duration(milliseconds: 200);
  static const Duration toast = Duration(milliseconds: 180);
  static const Duration toastReverse = Duration(milliseconds: 140);
  static const Duration size = Duration(milliseconds: 200);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
