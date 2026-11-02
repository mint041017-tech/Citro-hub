import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// 一组元素的交错入场：整体只用一个 ticker，每个子项错开 40ms。
///
/// 只做一次（首帧或首次可见），不做循环；动画期间不拦截点击，
/// 只是视觉上"从纸面上浮起来"。减少动态或关闭时直接呈现终态。
class CitroStagger extends StatefulWidget {
  final List<Widget> children;
  final double rise;
  final double slide;
  final Duration itemDuration;
  final Duration step;
  final Curve curve;
  final bool enabled;

  const CitroStagger({
    super.key,
    required this.children,
    this.rise = 10,
    this.slide = 0,
    this.itemDuration = CitroMotion.staggerItem,
    this.step = CitroMotion.staggerStep,
    this.curve = CitroMotion.easeOut,
    this.enabled = true,
  });

  @override
  State<CitroStagger> createState() => _CitroStaggerState();
}

class _CitroStaggerState extends State<CitroStagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final int _totalUs;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final count = widget.children.isEmpty ? 1 : widget.children.length;
    _totalUs =
        widget.itemDuration.inMicroseconds +
        widget.step.inMicroseconds * (count - 1);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(microseconds: _totalUs),
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _start();
  }

  void _start() {
    if (_started) return;
    _started = true;
    if (!widget.enabled || CitroMotion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    _controller.value = 0;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    if (children.isEmpty) return const SizedBox.shrink();
    final itemFraction = widget.itemDuration.inMicroseconds / _totalUs;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++)
          _staggered(i, children[i], itemFraction),
      ],
    );
  }

  Widget _staggered(int i, Widget child, double itemFraction) {
    final start = (widget.step.inMicroseconds * i) / _totalUs;
    final end = (start + itemFraction).clamp(0.0, 1.0);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        // 把卡片作为 child 传入：动画期间只做搬运与合成，不再逐帧重建子树。
        child: child,
        builder: (context, child) {
          final t = end <= start
              ? 1.0
              : ((_controller.value - start) / (end - start)).clamp(0.0, 1.0);
          final eased = widget.curve.transform(t);
          if (eased >= 1) return child!;
          return Opacity(
            opacity: .35 + .65 * eased,
            child: Transform.translate(
              offset: Offset(
                widget.slide * (1 - eased),
                widget.rise * (1 - eased),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// 单个元素的入场：淡入 + 轻微上浮。适合首屏主卡片、空状态、页头。
///
/// 与 [CitroStagger] 不同，这里不插入 Column，可以直接包住滚动视图/大面板。
class CitroReveal extends StatefulWidget {
  final Widget child;
  final double rise;
  final double slide;
  final Duration delay;
  final Duration duration;
  final bool enabled;

  const CitroReveal({
    super.key,
    required this.child,
    this.rise = 10,
    this.slide = 0,
    this.delay = Duration.zero,
    this.duration = CitroMotion.staggerItem,
    this.enabled = true,
  });

  @override
  State<CitroReveal> createState() => _CitroRevealState();
}

class _CitroRevealState extends State<CitroReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
    value: 1,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || CitroMotion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    _controller.value = 0;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _progress() {
    final total = _controller.duration!.inMicroseconds;
    if (total <= 0) return 1;
    final elapsed = _controller.value * total;
    final start = widget.delay.inMicroseconds;
    final span = widget.duration.inMicroseconds;
    if (span <= 0) return 1;
    return ((elapsed - start) / span).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final eased = CitroMotion.easeOut.transform(_progress());
        if (eased >= 1) return child!;
        return Opacity(
          opacity: .35 + .65 * eased,
          child: Transform.translate(
            offset: Offset(
              widget.slide * (1 - eased),
              widget.rise * (1 - eased),
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 徽标 / 未读数出现时的弹入。只做一次，不循环，也不做键盘快捷操作反馈。
class CitroPop extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double from;

  const CitroPop({
    super.key,
    required this.child,
    this.enabled = true,
    this.from = .72,
  });

  @override
  State<CitroPop> createState() => _CitroPopState();
}

class _CitroPopState extends State<CitroPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CitroMotion.badge,
    value: 1,
  );
  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_played || !widget.enabled || CitroMotion.reduced(context)) return;
    _played = true;
    _controller.value = 0;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = CitroMotion.easeOut.transform(_controller.value);
        if (t >= 1) return child!;
        return Opacity(
          opacity: .4 + .6 * t,
          child: Transform.scale(
            scale: widget.from + (1 - widget.from) * t,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
