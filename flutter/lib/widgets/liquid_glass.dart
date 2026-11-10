import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../theme/app_theme.dart';

/// Citro 的液态玻璃表面。
///
/// 底层是 liquid_glass_widgets 的着色器玻璃（真模糊 + 折射 + 镜面高光 +
/// 边缘色散），在这里把配色接到 CitroSkin 的亮 / 暗 token 上，
/// 让玻璃材质和整站一致，而不是用包自带的 iOS 灰。
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
    final c = context.c;
    return GlassContainer(
      // 独立图层：Tab 栏、负一屏这类「浮在内容之上」的表面各自成层，
      // 不进分组渲染，避免和页面里的其它玻璃互相串味。
      useOwnLayer: true,
      // standard 走轻量着色器，Skia / Impeller / Web 都能出效果；
      // premium 只在 Impeller 上有效，Web 与部分安卓机会整块渲染不出来。
      quality: GlassQuality.standard,
      width: width,
      height: height,
      padding: padding,
      clipBehavior: clipBehavior,
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      settings: LiquidGlassSettings(
        // 底色：亮色给一层薄白，暗色给一层薄白 + 更透，
        // 让背后的页面内容透上来，玻璃才有「是页面的一部分」的感觉。
        glassColor: c.dark ? const Color(0x33FFFFFF) : const Color(0xE6FFFFFF),
        blur: 18,
        thickness: 1.4,
        chromaticAberration: .5,
        refractiveIndex: 1.34,
        lightIntensity: 1,
        lightAngle: GlassDefaults.lightAngle,
        saturation: 1.15,
        specularSharpness: GlassSpecularSharpness.medium,
        whitenStrength: c.dark ? .05 : .14,
        edgeAbsorption: .12,
        rimLight: .35,
        shadowElevation: 1,
      ),
      child: child,
    );
  }
}
