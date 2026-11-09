import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../overlays/pomodoro_sheet.dart';
import '../services/pomodoro.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import '../tingyu/tingyu_controller.dart';
import '../tingyu/tingyu_models.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'todo_models.dart';
import 'todo_rail.dart';
import 'todo_store.dart';
import 'todo_theme.dart';
import 'todo_ui.dart';

/// 专注面板：复用 PomodoroState 的计时、统计与通知，换成待办模块的纸张 UI。
Future<void> showTodoFocus(BuildContext context, {TodoTask? task}) {
  PomodoroState.instance.ensureInit();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '专注',
    barrierColor: const Color(0x8A23211C),
    transitionDuration: CitroMotion.modal,
    pageBuilder: (_, __, ___) => TodoScope(child: _FocusDialog(task: task)),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: CitroMotion.easeOut,
        reverseCurve: CitroMotion.exit,
      );
      final child2 = FadeTransition(opacity: curved, child: child);
      if (CitroMotion.reduced(context)) return child2;
      return SlideTransition(
        position: Tween(
          begin: const Offset(0, .03),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween(begin: .98, end: 1.0).animate(curved),
          child: child2,
        ),
      );
    },
  );
}

/// 独立的专注页面：带待办侧栏，版式与听隅的「专注」页一致。
class TodoFocusPage extends StatelessWidget {
  /// embedded 时只渲染内容：交给待办页的 tab 容器，切页时左侧栏不动。
  final bool embedded;

