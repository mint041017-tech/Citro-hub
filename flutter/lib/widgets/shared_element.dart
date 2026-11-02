import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// 共享元素转场：两个路由里的同一视觉元素在切换时"飞过去"。
///
/// 规则：
/// - tag 必须在同一时刻全局唯一（同一路由里不能出现两个相同 tag）；
/// - 减少动态时自动降级为普通切换，不做飞行；
/// - 飞行时用轻微透明度和 Material 包裹，避免文本样式丢失与硬切。
class CitroHero extends StatelessWidget {
  final Object tag;
  final Widget child;
  final bool enabled;

  const CitroHero({
    super.key,
    required this.tag,
    required this.child,
    this.enabled = true,
  });

  /// 业务侧统一用这个拼 tag，避免手写字符串撞车。
  static String tagOf(String scope, Object id) => '$scope::$id';

  /// 测试用：记录飞行次数，确认 Hero 真的起飞了。
  @visibleForTesting
  static int debugFlightCount = 0;

  @override
  Widget build(BuildContext context) {
    if (!enabled || CitroMotion.reduced(context)) return child;
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      flightShuttleBuilder: _shuttle,
      child: child,
    );
  }

  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    debugFlightCount++;
    final target = toContext.widget is Hero
        ? (toContext.widget as Hero).child
        : (fromContext.widget as Hero).child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: CitroMotion.easeInOut,
      reverseCurve: CitroMotion.exit,
    );
    // 飞行中保持近乎不透明：只补 8% 透明度收尾，避免出现"半透明的物体"。
    return FadeTransition(
      opacity: Tween<double>(begin: .92, end: 1).animate(curved),
      child: Material(type: MaterialType.transparency, child: target),
    );
  }
}
