import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';

/// 记账模块不再有专属强调色：全 App 统一用全局品牌橙（`context.c.accent`），
/// 超支 / 预警用全局 danger。表面、描边、文字本来就继承全局。

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
          CitroSkin(context.c),
        ],
      ),
      child: child,
    );
  }
}
