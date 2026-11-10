import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';

/// 记账模块的专用强调色（暖杏），只覆盖全局 accent 一个语义字段。
///
/// 表面 / 描边 / 文字 / 粉彩底全部继承全局：旧版给记账注入了一整套柠檬黄主题
/// （bg/surface/line 都换掉），深色下 accent 还变成浅黄，与全局品牌橙脱节。
const ledgerAccent = Color(0xFFE79A3C);
const ledgerAccent2 = Color(0xFFD0832B);
const ledgerAccentLt = Color(0xFFFFF3DE);
const ledgerInkLight = Color(0xFF8A5312);
const ledgerInkDark = Color(0xFFFFD9AE);

/// 预算 / 提醒用的杏橙色。
const ledgerWarm = Color(0xFFE79A3C);

/// 超支、图表高亮用的杏红色。
const ledgerCoral = Color(0xFFE28A5E);

/// 收入、结余用的薄荷色。
const ledgerCool = Color(0xFF6FA98E);

/// 只改强调色；深色下连 accent 也保持全局品牌橙，保证同一 App 内一致。
CitroColors ledgerColors(CitroColors base) => base.copyWith(
  accent: base.dark ? base.accent : ledgerAccent,
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
  ).copyWith(fontWeight: CitroType.strong);

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

  /// 金额 / 数字读出：等宽，多行金额左右对齐不抖。
  TextStyle lhand({
    double size = 16,
    Color? color,
    double? height,
    FontWeight weight = CitroType.medium,
  }) => hand(size: size, color: color, height: height, weight: weight);
}

FontWeight _heavierWeight(FontWeight weight) => switch (weight) {
  FontWeight.w400 => CitroType.medium,
  FontWeight.w500 => CitroType.strong,
  FontWeight.w600 => CitroType.strong,
  _ => weight,
};

/// 给记账子树注入专用强调色；首页卡片也会包一层，让入口有独立识别度。
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
