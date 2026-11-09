import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'ledger_theme.dart';

enum _LedgerPickerMode { date, time, dateTime }

/// 记账模块自己的日期 + 时间选择器。
///
/// 记一笔拆成「日期」「时间」两个入口；收据草稿仍使用合并选择器。
Future<DateTime?> showLedgerDateTimePicker(
  BuildContext context, {
  DateTime? initial,
}) {
  return _showLedgerPicker(
    context,
    initial: initial ?? DateTime.now(),
    mode: _LedgerPickerMode.dateTime,
  );
}

/// 只选择年月日；时间部分沿用调用方已有值。
Future<DateTime?> showLedgerDatePicker(
  BuildContext context, {
  DateTime? initial,
}) async {
  final picked = await _showLedgerPicker(
    context,
    initial: initial ?? DateTime.now(),
    mode: _LedgerPickerMode.date,
  );
  if (picked == null) return null;
  return DateTime(picked.year, picked.month, picked.day);
}

/// 只选择时分；日期部分沿用调用方已有值。
Future<TimeOfDay?> showLedgerTimePicker(
  BuildContext context, {
  DateTime? initial,
}) async {
  final picked = await _showLedgerPicker(
    context,
    initial: initial ?? DateTime.now(),
    mode: _LedgerPickerMode.time,
  );
  if (picked == null) return null;
  return TimeOfDay(hour: picked.hour, minute: picked.minute);
}

Future<DateTime?> _showLedgerPicker(
  BuildContext context, {
  required DateTime initial,
  required _LedgerPickerMode mode,
}) {
  return showCitroDialog<DateTime>(
    context,
    builder: (ctx) => LedgerScope(
      child: _LedgerDateTimeDialog(initial: initial, mode: mode),
    ),
  );
}

class _LedgerDateTimeDialog extends StatefulWidget {
  final DateTime initial;
  final _LedgerPickerMode mode;

  const _LedgerDateTimeDialog({
    required this.initial,
    this.mode = _LedgerPickerMode.dateTime,
  });

  @override
  State<_LedgerDateTimeDialog> createState() => _LedgerDateTimeDialogState();
}

