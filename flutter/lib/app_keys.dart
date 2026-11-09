import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> citroNavigatorKey = GlobalKey<NavigatorState>();

/// 当前非弹层页面的路由名，供截图接收等全局入口判断是否已打开账单页。
final ValueNotifier<String?> citroActiveRoute = ValueNotifier<String?>(null);
