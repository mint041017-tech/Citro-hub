import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/module_rail.dart';
import '../widgets/paper.dart';
import 'ledger_theme.dart';

/// 记账模块的左侧导航。
class LedgerRail extends StatelessWidget {
  /// 'home' / 'add'
  final String active;
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;

  const LedgerRail({
    super.key,
    required this.active,
    required this.onSelect,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ModuleRail(
      title: '记账',
      items: const [
        ('home', '首页', AppIcons.wallet),
        ('add', '记一笔', AppIcons.plus),
      ],
      footer: '收支 · 预算 · 复盘',
      active: active,
      onSelect: onSelect,
      onBack: onBack,
      selectedFg: context.c.accentInk,
      textStyle: (size, weight, color) =>
          context.lui(size: size, weight: weight, color: color),
    );
  }
}
