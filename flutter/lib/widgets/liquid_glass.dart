import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Citro 的液态玻璃表面。
///
/// 材质本身由 [LiquidGlassWidgets.wrap] 里的 `GlassThemeData.ios27()` 统一提供
/// （Apple `glassEffect(.regular)` 的校准值：半透明体 + 镜面高光 + 菲涅尔边缘 +
/// 边缘吸收 + 投影），这里只负责形状、质量和裁剪，让整站玻璃是同一套。
///
/// 全站玻璃统一**无边框**：ios27 预设自带一圈 rim 亮边（看起来像描边），
/// 这里把它和边缘吸收一起去掉，只留磨砂 / 折射 / 投影。
class CitroLiquidGlass extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double radius;

  /// 玻璃内容是否要裁到圆角内。Tab 栏这类贴边容器传 `Clip.antiAlias`。
  final Clip clipBehavior;

  /// 覆盖材质；为空时用 [borderlessSettings]（去掉边缘光的无边框玻璃）。
  final LiquidGlassSettings? settings;

  const CitroLiquidGlass({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.radius = 24,
    this.clipBehavior = Clip.antiAlias,
    this.settings,
  });

  /// 无边框玻璃材质：在当前主题的 ios27 预设上去掉 rim 亮边与边缘吸收。
  static LiquidGlassSettings borderlessSettings(BuildContext context) {
    final brightness = Theme.maybeBrightnessOf(context) ?? Brightness.light;
    final base = brightness == Brightness.dark
        ? LiquidGlassSettings.ios27Dark
        : LiquidGlassSettings.ios27Light;
    return base.copyWith(
      rimLight: 0,
      rimShade: 0,
      edgeAbsorption: 0,
      glowIntensity: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      // 独立图层：Tab 栏、负一屏这类「浮在内容之上」的表面各自成层，
      // 不进分组渲染，避免和页面里的其它玻璃互相串味。
      useOwnLayer: true,
      // standard 档：轻量 fragment shader，官方基准比 premium 的
      // 全管线 shader 快 5–10 倍。premium 每帧对身后全宽内容做实时
      // 折射模糊 —— Tab 栏身后正是滚动中的首页，滚动时每帧都在变，
      // 120Hz 的帧预算被它吃掉大半，是「滑动掉帧」的主要渲染负担。
      // 视觉差异在深色磨砂下几乎不可辨。
      quality: GlassQuality.standard,
      settings: settings ?? borderlessSettings(context),
      width: width,
      height: height,
      padding: padding,
      clipBehavior: clipBehavior,
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      child: child,
    );
  }
}
