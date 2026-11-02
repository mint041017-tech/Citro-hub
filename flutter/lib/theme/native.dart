/// Apple UI Design System – Verified: 8pt Grid, SF Pro Typography,
/// Material-Depth, Natural Spring Motion
///
/// Citro 的「原生规范层」：在不改动手账配色与纸感的前提下，
/// 把间距、材质、字体与触感对齐 Apple HIG，并保留各端自己的原生表达：
/// - iOS / iPadOS：真实背景模糊 + 发丝描边 + 内高光（Liquid Glass 的轻量版）；
/// - Android：tonal surface（Material 的原生语言），不使用玻璃模糊；
/// - Windows / Web：半透明纸面 + 发丝边（避免大面积 BackdropFilter 重绘）。
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'tokens.dart';

/// 平台能力与原生行为判定。
class CitroNative {
  const CitroNative._();

  static bool get isWeb => kIsWeb;

  static bool get isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// 指针型设备（桌面 / 网页）使用悬停与轻位移，触屏不使用。
  static bool get pointerLike =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

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

  /// UI 文字使用的系统字体族。缺省返回系统默认字体。
  static String? get uiFontFamily => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => '.SF UI Text',
    TargetPlatform.android => 'Roboto',
    TargetPlatform.windows => 'Segoe UI',
    TargetPlatform.linux => 'Noto Sans',
    _ => null,
  };

  /// 中文回退：优先本机系统中文字体，最后落到应用内置的 NotoSC，
  /// 保证四端中文形态一致。
  static List<String> get uiFontFallback => switch (defaultTargetPlatform) {
    TargetPlatform.iOS ||
    TargetPlatform.macOS => const ['PingFang SC', 'NotoSC'],
    TargetPlatform.android => const ['Noto Sans CJK SC', 'NotoSC'],
    TargetPlatform.windows => const ['Microsoft YaHei', 'NotoSC'],
    _ => const ['NotoSC'],
  };

  /// Apple 的字距规范：标题 >20pt 用 -0.022em，正文用 -0.011em。
  static double trackingFor(double size) =>
      size >= 20 ? -0.022 * size : -0.011 * size;
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
      fontFamily: CitroNative.uiFontFamily,
      fontFamilyFallback: CitroNative.uiFontFallback,
      fontSize: size,
      fontWeight: weight,
      color: color ?? colors.ink,
      height: height,
      letterSpacing: letterSpacing ?? CitroNative.trackingFor(size),
      fontStyle: fontStyle,
    );
  }
}

/// 玻璃 / tonal 材质的配色。亮色沿用纸面暖调，暗色对齐 iOS 的
/// secondarySystemBackground，避免"发蓝的深灰"。
extension CitroMaterialColors on CitroColors {
  /// 导航栏、侧栏、浮动胶囊的底色。
  Color get glassTint =>
      dark ? const Color(0xC71C1C23) : const Color(0xC4FBF7EC);

  /// 对话框 / 弹层用的更实一点的底色，保证正文对比度。
  Color get glassTintStrong =>
      dark ? const Color(0xE61C1C23) : const Color(0xF2FBF7EC);

  /// 发丝描边：亮色 black 10%，暗色 white 16%。
  Color get glassBorder =>
      dark ? const Color(0x29FFFFFF) : const Color(0x1A000000);

  /// 顶部内高光，模拟玻璃边缘折射。
  Color get glassHighlight =>
      dark ? const Color(0x14FFFFFF) : const Color(0x4DFFFFFF);

  /// 玻璃投影：比纸片阴影更收敛。
  Color get glassShadow =>
      dark ? const Color(0x59000000) : const Color(0x245A4A2C);

  /// Android / 非玻璃端使用的 tonal 表面。
  Color get tonalSurface => surface2;
}

/// 平台自适应的材质表面。
///
/// - iOS / iPadOS：背景模糊 + 半透明 + 发丝边 + 内高光；
/// - Android：半透明 tonal 表面 + 发丝边；
/// - Windows / Web：半透明纸面 + 发丝边（不做整块模糊）。
class CitroGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool blur;
  final double sigma;
  final Color? tint;
  final Color? borderColor;
  final bool highlight;
  final List<BoxShadow>? shadow;
  final EdgeInsetsGeometry? padding;
  final double? height;
  final double? width;

  const CitroGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.blur = true,
    this.sigma = 20,
    this.tint,
    this.borderColor,
    this.highlight = true,
    this.shadow,
    this.padding,
    this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final line = CitroNative.hairline(context);
    final radius = borderRadius;
    final tintColor = tint ?? colors.glassTint;

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: tintColor,
        borderRadius: radius,
        border: Border.all(
          color: borderColor ?? colors.glassBorder,
          width: line,
        ),
        boxShadow: shadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (highlight)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [colors.glassHighlight, Colors.transparent],
                        stops: const [0, .55],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ],
        ),
      ),
    );

    // BackdropFilter 必须在半透明底色之下，并且裁到圆角内，
    // 否则模糊会溢出到卡片外部。
    if (blur && CitroNative.supportsBackdropBlur) {
      surface = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
          child: surface,
        ),
      );
    }

    if (height != null || width != null) {
      surface = SizedBox(height: height, width: width, child: surface);
    }
    return surface;
  }
}

/// 材质阴影（导航栏 / 侧栏 / 浮动胶囊）。
extension CitroChromeShadow on AppShadows {
  List<BoxShadow> chrome(CitroColors c) => [
    BoxShadow(
      color: c.glassShadow,
      blurRadius: 24,
      spreadRadius: -14,
      offset: const Offset(0, 10),
    ),
  ];
}
