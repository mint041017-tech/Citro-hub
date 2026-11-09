import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'todo_models.dart';
import 'todo_store.dart';
import 'todo_theme.dart';
import 'todo_ui.dart';

/// 记录一次心情。
Future<MoodEntry?> showMoodSheet(
  BuildContext context, {
  MoodKind? kind,
  DateTime? day,
}) {
  return showCitroSheet<MoodEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => TodoScope(
      child: _MoodSheet(initial: kind, day: day ?? DateTime.now()),
    ),
  );
}

class _MoodSheet extends StatefulWidget {
  final MoodKind? initial;
  final DateTime day;

  const _MoodSheet({this.initial, required this.day});

  @override
  State<_MoodSheet> createState() => _MoodSheetState();
}

class _MoodSheetState extends State<_MoodSheet> {
  late MoodKind _kind = widget.initial ?? MoodKind.calm;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// 记录时刻：补记过去日期时取「该日期 + 此刻」，避免时间一律记成 00:00。
  DateTime _recordTime(DateTime day) {
    final now = DateTime.now();
    final sameDay =
        DateTime(day.year, day.month, day.day) ==
        DateTime(now.year, now.month, now.day);
    return sameDay
        ? now
        : DateTime(day.year, day.month, day.day, now.hour, now.minute);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: c.line),
            boxShadow: CitroColors.shadows.lg(c),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '记录心情',
                    style: context.ui(
                      weight: CitroType.strong,
                      size: CitroType.subtitle,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.day.month} 月 ${widget.day.day} 日',
                    style: context.ui(
                      size: CitroType.caption,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final kind in MoodKind.values) ...[
                    Expanded(
                      child: Pressable(
                        scale: .94,
                        onTap: () => setState(() => _kind = kind),
                        child: AnimatedContainer(
                          duration: CitroMotion.hover,
                          curve: CitroMotion.easeColor,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _kind == kind
                                ? kind.color.withAlpha(36)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _kind == kind
                                  ? kind.color.withAlpha(160)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            children: [
                              MoodFace(
                                kind: kind,
                                size: 36,
                                selected: _kind == kind,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                kind.label,
                                style: context.ui(
                                  size: CitroType.small,
                                  weight: _kind == kind
                                      ? CitroType.strong
                                      : CitroType.regular,
                                  color: _kind == kind ? kind.color : c.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (kind != MoodKind.values.last) const SizedBox(width: 4),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              CitroField(
                label: '发生了什么（可选）',
                hint: '一句话记下原因，之后回看更有用',
                controller: _note,
                maxLines: 3,
                maxLength: 120,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AccentButton(
                  text: '记下',
                  height: 44,
                  onTap: () {
                    final entry = TodoStore.instance.addMood(
                      _kind,
                      note: _note.text,
                      at: _recordTime(widget.day),
                    );
                    Navigator.of(context).pop(entry);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 心情详情：可切换日期查看记录与近 7 天趋势。
Future<void> showMoodDetail(BuildContext context, {DateTime? initial}) {
  return showCitroDialog<void>(
    context,
    builder: (_) =>
        TodoScope(child: _MoodDetailDialog(initial: initial ?? DateTime.now())),
  );
}

class _MoodDetailDialog extends StatefulWidget {
  final DateTime initial;
  const _MoodDetailDialog({required this.initial});

  @override
  State<_MoodDetailDialog> createState() => _MoodDetailDialogState();
}

class _MoodDetailDialogState extends State<_MoodDetailDialog> {
  late DateTime _day = dayOf(widget.initial);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      maxWidth: 520,
      child: ListenableBuilder(
        listenable: TodoStore.instance,
        builder: (context, _) {
          final store = TodoStore.instance;
          final entries = store.moodsOn(_day);
          final trend = store.moodTrend(7);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '心情记录',
                style: context.ui(
                  weight: CitroType.strong,
                  size: CitroType.heading,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Pressable(
                    onTap: () => setState(
                      () => _day = _day.subtract(const Duration(days: 1)),
                    ),
                    scale: .9,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.line),
                      ),
                      child: Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.chevronLeft, width: 2),
                          size: 16,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_day.year} 年 ${_day.month} 月 ${_day.day} 日',
                        style: context.ui(
                          size: CitroType.meta,
                          weight: CitroType.strong,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                  Pressable(
                    onTap: () => setState(
                      () => _day = _day.add(const Duration(days: 1)),
                    ),
                    scale: .9,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.line),
                      ),
                      child: Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.chevronRight, width: 2),
                          size: 16,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text(
                      '这一天还没有记录',
                      style: context.ui(size: CitroType.meta, color: c.inkSoft),
                    ),
                  ),
                )
              else
                for (final e in entries)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${e.ts.hour.toString().padLeft(2, '0')}:${e.ts.minute.toString().padLeft(2, '0')}',
                            style: context.ui(
                              size: CitroType.caption,
                              color: c.inkSoft,
                            ),
                          ),
                        ),
                        MoodFace(kind: e.kind, size: 26),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.kind.label,
                                style: context.ui(
                                  size: CitroType.label,
                                  weight: CitroType.strong,
                                  color: c.ink,
                                ),
                              ),
                              if (e.note.trim().isNotEmpty)
                                Text(
                                  e.note,
                                  style: context.ui(
                                    size: CitroType.caption,
                                    color: c.accentInk,
                                    height: 1.5,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Pressable(
                          onTap: () => store.deleteMood(e.id),
                          scale: .9,
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: AppIcon(
                              strokeSvg(AppIcons.trash, width: 2),
                              size: 15,
                              color: c.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 14),
              Text(
                '最近 7 天',
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final item in trend) ...[
                    Expanded(
                      child: Column(
                        children: [
                          if (item.$2 != null)
                            MoodFace(kind: item.$2!.kind, size: 28)
                          else
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: c.bg2,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.line),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.$1.day}',
                            style: context.ui(
                              size: CitroType.caption,
                              color: c.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AccentButton(
                  text: '记录这一天的心情',
                  outlined: true,
                  height: 46,
                  onTap: () async {
                    final entry = await showMoodSheet(context, day: _day);
                    if (entry != null) setState(() {});
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
