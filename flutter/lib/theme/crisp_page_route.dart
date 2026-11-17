import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'motion.dart';

/// 工具页专用路由：进场沿用全站节奏，退场干净利落。
///
/// 全站 [_CitroPageRoute] 的退场只把页面右移 4.5%、淡到 82%，页面在视觉
/// 上几乎没动就被路由移除了，收尾像"抖一下消失"。灵敏度 / 玩法抽签 /
/// 视野live / 一起看这几页内容重、停留久，退场改成完整淡出 + 轻微右移、
/// 时长压到 150ms —— 返回时一眼就知道页面真的走掉了。
///
/// iOS / macOS 例外：继续走系统的 Cupertino 转场。Cupertino 转场本身
/// 是整页滑出，不存在"淡一点就消失"的问题，而且只有它会在路由层装上
/// 左缘滑动返回手势；自定义 transitionsBuilder 会把手势一起绕过去。
class CitroCrispPageRoute<T> extends MaterialPageRoute<T> {
  CitroCrispPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration =>
      CitroMotion.desktopLike ? CitroMotion.pageDesktop : CitroMotion.pageTouch;

  @override
  Duration get reverseTransitionDuration => CitroMotion.desktopLike
      ? CitroMotion.pageCrispReverseDesktop
      : CitroMotion.pageCrispReverse;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final platform = Theme.of(context).platform;
    // Web 的主题统一用自定义转场（见 app_theme.dart 的 kIsWeb 分支），
    // 没有 Cupertino 手势可保留，仍然走完整淡出。
    if (!kIsWeb &&
        (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS)) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    if (CitroMotion.reduced(context)) return child;
    return _CrispPageTransition(animation: animation, child: child);
  }
}

class _CrispPageTransition extends StatefulWidget {
  const _CrispPageTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_CrispPageTransition> createState() => _CrispPageTransitionState();
}

class _CrispPageTransitionState extends State<_CrispPageTransition> {
  // 必须只建一次并 dispose：每帧重建 CurvedAnimation 会丢掉它的方向记忆，
  // 进场没走完就返回时，反向曲线会突然套在半程的 value 上，页面一帧闪灭。
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: widget.animation,
    curve: CitroMotion.easeOut,
    // 退场曲线独立：加速离开，不跟进场共用 ease-out。
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        final t = _curved.value.clamp(0.0, 1.0);
        // 进出一律用同一条连续公式，不按 status 切换：否则进场途中返回，
        // 透明度会在同一帧从 ~0.9 跳到 ~0.5。进场从 0 淡入，退场归零。
        final opacity = t;
        final dx = (1 - t) * .055;
        final scale = .994 + .006 * t;
        Widget page = Opacity(opacity: opacity, child: child);
        page = FractionalTranslation(translation: Offset(dx, 0), child: page);
        page = Transform.scale(scale: scale, child: page);
        return page;
      },
      child: widget.child,
    );
  }
}
