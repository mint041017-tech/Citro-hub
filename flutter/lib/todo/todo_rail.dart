import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../widgets/module_rail.dart';
import '../widgets/paper.dart';

/// 待办模块的左侧导航，待办页和专注页共用。
class TodoRail extends StatelessWidget {
  /// 'todo' / 'data' / 'focus'
  final String active;
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;

  const TodoRail({
    super.key,
    required this.active,
    required this.onSelect,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ModuleRail(
      title: switch (active) {
        'data' => '数据',
        'focus' => '专注',
        _ => '待办',
      },
      items: const [
        ('todo', '待办', AppIcons.check),
        ('data', '数据', AppIcons.board),
        ('focus', '专注', AppIcons.target),
      ],
      footer: '日程 · 复盘 · 专注',
      active: active,
      onSelect: onSelect,
      onBack: onBack,
      selectedFg: context.c.accent,
      textStyle: (size, weight, color) =>
          context.ui(size: size, weight: weight, color: color),
    );
  }
}
