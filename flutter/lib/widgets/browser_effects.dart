import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/platform.dart' as platform;

class CitroBackdropBlur extends StatelessWidget {
  final double sigma;
  final Widget child;

  const CitroBackdropBlur({
    super.key,
    required this.sigma,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Windows 的 BackdropFilter 在弹层动画期间会整块重绘背景，
    // 统一只保留半透明遮罩，避免弹层打开时掉帧。
    if (kIsWeb || platform.isWindows) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}
