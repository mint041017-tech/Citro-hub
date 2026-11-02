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
  CitroSkin get skin => Theme.of(this).extension<CitroSkin>()!;

  TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: AppFonts.noto,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: size,
    fontWeight: weight,
    color: color ?? c.ink,
    height: height,
    letterSpacing: letterSpacing,
  );

  TextStyle display({
    double size = 24,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: AppFonts.kalam,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: size,
    fontWeight: weight,
    color: color ?? c.ink,
    height: height,
    letterSpacing: letterSpacing,
  );

  TextStyle heading({
    double size = 23,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: AppFonts.zcool,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: size,
    fontWeight: FontWeight.w400,
    color: color ?? c.ink,
    height: height ?? 1.2,
    letterSpacing: letterSpacing ?? 0.46,
  );

  TextStyle hand({
    double size = 14,
    Color? color,
    double? height,
    FontStyle style = FontStyle.normal,
  }) => TextStyle(
    fontFamily: AppFonts.caveat,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: size,
    color: color ?? c.inkSoft,
    height: height,
    fontStyle: style,
  );
}

ThemeData buildCitroTheme(CitroColors colors) {
  final brightness = colors.dark ? Brightness.dark : Brightness.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.surface,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: colors.accent,
          brightness: brightness,
        ).copyWith(
          primary: colors.accent,
          secondary: colors.mint,
          surface: colors.surface,
          onSurface: colors.ink,
        ),
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    // Apple 的控件没有 Android 水波纹：按下只做缩放与颜色变化。
    splashFactory: NoSplash.splashFactory,
  );
  return base.copyWith(
    pageTransitionsTheme: PageTransitionsTheme(
      builders: kIsWeb
          ? const {
              TargetPlatform.android: CitroFastPageTransitionsBuilder(),
              TargetPlatform.iOS: CitroFastPageTransitionsBuilder(),
              TargetPlatform.macOS: CitroFastPageTransitionsBuilder(),
              TargetPlatform.windows: CitroFastSlidePageTransitionsBuilder(),
              TargetPlatform.linux: CitroFastPageTransitionsBuilder(),
              TargetPlatform.fuchsia: CitroFastPageTransitionsBuilder(),
            }
          : const {
              // 四端统一使用短时长；iOS/macOS 保留 Cupertino 转场以不丢边缘返回手势。
              // Android 不再使用 450ms 的 FadeForwards，避免同一操作在手机上明显更慢。
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
      fontFamily: AppFonts.noto,
      fontFamilyFallback: AppFonts.bodyFallback,
    ),
    extensions: [CitroSkin(colors)],
    dividerColor: colors.line,
    iconTheme: IconThemeData(color: colors.ink2),
    bottomSheetTheme: BottomSheetThemeData(
      constraints: const BoxConstraints(maxWidth: 760),
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      // Apple 原生 sheet：顶部 20pt 圆角 + 发丝分隔 + 拖拽条。
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      dragHandleColor: colors.line2,
      showDragHandle: false,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accentInk,
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
///   （弹层只盖住局部，若让旧页常驻压暗会在浮层打开期间一直变灰。）
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
/// 位移比例小，避免每帧大面积栅格化。
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
