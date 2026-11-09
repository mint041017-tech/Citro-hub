import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'todo_models.dart';
import 'todo_theme.dart';

/// 待办模块共用的小组件：分段、滚轮、步进器、心情脸、迷你图表。
///
/// 全部按 unslop 的规范取材：颜色只走 tokens、字号落在 CitroType 刻度、
/// 圆角由尺寸决定，动画统一用 CitroMotion 的曲线与时长。

// ---------------------------------------------------------------------------
// 图标
// ---------------------------------------------------------------------------

const _iconMap = <String, String>{
  'list': AppIcons.list,
  'check': AppIcons.check,
  'board': AppIcons.board,
  'smile': AppIcons.smile,
  'flag': AppIcons.flag,
  'repeat': AppIcons.repeat,
  'target': AppIcons.target,
  'book': AppIcons.book,
  'note': AppIcons.note,
  'heart': AppIcons.heart,
  'star': AppIcons.star,
  'sun': AppIcons.sun,
  'moon': AppIcons.moon,
  'clock': AppIcons.clock,
  'calendar': AppIcons.calendar,
  'fork': AppIcons.fork,
  'camera': AppIcons.camera,
  'image': AppIcons.image,
  'send': AppIcons.send,
  'sparkle': AppIcons.sparkle,
  'trophy': AppIcons.trophy,
  'cart': AppIcons.cart,
  'globe': AppIcons.globe,
  'lock': AppIcons.lock,
  'bell': AppIcons.bell,
  'flash': AppIcons.flash,
};

String todoIcon(String key) => _iconMap[key] ?? AppIcons.flag;

const todoIconKeys = <String>[
  'list',
  'check',
  'flag',
  'target',
  'book',
  'note',
  'heart',
  'repeat',
  'clock',
  'calendar',
  'star',
  'smile',
  'fork',
  'sun',
  'moon',
  'cart',
  'globe',
  'sparkle',
];

/// 分类/清单可选色，全部低饱和，能落在暖纸底上。
const todoPalette = <int>[
  0xFFE8935A,
  0xFFC08A4A,
  0xFF6F8CA8,
  0xFF6E9A78,
  0xFFB5717A,
  0xFF9A8FA6,
  0xFF8A7F6A,
  0xFF4F7F8C,
];

// ---------------------------------------------------------------------------
// 分段控件
// ---------------------------------------------------------------------------

class TodoSegTabs<T> extends StatefulWidget {
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  const TodoSegTabs({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  @override
  State<TodoSegTabs<T>> createState() => _TodoSegTabsState<T>();
}

class _TodoSegTabsState<T> extends State<TodoSegTabs<T>> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.bg2.withAlpha(c.dark ? 180 : 150),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < widget.items.length; i++)
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hover = i),
                onExit: (_) => setState(() {
                  if (_hover == i) _hover = null;
                }),
                child: Semantics(
                  button: true,
                  selected: widget.items[i].$1 == widget.value,
                  child: GestureDetector(
                    onTap: () => widget.onChanged(widget.items[i].$1),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: reduce ? Duration.zero : CitroMotion.hover,
                      curve: CitroMotion.easeColor,
                      height: widget.dense ? 30 : 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.items[i].$1 == widget.value
                            ? c.accent
                            : (_hover == i
                                  ? c.accent.withAlpha(c.dark ? 34 : 26)
                                  : Colors.transparent),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: widget.items[i].$1 == widget.value
                            ? [
                                BoxShadow(
                                  color: c.dark
                                      ? const Color(0x33000000)
                                      : const Color(0x1A5A4A2C),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        widget.items[i].$2,
                        style: context.ui(
                          size: widget.dense ? CitroType.label : CitroType.body,
                          weight: widget.items[i].$1 == widget.value
                              ? CitroType.strong
                              : CitroType.regular,
                          color: widget.items[i].$1 == widget.value
                              ? const Color(0xFF2E2C22)
                              : c.ink2,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 滚轮选择
// ---------------------------------------------------------------------------

/// 单列滚轮底部面板，返回选中的序号；取消返回 null。
Future<int?> showTodoWheel({
  required BuildContext context,
  required String title,
  required int count,
  required String Function(int index) labelOf,
  int initial = 0,
  double height = 260,
}) {
  var index = initial.clamp(0, math.max(0, count - 1)).toInt();
  final controller = FixedExtentScrollController(initialItem: index);
  return showCitroSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.c;
      return _WheelShell(
        title: title,
        height: height,
        child: CupertinoPicker(
          scrollController: controller,
          itemExtent: 40,
          looping: false,
          backgroundColor: Colors.transparent,
          selectionOverlay: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.accent.withAlpha(28),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.accent.withAlpha(70)),
            ),
          ),
          onSelectedItemChanged: (i) => index = i,
          children: [
            for (var i = 0; i < count; i++)
              Center(
                child: Text(
                  labelOf(i),
                  style: ctx.ui(
                    size: CitroType.title,
                    weight: CitroType.regular,
                    color: c.ink,
                  ),
                ),
              ),
          ],
        ),
        onDone: () => Navigator.of(ctx).pop(index),
      );
    },
  );
}

