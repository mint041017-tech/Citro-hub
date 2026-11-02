import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 四端统一动效语言（iOS / Android / Windows / Web）。
///
/// 取值遵循 Emil Kowalski 的界面动效基准：
/// - 曲线用强 ease-out / ease-in-out，不用系统自带的弱曲线；
/// - 进场慢一点、退场快一点（非对称），让界面"回得更利落"；
/// - UI 动效时长压在 300ms 以内，只有整页/浮层允许接近上限；
/// - 所有时长在 `MediaQuery.disableAnimations` 下自动归零。
///
/// 端差异只体现在时长和位移比例上，曲线与节奏保持一致，
/// 这样同一个操作在手机、桌面和网页上"手感"是同一个产品。
class CitroMotion {
  CitroMotion._();

  // ---------------------------------------------------------------------------
  // 曲线
  // ---------------------------------------------------------------------------

  /// 进场/退场：强 ease-out，cubic-bezier(0.23, 1, 0.32, 1)。
  /// 第一帧就有明显位移，操作立刻有回应。
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);

  /// 屏内移动/变形：cubic-bezier(0.77, 0, 0.175, 1)。
  static const Curve easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// 悬停、颜色、轻量状态变化：接近 easeOutCubic。
  static const Curve easeColor = Cubic(0.33, 1, 0.68, 1);

  /// 抽屉式曲线，底部弹层与手势回弹共用。
  static const Curve drawer = Cubic(0.32, 0.72, 0, 1);

  /// 退场曲线：加速离开，不与进场共用同一条曲线。
  /// ease-out 的进场 + ease-in 的退场，收尾干脆不拖沓。
  static const Curve exit = Cubic(0.4, 0, 1, 1);

  /// 强调位移（跨页共享元素、指示器滑动）。
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1);

  /// 轻微回弹：只给装饰性动效（徽标、贴纸），不做大位移。
  static const Curve settle = Cubic(0.34, 1.56, 0.64, 1);

  // ---------------------------------------------------------------------------
  // 时长（所有 UI 动效 < 300ms）
  // ---------------------------------------------------------------------------

  /// 按下反馈（缩放），必须短到"手感即时"。
  static const Duration press = Duration(milliseconds: 120);

  /// 悬停 / 聚焦 / 颜色过渡。
  static const Duration hover = Duration(milliseconds: 160);

  /// tooltip、小气泡。
  static const Duration popover = Duration(milliseconds: 180);

  /// 弹窗进场。窗口本身的位移/缩放略慢于内容，视觉更稳。
  static const Duration modal = Duration(milliseconds: 280);
  static const Duration modalReverse = Duration(milliseconds: 200);

  /// 底部弹层：抽屉曲线需要一点惯性，仍控制在 300ms 内。
  static const Duration sheet = Duration(milliseconds: 300);
  static const Duration sheetReverse = Duration(milliseconds: 220);

  /// 整页转场：桌面/网页更短，触屏端留一点位移时间。
  static const Duration pageDesktop = Duration(milliseconds: 220);
  static const Duration pageDesktopReverse = Duration(milliseconds: 150);
  static const Duration pageTouch = Duration(milliseconds: 280);
  static const Duration pageTouchReverse = Duration(milliseconds: 200);

  /// Tab / 侧栏页切换：与整页转场同一节奏，但略短，避免"等页面"。
  static const Duration tab = Duration(milliseconds: 280);
  static const Duration tabDesktop = Duration(milliseconds: 220);

  /// 共享指示器滑动（Tab 胶囊、侧栏高亮）。比页面切换稍慢一点，
  /// 让"高亮先到、内容后到"，形成连贯的引导。
  static const Duration indicator = Duration(milliseconds: 260);
  static const Duration indicatorDesktop = Duration(milliseconds: 200);

  static const Duration toast = Duration(milliseconds: 180);
  static const Duration toastReverse = Duration(milliseconds: 140);
  static const Duration size = Duration(milliseconds: 200);

  /// 首屏卡片交错入场：每张 40ms 间隔，整组不超过 300ms。
  static const Duration staggerStep = Duration(milliseconds: 40);
  static const Duration staggerItem = Duration(milliseconds: 220);

  /// 徽标 / 未读数的弹入。
  static const Duration badge = Duration(milliseconds: 180);

  // ---------------------------------------------------------------------------
  // 物理弹簧（手势、可中断动效）
  // ---------------------------------------------------------------------------

  /// 常规回落：无回弹，跟手。
  static const SpringDescription snappy = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 40,
  );

  /// 轻微回弹：装饰性元素、卡面翻转。
  static const SpringDescription bouncy = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 26,
  );

  /// 柔和：整页/大面板（避免弹簧过冲造成大面积重绘）。
  static const SpringDescription gentle = SpringDescription(
    mass: 1,
    stiffness: 240,
    damping: 30,
  );

  // ---------------------------------------------------------------------------
  // 端差异
  // ---------------------------------------------------------------------------

  /// 桌面（Windows / Web）：位移更小、时长更短。
  static bool get desktopLike =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.windows;

  /// Tab 页切换时长。
  static Duration get tabLength => desktopLike ? tabDesktop : tab;

  /// 共享指示器滑动时长。
  static Duration get indicatorLength =>
      desktopLike ? indicatorDesktop : indicator;

  /// 底部弹层统一动画参数。四端共用，只由 reduce 决定是否关闭。
  static AnimationStyle sheetStyle(BuildContext context) => reduced(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          curve: drawer,
          duration: sheet,
          reverseCurve: exit,
          reverseDuration: sheetReverse,
        );

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// 无障碍：减少动态时保留透明度过渡，只去掉位移/缩放。
  static Duration guard(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  static Curve curveFor(BuildContext context, Curve curve) =>
      reduced(context) ? Curves.linear : curve;
}
