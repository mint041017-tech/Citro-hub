import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Citro 的卡片表面。
///
/// 早期用过液态玻璃，现在统一改成实色表面（奶青底 + 四色搭配），
/// 类名保留下来，各处调用点不用改。
class CitroLiquidGlass extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double radius;

  /// 玻璃内容是否要裁到圆角内。Tab 栏这类贴边容器传 `Clip.antiAlias`。
  final Clip clipBehavior;

  const CitroLiquidGlass({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.radius = 24,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final br = BorderRadius.circular(radius);
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: br,
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.card(c),
      ),
      child: clipBehavior == Clip.none
          ? child
          : ClipRRect(borderRadius: br, child: child),
    );
  }
}
