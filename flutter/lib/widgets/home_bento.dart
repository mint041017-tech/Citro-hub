import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'home_layout.dart';
import 'modal.dart';
import 'paper.dart';

typedef HomeCardBuilder = Widget Function(HomeSlot slot);

/// 首页栅格：手机 / iPad / Windows 共用一套「列 × 行」坐标系。
///
/// 普通态只负责按保存的布局摆放卡片；编辑态叠加拖拽换位与右下角缩放，
/// 所有改动写回 [HomeLayoutStore]，下次启动直接复现。
class HomeBento extends StatefulWidget {
  final HomeLayoutKey layoutKey;

  /// 当前是否处于布局编辑态。
  final bool editing;

  /// 卡片内容由首页提供，栅格只关心位置与尺寸。
  final HomeCardBuilder builder;

  /// 首页外层滚动容器，编辑时用于边缘自动滚动。
  final ScrollController? scrollController;

  const HomeBento({
    super.key,
    required this.layoutKey,
    required this.editing,
    required this.builder,
    this.scrollController,
  });

  @override
  State<HomeBento> createState() => _HomeBentoState();
}

class _HomeBentoState extends State<HomeBento> {
  String? _activeKey;
  HomeSlot? _startSlot;
  Offset _startTopLeft = Offset.zero;
  Size _startSize = Size.zero;
  Offset _pointerStart = Offset.zero;
  Offset _pointerDelta = Offset.zero;
  double _scrollAccum = 0;
  bool _resizing = false;
  Timer? _edgeTimer;
  double _edgeDir = 0;
  late HomeForm _form;
  late double _cellW;
  late double _totalWidth;

  bool get _dragging => _activeKey != null;

  @override
  void initState() {
    super.initState();
    _form = widget.layoutKey.form;
  }

