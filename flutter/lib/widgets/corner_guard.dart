import 'package:flutter/material.dart';

/// 折叠屏四角的屏幕曲率远大于普通刘海安全区，纯 SafeArea 不会避让圆角。
/// 在 Duo 上把左右上下的可用安全区各加一段，所有页面的 SafeArea 会一起生效。
class CitroDuoCornerGuard extends StatelessWidget {
  static const double inset = 16;

  final Widget child;
  final bool enabled;

  const CitroDuoCornerGuard({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          left: media.padding.left + inset,
          top: media.padding.top + inset,
          bottom: media.padding.bottom + inset,
        ),
      ),
      child: child,
    );
  }
}
