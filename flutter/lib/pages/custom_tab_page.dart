import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/custom_tab.dart';
import 'cook_page.dart';
import '../ledger/ledger_page.dart';
import '../tingyu/tingyu_page.dart';
import '../todo/todo_page.dart';

/// Tab 栏第 4 格：展示当前选中的模块（默认待办，长按 Tab 可切换）。
class CustomTabPage extends StatelessWidget {
  const CustomTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final module = context.app.customTabModule;
    return switch (module) {
      CustomTabModule.todo => const TodoPage(),
      CustomTabModule.tingyu => const TingyuPage(),
      CustomTabModule.ledger => const LedgerPage(),
      CustomTabModule.cook => const CookPage(),
    };
  }
}
