import 'package:flutter/material.dart';

import '../services/pomodoro.dart';
import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'todo_ai.dart';
import 'todo_board.dart';
import 'todo_cici.dart';
import 'todo_editor.dart';
import 'todo_focus.dart';
import 'todo_models.dart';
import 'todo_store.dart';
import '../tingyu/tingyu_controller.dart';
import 'todo_rail.dart';
import 'todo_theme.dart';
import 'todo_ui.dart';

/// 待办模块的一级页面：待办 / 看板 / 小c助手。
class TodoPage extends StatefulWidget {
  final int initialTab;

  const TodoPage({super.key, this.initialTab = 0});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage>
    with SingleTickerProviderStateMixin {
  late int _tab = widget.initialTab.clamp(0, 3);
  int _sub = 0;
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: CitroMotion.tab,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    TodoStore.instance.ensureInit();
    PomodoroState.instance.ensureInit();
    // 待办页也接管混音：专注开始时自动播放听隅的当前混音。
    final nook = NookController.instance;
    PomodoroState.instance.audioHook = (play) async {
      if (play) {
        if (!nook.playing && nook.tracks.isNotEmpty) await nook.send('play');
      } else if (nook.playing) {
        await nook.send('pause');
      }
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _askOverdue());
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  /// 每进一次待办页问一次逾期任务，问过的不再重复打扰。
  final Set<String> _overdueAsked = <String>{};

  Future<void> _askOverdue() async {
    await TodoStore.instance.ensureInit();
    if (!mounted) return;
    final now = DateTime.now();
    TodoTask? target;
    for (final t in TodoStore.instance.tasks) {
      if (t.done || t.kind != TodoKind.task) continue;
      final at = t.dueAt;
      if (at == null || !at.isBefore(now)) continue;
      if (_overdueAsked.contains(t.id)) continue;
      target = t;
      break;
    }
    if (target == null) return;
    final task = target;
    _overdueAsked.add(task.id);
    final action = await showCitroDialog<String>(
      context,
      builder: (ctx) => _overdueCard(ctx, task),
    );
    if (!mounted || action == null) return;
    if (action == 'done') {
      TodoStore.instance.setTaskState(task, TodoTaskState.done);
      return;
    }
    // 没做完：直接让用户换一个新时间。
    final day = await showTodoDatePicker(
      context,
      initial: DateTime.now().add(const Duration(days: 1)),
    );
    if (day == null || !mounted) return;
    final due = task.dueAt ?? DateTime.now();
    final hm = await showTodoTimePicker(
      context,
      initial:
          '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}',
    );
    if (hm == null || !mounted) return;
    final p = hm.split(':');
    task.dueAt = DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(p[0]),
      int.parse(p[1]),
    );
    TodoStore.instance.updateTask(task);
  }

