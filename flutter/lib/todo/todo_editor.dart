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

/// 新建 / 编辑任务。
Future<TodoTask?> showTodoEditor(
  BuildContext context, {
  TodoTask? initial,
  TodoKind kind = TodoKind.task,
  DateTime? day,
}) {
  return showCitroSheet<TodoTask>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8A23211C),
    builder: (ctx) => TodoScope(
      child: _TodoEditorSheet(initial: initial, kind: kind, day: day),
    ),
  );
}

class _TodoEditorSheet extends StatefulWidget {
  final TodoTask? initial;
  final TodoKind kind;
  final DateTime? day;

  const _TodoEditorSheet({this.initial, required this.kind, this.day});

  @override
  State<_TodoEditorSheet> createState() => _TodoEditorSheetState();
}

class _TodoEditorSheetState extends State<_TodoEditorSheet> {
  late TodoKind _kind = widget.initial?.kind ?? widget.kind;
  late final TextEditingController _title = TextEditingController(
    text: widget.initial?.title ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.initial?.note ?? '',
  );
  late final TextEditingController _subInput = TextEditingController();

  late String _categoryId =
      widget.initial?.categoryId ?? TodoStore.instance.categories.first.id;
  late String _listId =
      widget.initial?.listId ?? TodoStore.instance.lists.first.id;
  late DateTime? _remindAt = widget.initial?.remindAt;
  late DateTime? _dueAt = widget.initial?.dueAt;
  late Set<int> _habitDays = {...?widget.initial?.habitDays};
  late String _habitTime = widget.initial?.habitTime ?? '20:00';
  late int _priority = widget.initial?.priority ?? 0;
  late List<TodoSubtask> _subtasks = [...?widget.initial?.subtasks];

  /// 待办的提前提醒（分钟，0 表示截止那一刻），可多选。
  late List<int> _leadMinutes = widget.initial == null
      ? [15]
      : [...widget.initial!.leadMinutes];
  bool _saving = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    if (_kind == TodoKind.habit && _habitDays.isEmpty) {
      _habitDays = {1, 2, 3, 4, 5};
    }
    final base = widget.day ?? DateTime.now();
    if (_kind == TodoKind.reminder && _remindAt == null) {
      _remindAt = DateTime(base.year, base.month, base.day, 20, 0);
    }
    if (_kind == TodoKind.task && _dueAt == null) {
      final d = base.add(const Duration(days: 1));
      _dueAt = DateTime(d.year, d.month, d.day, 18, 0);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _subInput.dispose();
    super.dispose();
  }

  void _switchKind(TodoKind k) {
    setState(() {
      _kind = k;
      _error = null;
      if (k == TodoKind.habit && _habitDays.isEmpty) {
        _habitDays = {1, 2, 3, 4, 5};
      }
      if (k == TodoKind.reminder && _remindAt == null) {
        _remindAt = DateTime.now().add(const Duration(hours: 1));
      }
      if (k == TodoKind.task && _dueAt == null) {
        _dueAt = DateTime.now().add(const Duration(days: 1));
      }
    });
  }

  /// 日期和时间拆成两个入口：点日期只改年月日，点时间只改时分。
  Future<void> _pickRemindDate() async {
    final d = await showTodoDatePicker(context, initial: _remindAt);
    if (d == null || !mounted) return;
    final base = _remindAt ?? DateTime.now();
    setState(
      () =>
          _remindAt = DateTime(d.year, d.month, d.day, base.hour, base.minute),
    );
  }

