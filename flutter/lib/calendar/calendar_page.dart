import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ledger/ledger_date_picker.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../utils/lunar.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'calendar_models.dart';
import 'calendar_store.dart';

/// 日历详情页：整月月历 + 倒数日 / 纪念日管理。
///
/// 从首页日历卡片点进来，卡片会做一次柔和的形变过渡；页头沿用首页的
/// 顶部留白，返回按钮、同步状态和「添加」都在同一行，窄屏自动收拢。
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    CalendarStore.instance.ensureInit();
  }

  void _back() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushNamedAndRemoveUntil('/home', (_) => false);
    }
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month);
      _selected = DateTime(now.year, now.month, now.day);
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  bool get _onCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final wide = width >= 900;
    final side = math.max(16.0, (width - 1120) / 2);
    // 与首页保持一致：手机压到 8px，平板 / 桌面保留 48px。
    final top = width < 700 ? 8.0 : AppSpacing.pageTop(width);
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      body: PaperBackground(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(side, top, side, 0),
            child: Column(
              children: [
                _header(context),
                const SizedBox(height: 10),
                Expanded(
                  child: ListenableBuilder(
                    listenable: CalendarStore.instance,
                    builder: (context, _) {
                      if (!wide) {
                        return _scroll(
                          Column(
                            children: [
                              _monthCard(context),
                              const SizedBox(height: 12),
                              _marksCard(context),
                            ],
                          ),
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _scroll(_monthCard(context)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 5,
                            child: _scroll(_marksCard(context)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
    physics: const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    ),
    padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
    child: child,
  );

  Widget _header(BuildContext context) {
    final c = context.c;
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return Row(
      children: [
        _roundButton(icon: AppIcons.arrowLeft, onTap: _back, tooltip: '返回首页'),
        const SizedBox(width: 10),
        Text('日历', style: context.heading(size: AppSpacing.x3)),
        const Spacer(),
        _CalendarSyncBadge(
          signedIn: AppState.instance.loggedIn,
          compact: narrow,
        ),
        const SizedBox(width: 10),
        if (!narrow && !_onCurrentMonth) ...[
          Pressable(
            onTap: _goToday,
            scale: .94,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.line2),
              ),
              child: Center(
                child: Text(
                  '回到今天',
                  style: context.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: c.accentInk,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        _roundButton(
          icon: AppIcons.plus,
          onTap: () => showCalendarMarkSheet(context),
          filled: true,
          tooltip: '添加倒数日或纪念日',
        ),
      ],
    );
  }

  Widget _roundButton({
    required String icon,
    required VoidCallback onTap,
    String? tooltip,
    bool filled = false,
  }) {
    final c = context.c;
    final button = Pressable(
      onTap: onTap,
      scale: .92,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: filled ? c.accent : c.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: filled ? c.accent2 : c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Center(
          child: AppIcon(
            strokeSvg(icon, width: 2.2),
            size: 18,
            color: filled ? const Color(0xFF2E2C22) : c.ink2,
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }

  // ---------------------------------------------------------------------------
  // 月历
  // ---------------------------------------------------------------------------

  List<_CalDay> _cellsFor(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final startWd = first.weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final prevDays = DateTime(month.year, month.month, 0).day;
    final cells = <_CalDay>[];
    for (var i = 0; i < 42; i++) {
      int day;
      var cy = month.year, cm = month.month;
      var dim = false;
      if (i < startWd) {
        day = prevDays - startWd + 1 + i;
        dim = true;
        cm = month.month == 1 ? 12 : month.month - 1;
        if (month.month == 1) cy = month.year - 1;
      } else if (i >= startWd + days) {
        day = i - startWd - days + 1;
        dim = true;
        cm = month.month == 12 ? 1 : month.month + 1;
        if (month.month == 12) cy = month.year + 1;
      } else {
        day = i - startWd + 1;
      }
      cells.add(_CalDay(day, DateTime(cy, cm, day), dim));
    }
    return cells;
  }

  Widget _monthCard(BuildContext context) {
    final c = context.c;
    final cells = _cellsFor(_month);
    const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
    final today = CalendarDates.dayOnly(DateTime.now());
    final selected = CalendarDates.dayOnly(_selected);
    return PaperCard(
      tapeColor: c.tape2,
      tapeAngle: 2.2,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Pressable(
                onTap: () => _shiftMonth(-1),
                scale: .9,
                borderRadius: BorderRadius.circular(99),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 22,
                    color: c.accentInk,
                  ),
                ),
              ),
              Text(
                CalendarDates.monthLabel(_month),
                style: context.display(size: 20, color: c.accentInk),
              ),
              Pressable(
                onTap: () => _shiftMonth(1),
                scale: .9,
                borderRadius: BorderRadius.circular(99),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: c.accentInk,
                  ),
                ),
              ),
              const Spacer(),
              Pressable(
                onTap: _goToday,
                scale: .94,
                child: Text(
                  '今天',
                  style: context.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: c.accentInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      weekdays[i],
                      textAlign: TextAlign.center,
                      style: context.body(
                        size: 12,
                        weight: FontWeight.w700,
                        color: (i == 0 || i == 6) ? c.accentInk : c.inkSoft,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          for (var r = 0; r < 6; r++) ...[
            if (r > 0) const SizedBox(height: 2),
            SizedBox(
              height: 40,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var col = 0; col < 7; col++) ...[
                    if (col > 0) const SizedBox(width: 2),
                    Expanded(
                      child: _dayCell(
                        context,
                        cells[r * 7 + col],
                        today: today,
                        selected: selected,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _selectedStrip(context),
        ],
      ),
    );
  }

  Widget _dayCell(
    BuildContext context,
    _CalDay data, {
    required DateTime today,
    required DateTime selected,
  }) {
    final c = context.c;
    final date = CalendarDates.dayOnly(data.date);
    final isToday = date == today;
    final isSelected = date == selected;
    final marks = CalendarStore.instance.marks
        .where((mark) => CalendarDates.hits(mark, date))
        .toList();
    String? label;
    Color? labelColor;
    if (!data.dim) {
      final fid = festivalIdOf(data.date);
      final term = termToday(data.date);
      if (fid != null) {
        label = festivalName(fid);
        labelColor = c.accentInk;
      } else if (term != null) {
        label = term;
        labelColor = c.mintInk;
      } else {
        final lu = lunarOf(data.date);
        if (lu != null) {
          label = lu.day == 1
              ? lu.name
              : lu.name.substring(math.max(0, lu.name.length - 2));
        }
      }
    }
    final fg = isSelected
        ? const Color(0xFF2E2C22)
        : (data.dim ? c.inkSoft.withAlpha(150) : c.ink);
    return Pressable(
      onTap: () => setState(() {
        _selected = data.date;
        // 点到上/下月的补位日期时，顺手翻到那个月，避免选中条与网格脱节。
        if (data.dim) {
          _month = DateTime(data.date.year, data.date.month);
        }
      }),
      scale: .94,
      hoverLift: 0,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: isSelected ? c.accent : (isToday ? c.accentLt : null),
          borderRadius: BorderRadius.circular(9),
          border: isSelected ? Border.all(color: c.accent2, width: 1.1) : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${data.day}',
                    style: context.display(size: 16, color: fg, height: 1.05),
                  ),
                  if (marks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF2E2C22)
                              : (marks.first.kind == CalendarMarkKind.countdown
                                    ? c.accent2
                                    : c.stamp),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              if (label != null && !data.dim)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 8.5,
                      color: isSelected
                          ? const Color(0xFF2E2C22)
                          : (labelColor ?? c.inkSoft),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedStrip(BuildContext context) {
    final c = context.c;
    final selected = CalendarDates.dayOnly(_selected);
    final lunar = lunarOf(selected);
    final fid = festivalIdOf(selected);
    final term = termToday(selected);
    final extras = <String>[
      if (lunar != null) lunar.name,
      if (term != null) term,
      if (fid != null) festivalName(fid),
    ];
    final marks = CalendarStore.instance.marks
        .where((mark) => CalendarDates.hits(mark, selected))
        .toList();
    final today = CalendarDates.dayOnly(DateTime.now());
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${selected.month}月${selected.day}日',
                      style: context.display(size: 17, color: c.ink),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      CalendarDates.weekday(selected),
                      style: context.body(size: 11.5, color: c.inkSoft),
                    ),
                    if (selected == today)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          '今天',
                          style: context.body(
                            size: 10,
                            weight: FontWeight.w700,
                            color: c.accentInk,
                          ),
                        ),
                      ),
                  ],
                ),
                if (extras.isNotEmpty)
                  Text(
                    extras.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.hand(size: 12, color: c.mintInk),
                  ),
              ],
            ),
          ),
          if (marks.isNotEmpty)
            Flexible(
              child: Text(
                marks.map((m) => m.title).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: context.body(size: 10.5, color: c.stamp),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 倒数日 / 纪念日
  // ---------------------------------------------------------------------------

  Widget _marksCard(BuildContext context) {
    final c = context.c;
    final today = DateTime.now();
    final marks = CalendarStore.instance.sorted(today);
    return PaperCard(
      tapeColor: c.tape3,
      tapeAngle: -1.6,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '倒数日 & 纪念日',
                style: context.heading(size: 17, color: c.accentInk),
              ),
              const Spacer(),
              if (marks.isNotEmpty)
                Text(
                  '${marks.length} 个日子',
                  style: context.body(size: 10.5, color: c.inkSoft),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text('把期待和珍惜都写在这里', style: context.hand(size: 12, color: c.inkSoft)),
          const SizedBox(height: 10),
          if (marks.isEmpty)
            _emptyMarks(context)
          else
            for (final mark in marks)
              _MarkTile(
                mark: mark,
                today: today,
                onTap: () => showCalendarMarkSheet(context, mark: mark),
              ),
        ],
      ),
    );
  }

  Widget _emptyMarks(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          AppIcon(
            strokeSvg(AppIcons.calendar, width: 1.8),
            size: 26,
            color: c.inkSoft.withAlpha(160),
          ),
          const SizedBox(height: 8),
          Text(
            '还没有记录的日子',
            style: context.body(
              size: 13,
              weight: FontWeight.w700,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '点右上角的 + 记一个生日、旅行或倒计时',
            textAlign: TextAlign.center,
            style: context.body(size: 11, color: c.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _CalDay {
  final int day;
  final DateTime date;
  final bool dim;

  const _CalDay(this.day, this.date, this.dim);
}

/// 单条倒数日 / 纪念日：左边色条，中间日期信息，右边大天数。
class _MarkTile extends StatelessWidget {
  final CalendarMark mark;
  final DateTime today;
  final VoidCallback onTap;

  const _MarkTile({
    required this.mark,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isCountdown = mark.kind == CalendarMarkKind.countdown;
    final color = isCountdown ? c.accent2 : c.stamp;
    final days = CalendarDates.daysFor(mark, today);
    final years = CalendarDates.yearCount(mark, today);
    return Pressable(
      onTap: onTap,
      scale: .98,
      hoverLift: 1,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: color.withAlpha(14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(70)),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          mark.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.body(
                            size: 14,
                            weight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withAlpha(28),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          mark.kind.label,
                          style: context.body(
                            size: 8.5,
                            weight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${CalendarDates.fullDate(mark.date)}'
                    '${mark.yearly ? ' · 每年' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(size: 10.5, color: c.inkSoft),
                  ),
                  if (mark.note.isNotEmpty)
                    Text(
                      mark.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.hand(size: 11, color: c.inkSoft),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  days == 0 ? '今天' : '${days.abs()}',
                  style: context.display(
                    size: days == 0 ? 16 : 22,
                    color: color,
                    height: 1,
                  ),
                ),
                if (days != 0)
                  Text(
                    CalendarDates.unitFor(mark, today),
                    style: context.body(size: 9, color: c.inkSoft),
                  ),
                if (years != null)
                  Text(
                    '第 $years 年',
                    style: context.body(size: 8.5, color: color),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部同步状态：与记账页同一套小圆点语言。
class _CalendarSyncBadge extends StatelessWidget {
  final bool signedIn;
  final bool compact;

  const _CalendarSyncBadge({required this.signedIn, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = signedIn ? c.mintInk : c.inkSoft;
    final label = signedIn ? '已同步' : '仅本机';
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (compact) {
      return Tooltip(message: label, child: dot);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 4),
        Text(label, style: context.body(size: 10, color: c.inkSoft)),
      ],
    );
  }
}

/// 新增 / 编辑倒数日与纪念日的手账底部弹层。
Future<void> showCalendarMarkSheet(BuildContext context, {CalendarMark? mark}) {
  return showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MarkSheet(mark: mark),
  );
}

class _MarkSheet extends StatefulWidget {
  final CalendarMark? mark;

  const _MarkSheet({this.mark});

  @override
  State<_MarkSheet> createState() => _MarkSheetState();
}

class _MarkSheetState extends State<_MarkSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.mark?.title ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.mark?.note ?? '',
  );
  late CalendarMarkKind _kind = widget.mark?.kind ?? CalendarMarkKind.countdown;
  late DateTime _date = widget.mark?.date ?? DateTime.now();
  late bool _yearly = widget.mark?.yearly ?? false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showLedgerDatePicker(context, initial: _date);
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      AppToast.show(context, '给这个日子起个名字');
      return;
    }
    final mark = CalendarMark(
      id: widget.mark?.id ?? 'cal-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      date: CalendarDates.dayOnly(_date),
      kind: _kind,
      yearly: _yearly,
      note: _note.text.trim(),
      createdAt:
          widget.mark?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    await CalendarStore.instance.saveMark(mark);
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.show(context, widget.mark == null ? '已添加到日历' : '已保存');
  }

  Future<void> _delete() async {
    final current = widget.mark;
    if (current == null) return;
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        maxWidth: 330,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '删除「${current.title}」？',
              style: ctx.heading(size: 18, color: ctx.c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              '删除后不会从云端恢复，但可以重新添加。',
              style: ctx.body(size: 13, color: ctx.c.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '取消',
                    outlined: true,
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AccentButton(
                    text: '删除',
                    danger: true,
                    onTap: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await CalendarStore.instance.removeMark(current.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.show(context, '已删除');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.mark == null ? '记录一个日子' : '编辑这个日子',
                      style: context.heading(size: 20, color: c.ink),
                    ),
                  ),
                  if (widget.mark != null)
                    Pressable(
                      onTap: _delete,
                      scale: .94,
                      hoverLift: 0,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c.stamp.withAlpha(24),
                          shape: BoxShape.circle,
                          border: Border.all(color: c.stamp.withAlpha(80)),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.trash, width: 1.9),
                            size: 16,
                            color: c.stamp,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _kindSwitch(context),
              const SizedBox(height: 14),
              CitroField(
                label: '标题',
                hint: _kind == CalendarMarkKind.countdown
                    ? '例如：出发去大理、考试、发工资'
                    : '例如：在一起、妈妈生日、搬家',
                controller: _title,
                maxLength: 20,
              ),
              const SizedBox(height: 12),
              _dateRow(context),
              const SizedBox(height: 12),
              _yearlyRow(context),
              const SizedBox(height: 12),
              CitroField(
                label: '备注',
                hint: '想对这个日子说点什么（可选）',
                controller: _note,
                maxLength: 40,
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              AccentButton(
                text: widget.mark == null ? '添加' : '保存修改',
                onTap: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindSwitch(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        for (final kind in CalendarMarkKind.values) ...[
          if (kind != CalendarMarkKind.values.first) const SizedBox(width: 8),
          Expanded(
            child: Pressable(
              onTap: () => setState(() => _kind = kind),
              scale: .97,
              child: AnimatedContainer(
                duration: CitroMotion.size,
                curve: CitroMotion.easeOut,
                height: 40,
                decoration: BoxDecoration(
                  color: _kind == kind
                      ? (kind == CalendarMarkKind.countdown
                                ? c.accent2
                                : c.stamp)
                            .withAlpha(24)
                      : c.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _kind == kind
                        ? (kind == CalendarMarkKind.countdown
                              ? c.accent2
                              : c.stamp)
                        : c.line,
                  ),
                ),
                child: Center(
                  child: Text(
                    kind.label,
                    style: context.body(
                      size: 13,
                      weight: _kind == kind ? FontWeight.w700 : FontWeight.w400,
                      color: _kind == kind
                          ? (kind == CalendarMarkKind.countdown
                                ? c.accentInk
                                : c.stamp)
                          : c.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateRow(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '日期',
          style: context.body(
            size: 12,
            weight: FontWeight.w700,
            color: c.inkSoft,
          ),
        ),
        const SizedBox(height: 8),
        Pressable(
          onTap: _pickDate,
          scale: .98,
          hoverLift: 0,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.line2),
            ),
            child: Row(
              children: [
                AppIcon(
                  strokeSvg(AppIcons.calendar, width: 1.9),
                  size: 17,
                  color: c.accentInk,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${CalendarDates.fullDate(_date)} '
                    '${CalendarDates.weekday(_date)}',
                    style: context.body(size: 14, color: c.ink),
                  ),
                ),
                Text('更换', style: context.body(size: 11, color: c.inkSoft)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _yearlyRow(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '每年重复',
                style: context.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '生日、周年纪念会每年提醒一次',
                style: context.body(size: 10.5, color: c.inkSoft),
              ),
            ],
          ),
        ),
        Pressable(
          onTap: () => setState(() => _yearly = !_yearly),
          scale: .94,
          hoverLift: 0,
          borderRadius: BorderRadius.circular(99),
          child: AnimatedContainer(
            duration: CitroMotion.size,
            curve: CitroMotion.easeOut,
            width: 46,
            height: 27,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _yearly ? c.mint : c.line,
              borderRadius: BorderRadius.circular(99),
            ),
            child: AnimatedAlign(
              duration: CitroMotion.size,
              curve: CitroMotion.easeOut,
              alignment: _yearly ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                  boxShadow: CitroColors.shadows.paper(c),
                ),
                child: _yearly
                    ? Icon(Icons.check_rounded, size: 13, color: c.mintInk)
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