  @override
  void didUpdateWidget(covariant HomeBento oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layoutKey != widget.layoutKey) {
      _form = widget.layoutKey.form;
    }
    if (!widget.editing && oldWidget.editing) {
      _cancelInteraction();
    }
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    super.dispose();
  }

  void _cancelInteraction() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _edgeDir = 0;
    if (!mounted) return;
    setState(() {
      _activeKey = null;
      _startSlot = null;
      _resizing = false;
      _pointerDelta = Offset.zero;
      _scrollAccum = 0;
    });
  }

  // ---------------------------------------------------------------------------
  // 几何换算
  // ---------------------------------------------------------------------------

  double _x(int col) => col * (_cellW + _form.gap);

  double _y(int row) => row * (_form.rowUnit + _form.gap);

  Rect _rectOf(HomeSlot slot) => Rect.fromLTWH(
    _x(slot.col),
    _y(slot.row),
    slot.w * _cellW + (slot.w - 1) * _form.gap,
    slot.h * _form.rowUnit + (slot.h - 1) * _form.gap,
  );

  HomeSlot _snap(Rect rect, HomeSlot base) {
    final col = (rect.left / (_cellW + _form.gap)).round().clamp(
      0,
      _form.columns - base.w,
    );
    final row = (rect.top / (_form.rowUnit + _form.gap)).round().clamp(
      0,
      _form.maxRows - base.h,
    );
    return base.copyWith(col: col, row: row);
  }

  double get _gridHeight {
    final slots = HomeLayoutStore.instance.visibleSlots(widget.layoutKey);
    if (slots.isEmpty) return 180;
    var bottom = 0;
    for (final slot in slots) {
      bottom = math.max(bottom, slot.bottom);
    }
    final preview = _previewSlot();
    if (preview != null) bottom = math.max(bottom, preview.bottom);
    return math.max(80, _y(bottom) - _form.gap);
  }

  HomeSlot? _previewSlot() {
    if (!_dragging || _startSlot == null) return null;
    final base = _startSlot!;
    if (!_resizing) {
      final rect = _visualRect(base);
      return _snap(rect, base);
    }
    final nextW = _snappedW(base);
    final nextH = _snappedH(base);
    return base.copyWith(w: nextW, h: nextH);
  }

  Rect _visualRect(HomeSlot slot) {
    final rect = _rectOf(slot);
    if (slot.key != _activeKey) return rect;
    if (_resizing) {
      final width = math.max(48.0, _startSize.width + _pointerDelta.dx);
      final height = math.max(40.0, _startSize.height + _pointerDelta.dy);
      return Rect.fromLTWH(rect.left, rect.top, width, height);
    }
    final left = (_startTopLeft.dx + _pointerDelta.dx)
        .clamp(0.0, math.max(0.0, _totalWidth - rect.width))
        .toDouble();
    final top = math.max(
      0.0,
      _startTopLeft.dy + _pointerDelta.dy + _scrollAccum,
    );
    return Rect.fromLTWH(left, top, rect.width, rect.height);
  }

  int _snappedW(HomeSlot base) {
    final raw =
        (_startSize.width + _pointerDelta.dx + _form.gap) /
        (_cellW + _form.gap);
    return raw.round().clamp(1, _form.columns - base.col).toInt();
  }

  int _snappedH(HomeSlot base) {
    final raw =
        (_startSize.height + _pointerDelta.dy + _form.gap) /
        (_form.rowUnit + _form.gap);
    return raw.round().clamp(1, _form.maxRows - base.row).toInt();
  }

  // ---------------------------------------------------------------------------
  // 拖拽 / 缩放
  // ---------------------------------------------------------------------------

  void _beginInteraction(
    HomeSlot slot,
    Offset global, {
    required bool resizing,
  }) {
    final rect = _rectOf(slot);
    setState(() {
      _activeKey = slot.key;
      _startSlot = slot;
      _startTopLeft = rect.topLeft;
      _startSize = rect.size;
      _pointerStart = global;
      _pointerDelta = Offset.zero;
      _scrollAccum = 0;
      _resizing = resizing;
    });
    if (!resizing) _startEdgeWatch();
  }

  void _updatePointer(Offset global) {
    if (!_dragging) return;
    setState(() {
      _pointerDelta = global - _pointerStart;
    });
    _edgeDir = _edgeDirection(global);
  }

  void _startEdgeWatch() {
    _edgeTimer?.cancel();
    _edgeTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_dragging || _edgeDir == 0) return;
      final controller = widget.scrollController;
      if (controller == null || !controller.hasClients) return;
      final before = controller.offset;
      controller.jumpTo(
        (before + _edgeDir * 10).clamp(
          controller.position.minScrollExtent,
          controller.position.maxScrollExtent,
        ),
      );
      final moved = controller.offset - before;
      if (moved == 0) return;
      setState(() {
        _scrollAccum += moved;
      });
    });
  }

  double _edgeDirection(Offset global) {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return 0;
    final height = media.size.height;
    if (global.dy < 120) return -1;
    if (global.dy > height - 140) return 1;
    return 0;
  }

  void _finishInteraction() {
    final active = _activeKey;
    final base = _startSlot;
    if (active == null || base == null) {
      _cancelInteraction();
      return;
    }
    final store = HomeLayoutStore.instance;
    final preview = _previewSlot();
    var ok = true;
    if (_resizing) {
      final w = _snappedW(base);
      final h = _snappedH(base);
      ok = store.resize(widget.layoutKey, base.id, w, h, item: base.item);
    } else if (preview != null) {
      ok = store.move(
        widget.layoutKey,
        base.id,
        preview.col,
        preview.row,
        item: base.item,
      );
    }
    if (!ok && mounted) {
      AppToast.show(context, '这里放不下，换一个位置试试');
    }
    _cancelInteraction();
  }

  /// 键盘 / 读屏用户的替代移动方式：每次挪一格。
  void _nudge(HomeSlot slot, int dc, int dr) {
    final col = (slot.col + dc).clamp(0, _form.columns - slot.w);
    final row = (slot.row + dr).clamp(0, _form.maxRows - slot.h);
    final ok = HomeLayoutStore.instance.move(
      widget.layoutKey,
      slot.id,
      col,
      row,
      item: slot.item,
    );
    if (!ok && mounted) {
      AppToast.show(context, '这里放不下，换一个位置试试');
    }
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final store = HomeLayoutStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final slots = store.visibleSlots(widget.layoutKey);
        return LayoutBuilder(
          builder: (context, constraints) {
            _form = widget.layoutKey.form;
            final gap = _form.gap;
            final cols = _form.columns;
            _cellW = (constraints.maxWidth - gap * (cols - 1)) / cols;
            _totalWidth = constraints.maxWidth;
            if (slots.isEmpty) {
              return _EmptyBoard(
                onAdd: () => showAddCardSheet(
                  context: context,
                  layoutKey: widget.layoutKey,
                ),
              );
            }
            final preview = _previewSlot();
            final active = _activeKey;
            final ordered = [
              ...slots.where((s) => s.key != active),
              ...slots.where((s) => s.key == active),
            ];
            return SizedBox(
              height: _gridHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (widget.editing && preview != null)
                    _Ghost(
                      rect: _rectOf(preview),
                      free: store.canPlace(widget.layoutKey, preview),
                    ),
                  for (final slot in ordered) _positioned(slot, preview),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _positioned(HomeSlot slot, HomeSlot? preview) {
    final isActive = slot.key == _activeKey;
    final rect = isActive ? _visualRect(slot) : _rectOf(slot);
    final reduce = CitroMotion.reduced(context);
    final child = _cell(slot);
    // 始终使用同一种 Positioned?Positioned 组件：拖动时若在 Positioned /
    // AnimatedPositioned 之间切换，子树会被销毁重建，正在进行，
    // 手势也会随 recognizer?recognizer 一起丢失，后续 onPanUpdate 不再触发。
    return AnimatedPositioned(
      key: ValueKey(slot.key),
      duration: reduce || isActive ? Duration.zero : CitroMotion.size,
      curve: CitroMotion.easeOut,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      // 每张卡片独立图层：滚动或单卡重绘时不会牵动整块首页。
      child: RepaintBoundary(child: child),
    );
  }

  /// 删除前先确认，避免编辑态误触卡片内部的垃圾桶。
  Future<void> _confirmDelete(HomeSlot slot) async {
    final label = homeCardLabel(slot);
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('删除「$label」卡片？', style: context.heading(size: 19)),
            const SizedBox(height: 8),
            Text(
              '删除后可以在「添加卡片」里随时加回来。',
              textAlign: TextAlign.center,
              style: context.body(size: 12, color: ctx.c.inkSoft),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '取消',
                    outlined: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AccentButton(
                    text: '删除',
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      HomeLayoutStore.instance.remove(
        widget.layoutKey,
        slot.id,
        item: slot.item,
      );
    }
  }

  Widget _cell(HomeSlot slot) {
    final card = RepaintBoundary(
      key: ValueKey('card-${slot.key}'),
      child: widget.builder(slot),
    );
    if (!widget.editing) return card;

    final isActive = slot.key == _activeKey;
    return Semantics(
      label: '正在编辑${homeCardLabel(slot)}卡片',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedScale(
              scale: isActive && !_resizing ? 1.02 : 1,
              duration: CitroMotion.press,
              curve: CitroMotion.easeOut,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: IgnorePointer(child: card),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive
                                ? context.c.accent
                                : context.c.accent.withAlpha(96),
                            width: isActive ? 2 : 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: IgnorePointer(
                      child: _SizeBadge(
                        w: _resizing ? _snappedW(slot) : slot.w,
                        h: _resizing ? _snappedH(slot) : slot.h,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 只有顶部圆柄和右下角手柄接管手势，卡片其余区域仍可滚动页面。
          Positioned(
            top: -8,
            left: 0,
            right: 0,
            child: Center(
              child: _DragHandle(
                slot: slot,
                active: isActive,
                onDown: (point) =>
                    _beginInteraction(slot, point, resizing: false),
                onMove: _updatePointer,
                onUp: _finishInteraction,
                onCancel: _cancelInteraction,
                onNudge: (dc, dr) => _nudge(slot, dc, dr),
              ),
            ),
          ),
          // 删除钮贴在卡片内部右上角，避免压到相邻卡片的边线。
          Positioned(
            right: 6,
            top: 6,
            child: _DeleteHandle(
              key: ValueKey('card-delete-${slot.key}'),
              label: homeCardLabel(slot),
              onTap: () => _confirmDelete(slot),
            ),
          ),
          Positioned(
            right: -16,
            bottom: -16,
            child: _ResizeHandle(
              onDown: (point) => _beginInteraction(slot, point, resizing: true),
              onMove: _updatePointer,
              onUp: _finishInteraction,
              onCancel: _cancelInteraction,
            ),
          ),
        ],
      ),
    );
  }
}

/// 立刻接管手势的指针区域。
///
/// 普通 pan?pan 会和外层滚动容器争夺手势，纵向拖动时经常被页面滚动抢走；
/// 编辑态的手柄必须由自己赢下竞技场，所以这里用 [EagerGestureRecognizer]
/// 在按下瞬间接管，再用 [Listener] 读取精确的全局坐标。
class _EagerPointer extends StatelessWidget {
  final Widget child;
  final ValueChanged<Offset> onDown;
  final ValueChanged<Offset> onMove;
  final VoidCallback onUp;
  final VoidCallback onCancel;

  const _EagerPointer({
    required this.child,
    required this.onDown,
    required this.onMove,
    required this.onUp,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              () => EagerGestureRecognizer(),
              (_) {},
            ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => onDown(event.position),
        onPointerMove: (event) => onMove(event.position),
        onPointerUp: (_) => onUp(),
        onPointerCancel: (_) => onCancel(),
        child: child,
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  final HomeSlot slot;
  final bool active;
  final ValueChanged<Offset> onDown;
  final ValueChanged<Offset> onMove;
  final VoidCallback onUp;
  final VoidCallback onCancel;
  final void Function(int dc, int dr) onNudge;

  const _DragHandle({
    required this.slot,
    required this.active,
    required this.onDown,
    required this.onMove,
    required this.onUp,
    required this.onCancel,
    required this.onNudge,
  });

  @override
  Widget build(BuildContext context) {
    final label = homeCardLabel(slot);
    return Semantics(
      button: true,
      label: '拖动$label卡片',
      customSemanticsActions: {
        const CustomSemanticsAction(label: '向左移动'): () => onNudge(-1, 0),
        const CustomSemanticsAction(label: '向右移动'): () => onNudge(1, 0),
        const CustomSemanticsAction(label: '向上移动'): () => onNudge(0, -1),
        const CustomSemanticsAction(label: '向下移动'): () => onNudge(0, 1),
      },
      child: Focus(
        canRequestFocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            onNudge(-1, 0);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            onNudge(1, 0);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            onNudge(0, -1);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            onNudge(0, 1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _EagerPointer(
          onDown: onDown,
          onMove: onMove,
          onUp: onUp,
          onCancel: onCancel,
          child: SizedBox(
            key: ValueKey('drag-${slot.key}'),
            width: 48,
            height: 30,
            child: Center(child: _DragPill(active: active)),
          ),
        ),
      ),
    );
  }
}

class _DragPill extends StatelessWidget {
  final bool active;
  const _DragPill({required this.active});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 34,
      height: 14,
      decoration: BoxDecoration(
        color: active ? c.accent : c.surface.withAlpha(220),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.line),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Container(
                width: 2,
                height: 2,
                decoration: BoxDecoration(
                  color: active ? Colors.white : c.inkSoft,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SizeBadge extends StatelessWidget {
  final int w;
  final int h;
  const _SizeBadge({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.surface.withAlpha(235),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.line),
      ),
      child: Text(
        '$w × $h',
        style: context.body(
          size: 10,
          weight: FontWeight.w700,
          color: c.inkSoft,
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final ValueChanged<Offset> onDown;
  final ValueChanged<Offset> onMove;
  final VoidCallback onUp;
  final VoidCallback onCancel;

  const _ResizeHandle({
    required this.onDown,
    required this.onMove,
    required this.onUp,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: '拖动调整卡片大小',
      child: _EagerPointer(
        onDown: onDown,
        onMove: onMove,
        onUp: onUp,
        onCancel: onCancel,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
                border: Border.all(color: c.surface, width: 2),
                boxShadow: CitroColors.shadows.paper(c),
              ),
              child: const Icon(
                Icons.open_in_full_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ghost extends StatelessWidget {
  final Rect rect;
  final bool free;
  const _Ghost({required this.rect, required this.free});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = free ? c.accent : c.stamp;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: color.withAlpha(190),
            radius: 16,
            fill: color.withAlpha(18),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final Color fill;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(rrect, Paint()..color = fill);
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 7.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.fill != fill || old.radius != radius;
}

class _DeleteHandle extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DeleteHandle({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: '删除$label卡片',
      child: Pressable(
        onTap: onTap,
        hoverLift: 0,
        hoverShadow: false,
        borderRadius: BorderRadius.circular(99),
        hoverColor: c.stamp.withAlpha(40),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: c.surface.withAlpha(235),
            shape: BoxShape.circle,
            border: Border.all(color: c.line),
          ),
          child: Center(
            child: AppIcon(
              strokeSvg(AppIcons.trash, width: 2),
              size: 13,
              color: c.stamp,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyBoard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 180,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('首页空空的', style: context.heading(size: 17, color: c.ink)),
          const SizedBox(height: 6),
          Text(
            '右上角「添加卡片」可以找回，删除后也能随时加回来',
            style: context.body(size: 12, color: c.inkSoft),
          ),
          const SizedBox(height: 12),
          Pressable(
            onTap: onAdd,
            hoverLift: 0,
            hoverShadow: false,
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: c.hl,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.plus, width: 2.2),
                    size: 15,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '添加卡片',
                    style: context.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: c.accentInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 内容面板
// -----------------------------------------------------------------------------

Future<void> showAddCardSheet({
  required BuildContext context,
  required HomeLayoutKey layoutKey,
}) {
  return showCitroSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddCardSheet(layoutKey: layoutKey),
  );
}

class _AddCardSheet extends StatefulWidget {
  final HomeLayoutKey layoutKey;
  const _AddCardSheet({required this.layoutKey});

  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  HomeCardCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final layoutKey = widget.layoutKey;
    final c = context.c;
    final media = MediaQuery.maybeOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media?.viewInsets.bottom ?? 0),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: (media?.size.height ?? 800) * .82,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(
            top: BorderSide(color: c.line),
            left: BorderSide(color: c.line),
            right: BorderSide(color: c.line),
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: HomeLayoutStore.instance,
            builder: (context, _) {
              final available = HomeLayoutStore.instance.available(layoutKey);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.line2,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '添加卡片',
                                style: context.heading(size: 20, color: c.ink),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '按分类挑选要放回首页的卡片，会自动寻找空位；卡片右上角的垃圾桶可以删除',
                                style: context.body(
                                  size: 11.5,
                                  color: c.inkSoft,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Pressable(
                          onTap: () => Navigator.of(context).maybePop(),
                          borderRadius: BorderRadius.circular(99),
                          hoverLift: 0,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: c.surface2,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.line),
                            ),
                            child: AppIcon(
                              strokeSvg(AppIcons.close, width: 2),
                              size: 16,
                              color: c.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  _CategoryFilter(
                    available: available,
                    selected: _filter,
                    onSelect: (category) => setState(() => _filter = category),
                  ),
                  const SizedBox(height: 2),
                  Flexible(
                    child: available.isEmpty
                        ? const _AllCardsAdded()
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.maxWidth >= 520
                                  ? 2
                                  : 1;
                              final groups =
                                  <HomeCardCategory, List<HomeCardOption>>{};
                              for (final category in HomeCardCategory.values) {
                                if (_filter != null && _filter != category) {
                                  continue;
                                }
                                final items = available
                                    .where((o) => o.category == category)
                                    .toList(growable: false);
                                if (items.isNotEmpty) groups[category] = items;
                              }
                              if (groups.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(28),
                                    child: Text(
                                      '这个分类已经全部放到首页了',
                                      style: context.body(
                                        size: 12,
                                        color: c.inkSoft,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return CustomScrollView(
                                slivers: [
                                  for (final entry in groups.entries) ...[
                                    SliverToBoxAdapter(
                                      child: _CategoryHeader(
                                        category: entry.key,
                                        count: entry.value.length,
                                      ),
                                    ),
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        0,
                                        14,
                                        8,
                                      ),
                                      sliver: SliverGrid(
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: columns,
                                              crossAxisSpacing: 10,
                                              mainAxisSpacing: 10,
                                              mainAxisExtent: 88,
                                            ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) => _AddCardTile(
                                            layoutKey: layoutKey,
                                            option: entry.value[index],
                                          ),
                                          childCount: entry.value.length,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            HomeLayoutStore.instance.reset(layoutKey);
                            AppToast.show(context, '已恢复默认布局');
                          },
                          child: Text(
                            '恢复默认',
                            style: context.body(size: 12.5, color: c.inkSoft),
                          ),
                        ),
                        const Spacer(),
                        Pressable(
                          onTap: () => Navigator.of(context).maybePop(),
                          borderRadius: BorderRadius.circular(99),
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: c.accent,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: c.accentInk.withAlpha(40),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '完成',
                                style: context.body(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: const Color(0xFF2E2C34),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AllCardsAdded extends StatelessWidget {
  const _AllCardsAdded();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.mintSoft,
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
            child: Center(
              child: AppIcon(
                strokeSvg(AppIcons.calendar, width: 2),
                size: 24,
                color: c.mintInk,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('所有卡片都在首页了', style: context.heading(size: 16, color: c.ink)),
          const SizedBox(height: 4),
          Text(
            '删掉的卡片会重新出现在这里',
            style: context.body(size: 11.5, color: c.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _AddCardTile extends StatelessWidget {
  final HomeLayoutKey layoutKey;
  final HomeCardOption option;

  const _AddCardTile({required this.layoutKey, required this.option});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = initialHomeSlotFor(layoutKey, option.id, item: option.item);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.paper(c),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: c.hl,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line.withAlpha(140)),
            ),
            child: Center(
              child: AppIcon(
                strokeSvg(option.icon ?? _homeCardIcon(option.id), width: 2),
                size: 20,
                color: c.accentInk,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.label,
                  style: context.heading(size: 14, color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  option.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: 10.5, color: c.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${size.w}×${size.h}',
                style: context.body(size: 9.5, color: c.inkSoft),
              ),
              const SizedBox(height: 4),
              Pressable(
                key: ValueKey('add-${option.key}'),
                onTap: () {
                  if (!HomeLayoutStore.instance.add(
                    layoutKey,
                    option.id,
                    item: option.item,
                  )) {
                    AppToast.show(context, '没有空位，先删除或缩小一张卡片');
                  }
                },
                hoverLift: 0,
                hoverShadow: false,
                borderRadius: BorderRadius.circular(99),
                child: Semantics(
                  button: true,
                  label: '添加${option.label}卡片',
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.accentInk.withAlpha(40)),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: Color(0xFF2E2C34),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  final List<HomeCardOption> available;
  final HomeCardCategory? selected;
  final ValueChanged<HomeCardCategory?> onSelect;

  const _CategoryFilter({
    required this.available,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    int countFor(HomeCardCategory? category) => category == null
        ? available.length
        : available.where((o) => o.category == category).length;
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          Center(
            child: _CategoryChip(
              label: '全部',
              count: available.length,
              selected: selected == null,
              background: c.hl,
              foreground: c.accentInk,
              onTap: () => onSelect(null),
            ),
          ),
          for (final category in HomeCardCategory.values) ...[
            const SizedBox(width: 6),
            Center(
              child: _CategoryChip(
                label: category.label,
                count: countFor(category),
                selected: selected == category,
                background: _categoryTint(c, category),
                foreground: _categoryInk(c, category),
                onTap: () => onSelect(category),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      hoverLift: 0,
      hoverShadow: false,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: CitroMotion.reduced(context)
            ? Duration.zero
            : CitroMotion.press,
        curve: CitroMotion.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? background : c.surface2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? foreground.withAlpha(70) : c.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.body(
                size: 11.5,
                weight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? foreground : c.inkSoft,
                height: 1,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: context.body(
                size: 9.5,
                weight: FontWeight.w600,
                color: selected ? foreground.withAlpha(200) : c.inkSoft,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final HomeCardCategory category;
  final int count;

  const _CategoryHeader({required this.category, required this.count});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _categoryInk(c, category),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            category.label,
            style: context.heading(size: 13.5, color: c.ink),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${category.hint} · $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(size: 10, color: c.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

Color _categoryTint(CitroColors c, HomeCardCategory category) =>
    switch (category) {
      HomeCardCategory.core => c.noteG,
      HomeCardCategory.game => c.hl,
      HomeCardCategory.tool => c.mintSoft,
      HomeCardCategory.driver => c.noteB,
    };

Color _categoryInk(CitroColors c, HomeCardCategory category) =>
    switch (category) {
      HomeCardCategory.core => c.accentInk,
      HomeCardCategory.game => c.accentInk,
      HomeCardCategory.tool => c.mintInk,
      HomeCardCategory.driver => c.accentInk,
    };

String _homeCardIcon(HomeCardId id) => switch (id) {
  HomeCardId.checkin => AppIcons.calendar,
  HomeCardId.tingyu => AppIcons.wave,
  HomeCardId.fish => '<path d="M2.5 12s3.2-5 8-5 8.5 5 8.5 5-3.7 5-8.5 5-8-5-8-5z"/><circle cx="9" cy="12" r="1.2"/><path d="M18.5 8.5 22 5v14l-3.5-3.5"/>',
  HomeCardId.weather => AppIcons.sun,
  HomeCardId.cook => AppIcons.fork,
  HomeCardId.calendar => AppIcons.calendar,
  HomeCardId.zodiac => AppIcons.star,
  HomeCardId.quote => AppIcons.book,
  HomeCardId.game => AppIcons.games,
  HomeCardId.res => AppIcons.download,
};
