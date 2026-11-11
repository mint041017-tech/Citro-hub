import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 待办模块保留自己的钢青蓝，和全站暖橙区分开（产品明确要求）。
///
/// 只覆盖 accent / accent2 / accentLt / accentInk 四个语义字段，
/// 表面、描边、文字全部继承全局，避免同一 App 内出现两套底色。
const todoAccent = Color(0xFF7A9BBE);
const todoAccent2 = Color(0xFF5F7FA3);
const todoAccentLt = Color(0xFFC6D8E8);
const todoInkLight = Color(0xFF35506E);
const todoInkDark = Color(0xFFD3E2F2);

CitroColors todoColors(CitroColors base) => base.copyWith(
  accent: base.dark ? const Color(0xFF8FB2D4) : todoAccent,
  accent2: base.dark ? const Color(0xFF6E8FB0) : todoAccent2,
  // 深色下 accentLt 是「软强调底」，必须是暗色块，不能沿用浅色值。
  accentLt: base.dark ? const Color(0xFF22303E) : todoAccentLt,
  accentInk: base.dark ? todoInkDark : todoInkLight,
);

/// 给子树注入待办专用的钢青蓝。首页其他卡片仍使用全局配色。
class TodoScope extends StatelessWidget {
  final Widget child;

  const TodoScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [
          for (final e in theme.extensions.values)
            if (e is! CitroSkin) e,
          CitroSkin(todoColors(context.c)),
        ],
      ),
      child: child,
    );
  }
}