  Widget _overdueCard(BuildContext context, TodoTask task) {
    final c = context.c;
    Widget action(String label, String value, bool primary) => Expanded(
      child: Pressable(
        scale: .98,
        onTap: () => Navigator.of(context).pop(value),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? c.accent.withAlpha(190) : c.bg2.withAlpha(90),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: primary ? c.accent : c.line),
          ),
          child: Text(
            label,
            style: context.body(
              size: CitroType.label,
              weight: CitroType.strong,
              color: primary ? const Color(0xFF2E2C22) : c.ink2,
            ),
          ),
        ),
      ),
    );
    return Center(
      child: DefaultTextStyle.merge(
        // 明确清掉下划线/装饰，避免弹窗文字出现多余的线。
        style: const TextStyle(decoration: TextDecoration.none),
        child: Container(
          width: 340,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '过了截止时间',
                style: context.body(
                  size: CitroType.title,
                  weight: CitroType.strong,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: CitroType.body, color: c.ink2),
              ),
              const SizedBox(height: 6),
              Text(
                '这条任务完成了吗？没完成就给它换个新时间。',
                style: context.body(size: CitroType.caption, color: c.inkSoft),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  action('还没做', 'reschedule', false),
                  const SizedBox(width: 8),
                  action('已完成', 'done', true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _switchTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
    if (!CitroMotion.reduced(context)) {
      _fade.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final desktop = CitroMotion.desktopLike;
    final top =
        (desktop ? AppSpacing.pageTop(media.size.width) : 4.0) +
        media.padding.top;
    final wide = media.size.width >= 900;
    final pages = <Widget>[
      _TodoTab(
        sub: _sub,
        onSub: (v) => setState(() => _sub = v),
        wide: wide,
        hideTabs: wide,
      ),
      TodoBoard(wide: wide),
      const TodoCici(),
      // 专注也放进 tab 容器：切换时左侧栏完全不动，和待办/数据一致。
      const TodoFocusPage(embedded: true),
    ];
    return TodoScope(
      child: Builder(
        builder: (context) {
          final c = context.c;
          return Scaffold(
            backgroundColor: c.bg,
            body: PaperBackground(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) _rail(context),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 0),
                      child: Column(
                        children: [
                          SizedBox(height: top),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1120),
                              child: _header(context, wide: wide),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1120,
                                ),
                                child: _pages(pages),
                              ),
                            ),
                          ),
                          // 键盘弹起时收起底栏，用高度动画过渡，避免突然消失/出现。
                          if (!wide)
                            AnimatedSize(
                              duration: const Duration(milliseconds: 180),
                              curve: CitroMotion.easeOut,
                              alignment: Alignment.bottomCenter,
                              child:
                                  MediaQuery.viewInsetsOf(context).bottom == 0
                                  ? _bottomBar(context)
                                  : const SizedBox(width: double.infinity),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 三个页面同时挂在树上，切页时只做「淡入 + 轻微右移」，
  /// 曲线与时长跟听隅的切页保持一致，且页面状态不会丢。
  ///
  /// 这里始终保留同一层过渡外壳，切 tab 时不重建页面子树，
  /// 所以 CiCi 这类有内部滚动/输入焦点的页面不会闪一下。
  Widget _pages(List<Widget> pages) {
    return Stack(
      children: [
        for (var i = 0; i < pages.length; i++)
          Offstage(
            offstage: _tab != i,
            child: TickerMode(
              enabled: _tab == i,
              child: _EnterVeil(
                animation: _fade,
                active: _tab == i,
                child: pages[i],
              ),
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 桌面端左侧窄条：只显示图标，悬停展开文字
  // -------------------------------------------------------------------------

  Widget _rail(BuildContext context) => TodoRail(
    active: switch (_tab) {
      1 => 'data',
      2 => 'cici',
      3 => 'focus',
      _ => 'todo',
    },
    onBack: () => _back(context),
    onSelect: (key) {
      switch (key) {
        case 'todo':
          _switchTab(0);
        case 'data':
          _switchTab(1);
        case 'cici':
          _switchTab(2);
        case 'focus':
          _switchTab(3);
      }
    },
  );

  Widget _bottomBar(BuildContext context) {
    final c = context.c;
    const items = [
      (0, '待办', AppIcons.check),
      (3, '专注', AppIcons.target),
      (1, '数据', AppIcons.board),
      (2, 'CiCi', AppIcons.sparkle),
    ];
    // 贴底导航：与食谱页一致，只留一条上边线，不做悬浮胶囊。
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _switchTab(item.$1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(
                          strokeSvg(item.$3, width: 1.9),
                          size: 22,
                          color: _tab == item.$1 ? c.accentInk : c.inkSoft,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.$2,
                          maxLines: 1,
                          style: context.ui(
                            size: 12,
                            weight: _tab == item.$1
                                ? CitroType.strong
                                : FontWeight.w400,
                            color: _tab == item.$1 ? c.accentInk : c.inkSoft,
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

  Widget _header(BuildContext context, {required bool wide}) {
    final c = context.c;
    final title = switch (_tab) {
      1 => '数据',
      2 => 'CiCi',
      3 => '专注',
      _ => '待办',
    };
    final subtitle = switch (_tab) {
      2 => '拆解、提醒、总结',
      3 => '一段一段地做',
      _ => _dateLine(DateTime.now()),
    };
    return Padding(
      padding: wide
          ? const EdgeInsets.only(bottom: 6)
          : const EdgeInsets.fromLTRB(10, 0, 16, 6),
      child: Row(
        children: [
          if (!wide) ...[
            Pressable(
              onTap: () => _back(context),
              scale: .92,
              borderRadius: BorderRadius.circular(99),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.line),
                  boxShadow: CitroColors.shadows.paper(c),
                ),
                child: Center(
                  child: AppIcon(
                    strokeSvg(AppIcons.arrowLeft, width: 2.2),
                    size: 18,
                    color: c.ink2,
                  ),
                ),
              ),
            ),
          ],
          if (!wide) ...[
            const SizedBox(width: 10),
            Text(
              title,
              style: context.ui(
                weight: CitroType.strong,
                size: CitroType.heading,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.ui(size: CitroType.label, color: c.inkSoft),
              ),
            ),
          ],
          if (wide && _tab == 0) ...[
            SizedBox(
              width: 150,
              child: TodoSegTabs<int>(
                dense: true,
                items: const [(0, '今日'), (1, '日程')],
                value: _sub,
                onChanged: (v) => setState(() => _sub = v),
              ),
            ),
          ],
          const Spacer(),
          // 新建只在「待办」页出现；数据和 CiCi 页不需要。
          if (_tab == 0)
            Pressable(
              onTap: () => _openCreate(context),
              scale: .94,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: c.accent.withAlpha(40),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.plus, width: 2.2, color: '#2E2C22'),
                      size: 16,
                      color: const Color(0xFF2E2C22),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '新建',
                      style: context.ui(
                        size: CitroType.label,
                        weight: CitroType.strong,
                        color: const Color(0xFF2E2C22),
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

  /// 待办是从首页进来的，返回时直接回首页，不在中间页面停留。
  void _back(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  Future<void> _openCreate(
    BuildContext context, {
    TodoKind kind = TodoKind.task,
    DateTime? day,
  }) async {
    await showTodoEditor(context, kind: kind, day: day);
  }

  String _dateLine(DateTime d) {
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    return '${d.month} 月 ${d.day} 日 · 周${week[d.weekday - 1]}';
  }
}

// ---------------------------------------------------------------------------
// 待办 Tab（今日 / 日程）
// ---------------------------------------------------------------------------

class _TodoTab extends StatelessWidget {
  final int sub;
  final ValueChanged<int> onSub;
  final bool wide;
  final bool hideTabs;

  const _TodoTab({
    required this.sub,
    required this.onSub,
    this.wide = false,
    this.hideTabs = false,
  });

  @override
  Widget build(BuildContext context) {
    final view = sub == 0
        ? _TodayView(wide: wide)
        : _ScheduleView(
            wide: wide,
            onCreate: (d) => showTodoEditor(context, day: d),
          );
    if (hideTabs) return view;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: TodoSegTabs<int>(
                  dense: true,
                  items: const [(0, '今日'), (1, '日程')],
                  value: sub,
                  onChanged: onSub,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(child: view),
      ],
    );
  }
}

/// 用对话框展示草稿，确认后写入。
Future<bool?> showTodoDraftPreview(
  BuildContext context,
  List<TodoDraft> drafts,
) {
  return showCitroDialog<bool>(
    context,
    builder: (ctx) => _DraftPreviewDialog(drafts: drafts),
  );
}

class _DraftPreviewDialog extends StatefulWidget {
  final List<TodoDraft> drafts;
  const _DraftPreviewDialog({required this.drafts});

  @override
  State<_DraftPreviewDialog> createState() => _DraftPreviewDialogState();
}

class _DraftPreviewDialogState extends State<_DraftPreviewDialog> {
  late final List<bool> _selected = List.filled(widget.drafts.length, true);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '整理结果',
            style: context.ui(
              weight: CitroType.strong,
              size: CitroType.heading,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '确认后写入待办，之后都可以再改。',
            style: context.ui(size: CitroType.meta, color: c.ink2),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.drafts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Pressable(
                scale: .995,
                onTap: () => setState(() => _selected[i] = !_selected[i]),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  decoration: BoxDecoration(
                    color: _selected[i]
                        ? c.accent.withAlpha(22)
                        : c.bg2.withAlpha(70),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selected[i] ? c.accent.withAlpha(120) : c.line,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _selected[i] ? c.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _selected[i] ? c.accent : c.line2,
                          ),
                        ),
                        child: _selected[i]
                            ? const Center(
                                child: AppIcon(
                                  '<path d="M20 6 9 17l-5-5"/>',
                                  size: 10,
                                  color: Color(0xFF2E2C22),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.drafts[i].title,
                              style: context.ui(
                                size: CitroType.body,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _draftMeta(widget.drafts[i]),
                              style: context.ui(
                                size: CitroType.small,
                                color: c.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  text: '取消',
                  outlined: true,
                  height: 42,
                  onTap: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AccentButton(
                  text: '创建 ${_selected.where((e) => e).length} 条',
                  height: 42,
                  onTap: () {
                    _createSelected(context);
                    Navigator.of(context).pop(true);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _draftMeta(TodoDraft d) {
    final parts = <String>[d.kind.label];
    if (d.categoryName.isNotEmpty) parts.add(d.categoryName);
    if (d.at != null) parts.add(formatDateTime(d.at!));
    if (d.kind == TodoKind.habit) {
      final names = <String>['一', '二', '三', '四', '五', '六', '日'];
      parts.add('周${d.days.map((e) => names[e - 1]).join('、')} ${d.time}');
    }
    return parts.join(' · ');
  }

  void _createSelected(BuildContext context) {
    final store = TodoStore.instance;
    for (var i = 0; i < widget.drafts.length; i++) {
      if (!_selected[i]) continue;
      final d = widget.drafts[i];
      final cat = store.categories.firstWhere(
        (c2) => c2.name == d.categoryName,
        orElse: () => store.categories.first,
      );
      final list = store.lists.first;
      store.createTask(
        title: d.title,
        note: d.note,
        kind: d.kind,
        categoryId: cat.id,
        listId: list.id,
        remindAt: d.kind == TodoKind.reminder
            ? (d.at ?? DateTime.now().add(const Duration(hours: 1)))
            : null,
        dueAt: d.kind == TodoKind.task
            ? (d.at ?? DateTime.now().add(const Duration(days: 1)))
            : null,
        habitDays: d.kind == TodoKind.habit
            ? (d.days.isEmpty ? {1, 2, 3, 4, 5} : d.days)
            : null,
        habitTime: d.time,
        subtasks: d.subtasks,
        source: 'ai',
      );
    }
    AppToast.show(context, '已创建任务');
  }
}

// ---------------------------------------------------------------------------
// 今日
// ---------------------------------------------------------------------------

class _TodayView extends StatelessWidget {
  final bool wide;
  const _TodayView({this.wide = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        TodoStore.instance,
        PomodoroState.instance,
      ]),
      builder: (context, _) {
        final store = TodoStore.instance;
        final tasks = store.todayTasks;
        final panels = [
          for (final s in TodoTaskState.values)
            _StatePanel(
              state: s,
              tasks: tasks.where((t) => t.state == s).toList(),
              scrollable: wide,
            ),
        ];
        final head = _TodaySummary(tasks: tasks, horizontal: wide);
        if (!wide) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              head,
              const SizedBox(height: 12),
              for (final p in panels) ...[p, const SizedBox(height: 12)],
              const _TodayFoot(),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head,
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < panels.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: panels[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            const _TodayFoot(),
          ],
        );
      },
    );
  }
}

class _TodayFoot extends StatelessWidget {
  const _TodayFoot();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '本地已保存',
            style: context.ui(size: CitroType.caption, color: c.inkSoft),
          ),
          const Spacer(),
          Text(
            '一步一步，也是向前。',
            style: context.ui(size: CitroType.caption, color: c.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// 待办 / 进行中 / 已完成 三块面板。
class _StatePanel extends StatelessWidget {
  final TodoTaskState state;
  final List<TodoTask> tasks;
  final bool scrollable;

  const _StatePanel({
    required this.state,
    required this.tasks,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = switch (state) {
      TodoTaskState.todo => c.accent,
      TodoTaskState.doing => c.mint,
      TodoTaskState.done => c.inkSoft,
    };
    final empty = switch (state) {
      TodoTaskState.todo => '还没有要做的',
      TodoTaskState.doing => '在任务卡右下角把状态改成进行中',
      TodoTaskState.done => '做完的会收在这里',
    };
    final tiles = tasks.isEmpty
        ? Padding(
            padding: const EdgeInsets.fromLTRB(6, 16, 6, 18),
            child: Text(
              empty,
              style: context.ui(
                size: CitroType.caption,
                color: c.inkSoft,
                height: 1.5,
              ),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final t in tasks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TodoTaskTile(task: t),
                ),
            ],
          );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.paper(c),
      ),
      child: Column(
        mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  state.label,
                  style: context.ui(
                    size: CitroType.label,
                    weight: CitroType.strong,
                    color: c.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  '${tasks.length}',
                  style: context.ui(size: CitroType.caption, color: c.inkSoft),
                ),
              ],
            ),
          ),
          if (scrollable)
            Expanded(
              child: ListView(padding: EdgeInsets.zero, children: [tiles]),
            )
          else
            tiles,
        ],
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  final List<TodoTask> tasks;
  final bool horizontal;

  const _TodaySummary({required this.tasks, this.horizontal = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = TodoStore.instance;
    final total = tasks.length;
    final done = tasks.where((t) => t.done).length;
    final doing = tasks.where((t) => t.state == TodoTaskState.doing).length;
    final todo = tasks.where((t) => t.state == TodoTaskState.todo).length;
    final rate = total == 0 ? 0.0 : done / total;
    final focus = PomodoroState.instance.todayMinutes;
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: rate.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: c.line2.withAlpha(100),
        valueColor: AlwaysStoppedAnimation(c.accent),
      ),
    );
    final dots = <Widget>[
      _dot(context, c.accent, '待办 $todo'),
      _dot(context, c.mint, '进行中 $doing'),
      _dot(context, c.inkSoft, '已完成 $done'),
    ];
    final focusText = Text(
      '专注 $focus 分钟 · 连续 ${store.streak} 天',
      style: context.ui(size: CitroType.caption, color: c.inkSoft),
    );
    final legend = horizontal
        ? Row(
            children: [
              for (var i = 0; i < dots.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                dots[i],
              ],
              const Spacer(),
              focusText,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 12, runSpacing: 6, children: dots),
              const SizedBox(height: 8),
              focusText,
            ],
          );
    final countText = Text(
      total == 0 ? '还没开始' : '$done / $total',
      style: context.ui(size: CitroType.caption, color: c.inkSoft),
    );
    final title = Text(
      '今日进度',
      style: context.ui(
        size: CitroType.label,
        weight: CitroType.strong,
        color: c.ink,
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.paper(c),
      ),
      child: horizontal
          ? Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 4), countText],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [bar, const SizedBox(height: 8), legend],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [title, const Spacer(), countText]),
                const SizedBox(height: 10),
                bar,
                const SizedBox(height: 10),
                legend,
              ],
            ),
    );
  }

  Widget _dot(BuildContext context, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: context.ui(size: CitroType.caption, color: context.c.inkSoft),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 任务行
// ---------------------------------------------------------------------------

/// 任务状态下拉：待办 / 进行中 / 已完成。
class _TaskStateSelect extends StatelessWidget {
  final TodoTask task;

  const _TaskStateSelect({required this.task});

  Color _color(CitroColors c, TodoTaskState s) => switch (s) {
    TodoTaskState.todo => c.accent,
    TodoTaskState.doing => c.mint,
    TodoTaskState.done => c.inkSoft,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = task.state;
    final color = _color(c, state);
    return PopupMenuButton<TodoTaskState>(
      initialValue: state,
      tooltip: '切换状态',
      position: PopupMenuPosition.over,
      color: c.surface2,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.line),
      ),
      onSelected: (v) => TodoStore.instance.setTaskState(task, v),
      itemBuilder: (ctx) => [
        for (final s in TodoTaskState.values)
          PopupMenuItem<TodoTaskState>(
            value: s,
            height: 44,
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _color(c, s).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _color(c, s),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '标记为${s.label}',
                  style: context.ui(
                    size: CitroType.label,
                    weight: CitroType.strong,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withAlpha(90)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              state.label,
              style: context.ui(
                size: CitroType.caption,
                weight: CitroType.strong,
                color: state == TodoTaskState.done ? c.ink2 : c.accentInk,
                height: 1,
              ),
            ),
            const SizedBox(width: 2),
            AppIcon(
              strokeSvg(AppIcons.chevronDown, width: 2),
              size: 12,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

/// 任务卡的右键 / 长按菜单：标记重点、删除。
Future<void> _showTaskMenu(
  BuildContext context,
  Offset at,
  TodoTask task,
) async {
  final c = context.c;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  final result = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      at & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    color: c.surface2,
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: c.line),
    ),
    items: [
      PopupMenuItem<String>(
        value: 'edit',
        height: 44,
        child: _menuRow(context, AppIcons.note, '编辑', c.ink),
      ),
      PopupMenuItem<String>(
        value: 'focus',
        height: 44,
        child: _menuRow(
          context,
          AppIcons.flag,
          task.priority > 0 ? '取消重点' : '标记重点',
          c.ink,
        ),
      ),
      PopupMenuItem<String>(
        value: 'delete',
        height: 44,
        child: _menuRow(context, AppIcons.trash, '删除', c.stamp),
      ),
    ],
  );
  if (!context.mounted) return;
  switch (result) {
    case 'edit':
      showTodoEditor(context, initial: task);
    case 'focus':
      TodoStore.instance.toggleFocus(task);
    case 'delete':
      TodoStore.instance.deleteTask(task.id);
  }
}

/// 统一的切页过渡：淡入 + 轻微右移。结构固定，切 tab 时不重建页面子树。
class _EnterVeil extends StatelessWidget {
  final Animation<double> animation;
  final bool active;
  final Widget child;

  const _EnterVeil({
    required this.animation,
    required this.active,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (CitroMotion.reduced(context)) return child;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, inner) {
        final t = active ? Curves.easeOutCubic.transform(animation.value) : 1.0;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: FractionalTranslation(
            translation: Offset(.05 * (1 - t), 0),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }
}

/// 菜单行：小图标底 + 文字，右键菜单和状态下拉共用。
Widget _menuRow(BuildContext context, String icon, String label, Color color) {
  return Row(
    children: [
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: AppIcon(strokeSvg(icon, width: 1.9), size: 14, color: color),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        label,
        style: context.ui(
          size: CitroType.label,
          weight: CitroType.strong,
          color: color,
        ),
      ),
    ],
  );
}

Widget _meta(BuildContext context, Color color, String text) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        text,
        style: context.ui(
          size: CitroType.caption,
          color: context.c.inkSoft,
          height: 1,
        ),
      ),
    ],
  );
}

class TodoTaskTile extends StatefulWidget {
  final TodoTask task;
  final bool compact;

  const TodoTaskTile({super.key, required this.task, this.compact = false});

  @override
  State<TodoTaskTile> createState() => _TodoTaskTileState();
}

class _TodoTaskTileState extends State<TodoTaskTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = TodoStore.instance;
    final task = widget.task;
    final compact = widget.compact;
    final category = store.categoryOf(task.categoryId);
    final time = taskTimeText(task);
    final hasSubs = task.subtasks.isNotEmpty;
    final expanded = _open && hasSubs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onSecondaryTapDown: (d) =>
              _showTaskMenu(context, d.globalPosition, task),
          onLongPressStart: (d) =>
              _showTaskMenu(context, d.globalPosition, task),
          child: Pressable(
            onTap: hasSubs
                ? () => setState(() => _open = !_open)
                : () => showTodoEditor(context, initial: task),
            scale: .995,
            child: AnimatedContainer(
              duration: CitroMotion.hover,
              curve: CitroMotion.easeColor,
              padding: EdgeInsets.fromLTRB(
                12,
                compact ? 10 : 12,
                12,
                compact ? 9 : 10,
              ),
              decoration: BoxDecoration(
                color: c.surface2.withAlpha(task.done ? 165 : 245),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: task.overdue
                      ? c.stamp.withAlpha(120)
                      : (task.state == TodoTaskState.doing
                            ? c.accent.withAlpha(90)
                            : c.line),
                ),
                boxShadow: task.done ? null : CitroColors.shadows.paper(c),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.ui(
                            size: compact ? CitroType.body : CitroType.title,
                            weight: task.done
                                ? CitroType.regular
                                : CitroType.strong,
                            color: task.done ? c.inkSoft : c.ink,
                            height: 1.35,
                          ),
                        ),
                      ),
                      if (hasSubs)
                        AnimatedRotation(
                          turns: _open ? .5 : 0,
                          duration: CitroMotion.hover,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6, top: 2),
                            child: AppIcon(
                              strokeSvg(AppIcons.chevronDown, width: 2),
                              size: 14,
                              color: c.inkSoft,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (time.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: task.overdue ? c.stamp : c.inkSoft,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          time,
                          style: context.ui(
                            size: CitroType.title,
                            weight: CitroType.strong,
                            color: task.overdue ? c.stamp : c.ink,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (task.note.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        task.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.ui(
                          size: CitroType.caption,
                          color: c.inkSoft,
                          height: 1.5,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 标签可能在窄卡片里放不下，交给 Wrap 换行，避免右侧溢出。
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(8, 3, 9, 3),
                              decoration: BoxDecoration(
                                color: category.tint.withAlpha(24),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: category.tint.withAlpha(70),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: category.tint,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    category.name,
                                    style: context.ui(
                                      size: CitroType.caption,
                                      color: c.ink2,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            // 卡片上标出所属清单，方便区分「我的清单 / 工作 / 学习」。
                            Container(
                              padding: const EdgeInsets.fromLTRB(8, 3, 9, 3),
                              decoration: BoxDecoration(
                                color: c.bg2.withAlpha(c.dark ? 150 : 110),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: c.line),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppIcon(
                                    strokeSvg(AppIcons.list, width: 2),
                                    size: 10,
                                    color: c.inkSoft,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    store.listOf(task.listId).name,
                                    style: context.ui(
                                      size: CitroType.caption,
                                      color: c.inkSoft,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (task.priority > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: _meta(context, c.stamp, '重点'),
                              ),
                            if (task.overdue)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: _meta(context, c.stamp, '已逾期'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _TaskStateSelect(task: task),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          for (final s in task.subtasks)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 6),
              child: _SubtaskCard(task: task, sub: s),
            ),
      ],
    );
  }
}

/// 独立的小子任务卡：叠在主任务下方，点一下切换完成。
class _SubtaskCard extends StatelessWidget {
  final TodoTask task;
  final TodoSubtask sub;

  const _SubtaskCard({required this.task, required this.sub});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => TodoStore.instance.toggleSubtask(task, sub),
      scale: .995,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(
          color: c.surface2.withAlpha(sub.done ? 150 : 230),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sub.done ? c.line : c.line2),
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: sub.done ? c.mint : c.inkSoft,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                sub.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.ui(
                  size: CitroType.caption,
                  color: sub.done ? c.inkSoft : c.ink2,
                  height: 1.4,
                ),
              ),
            ),
            if (sub.done)
              AppIcon(
                strokeSvg(AppIcons.check, width: 2.4),
                size: 13,
                color: c.mintInk,
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleView extends StatefulWidget {
  final ValueChanged<DateTime> onCreate;
  final bool wide;
  const _ScheduleView({required this.onCreate, this.wide = false});

  @override
  State<_ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<_ScheduleView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = dayOf(DateTime.now());

  /// 日程默认按周看，需要时再切到整月。
  bool _weekView = true;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TodoStore.instance,
      builder: (context, _) {
        final tasks = TodoStore.instance.tasksOn(_selected);
        final taskSection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '${_selected.month} 月 ${_selected.day} 日',
                  style: context.ui(
                    weight: CitroType.strong,
                    size: CitroType.titleLg,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${tasks.length} 条',
                  style: context.ui(
                    size: CitroType.caption,
                    color: context.c.inkSoft,
                  ),
                ),
                const Spacer(),
                Pressable(
                  onTap: () => widget.onCreate(_selected),
                  scale: .95,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        strokeSvg(AppIcons.plus, width: 2),
                        size: 14,
                        color: context.c.accentInk,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '加一条',
                        style: context.ui(
                          size: CitroType.caption,
                          weight: CitroType.strong,
                          color: context.c.accentInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Timeline(tasks: tasks, day: _selected),
          ],
        );
        if (widget.wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  children: [_calendar(context)],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 0, 12, 96),
                  children: [taskSection],
                ),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            _calendar(context),
            const SizedBox(height: 16),
            taskSection,
          ],
        );
      },
    );
  }

  Widget _calendar(BuildContext context) {
    final c = context.c;
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    final cellH = _weekView
        ? (widget.wide ? 132.0 : 104.0)
        : (widget.wide ? 96.0 : 78.0);
    final maxItems = _weekView ? (widget.wide ? 4 : 2) : (widget.wide ? 2 : 1);
    final cells = <Widget>[];
    final weekStart = dayOf(_selected)
        .subtract(Duration(days: _selected.weekday - 1));
    if (!_weekView) {
      final first = DateTime(_month.year, _month.month, 1);
      for (var i = 0; i < first.weekday - 1; i++) {
        cells.add(const SizedBox.shrink());
      }
    }
    final dates = _weekView
        ? [for (var i = 0; i < 7; i++) weekStart.add(Duration(days: i))]
        : [
            for (
              var d = 1;
              d <= DateTime(_month.year, _month.month + 1, 0).day;
              d++
            )
              DateTime(_month.year, _month.month, d),
          ];
    for (final date in dates) {
      final d = date.day;
      final selected = date == _selected;
      final today = date == dayOf(DateTime.now());
      final list = TodoStore.instance.tasks
          .where((t) => t.occursOn(date))
          .toList();
      final hasOverdue = list.any((t) => t.overdue);
      final hasDoing = list.any((t) => t.state == TodoTaskState.doing);
      final allDone = list.isNotEmpty && list.every((t) => t.done);
      cells.add(
        Pressable(
          scale: .98,
          onTap: () => setState(() => _selected = date),
          child: Container(
            margin: const EdgeInsets.all(1.5),
            padding: const EdgeInsets.fromLTRB(5, 4, 5, 4),
            decoration: BoxDecoration(
              color: selected
                  ? c.accent.withAlpha(30)
                  : (today ? c.hl.withAlpha(90) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? c.accent.withAlpha(160)
                    : (today ? c.accent.withAlpha(70) : c.line.withAlpha(170)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 19,
                      height: 19,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? c.accent : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$d',
                        style: context.ui(
                          size: CitroType.caption,
                          weight: selected || today
                              ? CitroType.strong
                              : CitroType.regular,
                          color: selected ? const Color(0xFF2E2C22) : c.ink,
                          height: 1,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (hasOverdue)
                      _mark(context, c.stamp)
                    else if (hasDoing)
                      _mark(context, c.accent)
                    else if (allDone)
                      AppIcon(
                        strokeSvg(AppIcons.check, width: 2.6),
                        size: 10,
                        color: c.mintInk,
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                for (final t in list.take(maxItems))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 3.5,
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: TodoStore.instance
                                .categoryOf(t.categoryId)
                                .tint,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.ui(
                              size: CitroType.small,
                              color: t.done ? c.inkSoft : c.ink2,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (list.length > maxItems)
                  Text(
                    '+${list.length - maxItems}',
                    style: context.ui(
                      size: CitroType.micro,
                      color: c.inkSoft,
                      height: 1,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.paper(c),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Pressable(
                onTap: () => setState(() {
                  if (_weekView) {
                    _selected = _selected.subtract(const Duration(days: 7));
                    _month = DateTime(_selected.year, _selected.month);
                  } else {
                    _month = DateTime(_month.year, _month.month - 1);
                  }
                }),
                scale: .9,
                child: Padding(
                  padding: const EdgeInsets.all(6),
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
                    _weekView
                        ? '${weekStart.month} 月 ${weekStart.day} 日 - '
                              '${weekStart.add(const Duration(days: 6)).month} 月 '
                              '${weekStart.add(const Duration(days: 6)).day} 日'
                        : '${_month.year} 年 ${_month.month} 月',
                    style: context.ui(
                      weight: CitroType.strong,
                      size: CitroType.title,
                    ),
                  ),
                ),
              ),
              Pressable(
                onTap: () => setState(() {
                  if (_weekView) {
                    _selected = _selected.add(const Duration(days: 7));
                    _month = DateTime(_selected.year, _selected.month);
                  } else {
                    _month = DateTime(_month.year, _month.month + 1);
                  }
                }),
                scale: .9,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AppIcon(
                    strokeSvg(AppIcons.chevronRight, width: 2),
                    size: 16,
                    color: c.inkSoft,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _modeToggle(context),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: c.bg2.withAlpha(c.dark ? 150 : 110),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                for (var i = 0; i < week.length; i++)
                  Expanded(
                    child: Center(
                      child: Text(
                        week[i],
                        style: context.ui(
                          size: CitroType.caption,
                          weight: CitroType.strong,
                          color: i >= 5 ? c.inkSoft : c.ink2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cells.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: cellH,
            ),
            itemBuilder: (_, i) => cells[i],
          ),
        ],
      ),
    );
  }

  /// 周 / 月视图切换，默认周。
  Widget _modeToggle(BuildContext context) {
    final c = context.c;
    Widget item(String label, bool active, bool week) => Pressable(
      scale: .94,
      onTap: () {
        if (active) return;
        setState(() {
          _weekView = week;
          if (week) _month = DateTime(_selected.year, _selected.month);
        });
      },
      child: AnimatedContainer(
        duration: CitroMotion.hover,
        curve: CitroMotion.easeColor,
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.accent.withAlpha(190) : c.bg2.withAlpha(90),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: active ? c.accent : c.line),
        ),
        child: Text(
          label,
          style: context.ui(
            size: CitroType.caption,
            weight: active ? CitroType.strong : CitroType.regular,
            color: active ? const Color(0xFF2E2C22) : c.ink2,
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        item('周', _weekView, true),
        const SizedBox(width: 4),
        item('月', !_weekView, false),
      ],
    );
  }

  Widget _mark(BuildContext context, Color color) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ---------------------------------------------------------------------------
// 一天的时间线
// ---------------------------------------------------------------------------

class _Timeline extends StatelessWidget {
  final List<TodoTask> tasks;
  final DateTime day;

  const _Timeline({required this.tasks, required this.day});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: c.surface2.withAlpha(160),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Text(
          '这一天还没有安排',
          textAlign: TextAlign.center,
          style: context.ui(size: CitroType.meta, color: c.inkSoft),
        ),
      );
    }
    final timed = tasks.where((t) => t.scheduledAt(day) != null).toList()
      ..sort((a, b) => a.scheduledAt(day)!.compareTo(b.scheduledAt(day)!));
    final anytime = tasks.where((t) => t.scheduledAt(day) == null).toList();
    final isToday = dayOf(DateTime.now()) == dayOf(day);
    final now = DateTime.now();
    final rows = <Widget>[];
    for (final t in anytime) {
      rows.add(_slot(context, null, t));
    }
    var shownNow = false;
    for (final t in timed) {
      final at = t.scheduledAt(day)!;
      if (isToday && !shownNow && now.isBefore(at)) {
        rows.add(_nowRow(context, now));
        shownNow = true;
      }
      rows.add(_slot(context, at, t));
    }
    if (isToday && !shownNow) rows.add(_nowRow(context, now));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _slot(BuildContext context, DateTime? at, TodoTask task) {
    final c = context.c;
    final time = at == null
        ? '全天'
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                time,
                textAlign: TextAlign.right,
                style: context.ui(
                  size: CitroType.caption,
                  weight: at == null ? CitroType.regular : CitroType.strong,
                  color: at == null ? c.inkSoft : c.ink2,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Expanded(child: Container(width: 1.5, color: c.line)),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: task.done ? c.mint : c.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surface2, width: 1.5),
                  ),
                ),
                Expanded(child: Container(width: 1.5, color: c.line)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 0, 7),
              child: TodoTaskTile(task: task, compact: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nowRow(BuildContext context, DateTime now) {
    final c = context.c;
    final label =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: context.ui(
                size: CitroType.caption,
                weight: CitroType.strong,
                color: c.stamp,
              ),
            ),
          ),
          SizedBox(
            width: 22,
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: c.stamp,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface2, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(height: 1.5, color: c.stamp.withAlpha(150)),
          ),
        ],
      ),
    );
  }
}
