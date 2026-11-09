import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion.dart';
import 'app_image.dart';
import 'paper.dart';
import 'shared_element.dart';

/// 社区图片全屏查看（四端共用）。
///
/// 与旧版相比：
/// - 支持同一条动态里的多张图左右翻页（PageView + 键盘左右键）；
/// - 单指滑动翻页，双指缩放后自动接管平移，不会和翻页抢手势；
/// - 保留 Hero 共享元素，缩略图与全屏图之间连续过渡；
/// - 顶部计数、底部圆点、关闭与箭头都带 44pt 触控区。
class CitroImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final Object Function(int index) tagOf;
  final int cacheWidth;

  const CitroImageViewer({
    super.key,
    required this.urls,
    required this.tagOf,
    this.initialIndex = 0,
    this.cacheWidth = 900,
  });

  @override
  State<CitroImageViewer> createState() => _CitroImageViewerState();
}

class _CitroImageViewerState extends State<CitroImageViewer> {
  late final PageController _controller;
  late int _current;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = _current + delta;
    if (next < 0 || next >= widget.urls.length) return;
    if (_zoomed) setState(() => _zoomed = false);
    _controller.animateToPage(
      next,
      duration: CitroMotion.indicator,
      curve: CitroMotion.easeInOut,
    );
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top + 10;
    final bottom = media.padding.bottom + 18;
    final wide = media.size.width >= 720;
    final multi = widget.urls.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.urls.length,
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  onPageChanged: (i) => setState(() {
                    _current = i;
                    _zoomed = false;
                  }),
                  itemBuilder: (context, i) => _PhotoPage(
                    url: widget.urls[i],
                    tag: widget.tagOf(i),
                    cacheWidth: widget.cacheWidth,
                    active: i == _current,
                    onZoomChanged: (z) {
                      if (i == _current && z != _zoomed) {
                        setState(() => _zoomed = z);
                      }
                    },
                    onTap: _close,
                  ),
                ),
              ),
              Positioned(
                top: top,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    if (multi)
                      _CountPill(current: _current, total: widget.urls.length),
                    const Spacer(),
                    _CircleButton(
                      label: '关闭',
                      icon: AppIcons.close,
                      onTap: _close,
                    ),
                  ],
                ),
              ),
              if (multi && wide) ...[
                Positioned(
                  left: 14,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _ArrowButton(
                      label: '上一张',
                      icon: AppIcons.arrowLeft,
                      enabled: _current > 0,
                      onTap: () => _go(-1),
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _ArrowButton(
                      label: '下一张',
                      icon: AppIcons.arrowRight,
                      enabled: _current < widget.urls.length - 1,
                      onTap: () => _go(1),
                    ),
                  ),
                ),
              ],
              if (multi)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottom,
                  child: IgnorePointer(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < widget.urls.length; i++)
                          AnimatedContainer(
                            duration: CitroMotion.guard(
                              context,
                              CitroMotion.press,
                            ),
                            curve: CitroMotion.easeColor,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _current ? 16 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _current
                                  ? const Color(0xFFFFC078)
                                  : Colors.white.withAlpha(90),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPage extends StatefulWidget {
  final String url;
  final Object tag;
  final int cacheWidth;
  final bool active;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onTap;

  const _PhotoPage({
    required this.url,
    required this.tag,
    required this.cacheWidth,
    required this.active,
    required this.onZoomChanged,
    required this.onTap,
  });

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  final TransformationController _transform = TransformationController();
  bool _zoomed = false;
  Offset _doubleTapAt = Offset.zero;

  @override
  void didUpdateWidget(covariant _PhotoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 翻到别的图时把上一张的缩放收回来，回来时仍是完整视图。
    if (!widget.active && _zoomed) {
      _transform.value = Matrix4.identity();
      _zoomed = false;
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _syncZoom() {
    final scaled = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (scaled == _zoomed) return;
    setState(() => _zoomed = scaled);
    widget.onZoomChanged(scaled);
  }

  void _toggleDoubleTap() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
    } else {
      const scale = 2.4;
      _transform.value = Matrix4.identity()
        ..translateByDouble(
          -_doubleTapAt.dx * (scale - 1),
          -_doubleTapAt.dy * (scale - 1),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1);
    }
    _syncZoom();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: _toggleDoubleTap,
      child: IgnorePointer(
        ignoring: !_zoomed,
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 4,
          // 未放大时整个 InteractiveViewer 不参与命中测试，
          // 把单指拖动完整让给 PageView；双击放大后再接管平移与缩放。
          scaleEnabled: _zoomed,
          panEnabled: _zoomed,
          onInteractionUpdate: (_) => _syncZoom(),
          onInteractionEnd: (_) => _syncZoom(),
          child: Center(
            child: CitroHero(
              tag: widget.tag,
              child: AppImage(
                widget.url,
                fit: BoxFit.contain,
                cacheWidth: widget.cacheWidth,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    '图片加载失败',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int current;
  final int total;

  const _CountPill({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(24),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Center(
        child: Text(
          '${current + 1} / $total',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;

  const _CircleButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        scale: .92,
        hoverLift: 0,
        hoverShadow: false,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: AppIcon(
              strokeSvg(icon, width: 2),
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final String label;
  final String icon;
  final bool enabled;
  final VoidCallback onTap;

  const _ArrowButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Opacity(
        opacity: .25,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(18),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: AppIcon(
              strokeSvg(icon, width: 2),
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        scale: .92,
        hoverLift: 0,
        hoverShadow: false,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(90),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withAlpha(36)),
          ),
          child: Center(
            child: AppIcon(
              strokeSvg(icon, width: 2),
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
