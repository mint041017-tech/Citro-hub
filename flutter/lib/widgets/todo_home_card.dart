import 'package:flutter/material.dart';

import '../services/pomodoro.dart';
import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import '../todo/todo_models.dart';
import '../todo/todo_page.dart';
import '../todo/todo_store.dart';
import '../todo/todo_theme.dart';
import '../widgets/card_flight.dart';
import '../widgets/card_morph.dart';
import 'paper.dart';

/// 首页待办卡片。
///
/// 与记账卡同一套信息层级：标题行 → 主指标 → 进度 → 任务列表 →
/// 小票式指标块（专注 / 连续 / 本周）。小卡只保留主指标和进度，
/// 标准卡补两条任务与指标块，大卡自动列出更多任务。
class TodoHomeCard extends StatelessWidget {
  const TodoHomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TodoScope(
      child: PaperCard(
        tapeColor: c.tape3,
        tapeAngle: 1.8,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        onTap: () => _open(context),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            TodoStore.instance,
            PomodoroState.instance,
          ]),
          builder: (context, _) {
            final store = TodoStore.instance;
            final tasks = store.todayTasks;
            final done = tasks.where((t) => t.done).length;
            final open = tasks.where((t) => !t.done).toList();
            return LayoutBuilder(
              builder: (context, cons) {
                final compact = cons.maxHeight < 150 || cons.maxWidth < 230;
                if (compact) {
                  return _compact(context, tasks, done, open);
                }
                final large = cons.maxHeight >= 250 || cons.maxWidth >= 420;
                return _full(context, tasks, done, open, large: large);
              },
            );
          },
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final rect = CitroCardFlight.rectOf(context);
    if (rect.isEmpty) {
      Navigator.of(context).pushNamed('/todo');
      return;
    }
    CitroCardMorph.pushPageSoft(
      context,
      source: rect,
      settings: const RouteSettings(name: '/todo'),
      builder: (_) => const TodoPage(),
      snapshot: CitroCardFlight.snapshotOf(context, rect),
    );
  }

  // -------------------------------------------------------------------------
  // 紧凑：主数字 + 进度 + 专注/连续
  // -------------------------------------------------------------------------

  Widget _compact(
    BuildContext context,
    List<TodoTask> tasks,
    int done,
    List<TodoTask> open,
  ) {
    final c = context.c;
    final total = tasks.length;
    final remaining = total - done;
    final rate = total == 0 ? 0.0 : done / total;
    final focus = PomodoroState.instance.todayMinutes;
    final streak = TodoStore.instance.streak;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIcon(
              strokeSvg(AppIcons.list, width: 2),
              size: 15,
              color: c.accentInk,
            ),
            const SizedBox(width: 5),
            Text(
              '待办',
              style: context.heading(
                size: 13,
                color: c.accentInk,
                letterSpacing: .3,
              ),
            ),
            const Spacer(),
            Text(
              total == 0 ? '今天空着' : '完成 $done/$total',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: CitroType.caption, color: c.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$remaining',
                      style: context.heading(size: 24, color: c.ink, height: 1),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        total == 0 ? '件待办' : '件没做完',
                        style: context.ui(
                          size: CitroType.caption,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${(rate * 100).round()}%',
                style: context.ui(
                  size: CitroType.caption,
                  weight: CitroType.strong,
                  color: c.accentInk,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        _progress(context, rate),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '专注 $focus 分 · 连续 $streak 天',
            maxLines: 1,
            style: context.ui(size: CitroType.caption, color: c.inkSoft),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 标准 / 大卡
  // -------------------------------------------------------------------------

  Widget _full(
    BuildContext context,
    List<TodoTask> tasks,
    int done,
    List<TodoTask> open, {
    required bool large,
  }) {
    final c = context.c;
    final total = tasks.length;
    final remaining = total - done;
    final rate = total == 0 ? 0.0 : done / total;
    final focus = PomodoroState.instance.todayMinutes;
    final streak = TodoStore.instance.streak;
    final week = TodoStore.instance.weekDone.fold<int>(
      0,
      (sum, item) => sum + item.$2,
    );
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(
              strokeSvg(AppIcons.list, width: 2),
              size: 18,
              color: c.accentInk,
            ),
            const SizedBox(width: 6),
            Text(
              '待办',
              style: context.heading(
                size: 13,
                color: c.accentInk,
                letterSpacing: .3,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${now.month}月${now.day}日',
              style: context.ui(size: CitroType.caption, color: c.inkSoft),
            ),
            const Spacer(),
            Text(
              total == 0 ? '今天空着' : '完成 $done/$total',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: CitroType.caption, color: c.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$remaining',
                      style: context.heading(
                        size: large ? 32 : 24,
                        color: c.ink,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        total == 0 ? '件待办' : '件没做完',
                        style: context.ui(
                          size: CitroType.caption,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '专注 $focus 分',
                maxLines: 1,
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: _progress(context, rate)),
            const SizedBox(width: 6),
            Text(
              '${(rate * 100).round()}%',
              style: context.ui(
                size: CitroType.caption,
                weight: CitroType.strong,
                color: c.accentInk,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, cons) {
              if (open.isEmpty) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    total == 0 ? '今天还没有任务，先写一件小事' : '今天的都做完了，去休息一下',
                    maxLines: 2,
                    style: context.ui(
                      size: CitroType.caption,
                      color: c.inkSoft,
                      height: 1.5,
                    ),
                  ),
                );
              }
              final rowHeight = large ? 21.0 : 18.0;
              final maxRows = (cons.maxHeight / rowHeight).floor();
              final count = maxRows.clamp(1, open.length);
              return Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final task in open.take(count))
                    SizedBox(
                      height: rowHeight,
                      child: _row(context, task, large: large),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _stat(context, '专注', '$focus 分'),
            const SizedBox(width: 6),
            _stat(context, '连续', '$streak 天'),
            const SizedBox(width: 6),
            _stat(context, '本周', '$week 件'),
          ],
        ),
      ],
    );
  }

  Widget _progress(BuildContext context, double rate) {
    final c = context.c;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: rate.clamp(0.0, 1.0),
        minHeight: 4,
        backgroundColor: c.line2.withAlpha(90),
        valueColor: AlwaysStoppedAnimation(c.accent),
      ),
    );
  }

  Widget _row(BuildContext context, TodoTask task, {required bool large}) {
    final c = context.c;
    final category = TodoStore.instance.categoryOf(task.categoryId);
    final time = taskTimeText(task);
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: category.tint,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.ui(size: CitroType.label, color: c.ink),
          ),
        ),
        if (large && task.doing) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: c.accent.withAlpha(26),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '进行中',
              style: context.ui(
                size: 8.5,
                weight: CitroType.strong,
                color: c.accentInk,
              ),
            ),
          ),
        ],
        if (time.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            time,
            maxLines: 1,
            style: context.ui(size: CitroType.caption, color: c.inkSoft),
          ),
        ],
      ],
    );
  }

  /// 一枚小票式指标块，与记账卡保持同一套视觉。
  Widget _stat(BuildContext context, String label, String value) {
    final c = context.c;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: 8.5, color: c.inkSoft),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(
                size: 11,
                weight: CitroType.strong,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