  Future<void> _pickRemindTime() async {
    final base = _remindAt ?? DateTime.now();
    final t = await showTodoTimePicker(
      context,
      initial: _hm(base.hour, base.minute),
    );
    if (t == null || !mounted) return;
    final p = t.split(':');
    setState(
      () => _remindAt = DateTime(
        base.year,
        base.month,
        base.day,
        int.parse(p[0]),
        int.parse(p[1]),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final d = await showTodoDatePicker(context, initial: _dueAt);
    if (d == null || !mounted) return;
    final base = _dueAt ?? DateTime.now();
    setState(
      () => _dueAt = DateTime(d.year, d.month, d.day, base.hour, base.minute),
    );
  }

  Future<void> _pickDueTime() async {
    final base = _dueAt ?? DateTime.now();
    final t = await showTodoTimePicker(
      context,
      initial: _hm(base.hour, base.minute),
    );
    if (t == null || !mounted) return;
    final p = t.split(':');
    setState(
      () => _dueAt = DateTime(
        base.year,
        base.month,
        base.day,
        int.parse(p[0]),
        int.parse(p[1]),
      ),
    );
  }

  String _hm(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '先写一个任务名');
      return;
    }
    if (_kind == TodoKind.reminder && _remindAt == null) {
      setState(() => _error = '提醒需要选一个时间');
      return;
    }
    if (_kind == TodoKind.task && _dueAt == null) {
      setState(() => _error = '待办需要选一个截止时间');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final store = TodoStore.instance;
    if (_editing) {
      final t = widget.initial!
        ..title = title
        ..note = _note.text.trim()
        ..kind = _kind
        ..categoryId = _categoryId
        ..listId = _listId
        ..remindAt = _kind == TodoKind.reminder ? _remindAt : null
        ..dueAt = _kind == TodoKind.task ? _dueAt : null
        ..leadMinutes = _kind == TodoKind.task
            ? ([..._leadMinutes]..sort())
            : <int>[]
        ..habitDays = _kind == TodoKind.habit ? {..._habitDays} : <int>{}
        ..habitTime = _habitTime
        ..priority = _priority
        ..subtasks = _subtasks;
      store.updateTask(t);
      if (mounted) Navigator.of(context).pop(t);
    } else {
      final t = store.createTask(
        title: title,
        note: _note.text.trim(),
        kind: _kind,
        categoryId: _categoryId,
        listId: _listId,
        remindAt: _remindAt,
        dueAt: _dueAt,
        leadMinutes: _kind == TodoKind.task
            ? ([..._leadMinutes]..sort())
            : const [],
        habitDays: _habitDays,
        habitTime: _habitTime,
        subtasks: const [],
        priority: _priority,
      );
      if (_subtasks.isNotEmpty) {
        t.subtasks = _subtasks
            .map((s) => TodoSubtask(id: '${s.id}-${t.id}', title: s.title))
            .toList();
        store.updateTask(t);
      }
      if (mounted) Navigator.of(context).pop(t);
    }
  }

  Future<void> _delete() async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        maxWidth: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '删除这条任务？',
              style: ctx.ui(weight: CitroType.strong, size: CitroType.subtitle),
            ),
            const SizedBox(height: 12),
            Text(
              '删除后不能恢复。',
              style: ctx.ui(size: CitroType.meta, color: ctx.c.ink2),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '取消',
                    outlined: true,
                    onTap: () => Navigator.of(ctx).pop(false),
                    height: 42,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AccentButton(
                    text: '删除',
                    danger: true,
                    onTap: () => Navigator.of(ctx).pop(true),
                    height: 42,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    TodoStore.instance.deleteTask(widget.initial!.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * .92;
    final reduce = CitroMotion.reduced(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: maxHeight),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: c.line),
            boxShadow: CitroColors.shadows.lg(c),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(c),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Text(
                      _editing ? '编辑任务' : '新建任务',
                      style: context.ui(
                        weight: CitroType.strong,
                        size: CitroType.subtitle,
                      ),
                    ),
                    const Spacer(),
                    if (_editing)
                      Pressable(
                        onTap: _delete,
                        scale: .94,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: AppIcon(
                            strokeSvg(AppIcons.trash, width: 2),
                            size: 18,
                            color: c.stamp,
                          ),
                        ),
                      ),
                    const SizedBox(width: 2),
                    TodoCloseButton(onTap: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: AnimatedSize(
                    duration: reduce ? Duration.zero : CitroMotion.size,
                    curve: CitroMotion.easeOut,
                    alignment: Alignment.topCenter,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TodoSegTabs<TodoKind>(
                          items: [
                            for (final k in TodoKind.values) (k, k.label),
                          ],
                          value: _kind,
                          onChanged: _switchKind,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _kind.hint,
                          style: context.ui(
                            size: CitroType.meta,
                            color: c.inkSoft,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        CitroField(
                          label: '任务名',
                          hint: _kind == TodoKind.habit
                              ? '例如：每天读 20 页'
                              : '要做什么',
                          controller: _title,
                          maxLength: 60,
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                        ),
                        const SizedBox(height: 16),
                        _label(context, '时间'),
                        _timeField(context),
                        if (_kind != TodoKind.quick) ...[
                          const SizedBox(height: 16),
                          _label(context, '优先级'),
                          _priorityRow(context),
                        ],
                        const SizedBox(height: 18),
                        _label(context, '分类'),
                        _categoryRow(context),
                        const SizedBox(height: 18),
                        _label(context, '清单'),
                        _listRow(context),
                        const SizedBox(height: 18),
                        if (_kind == TodoKind.task ||
                            _kind == TodoKind.habit) ...[
                          _label(context, '子任务'),
                          _subtaskEditor(context),
                          const SizedBox(height: 18),
                        ],
                        CitroField(
                          label: '备注',
                          hint: '补一句背景，AI 总结时会参考',
                          controller: _note,
                          maxLines: 3,
                          maxLength: 300,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _error!,
                          style: context.ui(
                            size: CitroType.meta,
                            color: c.stamp,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: AccentButton(
                        text: _editing ? '保存修改' : '创建任务',
                        loading: _saving,
                        onTap: _saving ? null : _save,
                        height: 46,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle(CitroColors c) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: c.line2,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Text(
      text,
      style: context.ui(
        size: CitroType.caption,
        weight: CitroType.strong,
        color: context.c.inkSoft,
      ),
    ),
  );

  Widget _timeField(BuildContext context) {
    final c = context.c;
    if (_kind == TodoKind.quick) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.bg2.withAlpha(c.dark ? 120 : 90),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            AppIcon(
              strokeSvg(AppIcons.flash, width: 2),
              size: 16,
              color: c.inkSoft,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '随手做不设时间，只在创建当天出现',
                style: context.ui(size: CitroType.meta, color: c.inkSoft),
              ),
            ),
          ],
        ),
      );
    }
    if (_kind == TodoKind.habit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (var d = 1; d <= 7; d++) _weekChip(context, d)],
          ),
          const SizedBox(height: 10),
          _tapField(
            context,
            icon: AppIcons.clock,
            text: '执行时间 $_habitTime',
            onTap: () async {
              final t = await showTodoTimePicker(context, initial: _habitTime);
              if (t != null && mounted) setState(() => _habitTime = t);
            },
          ),
        ],
      );
    }
    final isReminder = _kind == TodoKind.reminder;
    final at = isReminder ? _remindAt : _dueAt;
    final row = Row(
      children: [
        Expanded(
          child: _tapField(
            context,
            icon: AppIcons.calendar,
            text: at == null ? '选择日期' : formatDayLabel(at),
            onTap: isReminder ? _pickRemindDate : _pickDueDate,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _tapField(
            context,
            icon: AppIcons.clock,
            text: at == null ? '选择时间' : _hm(at.hour, at.minute),
            onTap: isReminder ? _pickRemindTime : _pickDueTime,
          ),
        ),
      ],
    );
    if (isReminder) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        const SizedBox(height: 10),
        _tapField(
          context,
          icon: AppIcons.bell,
          text: _leadMinutes.isEmpty ? '不提醒' : '提醒：${_leadSummary()}',
          onTap: () => _pickLeads(context),
        ),
      ],
    );
  }

  /// 提前提醒的摘要，只在这里显示结果，具体选项收进弹层。
  String _leadSummary() {
    final sorted = [..._leadMinutes]..sort();
    String name(int m) {
      if (m <= 0) return '截止时';
      if (m < 60) return '提前 $m 分钟';
      if (m < 1440) return '提前 ${m ~/ 60} 小时';
      if (m < 10080) return '提前 ${m ~/ 1440} 天';
      return '提前 ${m ~/ 10080} 周';
    }

    if (sorted.length == 1) return name(sorted.first);
    return '${name(sorted.first)} 等 ${sorted.length} 项';
  }

  Future<void> _pickLeads(BuildContext context) async {
    final result = await showCitroSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LeadPicker(initial: _leadMinutes),
    );
    if (result == null || !mounted) return;
    setState(() => _leadMinutes = result);
  }

  Widget _weekChip(BuildContext context, int day) {
    final c = context.c;
    final active = _habitDays.contains(day);
    final names = ['一', '二', '三', '四', '五', '六', '日'];
    return Pressable(
      scale: .93,
      onTap: () => setState(() {
        if (active) {
          _habitDays.remove(day);
        } else {
          _habitDays.add(day);
        }
      }),
      child: AnimatedContainer(
        duration: CitroMotion.hover,
        curve: CitroMotion.easeColor,
        width: 38,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.accent.withAlpha(190) : c.bg2.withAlpha(110),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: active ? c.accent : c.line),
        ),
        child: Text(
          names[day - 1],
          style: context.ui(
            size: CitroType.meta,
            weight: active ? CitroType.strong : CitroType.regular,
            color: active ? const Color(0xFF2E2C22) : c.ink2,
            height: 1,
          ),
        ),
      ),
    );
  }

  Widget _tapField(
    BuildContext context, {
    required String icon,
    required String text,
    required VoidCallback onTap,
  }) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: .995,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            AppIcon(strokeSvg(icon, width: 2), size: 16, color: c.accentInk),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: context.ui(size: CitroType.body, color: c.ink),
              ),
            ),
            AppIcon(
              strokeSvg(AppIcons.chevronRight, width: 2),
              size: 15,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }

  Widget _priorityRow(BuildContext context) {
    final c = context.c;
    const labels = ['不标记', '重要', '紧急'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Pressable(
              scale: .98,
              onTap: () => setState(() => _priority = i),
              child: AnimatedContainer(
                duration: CitroMotion.hover,
                curve: CitroMotion.easeColor,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _priority == i
                      ? c.accent.withAlpha(190)
                      : c.bg2.withAlpha(90),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _priority == i ? c.accent : c.line),
                ),
                child: Text(
                  labels[i],
                  style: context.ui(
                    size: CitroType.meta,
                    weight: _priority == i
                        ? CitroType.strong
                        : CitroType.regular,
                    color: _priority == i ? const Color(0xFF2E2C22) : c.ink2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _categoryRow(BuildContext context) {
    return ListenableBuilder(
      listenable: TodoStore.instance,
      builder: (context, _) {
        final cats = TodoStore.instance.categories;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cat in cats)
              Pressable(
                scale: .97,
                onTap: () => setState(() => _categoryId = cat.id),
                child: AnimatedContainer(
                  duration: CitroMotion.hover,
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _categoryId == cat.id
                        ? context.c.accent.withAlpha(38)
                        : context.c.bg2.withAlpha(80),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _categoryId == cat.id
                          ? context.c.accent.withAlpha(150)
                          : context.c.line,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: cat.tint,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        cat.name,
                        style: context.ui(
                          size: CitroType.meta,
                          weight: _categoryId == cat.id
                              ? CitroType.strong
                              : CitroType.regular,
                          color: _categoryId == cat.id
                              ? cat.tint
                              : context.c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Pressable(
              scale: .95,
              onTap: () => showCategoryManager(context),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: context.c.bg2.withAlpha(70),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.c.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.plus, width: 2),
                      size: 14,
                      color: context.c.inkSoft,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '分类',
                      style: context.ui(
                        size: CitroType.meta,
                        color: context.c.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 长按清单可删除；至少保留一个。
  Future<void> _confirmDeleteList(BuildContext context, TodoList list) async {
    if (TodoStore.instance.lists.length <= 1) return;
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => TodoScope(
        child: _ConfirmCard(title: '删除清单', body: '「${list.name}」里的任务会移到第一个清单。'),
      ),
    );
    if (ok != true || !mounted) return;
    TodoStore.instance.deleteList(list.id);
    if (_listId == list.id && TodoStore.instance.lists.isNotEmpty) {
      setState(() => _listId = TodoStore.instance.lists.first.id);
    }
  }

  Widget _listRow(BuildContext context) {
    return ListenableBuilder(
      listenable: TodoStore.instance,
      builder: (context, _) {
        final lists = TodoStore.instance.lists;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final list in lists)
              Pressable(
                scale: .97,
                onTap: () => setState(() => _listId = list.id),
                onLongPress: () => _confirmDeleteList(context, list),
                child: AnimatedContainer(
                  duration: CitroMotion.hover,
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _listId == list.id
                        ? context.c.accent.withAlpha(38)
                        : context.c.bg2.withAlpha(80),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _listId == list.id
                          ? context.c.accent.withAlpha(150)
                          : context.c.line,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        strokeSvg(todoIcon(list.iconKey), width: 2),
                        size: 14,
                        color: _listId == list.id
                            ? list.tint
                            : context.c.inkSoft,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        list.name,
                        style: context.ui(
                          size: CitroType.meta,
                          weight: _listId == list.id
                              ? CitroType.strong
                              : CitroType.regular,
                          color: _listId == list.id
                              ? list.tint
                              : context.c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Pressable(
              scale: .95,
              onTap: () => showListManager(context),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: context.c.bg2.withAlpha(70),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.c.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.plus, width: 2),
                      size: 14,
                      color: context.c.inkSoft,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '清单',
                      style: context.ui(
                        size: CitroType.meta,
                        color: context.c.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _subtaskEditor(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _subtasks.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Pressable(
                  onTap: () => setState(() => _subtasks.removeAt(i)),
                  scale: .9,
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: c.stamp.withAlpha(24),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.stamp.withAlpha(130)),
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(AppIcons.close, width: 2.2),
                        size: 13,
                        color: c.stamp,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _subtasks[i].title,
                    style: context.ui(
                      size: CitroType.body,
                      color: _subtasks[i].done ? c.inkSoft : c.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          height: 46,
          padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _subInput,
                  style: context.ui(size: CitroType.body),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '加一个步骤，回车确认',
                    hintStyle: context.ui(
                      size: CitroType.body,
                      color: c.inkSoft,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _addSub(),
                ),
              ),
              const SizedBox(width: 6),
              Pressable(
                onTap: _addSub,
                scale: .94,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: AppIcon(
                      strokeSvg(AppIcons.plus, width: 2.4),
                      size: 18,
                      color: const Color(0xFF2E2C22),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _addSub() {
    final text = _subInput.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add(
        TodoSubtask(
          id: 'new-${DateTime.now().microsecondsSinceEpoch}',
          title: text,
        ),
      );
      _subInput.clear();
    });
  }
}

/// 只显示日期时的文案：今天 / 明天 / X 月 X 日。
String formatDayLabel(DateTime at) {
  final today = dayOf(DateTime.now());
  final d = dayOf(at);
  if (d == today) return '今天';
  if (d == today.add(const Duration(days: 1))) return '明天';
  return '${at.month} 月 ${at.day} 日';
}

String formatDateTime(DateTime at) {
  final now = DateTime.now();
  final sameDay = dayOf(at) == dayOf(now);
  final tomorrow = dayOf(at) == dayOf(now).add(const Duration(days: 1));
  final hm =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  if (sameDay) return '今天 $hm';
  if (tomorrow) return '明天 $hm';
  return '${at.month} 月 ${at.day} 日 $hm';
}

/// 提前提醒的多选弹层：列表式选项 + 明确的「可多选」提示。
class _LeadPicker extends StatefulWidget {
  final List<int> initial;

  const _LeadPicker({required this.initial});

  @override
  State<_LeadPicker> createState() => _LeadPickerState();
}

class _LeadPickerState extends State<_LeadPicker> {
  static const _options = <int, String>{
    0: '截止时',
    5: '提前 5 分钟',
    10: '提前 10 分钟',
    15: '提前 15 分钟',
    30: '提前 30 分钟',
    45: '提前 45 分钟',
    60: '提前 1 小时',
    120: '提前 2 小时',
    180: '提前 3 小时',
    240: '提前 4 小时',
    720: '提前 12 小时',
    1440: '提前 1 天',
    2880: '提前 2 天',
    10080: '提前 1 周',
  };

  late final Set<int> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .78,
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: c.line2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
              Text(
                '截止前提醒',
                style: context.ui(
                  size: CitroType.title,
                  weight: CitroType.strong,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '可多选',
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 2),
              child: Column(
                children: [
                  for (final e in _options.entries)
                    Pressable(
                      scale: .995,
                      onTap: () => setState(() {
                        if (!_selected.remove(e.key)) _selected.add(e.key);
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: _selected.contains(e.key)
                              ? c.accent.withAlpha(28)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _selected.contains(e.key)
                                ? c.accent.withAlpha(130)
                                : c.line,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.value,
                                style: context.ui(
                                  size: CitroType.body,
                                  color: c.ink,
                                ),
                              ),
                            ),
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: _selected.contains(e.key)
                                    ? c.accent
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _selected.contains(e.key)
                                      ? c.accent
                                      : c.line2,
                                ),
                              ),
                              child: _selected.contains(e.key)
                                  ? Center(
                                      child: AppIcon(
                                        strokeSvg(AppIcons.check, width: 3),
                                        size: 11,
                                        color: const Color(0xFF2E2C22),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  text: '清空',
                  outlined: true,
                  height: 42,
                  onTap: () => setState(_selected.clear),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AccentButton(
                  text: '确定',
                  height: 42,
                  onTap: () =>
                      Navigator.of(context).pop(_selected.toList()..sort()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 通用的小确认卡：删除清单等操作前问一句。
class _ConfirmCard extends StatelessWidget {
  final String title;
  final String body;

  const _ConfirmCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line2),
        boxShadow: CitroColors.shadows.lg(c),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.ui(
              size: CitroType.title,
              weight: CitroType.strong,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: context.ui(size: CitroType.body, color: c.ink2, height: 1.6),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  text: '取消',
                  outlined: true,
                  height: 40,
                  onTap: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AccentButton(
                  text: '删除',
                  height: 40,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 分类管理
// ---------------------------------------------------------------------------

Future<void> showCategoryManager(BuildContext context) => showCitroSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (ctx) =>
      const TodoScope(child: _ManagerSheet(kind: _ManagerKind.category)),
);

Future<void> showListManager(BuildContext context) => showCitroSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (ctx) =>
      const TodoScope(child: _ManagerSheet(kind: _ManagerKind.list)),
);

enum _ManagerKind { category, list }

class _ManagerSheet extends StatelessWidget {
  final _ManagerKind kind;
  const _ManagerSheet({required this.kind});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: c.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Text(
                  kind == _ManagerKind.category ? '分类' : '清单',
                  style: context.ui(
                    weight: CitroType.strong,
                    size: CitroType.subtitle,
                  ),
                ),
                const Spacer(),
                TodoCloseButton(onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          Flexible(
            child: ListenableBuilder(
              listenable: TodoStore.instance,
              builder: (context, _) {
                final items = kind == _ManagerKind.category
                    ? [
                        for (final cat in TodoStore.instance.categories)
                          _ManageItem(
                            id: cat.id,
                            name: cat.name,
                            color: cat.tint,
                            iconKey: cat.iconKey,
                            locked: cat.builtIn,
                          ),
                      ]
                    : [
                        for (final list in TodoStore.instance.lists)
                          _ManageItem(
                            id: list.id,
                            name: list.name,
                            color: list.tint,
                            iconKey: list.iconKey,
                            locked: TodoStore.instance.lists.length <= 1,
                          ),
                      ];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: c.line),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: item.color.withAlpha(36),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: AppIcon(
                                  strokeSvg(todoIcon(item.iconKey), width: 2),
                                  size: 15,
                                  color: item.color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.name,
                                style: context.ui(
                                  size: CitroType.body,
                                  color: c.ink,
                                ),
                              ),
                            ),
                            if (!item.locked)
                              Pressable(
                                onTap: () => _edit(context, item),
                                scale: .92,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: AppIcon(
                                    strokeSvg(AppIcons.edit, width: 2),
                                    size: 16,
                                    color: c.inkSoft,
                                  ),
                                ),
                              ),
                            if (!item.locked)
                              Pressable(
                                onTap: () => _delete(context, item),
                                scale: .92,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: AppIcon(
                                    strokeSvg(AppIcons.trash, width: 2),
                                    size: 16,
                                    color: c.stamp,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    AccentButton(
                      text: kind == _ManagerKind.category ? '新建分类' : '新建清单',
                      outlined: true,
                      height: 44,
                      onTap: () => _edit(context, null),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, _ManageItem item) async {
    if (kind == _ManagerKind.category) {
      TodoStore.instance.deleteCategory(item.id);
    } else {
      TodoStore.instance.deleteList(item.id);
    }
  }

  Future<void> _edit(BuildContext context, _ManageItem? item) async {
    final result = await showCitroDialog<_ManageItem>(
      context,
      builder: (ctx) => TodoScope(
        child: _EditManageDialog(kind: kind, initial: item),
      ),
    );
    if (result == null) return;
    if (kind == _ManagerKind.category) {
      if (item == null) {
        TodoStore.instance.addCategory(
          name: result.name,
          color: result.color.toARGB32(),
          iconKey: result.iconKey,
        );
      } else {
        TodoStore.instance.updateCategory(
          TodoStore.instance
              .categoryOf(item.id)
              .copyWith(
                name: result.name,
                color: result.color.toARGB32(),
                iconKey: result.iconKey,
              ),
        );
      }
    } else {
      if (item == null) {
        TodoStore.instance.addList(
          name: result.name,
          color: result.color.toARGB32(),
          iconKey: result.iconKey,
        );
      } else {
        TodoStore.instance.updateList(
          TodoStore.instance
              .listOf(item.id)
              .copyWith(
                name: result.name,
                color: result.color.toARGB32(),
                iconKey: result.iconKey,
              ),
        );
      }
    }
  }
}

class _ManageItem {
  final String id;
  final String name;
  final Color color;
  final String iconKey;
  final bool locked;

  const _ManageItem({
    required this.id,
    required this.name,
    required this.color,
    required this.iconKey,
    this.locked = false,
  });
}

class _EditManageDialog extends StatefulWidget {
  final _ManagerKind kind;
  final _ManageItem? initial;

  const _EditManageDialog({required this.kind, this.initial});

  @override
  State<_EditManageDialog> createState() => _EditManageDialogState();
}

class _EditManageDialogState extends State<_EditManageDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late Color _color = widget.initial?.color ?? Color(todoPalette.first);
  late String _icon =
      widget.initial?.iconKey ??
      (widget.kind == _ManagerKind.category ? 'flag' : 'list');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      maxWidth: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.initial == null
                ? (widget.kind == _ManagerKind.category ? '新建分类' : '新建清单')
                : '编辑',
            style: context.ui(
              weight: CitroType.strong,
              size: CitroType.subtitle,
            ),
          ),
          const SizedBox(height: 16),
          CitroField(
            label: widget.kind == _ManagerKind.category ? '分类名' : '清单名',
            hint: widget.kind == _ManagerKind.category ? '分类名，如阅读' : '清单名，如本周',
            controller: _name,
            maxLength: 12,
          ),
          const SizedBox(height: 14),
          Text(
            '颜色',
            style: context.ui(size: CitroType.caption, color: c.inkSoft),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in todoPalette)
                GestureDetector(
                  onTap: () => setState(() => _color = Color(v)),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(v),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color.toARGB32() == v
                            ? c.ink
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '图标',
            style: context.ui(size: CitroType.caption, color: c.inkSoft),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final key in todoIconKeys)
                GestureDetector(
                  onTap: () => setState(() => _icon = key),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _icon == key ? _color.withAlpha(40) : c.bg2,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: _icon == key ? _color : c.line),
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(todoIcon(key), width: 2),
                        size: 16,
                        color: _icon == key ? _color : c.inkSoft,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: AccentButton(
              text: '保存',
              height: 44,
              onTap: () {
                final name = _name.text.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop(
                  _ManageItem(
                    id: widget.initial?.id ?? '',
                    name: name,
                    color: _color,
                    iconKey: _icon,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
