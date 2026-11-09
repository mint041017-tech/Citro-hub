import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';

/// 记账模块的主题色：更浅的柠檬黄做主色，配深橄榄文字、杏橙与薄荷状态色。
const ledgerAccent = Color(0xFFF8E7A0);
const ledgerAccent2 = Color(0xFFE2C86A);
const ledgerAccentLt = Color(0xFFFFFAE0);
const ledgerInkLight = Color(0xFF6B5A1A);
const ledgerInkDark = Color(0xFFFBF0C0);

/// 预算 / 提醒用的杏橙色。
const ledgerWarm = Color(0xFFE79A3C);

/// 超支、图表高亮用的杏红色。
const ledgerCoral = Color(0xFFE28A5E);

/// 收入、结余用的薄荷色。
const ledgerCool = Color(0xFF6FA98E);

CitroColors ledgerColors(CitroColors base) => base.copyWith(
  bg: base.dark ? base.bg : const Color(0xFFFDF8E8),
  bg2: base.dark ? base.bg2 : const Color(0xFFF9F1D2),
  surface: base.dark ? base.surface : const Color(0xFFFFFDF5),
  surface2: base.dark ? base.surface2 : const Color(0xFFFFFFFF),
  paperLine: base.dark ? base.paperLine : const Color(0xFFF5EBCB),
  line: base.dark ? base.line : const Color(0xFFF0E5C2),
  line2: base.dark ? base.line2 : const Color(0xFFE5D6A4),
  grid: base.dark ? base.grid : const Color(0x12B09030),
  accent: base.dark ? const Color(0xFFF8E7A0) : ledgerAccent,
  accent2: base.dark ? const Color(0xFFE0C25E) : ledgerAccent2,
  accentLt: base.dark ? const Color(0xFF3A3214) : ledgerAccentLt,
  accentInk: base.dark ? ledgerInkDark : ledgerInkLight,
);

/// 记账页统一放大一档字号、加一档字重。
/// 不改全局 `context.ui`，避免影响首页和其它模块。
extension LedgerTypeX on BuildContext {
  TextStyle lui({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => ui(
    size: size + 2,
    weight: _heavierWeight(weight),
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  TextStyle lheading({
    double size = 24,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => heading(
    size: size + 2,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  ).copyWith(fontWeight: FontWeight.w700);

  TextStyle ldisplay({
    double size = 28,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => display(
    size: size + 3,
    weight: _heavierWeight(weight),
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

FontWeight _heavierWeight(FontWeight weight) => switch (weight) {
  FontWeight.w400 => FontWeight.w600,
  FontWeight.w500 => FontWeight.w700,
  FontWeight.w600 => FontWeight.w700,
  _ => weight,
};

/// 给记账子树注入柠檬黄主题；首页卡片也会包一层，让入口有独立识别度。
class LedgerScope extends StatelessWidget {
  final Widget child;

  const LedgerScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [
          for (final e in theme.extensions.values)
            if (e is! CitroSkin) e,
          CitroSkin(ledgerColors(context.c)),
        ],
      ),
      child: child,
    );
  }
}
