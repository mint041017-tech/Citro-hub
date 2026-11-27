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
  CitroSkin lerp(covariant CitroSkin? other, double t) {
    if (other == null || identical(other, this)) return this;
    // 逐色插值：背景图换主题色时，自定义令牌跟 ColorScheme 一起渐变。
    return CitroSkin(CitroColors.lerp(colors, other.colors, t));
  }
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
  // iOS 式：主操作用背景取色派生的强调色（accent2），白字 / 深字由
  // AmbientPalette 按亮度选好放在 onAccent 里。
  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent2,
    onPrimary: colors.onAccent,
    primaryContainer: colors.surface2,
    onPrimaryContainer: colors.ink,
    secondary: colors.accent,
    onSecondary: colors.onAccent,
    secondaryContainer: colors.accentLt,
    onSecondaryContainer: colors.accentInk,
    tertiary: colors.mint,
    onTertiary: colors.onAccent,
    // Material 组件（Card、Dialog、Menu…）的 surface 必须不透明。
    surface: colors.sheet,
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
      backgroundColor: colors.sheet,
      modalBackgroundColor: colors.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      // Apple 原生 sheet：顶部大圆角 + 发丝分隔 + 拖拽条。
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CitroColors.radii.modal),
        ),
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
    // —— 控件默认值：没显式传色的控件也跟随背景派生的强调色 ——
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.accent2,
      linearTrackColor: colors.accentLt,
      circularTrackColor: Colors.transparent,
      refreshBackgroundColor: colors.sheet,
      linearMinHeight: 4,
      borderRadius: BorderRadius.circular(999),
    ),
    switchTheme: SwitchThemeData(
      // iOS 观感：白色圆钮 + 强调色轨道，关闭时灰轨。
      thumbColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
      thumbIcon: const WidgetStatePropertyAll(null),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? colors.accent
            : colors.surface2.withValues(alpha: colors.dark ? .5 : .32),
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.transparent
            : colors.line2,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.accent2,
      inactiveTrackColor: colors.accentLt,
      thumbColor: colors.accent2,
      overlayColor: colors.accent.withAlpha(0x29),
      valueIndicatorColor: colors.ink,
      valueIndicatorTextStyle: TextStyle(
        color: colors.bg,
        fontFamily: AppFonts.mono,
        fontSize: CitroType.caption,
      ),
      trackHeight: 4,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? colors.accent2 : null,
      ),
      checkColor: WidgetStatePropertyAll(colors.onAccent),
      side: BorderSide(color: colors.line2, width: 1.5),
      // iOS 勾选是圆的。
      shape: const CircleBorder(),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? colors.accent2 : colors.line2,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accentInk,
        shape: const StadiumBorder(),
        overlayColor: colors.accent.withAlpha(0x1F),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent2,
        foregroundColor: colors.onAccent,
        shape: const StadiumBorder(),
        elevation: 0,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.ink,
      contentTextStyle: TextStyle(
        color: colors.bg,
        fontFamily: AppFonts.rounded,
        fontFamilyFallback: AppFonts.bodyFallback,
        fontSize: CitroType.label,
      ),
      actionTextColor: colors.accent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.ink.withAlpha(0xEB),
        borderRadius: BorderRadius.circular(CitroColors.radii.xs),
      ),
      textStyle: TextStyle(
        color: colors.bg,
        fontFamily: AppFonts.rounded,
        fontFamilyFallback: AppFonts.bodyFallback,
        fontSize: CitroType.caption,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CitroColors.radii.modal),
        side: colors.dark
            ? BorderSide(color: colors.line)
            : BorderSide.none,
      ),
      titleTextStyle: TextStyle(
        color: colors.ink,
        fontFamily: AppFonts.rounded,
        fontFamilyFallback: AppFonts.bodyFallback,
        fontSize: CitroType.title,
        fontWeight: CitroType.strong,
      ),
      contentTextStyle: TextStyle(
        color: colors.ink2,
        fontFamily: AppFonts.rounded,
        fontFamilyFallback: AppFonts.bodyFallback,
        fontSize: CitroType.body,
        height: 1.5,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        side: BorderSide(color: colors.line),
      ),
      textStyle: TextStyle(
        color: colors.ink,
        fontFamily: AppFonts.rounded,
        fontFamilyFallback: AppFonts.bodyFallback,
        fontSize: CitroType.body,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surface2,
      selectedColor: colors.accentLt,
      side: BorderSide(color: colors.line),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        color: colors.ink2,
        fontFamily: AppFonts.rounded,
        fontFamilyFallback: AppFonts.bodyFallback,
        fontSize: CitroType.label,
      ),
      secondaryLabelStyle: TextStyle(
        color: colors.accentInk,
        fontFamily: AppFonts.rounded,
        fontFamilyFallback: AppFonts.bodyFallback,
        fontSize: CitroType.label,
      ),
      checkmarkColor: colors.accentInk,
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
  // 新页是不透明的整页（自带沉浸背景），直接推入、不做半透明：
  // 半透明的那几帧会把旧页的字透出来，和新页叠在一起。
  final page = child;
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
