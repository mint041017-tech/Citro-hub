import 'package:flutter/widgets.dart';

/// 只在所属路由 / Tab 可见（[TickerMode] 开启）时监听 [listenable]。
///
/// 后台页面仍保留状态和布局，但不再响应播放计时、轮询这类高频通知；
/// 重新可见时 [didChangeDependencies] 会触发一次 rebuild，用最新状态补齐。
/// 与 [ListenableBuilder] 的参数保持一致，可直接替换。
class ActiveListenableBuilder extends StatefulWidget {
  const ActiveListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
  });

  final Listenable listenable;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  State<ActiveListenableBuilder> createState() =>
      _ActiveListenableBuilderState();
}

class _ActiveListenableBuilderState extends State<ActiveListenableBuilder> {
  bool _active = true;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode 由 RootShell（切 Tab）和 Navigator（路由被遮挡）维护。
    _active = TickerMode.valuesOf(context).enabled;
  }

  @override
  void didUpdateWidget(covariant ActiveListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_onChanged);
      widget.listenable.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    // 不可见时不重建；回到前台的那一帧会由 didChangeDependencies 自动刷新。
    if (!_active) return;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.child);
}