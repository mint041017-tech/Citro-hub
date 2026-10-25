import 'package:flutter/widgets.dart';

/// 非桌面端不加载 window_manager：Web 走这里，Android / iOS 也不会碰窗口 API。
class CitroDesktopShell {
  static bool get enabled => false;

  static Future<void> init() async {}

  static Widget wrap(BuildContext context, Widget child) => child;
}
