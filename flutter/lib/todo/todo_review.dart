import 'package:flutter/material.dart';

import '../services/pomodoro.dart';
import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'todo_ai.dart';
import 'todo_models.dart';
import 'todo_store.dart';
import 'todo_theme.dart';
import 'todo_ui.dart';

/// 编辑某天的复盘，也可以在这里设置每日自动复盘时间。
Future<void> showReviewEditor(BuildContext context, {required DateTime day}) {
  return showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TodoScope(child: _ReviewSheet(day: dayOf(day))),
  );
}

class _ReviewSheet extends StatefulWidget {
  final DateTime day;
  const _ReviewSheet({required this.day});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final TextEditingController _text = TextEditingController(
    text: TodoStore.instance.reviewFor(widget.day)?.text ?? '',
  );
  bool _loading = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int _focusMinutes() {
    var total = 0;
    for (final s in PomodoroState.instance.sessions) {
      if (dayOf(s.at) == widget.day) total += s.minutes;
    }
    return total;
  }

  Future<void> _generate() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final store = TodoStore.instance;
      final text = await TodoAi.summary(
        day: widget.day,
        tasks: store.tasksOn(widget.day),
        moods: store.moodsOn(widget.day),
        focusMinutes: _focusMinutes(),
        streak: store.streak,
      );
      if (!mounted) return;
      setState(() => _text.text = text);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString().replaceFirst('AiException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = TodoStore.instance;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
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
                    '今日复盘',
                    style: context.ui(
                      weight: CitroType.strong,
                      size: CitroType.subtitle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.day.month} 月 ${widget.day.day} 日',
                    style: context.ui(
                      size: CitroType.caption,
                      color: c.inkSoft,
                    ),
                  ),
                  const Spacer(),
                  TodoCloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 10),
              CitroField(
                label: '复盘',
                hint: '今天做了什么，哪里卡住了，明天先做哪一件',
                controller: _text,
                maxLines: 7,
                maxLength: 1200,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Pressable(
                    onTap: _loading ? null : _generate,
                    scale: .97,
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.accent.withAlpha(36),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.accent.withAlpha(110)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_loading)
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
                            _loading ? '正在写…' : 'CiCi 写一版',
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
                    'AI 只依据任务与专注数据',
                    style: context.ui(size: CitroType.small, color: c.inkSoft),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _autoRow(context, store),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AccentButton(
                  text: '保存复盘',
                  height: 44,
                  onTap: () async {
                    await store.saveReview(widget.day, _text.text);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      AppToast.show(context, '已保存');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _autoRow(BuildContext context, TodoStore store) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.bg2.withAlpha(c.dark ? 120 : 90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          AppIcon(
            strokeSvg(AppIcons.clock, width: 1.8),
            size: 16,
            color: c.inkSoft,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每日自动复盘',
                  style: context.ui(size: CitroType.meta, color: c.ink),
                ),
                Text(
                  store.autoReviewEnabled
                      ? '到 ${store.autoReviewTime} 生成一版草稿'
                      : '关闭时只在手动点击时生成',
                  style: context.ui(size: CitroType.small, color: c.inkSoft),
                ),
              ],
            ),
          ),
          if (store.autoReviewEnabled)
            Pressable(
              onTap: () async {
                final t = await showTodoTimePicker(
                  context,
                  initial: store.autoReviewTime,
                );
                if (t != null) store.setAutoReview(time: t);
              },
              scale: .95,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.line),
                ),
                child: Center(
                  child: Text(
                    store.autoReviewTime,
                    style: context.ui(
                      size: CitroType.caption,
                      weight: CitroType.strong,
                      color: c.accentInk,
                    ),
                  ),
                ),
              ),
            ),
          _PaperSwitch(
            value: store.autoReviewEnabled,
            onChanged: (v) => store.setAutoReview(enabled: v),
          ),
        ],
      ),
    );
  }
}

class _PaperSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PaperSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: CitroMotion.hover,
        curve: CitroMotion.easeColor,
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? c.accent : c.line2,
          borderRadius: BorderRadius.circular(13),
        ),
        child: AnimatedAlign(
          duration: CitroMotion.hover,
          curve: CitroMotion.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value ? const Color(0xFFFFFDF8) : c.surface2,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
