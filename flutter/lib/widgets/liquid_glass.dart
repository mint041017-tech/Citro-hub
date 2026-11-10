import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';


/// Citro 的液态玻璃表面。
///
/// 材质本身由 [LiquidGlassWidgets.wrap] 里的 `GlassThemeData.ios27()` 统一提供
/// （Apple `glassEffect(.regular)` 的校准值：半透明体 + 镜面高光 + 菲涅尔边缘 +
/// 边缘吸收 + 投影），这里只负责形状、质量和裁剪，让整站玻璃是同一套。
///
/// 质量固定用 [GlassQuality.premium]：Impeller 设备（iPhone / 新版安卓）走完整
/// 着色器管线，Skia / Web 会被 [AdaptiveGlass] 自动降级成轻量着色器，
/// 不会出现「整块渲染不出来」的情况。
class CitroLiquidGlass extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double radius;

  /// 玻璃内容是否要裁到圆角内。Tab 栏这类贴边容器传 `Clip.antiAlias`。
  final Clip clipBehavior;

  const CitroLiquidGlass({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.radius = 24,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      // 独立图层：Tab 栏、负一屏这类「浮在内容之上」的表面各自成层，
      // 不进分组渲染，避免和页面里的其它玻璃互相串味。
      useOwnLayer: true,
      quality: GlassQuality.premium,
      width: width,
      height: height,
      padding: padding,
      clipBehavior: clipBehavior,
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      child: child,
    );
  }
}
