import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 待办模块不再使用固定的钢青蓝，改为跟随全局（背景派生）配色。
///
/// 之前的产品要求保留待办钢青蓝，现已更改为跟随首页背景取色结果，
/// 使待办主题色与全站主题色保持一致，随背景图变化。
///
/// 所有相关常量已移除，相关组件直接使用 context.c 获取全局配色。

/// [已废弃] 待办模块现在直接使用全局配色，不再覆盖主题色。
/// 保留此函数以确保现有代码能正常编译，但实际返回原始配色。
CitroColors todoColors(CitroColors base) => base;

/// 待办模块的配色作用域，现已简化为透传全局主题。
/// 移除颜色覆盖后，TodoScope 仅作为组件容器，确保代码结构不变。
class TodoScope extends StatelessWidget {
  final Widget child;

  const TodoScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
