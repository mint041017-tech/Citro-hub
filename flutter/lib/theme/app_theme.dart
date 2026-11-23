import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

class CitroSkin extends ThemeExtension<CitroSkin> {
  final CitroColors colors;
  const CitroSkin(this.colors);

  @override
  CitroSkin copyWith({CitroColors? colors}) => CitroSkin(colors ?? this.colors);

  @override
  CitroSkin lerp(covariant CitroSkin? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

extension CitroContext on BuildContext {
  CitroColors get c => Theme.of(this).extension<CitroSkin>()!.colors;

  /// 正文 / 通用文字。
  TextStyle body({
    double size = CitroType.body,
    FontWeight weight = CitroType.regular,
    Color? color,
    double? height,
    double? letterSpacing,
    double? wordSpacing,
  }) => TextStyle(
    fontFamily: AppFonts.rounded,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: size,
    fontWeight: weight,
    color: color ?? c.ink,
    height: height,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
  );

  /// 标题 / 卡片主标题。圆体 700，字面圆润、存在感强。
  TextStyle heading({
    double size = CitroType.heading,
    FontWeight weight = CitroType.strong,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: AppFonts.rounded,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: size,
    fontWeight: weight,
    color: color ?? c.ink,
    height: height ?? 1.25,
    letterSpacing: letterSpacing ?? 0,
  );

  /// 展示字 / 大数字。圆体 700，用于首屏标题与关键读出。
  TextStyle display({
    double size = CitroType.display,
    FontWeight weight = CitroType.strong,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: AppFonts.rounded,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: size,
    fontWeight: weight,
    color: color ?? c.ink,
    height: height,
    letterSpacing: letterSpacing,
  );

  /// 数据 / 数字读出。等宽圆体，多行数字左右对齐不抖。
  TextStyle hand({
    double size = CitroType.body,
    Color? color,
    double? height,
    FontStyle style = FontStyle.normal,
    FontWeight weight = CitroType.medium,
  }) => TextStyle(
    fontFamily: AppFonts.mono,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: size,
    color: color ?? c.ink,
    height: height,
    fontStyle: style,
    fontWeight: weight,
  );
}

ThemeData buildCitroTheme(CitroColors colors) {
  final brightness = colors.dark ? Brightness.dark : Brightness.light;
  // 主按钮是近黑（浅色）/近白（深色）的胶囊，不是品牌橙——橙只作强调。
  // primary 与 bg 在两套主题里互为反色，因此 onPrimary 直接用 bg 即可过对比。
  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.ink,
    onPrimary: colors.bg,
    primaryContainer: colors.surface2,
    onPrimaryContainer: colors.ink,
    secondary: colors.accent,
    onSecondary: colors.onAccent,
    secondaryContainer: colors.accentLt,
    onSecondaryContainer: colors.accentInk,
    tertiary: colors.mint,
    onTertiary: colors.onAccent,
    surface: colors.surface,
    onSurface: colors.ink,
    surfaceContainerHighest: colors.surface2,
    onSurfaceVariant: colors.ink2,
    error: colors.danger,
    onError: colors.onAccent,
    errorContainer: colors.dangerSoft,
    onErrorContainer: colors.danger,
    outline: colors.line2,
    outlineVariant: colors.line,
    shadow: const Color(0xFF000000),
    scrim: colors.scrim,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.bg,
    colorScheme: scheme,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    // Apple 的控件没有 Android 水波纹：按下只做缩放与颜色变化。
    splashFactory: NoSplash.splashFactory,
  );
  return base.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: kIsWeb
          ? {
              TargetPlatform.android: CitroFastPageTransitionsBuilder(),
              TargetPlatform.iOS: CitroFastPageTransitionsBuilder(),
              TargetPlatform.macOS: CitroFastPageTransitionsBuilder(),
              TargetPlatform.windows: CitroFastSlidePageTransitionsBuilder(),
              TargetPlatform.linux: CitroFastPageTransitionsBuilder(),
              TargetPlatform.fuchsia: CitroFastPageTransitionsBuilder(),
            }
          : {
              // 四端统一使用短时长；iOS/macOS 保留 Cupertino 转场以不丢边缘返回手势。
              TargetPlatform.android: CitroFastSlidePageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.windows: CitroFastSlidePageTransitionsBuilder(),
              TargetPlatform.linux: CitroFastPageTransitionsBuilder(),
              TargetPlatform.fuchsia: CitroFastPageTransitionsBuilder(),
            },
    ),
    textTheme: base.textTheme.apply(
      bodyColor: colors.ink,
      displayColor: colors.ink,
      fontFamily: AppFonts.rounded,
      fontFamilyFallback: AppFonts.bodyFallback,
    ),
    extensions: [CitroSkin(colors)],
    dividerColor: colors.line,
    iconTheme: IconThemeData(color: colors.ink2),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      crossAxisMargin: 2,
      thumbColor: WidgetStatePropertyAll(colors.inkSoft.withAlpha(110)),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      constraints: const BoxConstraints(maxWidth: 760),
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      // Apple 原生 sheet：顶部 28pt 圆角 + 发丝分隔 + 拖拽条。
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      dragHandleColor: colors.line2,
      showDragHandle: false,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.hl,
      selectionHandleColor: colors.accent,
    ),
  );
}

/// 四端共用的页面转场骨架。
///
/// - 进场：强 ease-out，横向轻推 + 淡入，第一帧就有方向感；
/// - 旧页不额外位移/压暗：新页从透明渐入，旧页在下面继续可见，
///   形成真正的交叉过渡，而不是"上一页瞬间消失"；
/// - 退场时长由路由的 reverseDuration 控制，比进场短，收得利落；
/// - 减少动态时只保留透明度过渡，去掉所有位移。
Widget _citroPageTransition<T>({
  required BuildContext context,
  required Animation<double> animation,
  required Widget child,
  required Offset enterFrom,
}) {
  final enter = CurvedAnimation(
    parent: animation,
    curve: CitroMotion.easeOut,
    reverseCurve: CitroMotion.exit,
  );
  final reduce = CitroMotion.reduced(context);
  // 从 0 开始淡入会让旧页整段透出来，看起来像"闪一下"；
  // 起始就有 90% 不透明度，位移负责方向感，透明度只做收尾。
  final page = FadeTransition(
    opacity: Tween<double>(begin: .82, end: 1).animate(enter),
    child: child,
  );
  if (reduce) return page;
  return SlideTransition(
    position: Tween<Offset>(begin: enterFrom, end: Offset.zero).animate(enter),
    child: ScaleTransition(
      scale: Tween<double>(begin: .994, end: 1).animate(enter),
      child: page,
    ),
  );
}

/// Windows / Android：轻微的横向推入手感，去掉 Cupertino 的整页横推与边缘阴影。
class CitroFastSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const CitroFastSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _citroPageTransition(
      context: context,
      animation: animation,
      child: child,
      enterFrom: const Offset(.045, 0),
    );
  }
}

/// Web：更短的位移（.028），在保持方向感的同时避免整页重绘。
class CitroFastPageTransitionsBuilder extends PageTransitionsBuilder {
  const CitroFastPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _citroPageTransition(
      context: context,
      animation: animation,
      child: child,
      enterFrom: const Offset(.028, 0),
    );
  }
}
