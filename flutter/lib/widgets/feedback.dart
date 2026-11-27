import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'paper.dart';

/// 统一的空状态：圆形强调底上的图标 + 一句标题 + 可选说明 + 可选按钮。
///
/// 颜色全部取自 [CitroColors]，随首页背景派生的主题色一起变。
/// 用来替代各页面零散的「暂无数据」纯文字或空白。
class CitroEmptyState extends StatelessWidget {
  final Widget? icon;
  final String title;
  final String? hint;
  final String? action;
  final VoidCallback? onAction;

  /// 紧凑模式：卡片内、列表里用，图标与留白都收小一档。
  final bool compact;

  const CitroEmptyState({
    super.key,
    this.icon,
    required this.title,
    this.hint,
    this.action,
    this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final badge = compact ? 48.0 : 64.0;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: compact ? AppSpacing.x2 : AppSpacing.x4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: badge,
            height: badge,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [c.accentLt, c.accentLt.withAlpha(0x66)],
              ),
              border: Border.all(color: c.accent.withAlpha(0x40)),
            ),
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(color: c.accentInk, size: badge * .42),
              child: icon ?? const Icon(Icons.inbox_outlined),
            ),
          ),
          SizedBox(height: compact ? 12 : AppSpacing.x2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.heading(
              size: compact ? CitroType.bodyLg : CitroType.title,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                hint!,
                textAlign: TextAlign.center,
                style: context.body(
                  size: CitroType.meta,
                  color: c.inkSoft,
                  height: 1.5,
                ),
              ),
            ),
          ],
          if (action != null && onAction != null) ...[
            SizedBox(height: compact ? 12 : AppSpacing.x2),
            CitroButton(
              label: action!,
              onPressed: onAction,
              style: CitroButtonStyle.accent,
              height: compact ? 36 : 42,
            ),
          ],
        ],
      ),
    );
  }
}

/// 骨架屏占位块：accentLt 底上一道缓慢扫过的高光。
///
/// 减少动态时只显示静态色块。多个骨架块共用时，各自的动画相位一致，
/// 整组看起来是同一道光扫过。
class CitroSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double? radius;

  /// 圆形（头像占位）。
  final bool circle;

  const CitroSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius,
    this.circle = false,
  });

  /// 一组文字行占位：最后一行收短，更像真实段落。
  static Widget lines({int count = 3, double height = 12, double gap = 10}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(height: gap),
          FractionallySizedBox(
            widthFactor: i == count - 1 && count > 1 ? .6 : 1,
            child: CitroSkeleton(height: height),
          ),
        ],
      ],
    );
  }

  /// 动态流占位：头像圆 + 名字行 + 两行正文，按真实帖子卡排版。
  static Widget feed({int count = 3}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.x1 + 4),
            child: CitroCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      CitroSkeleton(width: 36, circle: true),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(
                              widthFactor: .35,
                              child: CitroSkeleton(height: 12),
                            ),
                            SizedBox(height: 6),
                            FractionallySizedBox(
                              widthFactor: .2,
                              child: CitroSkeleton(height: 9),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  CitroSkeleton.lines(count: 2),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 卡片网格占位（食谱、卡牌收藏）：方图块 + 标题行。
  static Widget grid({
    int count = 6,
    int columns = 2,
    double aspect = 1,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
  }) {
    return Padding(
      padding: padding,
      child: GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: aspect,
        children: [
          for (var i = 0; i < count; i++)
            LayoutBuilder(
              builder: (context, box) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CitroSkeleton(
                      width: box.maxWidth,
                      height: double.infinity,
                      radius: CitroColors.radii.inner,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CitroSkeleton(width: box.maxWidth * .6, height: 11),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  State<CitroSkeleton> createState() => _CitroSkeletonState();
}

class _CitroSkeletonState extends State<CitroSkeleton>
    with SingleTickerProviderStateMixin {
  /// 扫光相位 0..1。只驱动 CustomPaint 重绘，不触发 build。
  final ValueNotifier<double> _phase = ValueNotifier(0);
  late final Ticker _ticker = createTicker((_) {
    // 相位取全局时钟：同屏多个骨架块的高光同步扫过，像同一道光。
    final period = CitroMotion.shimmer.inMilliseconds;
    _phase.value = (DateTime.now().millisecondsSinceEpoch % period) / period;
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 轻量模式（Web / 入门机 / 减少动态）只给静态色块。
    // Ticker 来自 TickerProviderStateMixin：页面被盖住或不在前台时自动静音。
    if (CitroMotion.lite(context)) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = c.dark ? c.surface2 : c.accentLt.withAlpha(0xB3);
    final shine = Color.lerp(base, const Color(0xFFFFFFFF), c.dark ? .06 : .5)!;
    final h = widget.circle ? (widget.width ?? widget.height) : widget.height;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.width,
          height: h,
          child: CustomPaint(
            painter: _ShimmerPainter(
              phase: _phase,
              animate: _ticker.isActive,
              base: base,
              shine: shine,
              circle: widget.circle,
              radius: widget.radius ?? CitroColors.radii.xs,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  final ValueNotifier<double> phase;
  final bool animate;
  final Color base;
  final Color shine;
  final bool circle;
  final double radius;

  _ShimmerPainter({
    required this.phase,
    required this.animate,
    required this.base,
    required this.shine,
    required this.circle,
    required this.radius,
  }) : super(repaint: phase);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()..isAntiAlias = true;
    if (animate) {
      // 高光带宽为元素宽的 ~60%，从左外侧扫到右外侧。
      final t = phase.value * 2.4 - 1.2;
      paint.shader = LinearGradient(
        begin: Alignment(t - .6, 0),
        end: Alignment(t + .6, 0),
        colors: [base, shine, base],
      ).createShader(rect);
    } else {
      paint.color = base;
    }
    if (circle) {
      canvas.drawOval(rect, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) =>
      old.animate != animate ||
      old.base != base ||
      old.shine != shine ||
      old.circle != circle ||
      old.radius != radius;
}
