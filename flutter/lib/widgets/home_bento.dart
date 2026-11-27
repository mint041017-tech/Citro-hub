import 'package:flutter/material.dart';

import '../theme/motion.dart';
import 'home_layout.dart';

/// 首页按格子取卡片内容：栅格只给位置，内容由首页决定。
typedef HomeCardBuilder = Widget Function(HomeSlot slot);

class HomeBento extends StatelessWidget {
  final HomeForm form;

  /// 卡片内容由首页提供，栅格只关心位置与尺寸。
  final HomeCardBuilder builder;

  const HomeBento({super.key, required this.form, required this.builder});

  @override
  Widget build(BuildContext context) {
    final slots = homeSlots(form);
    // 入场顺序按「从上到下、从左到右」阅读顺序排，而不是列表顺序。
    final order = [...slots]
      ..sort((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW =
            (constraints.maxWidth - (form.columns - 1) * form.gap) /
            form.columns;
        double top(int row) => row * (form.rowUnit + form.gap);
        double height(int rows) => rows * form.rowUnit + (rows - 1) * form.gap;
        return SizedBox(
          height: homeGridHeight(form, slots),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final slot in slots)
                Positioned(
                  left: slot.col * (cellW + form.gap),
                  top: top(slot.row),
                  width: slot.w * cellW + (slot.w - 1) * form.gap,
                  height: height(rowHeightOf(slots, slot)),
                  child: _BentoEntrance(
                    order: order.indexOf(slot),
                    child: builder(slot),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 首页卡片的交错入场：淡入 + 上浮，每张错开一个 staggerStep。
///
/// 只在首次挂载时播放一次；栅格重排（窗口缩放）不会重播。
/// 超过前 8 张的卡片不再额外延迟，整组入场控制在约 500ms 内。
/// 减少动态 / 轻量模式时直接呈现终态。
///
/// 性能：FadeTransition + SlideTransition 只改合成层属性，不逐帧 rebuild
/// 卡片子树；卡片包在 RepaintBoundary 里，位移期间不重绘内容。
class _BentoEntrance extends StatefulWidget {
  final int order;
  final Widget child;

  const _BentoEntrance({required this.order, required this.child});

  @override
  State<_BentoEntrance> createState() => _BentoEntranceState();
}

class _BentoEntranceState extends State<_BentoEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: CitroMotion.staggerItem,
    value: 1,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _ctrl,
    curve: CitroMotion.easeOut,
  );
  // 上浮约 10px：SlideTransition 按子项高度的比例位移，取 0.06 在常见卡高
  // （120–200px）下约 7–12px。
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, .06),
    end: Offset.zero,
  ).animate(_t);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (CitroMotion.lite(context)) return;
    _ctrl.value = 0;
    final delay = CitroMotion.staggerStep * widget.order.clamp(0, 8);
    Future.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position: _slide,
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}
