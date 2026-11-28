/// Citro 的「原生规范层」：把间距、材质、字体与触感对齐各端原生表达，
/// 同时保持 nosh 式的干净表面（大圆角、柔和阴影、中性色）：
/// - iOS / iPadOS：真实背景模糊 + 发丝描边 + 内高光（Liquid Glass 的轻量版）；
/// - Android：tonal surface（Material 的原生语言），不使用玻璃模糊；
/// - Windows / Web：半透明表面 + 发丝边（避免大面积 BackdropFilter 重绘）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_theme.dart';
import 'tokens.dart';

/// 平台能力与原生行为判定。
class CitroNative {
  const CitroNative._();

  static bool get isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// 是否启用真实背景模糊。
  ///
  /// 只在 iOS / iPadOS 打开：这是系统原生材质；Windows / Web 的
  /// BackdropFilter 会在滚动与弹层动画期间整块重绘，Android 的原生
  /// 语言则是 tonal surface 而不是玻璃。
  static bool get supportsBackdropBlur => isApple;

  /// 1 物理像素的发丝边（0.5pt @2x / 0.33pt @3x）。
  static double hairline(BuildContext context) {
    final ratio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    if (ratio <= 1) return 1;
    return (1 / ratio).clamp(0.25, 0.5);
  }

  /// Apple 的字距规范：大标题收紧，小字保持 0，避免正文挤在一起。
  static double trackingFor(double size) => size >= 20 ? -0.02 * size : 0;
}

/// 给 UI 文本用的系统无衬线样式（导航、按钮、标签、表单）。
///
/// 内容正文继续走 `context.body()`（内置 NotoSC），
/// 这里只负责"界面骨架"的文字，让四端看起来像系统自己的控件。
extension CitroNativeType on BuildContext {
  TextStyle ui({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
    FontStyle? fontStyle,
  }) {
    final colors = c;
    return TextStyle(
      fontFamily: AppFonts.rounded,
      fontFamilyFallback: AppFonts.fallback,
      fontSize: size,
      fontWeight: weight,
      color: color ?? colors.ink,
      height: height,
      letterSpacing: letterSpacing ?? CitroNative.trackingFor(size),
      fontStyle: fontStyle,
    );
  }
}

/// 玻璃 / tonal 材质的配色。采用高模糊磨砂底色 + 柔和半透白边缘高光，
/// 在透出背景色彩波动的同时保证文字与控件的可读性。
extension CitroMaterialColors on CitroColors {
  /// 导航栏、侧栏、浮动胶囊的磨砂底色。
  Color get glassTint =>
      dark ? const Color(0x5225232F) : const Color(0x8CFFFFFF);

  /// 对话框 / 弹层用的更厚实的磨砂底色，保证正文对比度。
  Color get glassTintStrong =>
      dark ? const Color(0x78262430) : const Color(0xB3FFFFFF);

  /// 磨砂玻璃的柔和高光边缘。
  Color get glassBorder =>
      dark ? const Color(0x29FFFFFF) : const Color(0x8CFFFFFF);

  /// 顶部内高光，模拟磨砂玻璃边缘漫反射。
  Color get glassHighlight =>
      dark ? const Color(0x18FFFFFF) : const Color(0x40FFFFFF);
}

/// 平台自适应的毛玻璃材质表面。
///
/// 全站统一采用磨砂雾面玻璃（高高斯模糊 + 雾化面纱 + 柔和饱和度提升 +
/// 细微漫反射边缘），兼顾清晰度与层次感。
class CitroGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool blur;
  final double? sigma;
  final Color? tint;
  final Color? borderColor;
  final bool highlight;
  final List<BoxShadow>? shadow;
  final EdgeInsetsGeometry? padding;
  final double? height;
  final double? width;

  /// 全站默认毛玻璃模糊半径，避免未显式传 sigma 时退化成清玻璃。
  static const double defaultBlurSigma = 28.0;

  const CitroGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = true,
    this.sigma,
    this.tint,
    this.borderColor,
    this.highlight = false,
    this.shadow,
    this.padding,
    this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final line = CitroNative.hairline(context);
    final radius = borderRadius.topLeft.x;
    final base = LiquidGlassSettings.ios27(context);
    final tintColor = tint ?? colors.glassTint;
    final edgeColor = borderColor ??
        (colors.dark
            ? Colors.white.withValues(alpha: .16)
            : Colors.white.withValues(alpha: .58));
    final settings = base.copyWith(
      glassColor: tintColor,
      bodyMode: GlassBodyMode.adaptive,
      shadow: shadow ?? base.shadow,
      frost: 14,
      frostOpacity: colors.dark ? 0.62 : 0.70,
      bodyShade: colors.dark ? 0.04 : 0.0,
      saturation: 1.18,
      lightIntensity: highlight
          ? (colors.dark ? 0.14 : 0.24)
          : (colors.dark ? 0.06 : 0.12),
      ambientStrength: colors.dark ? 0.04 : 0.10,
      fresnelStrength: 0,
      edgeAbsorption: 0,
      glowIntensity: 0,
      rimLight: 0,
      rimShade: 0,
      whitenStrength: colors.dark ? 0.01 : 0.08,
      blur: blur ? (sigma ?? defaultBlurSigma) : 0,
    );
    Widget surface = GlassContainer(
      width: width,
      height: height,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      quality: GlassQuality.minimal,
      useOwnLayer: true,
      settings: settings,
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      child: child,
    );
    surface = CustomPaint(
      foregroundPainter: _GlassBorderPainter(
        radius: radius,
        color: edgeColor,
        width: line,
      ),
      child: surface,
    );
    return surface;
  }
}

class _GlassBorderPainter extends CustomPainter {
  final double radius;
  final Color color;
  final double width;

  const _GlassBorderPainter({
    required this.radius,
    required this.color,
    required this.width,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(width / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius - width / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..isAntiAlias = true
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_GlassBorderPainter old) =>
      old.radius != radius || old.color != color || old.width != width;
}