  const TodoFocusPage({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 900;
    final desktop = CitroMotion.desktopLike;
    final top =
        (desktop ? AppSpacing.pageTop(media.size.width) : 8.0) +
        media.padding.top;
    void back() {
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      } else {
        nav.pushReplacementNamed('/todo');
      }
    }

    final content = Builder(
      builder: (context) {
        final c = context.c;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide && !embedded)
              TodoRail(
                active: 'focus',
                onBack: back,
                onSelect: (key) {
                  switch (key) {
                    case 'todo':
                      Navigator.of(context).pushReplacementNamed('/todo');
                    case 'data':
                      Navigator.of(context)
                          .pushReplacementNamed('/todo', arguments: 1);
                    case 'cici':
                      Navigator.of(context)
                          .pushReplacementNamed('/todo', arguments: 2);
                  }
                },
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: wide && !embedded ? 24 : 0,
                ),
                child: Column(
                  children: [
                    SizedBox(height: embedded ? 4 : top),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 0 : 16,
                        0,
                        wide ? 0 : 16,
                        0,
                      ),
                      child: Row(
                        children: [
                          if (!wide && !embedded) ...[
                            Pressable(
                              onTap: back,
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
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: embedded
                                ? const SizedBox.shrink()
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '专注',
                                        style: context.ui(
                                          size: CitroType.heading,
                                          weight: CitroType.strong,
                                          color: c.ink,
                                        ),
                                      ),
                                      Text(
                                        '一段一段地做，把注意力放回此刻。',
                                        style: context.ui(
                                          size: CitroType.label,
                                          color: c.inkSoft,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          ListenableBuilder(
                            listenable: PomodoroState.instance,
                            builder: (context, _) {
                              final state = PomodoroState.instance;
                              // 还没有记录时不显示空状态文案。
                              if (state.todayMinutes == 0) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: c.accent.withAlpha(30),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '今日 ${state.todayMinutes} 分钟',
                                  style: context.ui(
                                    size: CitroType.caption,
                                    weight: CitroType.strong,
                                    color: c.accentInk,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 0 : 16,
                          0,
                          wide ? 0 : 16,
                          24,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1050),
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final card = const PomodoroCard(
                                  showHeader: false,
                                  showClose: false,
                                  showLongSlider: false,
                                  minHeight: 520,
                                );
                                final side = Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _settingsCard(context),
                                    const SizedBox(height: 16),
                                    _doingCard(context),
                                  ],
                                );
                                if (box.maxWidth >= 720) {
                                  return Column(
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(flex: 6, child: card),
                                          const SizedBox(width: 20),
                                          Expanded(flex: 5, child: side),
                                        ],
                                      ),
                                      const SizedBox(height: 18),
                                      _statsCard(context),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    card,
                                    const SizedBox(height: 18),
                                    side,
                                    const SizedBox(height: 18),
                                    _statsCard(context),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
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
    if (embedded) return TodoScope(child: content);
    return TodoScope(
      child: Builder(
        builder: (context) {
          final c = context.c;
          return Scaffold(
            backgroundColor: c.bg,
            body: PaperBackground(child: content),
          );
        },
      ),
    );
  }

  Widget _settingsCard(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: PomodoroState.instance,
      builder: (context, _) {
        final state = PomodoroState.instance;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.line2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '节奏',
                          style: context.ui(
                            size: CitroType.title,
                            weight: CitroType.strong,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${state.focusMinutes} 分钟专注 · ${state.shortMinutes} 分钟短休 · 每 ${state.longEvery} 轮长休',
                          style: context.ui(
                            size: CitroType.caption,
                            color: c.inkSoft,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: () => _openDurations(context),
                    scale: .94,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        '调时长',
                        style: context.ui(
                          size: CitroType.caption,
                          weight: CitroType.strong,
                          color: c.accentInk,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _mixRow(context),
              const SizedBox(height: 10),
              Divider(height: 1, color: c.line),
              _SettingsFold(
                children: [
                  _switchRow(
                    context,
                    '自动开始下一阶段',
                    '专注和休息自动衔接',
                    state.autoStart,
                    state.setAutoStart,
                  ),
                  _switchRow(
                    context,
                    '专注时播放混音',
                    '开始专注时自动播放当前混音',
                    state.playWithFocus,
                    state.setPlayWithFocus,
                  ),
                  _switchRow(
                    context,
                    '休息时暂停混音',
                    '让耳朵也一起休息',
                    state.pauseOnBreak,
                    state.setPauseOnBreak,
                  ),
                  _switchRow(
                    context,
                    '结束提示音',
                    '专注或休息结束时响一声',
                    state.chime,
                    state.setChime,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _switchRow(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.ui(
                    size: CitroType.label,
                    weight: CitroType.strong,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.ui(size: CitroType.caption, color: c.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: .8,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: c.accent.withAlpha(150),
              activeColor: c.accent,
            ),
          ),
        ],
      ),
    );
  }

  /// 混音快捷控件：在专注页就能开关、调听隅的音量。
  Widget _mixRow(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: NookController.instance,
      builder: (context, _) {
        final nook = NookController.instance;
        return Row(
          children: [
            Pressable(
              onTap: () {
                nook.send('toggle');
              },
              scale: .94,
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nook.playing ? c.accent.withAlpha(40) : c.surface2,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: nook.playing ? c.accent : c.line),
                ),
                child: Text(
                  nook.playing ? '暂停混音' : '播放混音',
                  style: context.ui(
                    size: CitroType.caption,
                    weight: CitroType.strong,
                    color: nook.playing ? c.accentInk : c.ink2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Pressable(
              onTap: () => _openMixPicker(context),
              scale: .94,
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: c.line),
                ),
                child: Text(
                  '切换',
                  style: context.ui(
                    size: CitroType.caption,
                    weight: CitroType.strong,
                    color: c.ink2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: nook.master.toDouble(),
                  max: 100,
                  activeColor: c.accent,
                  inactiveColor: c.line2,
                  onChanged: (v) {
                    nook.send('master', {'value': v.round()});
                  },
                ),
              ),
            ),
            SizedBox(
              width: 26,
              child: Text(
                '${nook.master}',
                textAlign: TextAlign.right,
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 选一个音源作为当前混音，专注时自动播放。
  Future<void> _openMixPicker(BuildContext context) async {
    final picked = await showCitroSheet<SoundSpec>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TodoScope(child: _MixPicker()),
    );
    if (picked == null) return;
    final nook = NookController.instance;
    await nook.send('load', {
      'tracks': [
        {'id': picked.id, 'volume': 60},
      ],
      'master': nook.master,
    });
    if (!nook.playing) await nook.send('play');
  }

  Widget _doingCard(BuildContext context) {
    final c = context.c;
    final doing = TodoStore.instance.tasks
        .where((t) => t.state == TodoTaskState.doing)
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(
                strokeSvg(AppIcons.target, width: 2),
                size: 18,
                color: c.accentInk,
              ),
              const SizedBox(width: 6),
              Text(
                '进行中的任务',
                style: context.ui(
                  size: CitroType.title,
                  weight: CitroType.strong,
                  color: c.ink,
                ),
              ),
              const Spacer(),
              Text(
                doing.isEmpty ? '无' : '${doing.length}',
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (doing.isEmpty)
            Text(
              '还没有进行中的任务。去待办把任务改成「进行中」，再回来专注。',
              style: context.ui(
                size: CitroType.caption,
                color: c.inkSoft,
                height: 1.6,
              ),
            )
          else
            for (final t in doing.take(6))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: c.mint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.ui(size: CitroType.label, color: c.ink),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _statsCard(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: PomodoroState.instance,
      builder: (context, _) {
        final state = PomodoroState.instance;
        // 本周是逐日列表，取合计分钟数展示。
        final week = state.weekMinutes.fold<int>(0, (a, b) => a + b);
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.line2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '这段时间',
                style: context.ui(
                  size: CitroType.title,
                  weight: CitroType.strong,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _kv(context, '今日', _value(state.todayMinutes, '分钟')),
                  _kv(context, '本周', _value(week, '分钟')),
                  _kv(context, '完成', _value(state.todayCount, '段')),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '计时在切到其他页面后仍会继续；系统省电策略仍可能暂停提醒，请不要把它当作闹钟。',
                style: context.ui(
                  size: CitroType.caption,
                  color: c.inkSoft,
                  height: 1.6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 还没有记录时显示占位符，避免整排 0 显得像坏掉了。
  String _value(int n, String unit) => n == 0 ? '—' : '$n $unit';

  Widget _kv(BuildContext context, String label, String value) {
    final c = context.c;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.ui(
              size: CitroType.titleLg,
              weight: CitroType.strong,
              color: c.accentInk,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.ui(size: CitroType.caption, color: c.inkSoft),
          ),
        ],
      ),
    );
  }
}

Future<void> _openDurations(BuildContext context) => showCitroDialog<void>(
  context,
  // 时长弹窗同样套用待办的钢青蓝，别跳回全局橙色。
  builder: (_) => const TodoScope(child: _DurationDialog()),
);

/// 混音切换面板：常用的几个自然声，点一下直接换掉当前混音。
class _MixPicker extends StatelessWidget {
  const _MixPicker();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        MediaQuery.paddingOf(context).bottom + 14,
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
          Text(
            '切换混音',
            style: context.ui(
              size: CitroType.title,
              weight: CitroType.strong,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '选一个声音作为当前混音，专注开始时自动播放。',
            style: context.ui(size: CitroType.caption, color: c.inkSoft),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in sounds.take(14))
                  Pressable(
                    onTap: () => Navigator.of(context).pop(s),
                    scale: .995,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.line),
                      ),
                      child: Row(
                        children: [
                          Icon(s.icon, size: 17, color: c.accentInk),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.name,
                              style: context.ui(
                                size: CitroType.body,
                                color: c.ink,
                              ),
                            ),
                          ),
                          Text(
                            s.category,
                            style: context.ui(
                              size: CitroType.caption,
                              color: c.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 高级设置默认收起：专注页只留节奏和混音，点开再调细节。
class _SettingsFold extends StatefulWidget {
  final List<Widget> children;

  const _SettingsFold({required this.children});

  @override
  State<_SettingsFold> createState() => _SettingsFoldState();
}

class _SettingsFoldState extends State<_SettingsFold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: () => setState(() => _open = !_open),
          scale: .995,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Text(
                  '更多设置',
                  style: context.ui(
                    size: CitroType.caption,
                    weight: CitroType.strong,
                    color: c.ink2,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _open ? .25 : 0,
                  duration: reduce ? Duration.zero : CitroMotion.hover,
                  child: AppIcon(
                    strokeSvg(AppIcons.chevronRight, width: 2),
                    size: 15,
                    color: c.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: reduce ? Duration.zero : CitroMotion.size,
          curve: CitroMotion.easeOut,
          alignment: Alignment.topCenter,
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _DurationDialog extends StatefulWidget {
  const _DurationDialog();

  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = PomodoroState.instance;
    return PaperDialog(
      maxWidth: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '调节节奏',
            style: context.ui(
              size: CitroType.heading,
              weight: CitroType.strong,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '专注 5–120 分钟，短休 1–30 分钟，长休 5–60 分钟。',
            style: context.ui(
              size: CitroType.caption,
              color: c.inkSoft,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _row(
            context,
            '专注时长',
            state.focusMinutes,
            (v) => state.setDuration('focus', v),
            5,
            120,
          ),
          _row(
            context,
            '短休时长',
            state.shortMinutes,
            (v) => state.setDuration('short', v),
            1,
            30,
          ),
          _row(
            context,
            '长休时长',
            state.longMinutes,
            (v) => state.setDuration('long', v),
            5,
            60,
          ),
          _row(context, '每几轮长休', state.longEvery, state.setLongEvery, 1, 8),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AccentButton(
              text: '完成',
              height: 42,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    int value,
    ValueChanged<int> onChanged,
    int min,
    int max,
  ) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.ui(size: CitroType.label, color: c.ink2),
            ),
          ),
          _step(context, '−', value > min ? () => onChanged(value - 1) : null),
          SizedBox(
            width: 52,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: context.ui(
                size: CitroType.title,
                weight: CitroType.strong,
                color: c.ink,
              ),
            ),
          ),
          _step(context, '+', value < max ? () => onChanged(value + 1) : null),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, String text, VoidCallback? onTap) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: .9,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? c.surface2.withAlpha(120) : c.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.line),
        ),
        child: Text(
          text,
          style: context.ui(
            size: CitroType.title,
            weight: CitroType.strong,
            color: onTap == null ? c.inkSoft : c.ink,
          ),
        ),
      ),
    );
  }
}

class _FocusDialog extends StatefulWidget {
  final TodoTask? task;
  const _FocusDialog({this.task});

  @override
  State<_FocusDialog> createState() => _FocusDialogState();
}

class _FocusDialogState extends State<_FocusDialog> {
  bool _completing = false;
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    PomodoroState.instance.finished.addListener(_onFinished);
  }

  @override
  void dispose() {
    PomodoroState.instance.finished.removeListener(_onFinished);
    super.dispose();
  }

  void _onFinished() {
    final next = PomodoroState.instance.finished.value;
    if (next == null || !mounted) return;
    setState(() => _completing = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    final media = MediaQuery.sizeOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: media.height * .92,
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(CitroColors.radii.modal),
                border: Border.all(color: c.line),
                boxShadow: CitroColors.shadows.lg(c),
              ),
              child: ListenableBuilder(
                listenable: PomodoroState.instance,
                builder: (context, _) {
                  final state = PomodoroState.instance;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _tape(context),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _header(context, state),
                              if (widget.task != null)
                                _taskLine(context)
                              else
                                _doingList(context),
                              const SizedBox(height: 8),
                              TodoSegTabs<String>(
                                dense: true,
                                items: const [
                                  ('focus', '专注'),
                                  ('short', '短休'),
                                  ('long', '长休'),
                                ],
                                value: state.mode,
                                onChanged: (v) {
                                  state.switchMode(v);
                                  setState(() => _completing = false);
                                },
                              ),
                              const SizedBox(height: 16),
                              _ring(context, state, reduce),
                              const SizedBox(height: 14),
                              if (_completing)
                                _doneHint(context, state)
                              else
                                Text(
                                  _hint(state),
                                  textAlign: TextAlign.center,
                                  style: context.ui(
                                    size: CitroType.caption,
                                    color: c.inkSoft,
                                    height: 1.5,
                                  ),
                                ),
                              const SizedBox(height: 14),
                              _actions(context, state),
                              const SizedBox(height: 12),
                              _durationRow(context, state),
                              AnimatedSize(
                                duration: reduce
                                    ? Duration.zero
                                    : CitroMotion.size,
                                curve: CitroMotion.easeOut,
                                alignment: Alignment.topCenter,
                                child: _showSettings
                                    ? _settings(context, state)
                                    : const SizedBox(width: double.infinity),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tape(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 18,
      child: Center(
        child: Transform.rotate(
          angle: -1.6 * math.pi / 180,
          child: Container(
            width: 96,
            height: 16,
            decoration: BoxDecoration(
              color: c.tape,
              boxShadow: [
                BoxShadow(
                  color: c.dark
                      ? const Color(0x30000000)
                      : const Color(0x735A4A2C),
                  blurRadius: 5,
                  spreadRadius: -3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, PomodoroState state) {
    final c = context.c;
    return Row(
      children: [
        Text(
          '专注',
          style: context.ui(weight: CitroType.strong, size: CitroType.subtitle),
        ),
        const SizedBox(width: 8),
        Text(
          state.todayMinutes == 0 ? '' : '今日 ${state.todayMinutes} 分钟',
          style: context.ui(size: CitroType.small, color: c.inkSoft),
        ),
        const Spacer(),
        TodoCloseButton(onTap: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _taskLine(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.task!.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: CitroType.meta, color: c.ink2),
            ),
          ),
        ],
      ),
    );
  }

  /// 专注时顺手列出「进行中」的任务，点一下标题可以看到正在做什么。
  Widget _doingList(BuildContext context) {
    final c = context.c;
    final doing = TodoStore.instance.tasks
        .where((t) => t.state == TodoTaskState.doing)
        .toList();
    if (doing.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: c.mint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '进行中的任务',
                style: context.ui(
                  size: CitroType.caption,
                  weight: CitroType.strong,
                  color: c.ink2,
                ),
              ),
            ],
          ),
          for (final t in doing.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.ui(size: CitroType.caption, color: c.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _ring(BuildContext context, PomodoroState state, bool reduce) {
    final c = context.c;
    return SizedBox(
      width: 196,
      height: 196,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: state.progress),
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 420),
            curve: CitroMotion.easeOut,
            builder: (_, v, __) => CustomPaint(
              size: const Size(196, 196),
              painter: _FocusRingPainter(
                progress: v,
                color: state.mode == 'focus' ? c.accent : c.mint,
                track: c.line2.withAlpha(120),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.timeText,
                style: context.ui(
                  weight: CitroType.strong,
                  size: 48,
                  color: c.ink,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _modeLabel(state.mode),
                style: context.ui(
                  size: CitroType.caption,
                  color: c.inkSoft,
                  letterSpacing: .4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, PomodoroState state) {
    final c = context.c;
    return Row(
      children: [
        _roundBtn(
          context,
          icon: AppIcons.refresh,
          label: '重置',
          onTap: () {
            state.reset();
            setState(() => _completing = false);
          },
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Pressable(
            onTap: () {
              if (_completing) {
                state.settleFinished();
                setState(() => _completing = false);
              } else {
                state.toggle();
              }
            },
            scale: .985,
            child: AnimatedContainer(
              duration: CitroMotion.hover,
              curve: CitroMotion.easeColor,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _completing ? '下一轮' : (state.running ? '暂停' : '开始'),
                style: context.ui(
                  size: CitroType.bodyLg,
                  weight: CitroType.strong,
                  color: const Color(0xFF2E2C22),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _roundBtn(
          context,
          icon: AppIcons.arrowRight,
          label: '跳过',
          onTap: () {
            state.switchMode(state.mode == 'focus' ? 'short' : 'focus');
            setState(() => _completing = false);
          },
        ),
      ],
    );
  }

  Widget _roundBtn(
    BuildContext context, {
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final c = context.c;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        scale: .92,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line),
          ),
          child: Center(
            child: AppIcon(strokeSvg(icon, width: 2), size: 18, color: c.ink2),
          ),
        ),
      ),
    );
  }

  Widget _durationRow(BuildContext context, PomodoroState state) {
    final c = context.c;
    final minutes = switch (state.mode) {
      'short' => state.shortMinutes,
      'long' => state.longMinutes,
      _ => state.focusMinutes,
    };
    return Row(
      children: [
        Text(
          '本段时长',
          style: context.ui(size: CitroType.caption, color: c.inkSoft),
        ),
        const SizedBox(width: 10),
        TodoStepper(
          value: minutes,
          min: 1,
          max: state.mode == 'focus' ? 180 : 60,
          suffix: ' 分钟',
          onChanged: (v) => state.setDuration(state.mode, v),
        ),
        const SizedBox(width: 8),
        _settingsButton(context),
        const Spacer(),
        Text(
          '第 ${state.todayCount + 1} 段',
          style: context.ui(size: CitroType.caption, color: c.inkSoft),
        ),
      ],
    );
  }

  Widget _settingsButton(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => setState(() => _showSettings = !_showSettings),
      scale: .94,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _showSettings ? c.accent.withAlpha(45) : c.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _showSettings ? c.accent.withAlpha(110) : c.line,
          ),
        ),
        child: Center(
          child: Text(
            _showSettings ? '收起' : '设置',
            style: context.ui(
              size: CitroType.caption,
              weight: _showSettings ? CitroType.strong : CitroType.regular,
              color: _showSettings ? c.accentInk : c.ink2,
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 设置：补齐听隅里的番茄设置项
  // -------------------------------------------------------------------------

  Widget _settings(BuildContext context, PomodoroState state) {
    final c = context.c;
    final week = state.weekMinutes.fold<int>(0, (a, b) => a + b);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: c.bg2.withAlpha(c.dark ? 120 : 80),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, '时长'),
          _durationLine(context, '专注', state.focusMinutes, 5, 180, (v) {
            state.setDuration('focus', v);
          }),
          _durationLine(context, '短休', state.shortMinutes, 1, 60, (v) {
            state.setDuration('short', v);
          }),
          _durationLine(context, '长休', state.longMinutes, 5, 120, (v) {
            state.setDuration('long', v);
          }),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '每 ${state.longEvery} 轮进入长休',
                  style: context.ui(size: CitroType.caption, color: c.ink2),
                ),
              ),
              TodoStepper(
                value: state.longEvery,
                min: 2,
                max: 8,
                onChanged: state.setLongEvery,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: c.line, height: 1),
          const SizedBox(height: 8),
          _toggleLine(context, '自动开始下一轮', state.autoStart, state.setAutoStart),
          _toggleLine(
            context,
            '专注时播放听隅混音',
            state.playWithFocus,
            state.setPlayWithFocus,
          ),
          _toggleLine(
            context,
            '休息时暂停混音',
            state.pauseOnBreak,
            state.setPauseOnBreak,
          ),
          _toggleLine(context, '结束提示音', state.chime, state.setChime),
          _toggleLine(context, '系统通知', state.notify, state.setNotify),
          if (state.chime) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '音色',
                  style: context.ui(size: CitroType.caption, color: c.inkSoft),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 132,
                  child: TodoSegTabs<String>(
                    dense: true,
                    items: const [('bell', '铃'), ('wood', '木')],
                    value: state.chimeKindWood ? 'wood' : 'bell',
                    onChanged: state.setChimeKind,
                  ),
                ),
                const Spacer(),
                Pressable(
                  onTap: state.chimePreview,
                  scale: .95,
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.line),
                    ),
                    child: Center(
                      child: Text(
                        '试听',
                        style: context.ui(size: CitroType.small, color: c.ink2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  '音量',
                  style: context.ui(size: CitroType.caption, color: c.inkSoft),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: c.accent,
                      inactiveTrackColor: c.line2,
                      thumbColor: c.accent,
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                    ),
                    child: Slider(
                      value: state.chimeVolume.toDouble(),
                      min: 0,
                      max: 100,
                      onChanged: (v) => state.setChimeVolume(v.round()),
                    ),
                  ),
                ),
                Text(
                  '${state.chimeVolume}',
                  style: context.ui(size: CitroType.small, color: c.inkSoft),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Divider(color: c.line, height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                state.todayMinutes == 0 ? '' : '今日 ${state.todayMinutes} 分钟',
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
              const Spacer(),
              Text(
                '本周 $week 分钟',
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: context.ui(
        size: CitroType.caption,
        weight: CitroType.strong,
        color: context.c.inkSoft,
      ),
    ),
  );

  Widget _durationLine(
    BuildContext context,
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.ui(size: CitroType.caption, color: context.c.ink2),
            ),
          ),
          TodoStepper(
            value: value,
            min: min,
            max: max,
            suffix: ' 分钟',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _toggleLine(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.ui(size: CitroType.caption, color: c.ink2),
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: CitroMotion.hover,
              curve: CitroMotion.easeColor,
              width: 42,
              height: 24,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? c.accent : c.line2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedAlign(
                duration: CitroMotion.hover,
                curve: CitroMotion.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
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
          ),
        ],
      ),
    );
  }

  Widget _doneHint(BuildContext context, PomodoroState state) {
    final c = context.c;
    final done = state.mode == 'focus';
    return Column(
      children: [
        Text(
          done ? '这一段完成了' : '休息结束',
          style: context.ui(
            weight: CitroType.strong,
            size: CitroType.titleLg,
            color: c.accentInk,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          done ? '喝口水，准备下一段' : '回到专注',
          style: context.ui(size: CitroType.caption, color: c.inkSoft),
        ),
        if (done && widget.task != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Pressable(
              onTap: () {
                final t = widget.task!;
                TodoStore.instance.toggleTask(t);
                Navigator.of(context).pop();
              },
              scale: .97,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: c.accent.withAlpha(40),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: c.accent.withAlpha(110)),
                ),
                child: Text(
                  '把「${widget.task!.title}」勾完成',
                  style: context.ui(
                    size: CitroType.caption,
                    color: c.accentInk,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _modeLabel(String mode) => switch (mode) {
    'short' => '短休息',
    'long' => '长休息',
    _ => '专注中',
  };

  String _hint(PomodoroState state) {
    if (state.running) return '把手机翻面，只做眼前这一件事。';
    if (state.mode == 'focus') return '选一段不被打断的时间。';
    return '休息时离开屏幕，眼睛会谢谢你。';
  }
}

class _FocusRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  _FocusRingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
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
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _FocusRingPainter old) =>
      old.progress != progress || old.color != color;
}
