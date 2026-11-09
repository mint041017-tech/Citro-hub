import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 待办模块有自己的主题色（钢青蓝），与全局的暖橙区分开。
const todoAccent = Color(0xFF7A9BBE);
const todoAccent2 = Color(0xFF5F7FA3);
const todoAccentLt = Color(0xFFC6D8E8);
const todoInkLight = Color(0xFF35506E);
const todoInkDark = Color(0xFFD3E2F2);

CitroColors todoColors(CitroColors base) => base.copyWith(
  accent: base.dark ? const Color(0xFF8FB2D4) : todoAccent,
  accent2: base.dark ? const Color(0xFF6E8FB0) : todoAccent2,
  accentLt: base.dark ? const Color(0xFFC6D8E8) : todoAccentLt,
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
