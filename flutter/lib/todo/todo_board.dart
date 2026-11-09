import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/play_log.dart';
import '../services/pomodoro.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'todo_ai.dart';
import 'todo_models.dart';
import 'todo_review.dart';
import 'todo_store.dart';
import 'todo_ui.dart';

/// 看板：日期、今日复盘、任务统计、专注统计、心情。
class TodoBoard extends StatefulWidget {
  final bool wide;
  const TodoBoard({super.key, this.wide = false});

  @override
  State<TodoBoard> createState() => _TodoBoardState();
}

class _TodoBoardState extends State<TodoBoard> {
  late DateTime _day = dayOf(DateTime.now());
  bool _summarizing = false;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    PomodoroState.instance.ensureInit();
    TodoStore.instance.ensureInit();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoReview());
  }

  /// 自动复盘：到点且今天还没有复盘时生成一版草稿，失败静默。
  Future<void> _maybeAutoReview() async {
    if (_autoTried) return;
    _autoTried = true;
    final store = TodoStore.instance;
    if (!store.autoReviewEnabled) return;
    final now = DateTime.now();
    final parts = store.autoReviewTime.split(':');
    final h = int.tryParse(parts.first) ?? 21;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 30 : 30;
    final due = DateTime(now.year, now.month, now.day, h, m);
    if (now.isBefore(due)) return;
    if (store.reviewFor(now) != null) return;
    try {
      final text = await TodoAi.summary(
        day: now,
        tasks: store.tasksOn(now),
        moods: store.moodsOn(now),
        focusMinutes: _focusMinutesOn(now),
        streak: store.streak,
      );
      if (!mounted) return;
      await store.saveReview(now, text, ai: true, auto: true);
      if (mounted) setState(() {});
    } catch (_) {
      // 自动任务失败不打扰用户，打开看板仍可手动生成。
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        TodoStore.instance,
        PomodoroState.instance,
      ]),
      builder: (context, _) {
        final store = TodoStore.instance;
        final tasks = store.tasksOn(_day);
        final isToday = _day == dayOf(DateTime.now());
        return widget.wide
            ? _wideBody(context, store, tasks, isToday)
            : _narrowBody(context, store, tasks, isToday);
      },
    );
  }

  Widget _wideBody(
    BuildContext context,
    TodoStore store,
    List<TodoTask> tasks,
    bool isToday,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: _dayBar(context, isToday),
      ),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                children: [
                  _reviewCard(context, store, tasks),
                  const SizedBox(height: 12),
                  _focusStats(context),
                  _footer(context, isToday),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 6,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 0, 12, 96),
                children: [_taskStats(context, tasks)],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _narrowBody(
    BuildContext context,
    TodoStore store,
    List<TodoTask> tasks,
    bool isToday,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
    children: [
      _dayBar(context, isToday),
      const SizedBox(height: 12),
      _reviewCard(context, store, tasks),
      const SizedBox(height: 12),
      _taskStats(context, tasks),
      const SizedBox(height: 12),
      _focusStats(context),
      _footer(context, isToday),
    ],
  );

  Widget _footer(BuildContext context, bool isToday) {
    if (isToday) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        '正在查看 ${_day.month} 月 ${_day.day} 日 的记录',
        textAlign: TextAlign.center,
        style: context.ui(size: CitroType.caption, color: context.c.inkSoft),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 日期
  // -------------------------------------------------------------------------

  Widget _dayBar(BuildContext context, bool isToday) {
    final c = context.c;
    return Row(
      children: [
        Pressable(
          onTap: () =>
              setState(() => _day = _day.subtract(const Duration(days: 1))),
          scale: .9,
          child: _arrow(context, AppIcons.chevronLeft),
        ),
        const SizedBox(width: 6),
        Pressable(
          onTap: () async {
            final d = await showTodoDatePicker(context, initial: _day);
            if (d != null && mounted) setState(() => _day = dayOf(d));
          },
          scale: .98,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  strokeSvg(AppIcons.calendar, width: 1.8),
                  size: 15,
                  color: c.accentInk,
                ),
                const SizedBox(width: 6),
                Text(
                  isToday
                      ? '今天 · ${_day.month}月${_day.day}日'
                      : '${_day.year}年${_day.month}月${_day.day}日',
                  style: context.ui(
                    size: CitroType.meta,
                    weight: CitroType.strong,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Pressable(
          onTap: () => setState(() => _day = _day.add(const Duration(days: 1))),
          scale: .9,
          child: _arrow(context, AppIcons.chevronRight),
        ),
        const Spacer(),
        if (!isToday)
          Pressable(
            onTap: () => setState(() => _day = dayOf(DateTime.now())),
            scale: .95,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: c.hl.withAlpha(120),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: c.accent.withAlpha(70)),
              ),
              child: Center(
                child: Text(
                  '回到今天',
                  style: context.ui(
                    size: CitroType.caption,
                    weight: CitroType.strong,
                    color: c.accentInk,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _arrow(BuildContext context, String icon) {
    final c = context.c;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.line),
      ),
      child: Center(
        child: AppIcon(strokeSvg(icon, width: 2), size: 15, color: c.inkSoft),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 复盘
  // -------------------------------------------------------------------------

  Widget _reviewCard(
    BuildContext context,
    TodoStore store,
    List<TodoTask> tasks,
  ) {
    final c = context.c;
    final review = store.reviewFor(_day);
    final highlights = _highlights(store, tasks);
    final auto = store.autoReviewEnabled
        ? '每天 ${store.autoReviewTime} 自动总结'
        : '自动复盘未开启';
    return _Panel(
      title: '今日复盘',
      icon: AppIcons.note,
      minHeight: 260,
      trailing: TodoMiniAction(
        label: '详情',
        onTap: () => _openDayDetail(context, store, tasks),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡片只放要点，完整内容点右上角「详情」。
          if (highlights.isEmpty)
            Text(
              '今天还没有留下记录，去待办或专注里做一点什么吧。',
              style: context.ui(
                size: CitroType.body,
                color: c.inkSoft,
                height: 1.7,
              ),
            )
          else
            for (final h in highlights.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    AppIcon(
                      strokeSvg(h.icon, width: 2),
                      size: 15,
                      color: c.accentInk,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        h.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.ui(
                          size: CitroType.body,
                          color: c.ink2,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (review != null) ...[
            const SizedBox(height: 2),
            Text(
              '复盘：${review.text}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.ui(
                size: CitroType.body,
                color: c.ink2,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Pressable(
                onTap: _summarizing ? null : () => _summarize(context, tasks),
                scale: .97,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: c.accent.withAlpha(40),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.accent.withAlpha(110)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_summarizing)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.accentInk,
                          ),
                        )
                      else
                        AppIcon(
                          strokeSvg(AppIcons.sparkle, width: 1.8),
                          size: 14,
                          color: c.accentInk,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        _summarizing ? '正在总结…' : 'CiCi 总结',
                        style: context.ui(
                          size: CitroType.caption,
                          weight: CitroType.strong,
                          color: c.accentInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                auto,
                style: context.ui(size: CitroType.small, color: c.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 当天在 App 里的行为要点：任务、专注、心情、打卡。
  List<({String icon, String text})> _highlights(
    TodoStore store,
    List<TodoTask> tasks,
  ) {
    final out = <({String icon, String text})>[];
    final done = tasks.where((t) => t.done).length;
    final doing = tasks.where((t) => t.state == TodoTaskState.doing).length;
    if (tasks.isNotEmpty) {
      out.add((
        icon: AppIcons.check,
        text:
            '完成 $done / ${tasks.length} 条任务'
            '${doing > 0 ? '，$doing 条进行中' : ''}',
      ));
      final titles = tasks
          .where((t) => t.done)
          .map((t) => t.title)
          .take(2)
          .toList();
      if (titles.isNotEmpty) {
        out.add((icon: AppIcons.note, text: '做完：${titles.join('、')}'));
      }
    }
    final focus = _focusMinutesOn(_day);
    if (focus > 0) {
      out.add((icon: AppIcons.target, text: '专注 $focus 分钟'));
    }
    final play = PlayLog.minutesOn(_day);
    if (play > 0) {
      out.add((icon: AppIcons.games, text: '小游戏 $play 分钟'));
    }
    final moods = store.moodsOn(_day);
    if (moods.isNotEmpty) {
      final kinds = {for (final m in moods) m.kind.label}.join('、');
      out.add((icon: AppIcons.smile, text: '心情 $kinds（${moods.length} 次）'));
    }
    if (dayOf(_day) == dayOf(DateTime.now())) {
      final state = AppState.instance;
      out.add((
        icon: AppIcons.calendar,
        text: state.checkedInToday
            ? '已打卡，连续 ${state.checkinStreak} 天'
            : '今天还没打卡',
      ));
    }
    return out;
  }

  Future<void> _openDayDetail(
    BuildContext context,
    TodoStore store,
    List<TodoTask> tasks,
  ) async {
    await showCitroSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DayDetailSheet(
        day: _day,
        highlights: _highlights(store, tasks),
        review: store.reviewFor(_day),
        auto: store.autoReviewEnabled
            ? '每天 ${store.autoReviewTime} 自动总结'
            : '自动复盘未开启',
        onEdit: () {
          Navigator.of(context).pop();
          showReviewEditor(context, day: _day);
        },
        onSummarize: () {
          Navigator.of(context).pop();
          _summarize(context, tasks);
        },
      ),
    );
  }

  Future<void> _summarize(BuildContext context, List<TodoTask> tasks) async {
    if (_summarizing) return;
    setState(() => _summarizing = true);
    try {
      final store = TodoStore.instance;
      // 社区动态里往往能看出当天的心情，一起喂给 CiCi 作参考。
      var extra = '';
      try {
        if (AppState.instance.loggedIn) {
          final posts = await Api.posts();
          final mine = posts
              .where(
                (p) =>
                    p.mine &&
                    dayOf(DateTime.fromMillisecondsSinceEpoch(p.ts)) ==
                        dayOf(_day),
              )
              .toList();
          if (mine.isNotEmpty) {
            extra =
                '今天发的社区动态（${mine.length} 条）：\n'
                '${mine.map((p) => '- ${p.text.trim()}').join('\n')}';
          }
        }
      } catch (_) {
        // 社区拉取失败不影响复盘生成。
      }
      final text = await TodoAi.summary(
        day: _day,
        tasks: tasks,
        moods: store.moodsOn(_day),
        focusMinutes: _focusMinutesOn(_day),
        streak: store.streak,
        gameMinutes: PlayLog.minutesOn(_day),
        extraContext: extra,
      );
      if (!mounted) return;
      await store.saveReview(_day, text, ai: true);
      if (mounted) AppToast.show(context, '复盘已生成，可以再编辑');
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString().replaceFirst('AiException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  // -------------------------------------------------------------------------
  // 任务统计
  // -------------------------------------------------------------------------

  Widget _taskStats(BuildContext context, List<TodoTask> tasks) {
    final c = context.c;
    final store = TodoStore.instance;
    final total = tasks.length;
    final done = tasks.where((t) => t.done).length;
    final open = total - done;
    final rate = total == 0 ? 0.0 : done / total;
    final week = store.weekDone;
    return _Panel(
      title: '任务看板',
      icon: AppIcons.board,
      minHeight: 380,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(rate * 100).round()}%',
                style: context.heading(size: 34, color: c.ink, height: 1),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 3),
                child: Text(
                  '完成率',
                  style: context.ui(size: CitroType.caption, color: c.inkSoft),
                ),
              ),
              const Spacer(),
              Text(
                '$done / $total',
                style: context.ui(
                  size: CitroType.label,
                  weight: CitroType.strong,
                  color: c.accentInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: rate.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: c.line2.withAlpha(100),
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat(context, '已完成', '$done', c.mintInk),
              _stat(context, '未完成', '$open', open > 0 ? c.stamp : c.mintInk),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat(context, '连续天数', '${store.streak} 天', c.accentInk),
              _stat(context, '今日任务', '$total 条', c.ink2),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                '最近 7 天完成',
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
              const Spacer(),
              Text(
                '合计 ${week.fold<int>(0, (s, e) => s + e.$2)} 条',
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 10),
          MiniBars(
            values: [for (final e in week) e.$2],
            labels: [for (final e in week) _weekLabel(e.$1)],
            color: c.accent,
            height: 132,
            showValues: true,
          ),
        ],
      ),
    );
  }

  String _weekLabel(DateTime d) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return names[d.weekday - 1];
  }

  Widget _stat(BuildContext context, String label, String value, Color color) {
    final c = context.c;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.ui(
              size: 27,
              weight: CitroType.strong,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: context.ui(size: CitroType.caption, color: c.inkSoft),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 专注统计
  // -------------------------------------------------------------------------

  int _focusMinutesOn(DateTime day) {
    final d = dayOf(day);
    var total = 0;
    for (final s in PomodoroState.instance.sessions) {
      if (dayOf(s.at) == d) total += s.minutes;
    }
    return total;
  }

  Widget _focusStats(BuildContext context) {
    final c = context.c;
    final today = _focusMinutesOn(DateTime.now());
    final week = <int>[];
    final labels = <String>[];
    for (var i = 6; i >= 0; i--) {
      final d = dayOf(DateTime.now()).subtract(Duration(days: i));
      week.add(_focusMinutesOn(d));
      labels.add(_weekLabel(d));
    }
    final total = week.fold<int>(0, (s, e) => s + e);
    return _Panel(
      title: '专注',
      icon: AppIcons.target,
      minHeight: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：当日
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$today',
                style: context.ui(
                  weight: CitroType.strong,
                  size: CitroType.hero,
                  color: c.ink,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '今日分钟',
                  style: context.ui(size: CitroType.small, color: c.inkSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: c.line),
          const SizedBox(height: 12),
          // 第二行：本周
          Row(
            children: [
              Text(
                '本周',
                style: context.ui(
                  size: CitroType.label,
                  weight: CitroType.strong,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$total 分钟',
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
              const Spacer(),
              Text(
                '近 7 天',
                style: context.ui(size: CitroType.small, color: c.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: MiniBars(
              values: week,
              labels: labels,
              color: c.mint,
              height: 96,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 心情
  // -------------------------------------------------------------------------
}

/// 复盘详情：完整的行为要点 + 复盘正文，可继续编辑或让 CiCi 重写。
class _DayDetailSheet extends StatelessWidget {
  final DateTime day;
  final List<({String icon, String text})> highlights;
  final DailyReview? review;
  final String auto;
  final VoidCallback onEdit;
  final VoidCallback onSummarize;

  const _DayDetailSheet({
    required this.day,
    required this.highlights,
    required this.review,
    required this.auto,
    required this.onEdit,
    required this.onSummarize,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: c.line2)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${day.month} 月 ${day.day} 日 · 这一天的记录',
                    style: context.ui(
                      size: CitroType.title,
                      weight: CitroType.strong,
                      color: c.ink,
                    ),
                  ),
                ),
                Pressable(
                  onTap: () => Navigator.of(context).pop(),
                  scale: .9,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.bg2.withAlpha(90),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.line),
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(AppIcons.close, width: 2),
                        size: 15,
                        color: c.ink2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              auto,
              style: context.ui(size: CitroType.caption, color: c.inkSoft),
            ),
            const SizedBox(height: 16),
            for (final h in highlights)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(
                      strokeSvg(h.icon, width: 2),
                      size: 16,
                      color: c.accentInk,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        h.text,
                        style: context.ui(
                          size: CitroType.bodyLg,
                          color: c.ink2,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Divider(color: c.line, height: 1),
            const SizedBox(height: 14),
            Text(
              '复盘',
              style: context.ui(
                size: CitroType.label,
                weight: CitroType.strong,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              review?.text.trim().isNotEmpty == true
                  ? review!.text
                  : '还没有写复盘。可以让 CiCi 根据这一天的记录总结一版。',
              style: context.ui(
                size: CitroType.bodyLg,
                color: c.ink2,
                height: 1.8,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '编辑复盘',
                    outlined: true,
                    height: 42,
                    onTap: onEdit,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AccentButton(
                    text: 'CiCi 总结',
                    height: 42,
                    onTap: onSummarize,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String icon;
  final Widget? trailing;
  final Widget child;

  /// 卡片的最小高度：页面上只剩三张时用大一点，别显得空。
  final double? minHeight;

  const _Panel({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.paper(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(
                strokeSvg(icon, width: 1.8),
                size: 17,
                color: c.accentInk,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: context.ui(
                  size: CitroType.label,
                  weight: CitroType.strong,
                  color: c.ink,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
