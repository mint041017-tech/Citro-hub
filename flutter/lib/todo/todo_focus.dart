import 'package:flutter/cupertino.dart' show CupertinoSwitch;
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
                              borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: c.surface2,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: c.line),
                                  boxShadow: CitroColors.shadows.card(c),
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
                                        '把注意力放回此刻。',
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
                                  borderRadius: BorderRadius.circular(CitroColors.radii.chip),
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
                          // 嵌在待办页里时，底部要避开浮动的玻璃导航条。
                          embedded ? 96 : 24,
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
                                    CitroFieldScope(tone: FieldTone.glass, child: Builder(builder: (context) => _settingsCard(context))),
                                    const SizedBox(height: 16),
                                    CitroFieldScope(tone: FieldTone.primary, child: Builder(builder: (context) => _doingCard(context))),
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
                                      CitroFieldScope(tone: FieldTone.deep, child: Builder(builder: (context) => _statsCard(context))),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    card,
                                    const SizedBox(height: 18),
                                    side,
                                    const SizedBox(height: 18),
                                    CitroFieldScope(tone: FieldTone.deep, child: Builder(builder: (context) => _statsCard(context))),
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
          return CitroBackground(
            child: Scaffold(
            // 沉浸式：页面底交给外层 CitroBackground（背景图 + 罩面）。
            backgroundColor: Colors.transparent,
            body: content,
          ),
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
        return CitroCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                        borderRadius: BorderRadius.circular(CitroColors.radii.small),
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
              CitroDivider(height: 1, color: c.line),
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
            child: CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: c.accent,
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
                  borderRadius: BorderRadius.circular(CitroColors.radii.xs),
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
                  borderRadius: BorderRadius.circular(CitroColors.radii.xs),
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
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
        return CitroCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
            style: context.hand(
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
  // 时长弹窗使用待办模块的主题配色（跟随全局背景图派生）。
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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CitroColors.radii.modal),
        ),
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
                borderRadius: BorderRadius.circular(CitroColors.radii.xs),
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
                        borderRadius: BorderRadius.circular(CitroColors.radii.small),
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
          color: onTap == null ? c.surface2.withValues(alpha: c.surface2.a * (120) / 255) : c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.xs),
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
