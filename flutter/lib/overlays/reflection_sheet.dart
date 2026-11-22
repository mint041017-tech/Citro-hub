import 'package:flutter/material.dart';

import '../checkin/checkin_models.dart';
import '../checkin/checkin_store.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

/// 晚间回签弹层。
///
/// 只做两件事：选一个落点、写一句可留可不留的话。
/// 不弹窗、不加红点、不催办；`今天先不写` 和 `收好今天` 一样大。
Future<bool?> showReflectionSheet(
  BuildContext context, {
  String? date,
}) {
  return showCitroSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.c.scrim,
    builder: (_) => _ReflectionSheet(date: date),
  );
}

class _ReflectionSheet extends StatefulWidget {
  final String? date;

  const _ReflectionSheet({this.date});

  @override
  State<_ReflectionSheet> createState() => _ReflectionSheetState();
}

class _ReflectionSheetState extends State<_ReflectionSheet> {
  late final TextEditingController _controller;
  String? _mood;
  bool _busy = false;
  String? _error;

  CheckinDayEntry? get _entry =>
      CheckinStore.instance.entryFor(widget.date ?? CheckinStore.instance.todayKey);

  @override
  void initState() {
    super.initState();
    final entry = _entry;
    _mood = entry?.reflectionMood;
    _controller = TextEditingController(text: entry?.reflectionText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final entry = await CheckinStore.instance.saveReflection(
      date: widget.date,
      mood: _mood,
      text: _controller.text,
    );
    if (!mounted) return;
    if (entry == null) {
      setState(() {
        _busy = false;
        _error = '这一天的记录还没准备好，稍后再试';
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final media = MediaQuery.of(context);
    final entry = _entry;
    final bottomInset = media.viewInsets.bottom;
    final already = entry?.hasReflection == true;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CitroColors.radii.modal),
          ),
          boxShadow: CitroColors.shadows.lg(c),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: c.accentLt,
                              borderRadius: BorderRadius.circular(
                                CitroColors.radii.inner,
                              ),
                            ),
                            child: Center(
                              child: AppIcon(
                                strokeSvg(AppIcons.edit, width: 2),
                                size: 18,
                                color: c.accentInk,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '给今天收个尾',
                                  style: context.heading(
                                    size: CitroType.titleLg,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  checkinDateLabel(
                                    entry?.date ??
                                        widget.date ??
                                        CheckinStore.instance.todayKey,
                                  ),
                                  style: context.body(
                                    size: CitroType.caption,
                                    color: c.inkSoft,
                                    letterSpacing: .4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Pressable(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: SizedBox(
                              width: AppSpacing.touch,
                              height: AppSpacing.touch,
                              child: Center(
                                child: AppIcon(
                                  strokeSvg(AppIcons.close, width: 2),
                                  size: 20,
                                  color: c.ink2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (entry != null) ...[
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(
                              CitroColors.radii.inner,
                            ),
                            border: Border.all(color: c.line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      entry.signTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.heading(
                                        size: CitroType.bodyLg,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _Tag(
                                    text: entry.kindLabel,
                                    color: c.accentInk,
                                    background: c.accentLt,
                                  ),
                                  const Spacer(),
                                  _Tag(
                                    text: entry.actionDone ? '已行动' : '待行动',
                                    color: entry.actionDone
                                        ? c.mintInk
                                        : c.inkSoft,
                                    background: entry.actionDone
                                        ? c.mintSoft
                                        : c.surface,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '今天的一小步：${entry.actionDone ? entry.completedActionText ?? entry.actionText : entry.actionText}',
                                style: context.body(
                                  size: CitroType.caption,
                                  color: c.ink2,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        '今天落在哪里？',
                        style: context.heading(size: CitroType.bodyLg),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '选一个最接近的就好，也可以不归类。',
                        style: context.body(
                          size: CitroType.caption,
                          color: c.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: CheckinMood.all.map((mood) {
                          final selected = (_mood ?? CheckinMood.unrated) == mood;
                          return _MoodChip(
                            label: CheckinMood.label(mood),
                            selected: selected,
                            onTap: () => setState(() => _mood = mood),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            '留一句话',
                            style: context.heading(size: CitroType.bodyLg),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '可留可不留',
                            style: context.body(
                              size: CitroType.micro,
                              color: c.inkSoft,
                              letterSpacing: .6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _controller,
                        maxLength: kCheckinReflectionMax,
                        minLines: 3,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        style: context.body(size: CitroType.bodyLg, height: 1.55),
                        cursorColor: c.accent,
                        decoration: InputDecoration(
                          hintText: '今天有什么小事，值得留一句？',
                          hintStyle: context.body(
                            size: CitroType.body,
                            color: c.inkSoft,
                          ),
                          counterText: '',
                          filled: true,
                          fillColor: c.surface2,
                          contentPadding: const EdgeInsets.fromLTRB(
                            16,
                            14,
                            16,
                            14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CitroColors.radii.inner,
                            ),
                            borderSide: BorderSide(color: c.line),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CitroColors.radii.inner,
                            ),
                            borderSide: BorderSide(color: c.accent),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_controller.text.runes.length} / $kCheckinReflectionMax',
                          style: context.hand(
                            size: CitroType.micro,
                            color: c.inkSoft,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppIcon(
                              strokeSvg(AppIcons.lock, width: 1.8),
                              size: 15,
                              color: c.inkSoft,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '回签只存在你的打卡记录与同步服务里，不会发到社区、CiCi 或任何公开位置。',
                                style: context.body(
                                  size: CitroType.small,
                                  color: c.inkSoft,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (already) ...[
                        const SizedBox(height: 10),
                        Text(
                          '今天已经收好过一次，修改会保留最新的落点与文字。',
                          style: context.body(
                            size: CitroType.small,
                            color: c.inkSoft,
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: context.body(
                            size: CitroType.caption,
                            color: c.danger,
                          ),
                        ),
                      ],
                      if (CheckinStore.instance.conflictDate ==
                              (entry?.date ?? widget.date) &&
                          CheckinStore.instance.conflictDate != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          '另一台设备也改过这一天，已保留你这一版的文字。',
                          style: context.body(
                            size: CitroType.small,
                            color: c.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  children: [
                    CitroButton(
                      label: '收好今天',
                      expanded: true,
                      height: 52,
                      busy: _busy,
                      onPressed: _busy ? null : _save,
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: c.ink2,
                        textStyle: context.body(
                          size: CitroType.label,
                          color: c.ink2,
                        ),
                      ),
                      child: const Text('今天先不写'),
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
}

class _MoodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MoodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? c.accentLt : c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? c.accent : c.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              AppIcon(
                strokeSvg(AppIcons.check, width: 2),
                size: 13,
                color: c.accentInk,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: context.body(
                size: CitroType.caption,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? c.accentInk : c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;

  const _Tag({
    required this.text,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: context.body(
          size: CitroType.micro,
          color: color,
          letterSpacing: .3,
        ),
      ),
    );
  }
}
