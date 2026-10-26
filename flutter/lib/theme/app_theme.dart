import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  );
  return base.copyWith(
    pageTransitionsTheme: PageTransitionsTheme(
      builders: kIsWeb
          ? const {
              TargetPlatform.android: CitroFastPageTransitionsBuilder(),
              TargetPlatform.iOS: CitroFastPageTransitionsBuilder(),
              TargetPlatform.macOS: CitroFastPageTransitionsBuilder(),
              TargetPlatform.windows: CitroFastPageTransitionsBuilder(),
              TargetPlatform.linux: CitroFastPageTransitionsBuilder(),
              TargetPlatform.fuchsia: CitroFastPageTransitionsBuilder(),
            }
          : const {
              TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
              // Windows 上保留 iPad 的横向推入 + 边缘阴影手感。
              TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
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
    bottomSheetTheme: const BottomSheetThemeData(
      constraints: BoxConstraints(maxWidth: 760),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accentInk,
      selectionColor: colors.hl,
      selectionHandleColor: colors.accent,
    ),
  );
}

/// 网页端使用短促的淡入 + 轻微右移，避免 300ms 以上的整页滑动掉帧。
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
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.012, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