class _LedgerDateTimeDialogState extends State<_LedgerDateTimeDialog> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);
  late DateTime _pick = DateTime(
    widget.initial.year,
    widget.initial.month,
    widget.initial.day,
  );
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;
  late final FixedExtentScrollController _hourWheel =
      FixedExtentScrollController(initialItem: _hour);
  late final FixedExtentScrollController _minuteWheel =
      FixedExtentScrollController(initialItem: _minute);

  bool get _showDate => widget.mode != _LedgerPickerMode.time;
  bool get _showTime => widget.mode != _LedgerPickerMode.date;
  bool get _showQuickChips => _showDate && _showTime;

  @override
  void dispose() {
    _hourWheel.dispose();
    _minuteWheel.dispose();
    super.dispose();
  }

  void _selectDay(DateTime day) {
    setState(() {
      _pick = DateTime(day.year, day.month, day.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final title = _showDate && !_showTime ? '选择日期' : '选择时间';
    return PaperDialog(
      maxWidth: _showDate ? 390 : 320,
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: context.lheading(size: CitroType.subtitle, color: c.ink),
          ),
          const SizedBox(height: 12),
          if (_showDate) _calendar(context),
          if (_showDate && _showTime) const SizedBox(height: 8),
          if (_showTime) _timeBox(context),
          if (_showQuickChips) ...[
            const SizedBox(height: 10),
            _quickChips(),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  text: '取消',
                  outlined: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AccentButton(
                  text: '确定',
                  onTap: () => Navigator.of(context).pop(
                    DateTime(
                      _pick.year,
                      _pick.month,
                      _pick.day,
                      _hour,
                      _minute,
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

  Widget _calendar(BuildContext context) {
    final c = context.c;
    final first = DateTime(_month.year, _month.month, 1);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final total = ((lead + days + 6) ~/ 7) * 7;
    final today = DateTime.now();
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _arrow(AppIcons.chevronLeft, () {
              setState(() {
                _month = DateTime(_month.year, _month.month - 1);
              });
            }),
            Expanded(
              child: Center(
                child: Text(
                  '${_month.year} 年 ${_month.month} 月',
                  style: context.lui(
                    size: CitroType.title,
                    weight: CitroType.strong,
                    color: c.ink,
                  ),
                ),
              ),
            ),
            _arrow(AppIcons.chevronRight, () {
              setState(() {
                _month = DateTime(_month.year, _month.month + 1);
              });
            }),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final w in week)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: context.lui(
                      size: CitroType.small,
                      weight: CitroType.strong,
                      color: c.inkSoft,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        LayoutBuilder(
          builder: (context, constraints) {
            // 月份可能跨 4~6 周；按实际格子宽度算高度，避免最后一整行被裁掉。
            final rows = total ~/ 7;
            final cell = (constraints.maxWidth - 6) / 7;
            final height = rows * cell + (rows - 1);
            return SizedBox(
              height: height,
              child: GridView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 1,
                      crossAxisSpacing: 1,
                      childAspectRatio: 1,
                    ),
                itemCount: total,
                itemBuilder: (context, index) {
                  final dayNumber = index - lead + 1;
                  if (dayNumber < 1 || dayNumber > days) {
                    return const SizedBox.shrink();
                  }
                  final day = DateTime(_month.year, _month.month, dayNumber);
                  final selected =
                      day.year == _pick.year &&
                      day.month == _pick.month &&
                      day.day == _pick.day;
                  final isToday =
                      day.year == today.year &&
                      day.month == today.month &&
                      day.day == today.day;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _selectDay(day),
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: selected ? c.accent : Colors.transparent,
                          shape: BoxShape.circle,
                          border: isToday && !selected
                              ? Border.all(color: c.accent.withAlpha(160))
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '$dayNumber',
                            style: context.lui(
                              size: CitroType.meta,
                              weight: selected
                                  ? CitroType.strong
                                  : CitroType.regular,
                              color: selected
                                  ? const Color(0xFF2E2C22)
                                  : (dayNumber == 1 ? c.inkSoft : c.ink2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _timeBox(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.bg2.withAlpha(c.dark ? 130 : 90),
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          AppIcon(
            strokeSvg(AppIcons.clock, width: 1.9),
            size: 16,
            color: c.accentInk,
          ),
          const SizedBox(width: 8),
          Text(
            '时间',
            style: context.lui(
              size: CitroType.caption,
              weight: CitroType.strong,
              color: c.inkSoft,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 74,
              child: Row(
                children: [
                  Expanded(child: _wheel(context, _hourWheel, 0, 23, true)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      ':',
                      style: context.ldisplay(
                        size: 20,
                        weight: FontWeight.w700,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                  Expanded(child: _wheel(context, _minuteWheel, 0, 59, false)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickChips() {
    return Row(
      children: [
        Expanded(
          child: LedgerQuickTimeChip(
            text: '现在',
            onTap: () {
              final now = DateTime.now();
              setState(() {
                _pick = DateTime(now.year, now.month, now.day);
                _month = DateTime(now.year, now.month);
                _hour = now.hour;
                _minute = now.minute;
              });
              _hourWheel.jumpToItem(_hour);
              _minuteWheel.jumpToItem(_minute);
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: LedgerQuickTimeChip(
            text: '昨天',
            onTap: () {
              final day = DateTime.now().subtract(const Duration(days: 1));
              setState(() {
                _pick = DateTime(day.year, day.month, day.day);
                _month = DateTime(day.year, day.month);
              });
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: LedgerQuickTimeChip(
            text: '今天上午',
            onTap: () {
              setState(() {
                _hour = 9;
                _minute = 0;
              });
              _hourWheel.jumpToItem(9);
              _minuteWheel.jumpToItem(0);
            },
          ),
        ),
      ],
    );
  }

  Widget _arrow(String icon, VoidCallback onTap) => Pressable(
    onTap: onTap,
    scale: .9,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: AppIcon(
        strokeSvg(icon, width: 2),
        size: 16,
        color: context.c.inkSoft,
      ),
    ),
  );

  Widget _wheel(
    BuildContext context,
    FixedExtentScrollController controller,
    int min,
    int max,
    bool isHour,
  ) {
    final c = context.c;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 30,
          decoration: BoxDecoration(
            color: c.accent2.withAlpha(30),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: 26,
          diameterRatio: 2.4,
          perspective: .003,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (index) {
            setState(() {
              if (isHour) {
                _hour = index;
              } else {
                _minute = index;
              }
            });
          },
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: max - min + 1,
            builder: (context, index) {
              final value = min + index;
              final selected = isHour ? value == _hour : value == _minute;
              return Center(
                child: Text(
                  value.toString().padLeft(2, '0'),
                  style: context.ldisplay(
                    size: selected ? 18 : 16,
                    weight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? c.ink : c.inkSoft,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class LedgerQuickTimeChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const LedgerQuickTimeChip({
    super.key,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: .95,
      hoverLift: 0,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.button),
          border: Border.all(color: c.accent.withAlpha(70)),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.lui(
            size: CitroType.label,
            weight: CitroType.strong,
            color: c.ink2,
          ),
        ),
      ),
    );
  }
}