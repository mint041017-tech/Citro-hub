import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 待办模块不再有专属的钢青蓝：全 App 统一用全局品牌橙（`context.c.accent`）。
///
/// 保留空的 [todoColors]，让既有的 `TodoScope` 调用点不用改。
CitroColors todoColors(CitroColors base) => base;

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
