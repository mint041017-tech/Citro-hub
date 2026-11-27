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

/// 数字计数过渡：值变化时从旧值快速滚到新值（[CitroMotion.counter]，≤300ms）。
///
/// 首次出现直接显示终值，不从 0 数起；减少动态时直接切换。
/// 配合等宽数字字体（XiaolaiMono / context.hand）使用，滚动时宽度不抖。
/// 只重建一个 Text，代价可忽略，适合卡片里的关键读数。
class CitroCountUp extends StatelessWidget {
  final num value;
  final TextStyle? style;

  /// 自定义格式（如金额、百分比）；缺省取整显示。
  final String Function(double v)? format;
  final TextAlign? textAlign;

  const CitroCountUp(
    this.value, {
    super.key,
    this.style,
    this.format,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final end = value.toDouble();
    String text(double v) => format?.call(v) ?? v.round().toString();
    if (CitroMotion.reduced(context)) {
      return Text(text(end), style: style, textAlign: textAlign);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: end),
      duration: CitroMotion.counter,
      curve: CitroMotion.easeOut,
      builder: (context, v, _) =>
          Text(text(v), style: style, textAlign: textAlign),
    );
  }
}

/// 勾选 / 完成时的轻弹：[checked] 从 false 变 true 时用 settle 曲线
/// 从 0.82 弹到 1；取消勾选不弹。只动 transform，不重绘子树。
class CitroCheckPop extends StatefulWidget {
  final bool checked;
  final Widget child;

  const CitroCheckPop({super.key, required this.checked, required this.child});

  @override
  State<CitroCheckPop> createState() => _CitroCheckPopState();
}

class _CitroCheckPopState extends State<CitroCheckPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: CitroMotion.check,
    value: 1,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: .82,
    end: 1,
  ).animate(CurvedAnimation(parent: _ctrl, curve: CitroMotion.settle));

  @override
  void didUpdateWidget(CitroCheckPop old) {
    super.didUpdateWidget(old);
    if (widget.checked && !old.checked && !CitroMotion.reduced(context)) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

/// 带增删过渡的竖排列表：新子项展开 + 淡入，被移除的子项收起 + 淡出，
/// 而不是瞬间出现 / 消失。
///
/// - 每个子项必须带唯一 [Key]（按 key 比对增删）。
/// - 只有「正在进出」的子项持有动画控制器，静止的子项就是原样的 widget，
///   列表再长也没有常驻开销；首帧已有的子项不播入场。
/// - 减少动态时直接增删。适合几十条以内的卡片列表（待办列、评论等），
///   长列表请继续用 ListView.builder。
class CitroAnimatedColumn extends StatefulWidget {
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final Duration duration;

  const CitroAnimatedColumn({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.duration = CitroMotion.size,
  });

  @override
  State<CitroAnimatedColumn> createState() => _CitroAnimatedColumnState();
}

class _ColumnEntry {
  final Key key;
  Widget widget;
  AnimationController? ctrl;
  bool removing = false;

  _ColumnEntry(this.key, this.widget);
}

class _CitroAnimatedColumnState extends State<CitroAnimatedColumn>
    with TickerProviderStateMixin {
  late List<_ColumnEntry> _entries = [
    for (final w in widget.children) _ColumnEntry(w.key!, w),
  ];

  AnimationController _controller({required bool entering}) {
    final ctrl = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: CitroMotion.sizeExit,
      value: entering ? 0 : 1,
    );
    return ctrl;
  }

  @override
  void didUpdateWidget(CitroAnimatedColumn old) {
    super.didUpdateWidget(old);
    final reduce = CitroMotion.reduced(context);
    final byKey = {for (final e in _entries) e.key: e};
    final newKeys = {for (final w in widget.children) w.key!};
    final next = <_ColumnEntry>[];
    for (final w in widget.children) {
      final existing = byKey[w.key!];
      if (existing != null && !existing.removing) {
        existing.widget = w;
        next.add(existing);
      } else {
        // 新出现（或正在收起时又被加回来）：展开入场。
        existing?.ctrl?.dispose();
        final e = _ColumnEntry(w.key!, w);
        if (!reduce) {
          final ctrl = _controller(entering: true);
          e.ctrl = ctrl;
          ctrl.forward().whenComplete(() {
            if (!mounted || e.ctrl != ctrl) return;
            ctrl.dispose();
            setState(() => e.ctrl = null);
          });
        }
        next.add(e);
      }
    }
    if (!reduce) {
      // 被移除的项留在原位置收起：插到它旧前邻居的后面。
      for (var i = 0; i < _entries.length; i++) {
        final e = _entries[i];
        // 仍在新列表里（含收起途中又被加回来的）：已在上面处理。
        if (newKeys.contains(e.key)) continue;
        if (!e.removing) {
          e.removing = true;
          e.ctrl?.dispose();
          final ctrl = _controller(entering: false);
          e.ctrl = ctrl;
          ctrl.reverse().whenComplete(() {
            if (!mounted || e.ctrl != ctrl) return;
            ctrl.dispose();
            setState(() => _entries.remove(e));
          });
        }
        var at = 0;
        for (var j = i - 1; j >= 0; j--) {
          final idx = next.indexOf(_entries[j]);
          if (idx >= 0) {
            at = idx + 1;
            break;
          }
        }
        next.insert(at, e);
      }
    } else {
      for (final e in _entries) {
        if (!newKeys.contains(e.key)) e.ctrl?.dispose();
      }
    }
    _entries = next;
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.ctrl?.dispose();
    }
    super.dispose();
  }

  Widget _wrap(_ColumnEntry e) {
    final ctrl = e.ctrl;
    if (ctrl == null) return KeyedSubtree(key: e.key, child: e.widget);
    final curved = CurvedAnimation(
      parent: ctrl,
      curve: CitroMotion.easeOut,
      reverseCurve: CitroMotion.exit,
    );
    Widget child = FadeTransition(
      opacity: curved,
      child: SizeTransition(
        sizeFactor: curved,
        alignment: Alignment.topCenter,
        child: e.widget,
      ),
    );
    if (e.removing) child = IgnorePointer(child: child);
    return KeyedSubtree(key: e.key, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.crossAxisAlignment,
      children: [for (final e in _entries) _wrap(e)],
    );
  }
}
