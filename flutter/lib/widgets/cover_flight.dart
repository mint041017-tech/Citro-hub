import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/motion.dart';

/// 飞行替身在 Overlay 里的身份，测试用来确认它插入后会被干净地撤掉。
const Key coverFlightKey = ValueKey('citro-cover-flight');

/// 同一个页面内的共享元素转场。
///
/// [Hero] 只在 PageRoute 之间飞行，而"食谱列表卡 → 食谱详情"是同一页面里的
/// 状态切换，所以这里用一层 Overlay 替身完成同样的效果：替身与两端使用同一份
/// 封面内容，起点严丝合缝地盖住源、终点与目标完全重合，两端在飞行期间隐藏，
/// 因此看不到双影，也没有"详情已打开、卡片还在慢慢消失"的尾段。
class CitroCoverFlight {
  CitroCoverFlight._();

  static Future<void> fly(
    BuildContext context, {
    required Rect from,
    required Rect to,
    required Widget child,
    Duration duration = const Duration(milliseconds: 420),
    Curve curve = Curves.easeOutCubic,

    /// 起飞前再解析一次精确落点：新页面刚插入时布局还没稳定，
    /// 先让替身停在起点，等布局完成再把终点定到卡片此刻的位置。
    Rect? Function()? resolveTo,
  }) async {
    if (from.isEmpty || to.isEmpty || CitroMotion.reduced(context)) return;
    var target = to;
    final overlay = Overlay.of(context, rootOverlay: true);
    final vsync = _Ticker();
    final controller = AnimationController(vsync: vsync, duration: duration);
    final entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, _) {
            final t = curve.transform(controller.value);
            final r = Rect.lerp(from, target, t)!;
            final radius = 8 + 4 * t;
            return Stack(
              key: coverFlightKey,
              children: [
                Positioned.fromRect(
                  rect: r,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x26000000),
                          blurRadius: 16 + 12 * t,
                          offset: Offset(0, 6 + 4 * t),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: child,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    overlay.insert(entry);
    if (resolveTo != null) {
      // 替身先在起点静止一帧：等新页面完成布局，再确定终点并起飞。
      // 落点因此一定是卡片此刻的位置，也不会出现"封面空一帧"的闪。
      await WidgetsBinding.instance.endOfFrame;
      final next = resolveTo();
      if (next != null && !next.isEmpty) target = next;
    }
    try {
      await controller.forward();
    } finally {
      entry.remove();
      controller.dispose();
      vsync.disposeTicker();
    }
  }
}

/// 脱离 widget 树的 TickerProvider：OverlayEntry 里没有 State 可用。
class _Ticker implements TickerProvider {
  Ticker? _ticker;

  @override
  Ticker createTicker(TickerCallback onTick) {
    _ticker = Ticker(onTick);
    return _ticker!;
  }

  void disposeTicker() {
    _ticker?.dispose();
    _ticker = null;
  }
}
