import 'dart:async';

import 'package:flutter/material.dart';

import '../checkin/checkin_models.dart';
import '../checkin/checkin_poster.dart';
import '../checkin/checkin_store.dart';
import '../data/cards.dart';
import '../overlays/card_draw.dart';
import '../overlays/reflection_sheet.dart';
import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

/// 打开长卷页。
Future<void> openCheckinScroll(BuildContext context, {int? volume}) {
  return Navigator.of(context).pushNamed('/checkin/scroll', arguments: volume);
}

/// 长卷页：七天一卷，可翻看历史卷，点任一格可补 / 改回签。
class CheckinScrollPage extends StatefulWidget {
  final int? initialVolume;

  const CheckinScrollPage({super.key, this.initialVolume});

  @override
  State<CheckinScrollPage> createState() => _CheckinScrollPageState();
}

class _CheckinScrollPageState extends State<CheckinScrollPage> {
  int? _selected;
  bool _mergeChecked = false;

  CheckinStore get _store => CheckinStore.instance;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialVolume;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_store.flushNow());
      _maybePromptGuestMerge();
    });
  }

  Future<void> _maybePromptGuestMerge() async {
    if (_mergeChecked || !mounted) return;
    _mergeChecked = true;
    final available = await _store.guestMergeAvailable;
    if (!available || !mounted) return;
    final bring = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final c = ctx.c;
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CitroColors.radii.modal),
          ),
          title: Text('这台设备上还有游客打卡', style: ctx.heading(size: 18)),
          content: Text(
            '要带进当前账号吗？带入后只在本机显示过去几天，跨设备同步从今天开始。',
            style: ctx.body(size: CitroType.body, color: c.ink2, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('先不带入'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('带入'),
            ),
          ],
        );
      },
    );
    if (bring == true) {
      final added = await _store.mergeGuestRecords();
      if (mounted && added > 0) {
        AppToast.show(context, '已带入 $added 天游客记录');
      }
    } else {
      await _store.dismissGuestMerge();
    }
  }

  CheckinVolume get _volume {
    final volumes = _store.volumes;
    if (volumes.isEmpty) {
      return _selected == null
          ? _store.currentVolume
          : CheckinVolume(index: _selected!, entries: const []);
    }
    final index = (_selected ?? volumes.last.index).clamp(1, volumes.length);
    return volumes.firstWhere(
      (v) => v.index == index,
      orElse: () => volumes.last,
    );
  }

  Future<void> _openEntry(CheckinDayEntry entry) async {
    if (!CheckinFlags.reflectionEnabled) return;
    final saved = await showReflectionSheet(context, date: entry.date);
    if (!mounted) return;
    if (saved == true) {
      AppToast.show(
        context,
        entry.date == _store.todayKey ? '今天收好了' : '已更新这一天',
      );
    }
  }

  void _go(int delta) {
    final volumes = _store.volumes;
    if (volumes.isEmpty) return;
    final current = _volume.index;
    final next = current + delta;
    if (next < 1 || next > volumes.length) return;
    setState(() => _selected = next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final media = MediaQuery.sizeOf(context);
    final wide = media.width >= 700;
    final side = wide ? 32.0 : 16.0;
    // 最外层必须是 Material：这个页面没有 Scaffold，缺了 Material 之后
    // 页面里每一条 Text 都会退回「未包 Material」的兜底样式，
    // 整页文字都拖着一根黄色下划线（同 games_page 的注释）。
    // 独立打开的页面：自己铺沉浸背景（背景图柔化版 + 罩面），
    // Material 只负责文字默认样式，不再铺不透明的页面底色。
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          CitroBackground(
            child: SafeArea(
              bottom: false,
              child: ListenableBuilder(
                listenable: _store,
                builder: (context, _) {
                  final volume = _volume;
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      side,
                      platform.isWindows ? AppSpacing.pageTop(media.width) : 8,
                      side,
                      110,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _header(context),
                            const SizedBox(height: 18),
                            _volumeCard(context, volume),
                            const SizedBox(height: 14),
                            _syncStrip(context),
                            const SizedBox(height: 18),
                            ...List.generate(7, (i) {
                              final entry = i < volume.entries.length
                                  ? volume.entries[i]
                                  : null;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: entry == null
                                    ? _EmptyCell(index: i)
                                    : _DayCell(
                                        entry: entry,
                                        onTap: () => _openEntry(entry),
                                      ),
                              );
                            }),
                            const SizedBox(height: 10),
                            _volumeNav(context, volume),
                            const SizedBox(height: 22),
                            _posterActions(context, volume),
                            const SizedBox(height: 10),
                            Text(
                              '七天一卷，不要求连续；漏掉的格子不会把前面的记录清空。',
                              textAlign: TextAlign.center,
                              style: context.body(
                                size: CitroType.small,
                                color: c.inkSoft,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Pressable(
          onTap: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
            } else {
              nav.pushReplacementNamed('/');
            }
          },
          child: SizedBox(
            width: AppSpacing.touch,
            height: AppSpacing.touch,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.line),
                ),
                child: Center(
                  child: AppIcon(
                    strokeSvg(AppIcons.arrowLeft, width: 2),
                    size: 18,
                    color: c.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('我的长卷', style: context.heading(size: CitroType.heading)),
              const SizedBox(height: 4),
              Text(
                '把每一次来过的日子，按七天收成一卷。',
                style: context.body(size: CitroType.caption, color: c.inkSoft),
              ),
            ],
          ),
        ),
        if (CheckinFlags.scrollEnabled)
          Pressable(
            onTap: () => showCheckinPoster(context, volume: _volume),
            child: SizedBox(
              width: AppSpacing.touch,
              height: AppSpacing.touch,
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c.ink,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    child: AppIcon(
                      strokeSvg(AppIcons.download, width: 2),
                      size: 17,
                      color: c.bg,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _volumeCard(BuildContext context, CheckinVolume volume) {
    final c = context.c;
    final volumes = _store.volumes;
    final total = volumes.isEmpty ? 1 : volumes.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.sm(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                volume.title,
                style: context.display(size: 30, color: c.accentInk, height: 1),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${volume.filled} / 7 天',
                  style: context.hand(
                    size: CitroType.caption,
                    color: c.inkSoft,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$total 卷',
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            volume.rangeLabel,
            style: context.body(
              size: CitroType.caption,
              color: c.ink2,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(7, (i) {
              final filled = i < volume.entries.length;
              final entry = filled ? volume.entries[i] : null;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 6 ? 0 : 5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 6,
                    decoration: BoxDecoration(
                      color: entry == null
                          ? c.surface2
                          : entry.hasReflection
                          ? c.accent
                          : c.mint,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _LegendDot(color: c.mint, text: '来过'),
              const SizedBox(width: 14),
              _LegendDot(color: c.accent, text: '已回签'),
              const SizedBox(width: 14),
              _LegendDot(color: c.surface2, text: '还空着'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _syncStrip(BuildContext context) {
    final c = context.c;
    final note = _store.syncNote;
    final text = _store.syncing
        ? '正在同步这几天的记录…'
        : _store.isGuest
        ? '游客记录只存在这台设备；登录后会按今天的记录开始同步。'
        : (_store.syncFailed
              ? (note ?? '已存本机，联网后再同步')
              : (_store.conflictDate != null
                    ? '另一台设备改过同一天的回签，本机文字已保留。'
                    : null));
    if (text == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          AppIcon(
            strokeSvg(AppIcons.info, width: 1.8),
            size: 15,
            color: c.inkSoft,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: context.body(
                size: CitroType.small,
                color: c.ink2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _volumeNav(BuildContext context, CheckinVolume volume) {
    final c = context.c;
    final volumes = _store.volumes;
    final total = volumes.isEmpty ? 1 : volumes.length;
    final canPrev = volume.index > 1;
    final canNext = volume.index < total;
    return Row(
      children: [
        _NavButton(
          icon: AppIcons.arrowLeft,
          label: '上一卷',
          enabled: canPrev,
          onTap: () => _go(-1),
        ),
        Expanded(
          child: Text(
            '第 ${volume.index} / $total 卷',
            textAlign: TextAlign.center,
            style: context.body(
              size: CitroType.caption,
              color: c.inkSoft,
              letterSpacing: .4,
            ),
          ),
        ),
        _NavButton(
          icon: AppIcons.arrowRight,
          label: '下一卷',
          enabled: canNext,
          onTap: () => _go(1),
        ),
      ],
    );
  }

  Widget _posterActions(BuildContext context, CheckinVolume volume) {
    if (!CheckinFlags.scrollEnabled) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: CitroButton(
            label: '保存纪念图',
            height: 48,
            onPressed: () => showCheckinPoster(context, volume: volume),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CitroButton(
            label: '分享',
            style: CitroButtonStyle.outline,
            height: 48,
            onPressed: () => showCheckinPoster(context, volume: volume),
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatefulWidget {
  final CheckinDayEntry entry;
  final VoidCallback onTap;

  const _DayCell({required this.entry, required this.onTap});

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final e = widget.entry;
    final card = CardCatalog.byId(e.cardId);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Pressable(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hover ? c.surface2 : c.surface,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
            border: Border.all(color: c.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 62,
                  height: 82,
                  child: card == null
                      ? ColoredBox(
                          color: c.tintYellow,
                          child: Center(
                            child: Text(
                              e.signTitle,
                              maxLines: 3,
                              textAlign: TextAlign.center,
                              style: context.heading(size: 11, color: c.ink2),
                            ),
                          ),
                        )
                      : _DayFace(card: card, muted: !e.hasReflection),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          checkinDateLabel(e.date),
                          style: context.body(
                            size: CitroType.small,
                            color: c.inkSoft,
                            weight: FontWeight.w600,
                            letterSpacing: .2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _MiniTag(text: e.kindLabel),
                        const Spacer(),
                        if (e.hasReflection)
                          const _Stamp(text: '已回签', accent: true)
                        else if (e.actionDone)
                          const _Stamp(text: '已做到'),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      e.signTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.heading(size: 15, color: c.ink),
                    ),
                    if (e.actionText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        e.actionText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(
                          size: CitroType.small,
                          color: c.ink2,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (e.hasText) ...[
                      const SizedBox(height: 5),
                      Text(
                        e.reflectionText.replaceAll('\n', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(
                          size: CitroType.small,
                          color: c.accentInk,
                          height: 1.35,
                        ),
                      ),
                    ],
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

class _EmptyCell extends StatelessWidget {
  final int index;

  const _EmptyCell({required this.index});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CustomPaint(
      painter: _DashedBoxPainter(color: c.line2),
      child: Container(
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.line),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: context.hand(
                    size: CitroType.caption,
                    color: c.inkSoft,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '第 ${index + 1} 格还空着',
              style: context.body(
                size: CitroType.caption,
                color: c.inkSoft,
                letterSpacing: .3,
              ),
            ),
            const Spacer(),
            Text(
              '不必补',
              style: context.body(
                size: CitroType.micro,
                color: c.inkSoft.withAlpha(150),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayFace extends StatelessWidget {
  final CardFace card;
  final bool muted;

  const _DayFace({required this.card, required this.muted});

  static const _mutedMatrix = <double>[
    0.88,
    0.07,
    0.05,
    0,
    8,
    0.07,
    0.88,
    0.05,
    0,
    8,
    0.05,
    0.05,
    0.88,
    0,
    8,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  Widget build(BuildContext context) {
    final face = CardFaceImage(card: card, cacheWidth: 200, fit: BoxFit.cover);
    if (!muted) return face;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(_mutedMatrix),
      child: face,
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String text;

  const _MiniTag({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.accentLt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: context.body(size: CitroType.micro, color: c.accentInk),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  final String text;
  final bool accent;

  const _Stamp({required this.text, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Transform.rotate(
      angle: -.035,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(
            color: (accent ? c.accent : c.mint).withAlpha(160),
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          text,
          style: context.body(
            size: CitroType.micro,
            color: accent ? c.accent : c.mintInk,
            weight: FontWeight.w700,
            letterSpacing: .5,
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String text;

  const _LegendDot({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: context.body(size: CitroType.micro, color: c.inkSoft),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final String icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : .35,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon == AppIcons.arrowLeft) ...[
                AppIcon(strokeSvg(icon, width: 2), size: 14, color: c.ink2),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: context.body(size: CitroType.small, color: c.ink2),
              ),
              if (icon == AppIcons.arrowRight) ...[
                const SizedBox(width: 5),
                AppIcon(strokeSvg(icon, width: 2), size: 14, color: c.ink2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  final Color color;

  _DashedBoxPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 5.0;
    const gap = 4.0;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBoxPainter old) => old.color != color;
}

/// 第七次打卡后出现的成卷提示。不弹全身彩纸，只给一个安静的印章。
Future<void> showCheckinVolumeDone(
  BuildContext context, {
  required int volumeIndex,
}) async {
  final store = CheckinStore.instance;
  final volumes = store.volumes;
  final volume = volumes.length >= volumeIndex
      ? volumes[volumeIndex - 1]
      : CheckinVolume(index: volumeIndex, entries: const []);
  await showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.c.scrim,
    builder: (ctx) {
      final c = ctx.c;
      return Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CitroColors.radii.modal),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.accent, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      volumeIndex.toString(),
                      style: ctx.display(size: 30, color: c.accentInk),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '第 $volumeIndex 卷已经集齐',
                  style: ctx.heading(size: CitroType.titleLg),
                ),
                const SizedBox(height: 8),
                Text(
                  '这七次来到 Citro 的日子，替你收成了一卷。',
                  textAlign: TextAlign.center,
                  style: ctx.body(
                    size: CitroType.body,
                    color: c.ink2,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 22),
                CitroButton(
                  label: '展开这一卷',
                  expanded: true,
                  height: 48,
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    openCheckinScroll(context, volume: volumeIndex);
                  },
                ),
                const SizedBox(height: 8),
                CitroButton(
                  label: '保存纪念图',
                  style: CitroButtonStyle.outline,
                  expanded: true,
                  height: 46,
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    showCheckinPoster(context, volume: volume);
                  },
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    openCheckinScroll(context, volume: volumeIndex + 1);
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('先看看下一卷'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