class _WheelShell extends StatelessWidget {
  final String title;
  final double height;
  final Widget child;
  final VoidCallback onDone;

  const _WheelShell({
    required this.title,
    required this.height,
    required this.child,
    required this.onDone,
  });

  /// 滚轮弹层里也统一用待办的钢青蓝，别和全局橙色混在一起。
  @override
  Widget build(BuildContext context) =>
      TodoScope(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Text(
                    title,
                    style: context.ui(
                      weight: CitroType.strong,
                      size: CitroType.subtitle,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onDone,
                    child: Text(
                      '完成',
                      style: context.ui(
                        size: CitroType.meta,
                        weight: CitroType.strong,
                        color: c.accentInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// 月历式日期选择：点日期格子选年月日，返回当天 0 点。
Future<DateTime?> showTodoDatePicker(
  BuildContext context, {
  DateTime? initial,
  DateTime? first,
  DateTime? last,
}) {
  final now = DateTime.now();
  final start = dayOf(first ?? now.subtract(const Duration(days: 365)));
  final end = dayOf(last ?? now.add(const Duration(days: 730)));
  final init = dayOf(initial ?? now);
  return showCitroDialog<DateTime>(
    context,
    builder: (ctx) => _TodoCalendar(initial: init, start: start, end: end),
  );
}

class _TodoCalendar extends StatefulWidget {
  final DateTime initial;
  final DateTime start;
  final DateTime end;

  const _TodoCalendar({
    required this.initial,
    required this.start,
    required this.end,
  });

  @override
  State<_TodoCalendar> createState() => _TodoCalendarState();
}

class _TodoCalendarState extends State<_TodoCalendar> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);
  late DateTime _pick = widget.initial;

  bool _inRange(DateTime d) =>
      !d.isBefore(widget.start) && !d.isAfter(widget.end);

  /// 日历弹层同理：整张纸都用待办蓝。
  @override
  Widget build(BuildContext context) =>
      TodoScope(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = context.c;
    final first = DateTime(_month.year, _month.month, 1);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1;
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    final today = dayOf(DateTime.now());
    return PaperDialog(
      maxWidth: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Pressable(
                onTap: () => setState(() {
                  _month = DateTime(_month.year, _month.month - 1);
                }),
                scale: .9,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AppIcon(
                    strokeSvg(AppIcons.chevronLeft, width: 2),
                    size: 16,
                    color: c.inkSoft,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_month.year} 年 ${_month.month} 月',
                    style: context.ui(
                      size: CitroType.title,
                      weight: CitroType.strong,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
              Pressable(
                onTap: () => setState(() {
                  _month = DateTime(_month.year, _month.month + 1);
                }),
                scale: .9,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AppIcon(
                    strokeSvg(AppIcons.chevronRight, width: 2),
                    size: 16,
                    color: c.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: c.bg2.withAlpha(c.dark ? 150 : 110),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                for (final w in week)
                  Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: context.ui(
                          size: CitroType.caption,
                          weight: CitroType.strong,
                          color: c.ink2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 264,
            child: GridView.builder(
              padding: EdgeInsets.zero,
              itemCount: lead + days,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 42,
              ),
              itemBuilder: (ctx, i) {
                if (i < lead) return const SizedBox.shrink();
                final d = DateTime(_month.year, _month.month, i - lead + 1);
                final enabled = _inRange(d);
                final selected = d == _pick;
                final isToday = d == today;
                return Padding(
                  padding: const EdgeInsets.all(2),
                  child: Pressable(
                    onTap: enabled ? () => setState(() => _pick = d) : null,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? c.accent : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? c.accent
                              : (isToday
                                    ? c.accent.withAlpha(120)
                                    : Colors.transparent),
                        ),
                      ),
                      child: Text(
                        '${d.day}',
                        style: context.ui(
                          size: CitroType.label,
                          weight: selected || isToday
                              ? CitroType.strong
                              : CitroType.regular,
                          color: !enabled
                              ? c.inkSoft.withAlpha(120)
                              : (selected ? const Color(0xFF2E2C22) : c.ink),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Pressable(
                onTap: () => setState(() {
                  _pick = today;
                  _month = DateTime(today.year, today.month);
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Text(
                    '回到今天',
                    style: context.ui(
                      size: CitroType.label,
                      color: c.accentInk,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Pressable(
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    '取消',
                    style: context.ui(size: CitroType.label, color: c.inkSoft),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 104,
                child: AccentButton(
                  text: '确定',
                  height: 40,
                  onTap: () => Navigator.of(context).pop(_pick),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 时间滚轮：时 / 分两列。
Future<String?> showTodoTimePicker(
  BuildContext context, {
  String initial = '20:00',
}) {
  final parts = initial.split(':');
  var hour = (int.tryParse(parts.first) ?? 20).clamp(0, 23);
  var minute = (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0).clamp(
    0,
    59,
  );
  return showCitroSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.c;
      return _WheelShell(
        title: '选择时间',
        height: 300,
        onDone: () => Navigator.of(ctx).pop(
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
        ),
        child: Row(
          children: [
            Expanded(
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(
                  initialItem: hour,
                ),
                itemExtent: 40,
                backgroundColor: Colors.transparent,
                selectionOverlay: _wheelOverlay(
                  c,
                  const EdgeInsets.symmetric(horizontal: 24),
                ),
                onSelectedItemChanged: (i) => hour = i,
                children: [
                  for (var h = 0; h < 24; h++)
                    Center(
                      child: Text(
                        '${h.toString().padLeft(2, '0')} 时',
                        style: _wheelText(ctx),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(
                  initialItem: minute,
                ),
                itemExtent: 40,
                backgroundColor: Colors.transparent,
                selectionOverlay: _wheelOverlay(
                  c,
                  const EdgeInsets.symmetric(horizontal: 24),
                ),
                onSelectedItemChanged: (i) => minute = i,
                children: [
                  for (var m = 0; m < 60; m++)
                    Center(
                      child: Text(
                        '${m.toString().padLeft(2, '0')} 分',
                        style: _wheelText(ctx),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _wheelOverlay(CitroColors c, EdgeInsets margin) => Container(
  margin: margin,
  decoration: BoxDecoration(
    color: c.accent.withAlpha(28),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: c.accent.withAlpha(70)),
  ),
);

TextStyle _wheelText(BuildContext ctx) =>
    ctx.ui(size: CitroType.title, weight: CitroType.regular, color: ctx.c.ink);

// ---------------------------------------------------------------------------
// 卡片右上角的小动作（详情 / 编辑）
// ---------------------------------------------------------------------------

class TodoMiniAction extends StatelessWidget {
  final String label;
  final String? svg;
  final VoidCallback onTap;

  const TodoMiniAction({
    super.key,
    required this.label,
    required this.onTap,
    this.svg,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: .95,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.ui(
                size: CitroType.label,
                weight: CitroType.strong,
                color: c.ink2,
              ),
            ),
            if (svg != null) ...[
              const SizedBox(width: 4),
              AppIcon(strokeSvg(svg!, width: 2), size: 15, color: c.inkSoft),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 关闭按钮（统一圆形）
// ---------------------------------------------------------------------------

class TodoCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;

  const TodoCloseButton({super.key, required this.onTap, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: '关闭',
      child: Pressable(
        onTap: onTap,
        scale: .9,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: c.bg2.withAlpha(c.dark ? 150 : 110),
            shape: BoxShape.circle,
            border: Border.all(color: c.line),
          ),
          child: Center(
            child: AppIcon(
              strokeSvg(AppIcons.close, width: 2),
              size: size * .45,
              color: c.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 步进器
// ---------------------------------------------------------------------------

class TodoStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  const TodoStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 99,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(
            context,
            AppIcons.minus,
            value > min ? () => onChanged(value - 1) : null,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 56),
            alignment: Alignment.center,
            child: Text(
              '$value$suffix',
              style: context.ui(
                size: CitroType.meta,
                weight: CitroType.strong,
                color: c.ink,
              ),
            ),
          ),
          _stepBtn(
            context,
            AppIcons.plus,
            value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(BuildContext context, String icon, VoidCallback? onTap) {
    final c = context.c;
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap,
      scale: .92,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: AppIcon(
            strokeSvg(icon, width: 2),
            size: 15,
            color: enabled ? c.ink2 : c.inkSoft.withAlpha(90),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 心情脸
// ---------------------------------------------------------------------------

class MoodFace extends StatelessWidget {
  final MoodKind kind;
  final double size;
  final bool selected;

  const MoodFace({
    super.key,
    required this.kind,
    this.size = 40,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kind.color.withAlpha(selected ? 54 : 32),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? kind.color.withAlpha(220)
              : kind.color.withAlpha(90),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: CustomPaint(
        painter: _MoodPainter(
          kind: kind,
          color: c.dark ? c.ink : const Color(0xFF3B3428),
        ),
      ),
    );
  }
}

class _MoodPainter extends CustomPainter {
  final MoodKind kind;
  final Color color;

  _MoodPainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final eye = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * .045)
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;

    final ey = h * .42;
    final left = w * .34;
    final right = w * .66;

    void dots() {
      canvas.drawCircle(Offset(left, ey), w * .045, fill);
      canvas.drawCircle(Offset(right, ey), w * .045, fill);
    }

    void closedEyes() {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(left, ey + w * .02),
          width: w * .16,
          height: w * .12,
        ),
        math.pi,
        math.pi,
        false,
        eye,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(right, ey + w * .02),
          width: w * .16,
          height: w * .12,
        ),
        math.pi,
        math.pi,
        false,
        eye,
      );
    }

    void tiredEyes() {
      canvas.drawLine(
        Offset(left - w * .06, ey),
        Offset(left + w * .06, ey + w * .01),
        eye,
      );
      canvas.drawLine(
        Offset(right - w * .06, ey + w * .01),
        Offset(right + w * .06, ey),
        eye,
      );
    }

    void brows() {
      canvas.drawLine(
        Offset(left - w * .06, ey - w * .1),
        Offset(left + w * .05, ey - w * .06),
        eye,
      );
      canvas.drawLine(
        Offset(right + w * .06, ey - w * .1),
        Offset(right - w * .05, ey - w * .06),
        eye,
      );
    }

    switch (kind) {
      case MoodKind.happy:
        closedEyes();
      case MoodKind.calm:
        dots();
      case MoodKind.neutral:
        dots();
      case MoodKind.tired:
        tiredEyes();
      case MoodKind.low:
        dots();
      case MoodKind.anxious:
        dots();
        brows();
    }

    final mouthY = h * .63;
    final mouth = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * .045)
      ..strokeCap = StrokeCap.round;

    switch (kind) {
      case MoodKind.happy:
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(w / 2, mouthY - w * .06),
            width: w * .34,
            height: w * .24,
          ),
          0.15 * math.pi,
          0.7 * math.pi,
          false,
          mouth,
        );
      case MoodKind.calm:
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(w / 2, mouthY - w * .02),
            width: w * .22,
            height: w * .1,
          ),
          0.15 * math.pi,
          0.7 * math.pi,
          false,
          mouth,
        );
      case MoodKind.neutral:
        canvas.drawLine(Offset(w * .4, mouthY), Offset(w * .6, mouthY), mouth);
      case MoodKind.tired:
        canvas.drawLine(Offset(w * .4, mouthY), Offset(w * .6, mouthY), mouth);
      case MoodKind.low:
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(w / 2, mouthY + w * .07),
            width: w * .26,
            height: w * .18,
          ),
          math.pi + .25,
          .5 * math.pi,
          false,
          mouth,
        );
      case MoodKind.anxious:
        final path = Path()
          ..moveTo(w * .38, mouthY)
          ..quadraticBezierTo(w * .44, mouthY - w * .05, w * .5, mouthY)
          ..quadraticBezierTo(w * .56, mouthY + w * .05, w * .62, mouthY);
        canvas.drawPath(path, mouth);
    }
  }

  @override
  bool shouldRepaint(covariant _MoodPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// 图表
// ---------------------------------------------------------------------------

class MiniBars extends StatelessWidget {
  final List<int> values;
  final List<String> labels;
  final Color color;
  final double height;
  final bool showValues;

  const MiniBars({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.height = 64,
    this.showValues = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final maxValue = values.fold<int>(1, (m, v) => math.max(m, v));
    final chartH = math.max(6.0, height - 34);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        AnimatedContainer(
                          duration: CitroMotion.size,
                          curve: CitroMotion.easeOut,
                          height: values[i] == 0
                              ? 3
                              : chartH * values[i] / maxValue,
                          decoration: BoxDecoration(
                            color: values[i] == 0
                                ? c.line2
                                : (i == values.length - 1
                                      ? color
                                      : color.withAlpha(130)),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        if (showValues && values[i] > 0)
                          Positioned(
                            bottom:
                                (values[i] == 0
                                    ? 3
                                    : chartH * values[i] / maxValue) +
                                4,
                            child: Text(
                              '${values[i]}',
                              style: context.ui(
                                size: CitroType.caption,
                                weight: CitroType.strong,
                                color: c.inkSoft,
                                height: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: context.ui(
                      size: CitroType.caption,
                      color: c.inkSoft,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TodoRing extends StatelessWidget {
  final double progress;
  final String label;
  final String caption;
  final Color color;
  final double size;

  const TodoRing({
    super.key,
    required this.progress,
    required this.label,
    required this.caption,
    required this.color,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0, 1)),
            duration: CitroMotion.size,
            curve: CitroMotion.easeOut,
            builder: (_, v, __) => CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(progress: v, color: color, track: c.line2),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: context.ui(
                  size: CitroType.subtitle,
                  weight: CitroType.strong,
                  color: c.ink,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: context.ui(
                  size: CitroType.small,
                  color: c.inkSoft,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 5;
    final stroke = 8.0;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
