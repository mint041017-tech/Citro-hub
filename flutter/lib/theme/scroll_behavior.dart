import 'package:flutter/material.dart';

/// 全局关闭滚动条，保留滚轮/触控滚动与回弹手感。
class CitroScrollBehavior extends MaterialScrollBehavior {
  const CitroScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
