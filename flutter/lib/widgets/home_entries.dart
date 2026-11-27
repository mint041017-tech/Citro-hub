import 'dart:async';

import 'package:flutter/material.dart';

import '../data/resources.dart';
import '../checkin/checkin_models.dart';
import '../checkin/checkin_store.dart';
import '../games/game_identity.dart';
import '../games/game_loader.dart';
import '../games/game_registry.dart';
import '../overlays/fortune_sheet.dart';
import '../pages/web_resource_actions.dart';
import '../pages/in_app_web.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import '../tingyu/tingyu_controller.dart';
import '../tingyu/tingyu_page.dart';
import '../utils/links.dart';
import 'card_flight.dart';
import 'card_morph.dart';
import 'home_layout.dart';
import 'paper.dart';

/// 首页的高频入口卡片：打卡与听隅。
///
/// 这两个入口原来分别是顶栏里的胶囊按钮和 52px 圆按钮，信息少、目标也小；
/// 换成和天气 / 食谱同一套纸卡之后，入口带上了可读的状态
/// （连续天数、是否已完成、正在播放的声景），点击区域也扩大到半屏宽。
class CheckinCard extends StatelessWidget {
  /// Web 桌面网格 / 较矮的容器用紧凑版：一行放下图标、天数与状态。
  final bool compact;

  const CheckinCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final c = context.c;
    final store = CheckinStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final view = store.homeViewFor(state.checkinStreak);
        final streak = state.checkinStreak;
        if (compact) {
          return CitroCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            onTap: () => showFortuneOverlay(context),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.tintYellow,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      strokeSvg(AppIcons.calendar, width: 2),
                      size: 19,
                      color: c.accentInk,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '打卡',
                        style: context.heading(
                          size: CitroType.label,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        view.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(
                          size: CitroType.small,
                          color: c.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.x1),
                _StatePill(text: view.pill, phase: view.phase),
              ],
            ),
          );
        }
        return CitroCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          onTap: () => showFortuneOverlay(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.calendar, width: 2),
                    size: 18,
                    color: c.ink2,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '打卡',
                    style: context.heading(size: CitroType.label, color: c.ink),
                  ),
                  const Spacer(),
                  _StatePill(text: view.pill, phase: view.phase),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 色场：连续天数是这块的主角，用超大粗体占满留白。
                  Text(
                    '$streak',
                    style: context.heading(
                      size: 64,
                      color: c.ink,
                      height: .86,
                      letterSpacing: -3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '天',
                      style: context.body(
                        size: CitroType.small,
                        weight: CitroType.medium,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _ArrowBadge(
                    icon: AppIcons.arrowUpRight,
                    tint: c.surface2,
                    ink: c.ink,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      view.syncFailed ? '已存本机，联网后再同步' : view.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: CitroType.small,
                        color: view.syncFailed ? c.accentInk : c.inkSoft,
                      ),
                    ),
                  ),
                  if (view.syncing)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 听隅入口卡片：把「白噪音混音」从顶栏圆按钮搬进纸卡。
/// 播放中直接显示当前声景，点进去的仍然是完整的听隅页面。
class TingyuCard extends StatelessWidget {
  const TingyuCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final accent = tingyuAccent(c);
    final reduce = CitroMotion.reduced(context);
    return ListenableBuilder(
      listenable: NookController.instance,
      builder: (context, _) {
        final player = NookController.instance;
        final playing = player.playing;
        void openPage() {
          final rect = CitroCardFlight.rectOf(context);
          if (rect.isEmpty) {
            Navigator.of(context).pushNamed('/tingyu');
            return;
          }
          CitroCardMorph.openCardPage(
            context,
            source: rect,
            settings: const RouteSettings(name: '/tingyu'),
            builder: (_) => const TingyuPage(),
            snapshot: CitroCardFlight.snapshotOf(context, rect),
          );
        }

        return CitroCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          onTap: openPage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.wave, width: 2),
                    size: 18,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '听隅',
                    style: context.heading(size: CitroType.label, color: c.ink),
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: reduce ? Duration.zero : CitroMotion.popover,
                    switchInCurve: CitroMotion.easeOut,
                    switchOutCurve: CitroMotion.exit,
                    child: _NookToggleButton(
                      key: ValueKey(playing ? 'pause' : 'play'),
                      playing: playing,
                      ready: player.tracks.isNotEmpty,
                      onTap: () async {
                        // 还没有声景时，先把人带进听隅挑选声音。
                        if (!playing && player.tracks.isEmpty) {
                          openPage();
                          return;
                        }
                        final ok = await player.send('toggle');
                        if (!ok && context.mounted) {
                          AppToast.show(
                            context,
                            player.error ?? '播放没有开始，请再试一次',
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                playing ? player.title : '白噪音 · 混音',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.heading(size: CitroType.title, color: c.ink),
              ),
              const SizedBox(height: 3),
              Text(
                playing
                    ? '正在播放 · 卡片上可暂停'
                    : (player.tracks.isEmpty ? '给自己，留一小片安静' : '已就绪，点右上角开始'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NookToggleButton extends StatelessWidget {
  final bool playing;
  final bool ready;
  final Future<void> Function() onTap;

  const _NookToggleButton({
    super.key,
    required this.playing,
    required this.ready,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // 播放态沿用听隅模块品牌色（鼠尾草绿）；未播放仍是全局薄荷软底。
    final accent = tingyuAccent(c);
    final onAccent = tingyuOnAccent(c);
    return Semantics(
      button: true,
      label: playing ? '暂停听隅' : (ready ? '播放听隅' : '进入听隅'),
      child: Pressable(
        onTap: () => unawaited(onTap()),
        scale: .92,
        hoverLift: 0,
        hoverShadow: false,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: playing ? accent : c.mintSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 20,
            color: playing ? onAccent : c.mintInk,
          ),
        ),
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  final String text;
  final CheckinHomePhase phase;

  const _StatePill({required this.text, required this.phase});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = switch (phase) {
      CheckinHomePhase.notChecked => (c.surface2, c.inkSoft),
      CheckinHomePhase.pendingReflection => (c.accentLt, c.accentInk),
      _ => (c.mintSoft, c.mintInk),
    };
    final checked = phase != CheckinHomePhase.notChecked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (checked)
            Text(
              phase == CheckinHomePhase.pendingReflection ? '·' : '✓',
              style: context.body(
                size: CitroType.micro,
                weight: CitroType.strong,
                color: fg,
                height: 1,
              ),
            ),
          if (checked) const SizedBox(width: 3),
          Text(
            text,
            style: context.body(
              size: CitroType.small,
              weight: CitroType.medium,
              color: fg,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrowBadge extends StatelessWidget {
  final String icon;
  final Color tint;
  final Color ink;

  const _ArrowBadge({
    required this.icon,
    required this.tint,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
        border: Border.all(color: c.line),
      ),
      child: Center(
        child: AppIcon(strokeSvg(icon, width: 2.2), size: 14, color: ink),
      ),
    );
  }
}

/// 首页小游戏卡片：内容与游戏页一致，点开直接进对应玩法。
class HomeGameCard extends StatelessWidget {
  final String gameKey;

  const HomeGameCard({super.key, required this.gameKey});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entry = gameCardByKey(gameKey);
    if (entry == null) return const SizedBox.shrink();
    final identity = entry.identity;
    final radius = BorderRadius.circular(CitroColors.radii.card);
    return Semantics(
      button: true,
      label: '${entry.title}，${identity.tag}',
      child: Pressable(
        onTap: () {
          final box = context.findRenderObject();
          if (box is! RenderBox || !box.hasSize) {
            Navigator.of(context).pushNamed('/${entry.key}');
            return;
          }
          final rect = box.localToGlobal(Offset.zero) & box.size;
          CitroCardMorph.openCardPage(
            context,
            source: rect,
            snapshot: CitroCardFlight.snapshotOf(context, rect),
            settings: RouteSettings(name: '/${entry.key}'),
            builder: (_) => buildGamePage(entry.key),
          );
        },
        scale: .98,
        hoverLift: 2,
        hoverShadow: false,
        hoverOverlayColor: Colors.white.withValues(alpha: c.dark ? .04 : .10),
        borderRadius: radius,
        child: CitroGlass(
          borderRadius: radius,
          tint: c.surface,
          borderColor: Colors.white.withValues(alpha: c.dark ? .12 : .42),
          highlight: true,
          shadow: CitroColors.shadows.sm(c),
          padding: const EdgeInsets.all(6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 190 && constraints.maxHeight >= 120;
              if (!wide) {
                return Column(
                  children: [
                    Expanded(
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(identity.soft, identity.primary, .12)!,
                              Color.lerp(identity.soft, identity.primary, .34)!,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: c.dark ? .10 : .34,
                            ),
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned(
                              top: -34,
                              right: -28,
                              child: Container(
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(
                                    alpha: c.dark ? .05 : .20,
                                  ),
                                ),
                              ),
                            ),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: entry.art(context),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 7,
                              left: 7,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: GameIdentity.paper.withValues(
                                    alpha: c.dark ? .78 : .66,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    CitroColors.radii.chip,
                                  ),
                                ),
                                child: Text(
                                  identity.tag,
                                  style: TextStyle(
                                    fontFamily: AppFonts.rounded,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: identity.deep,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 7,
                              right: 7,
                              child: Container(
                                width: 23,
                                height: 23,
                                decoration: BoxDecoration(
                                  color: GameIdentity.paper.withValues(
                                    alpha: c.dark ? .68 : .54,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: AppIcon(
                                    strokeSvg(
                                      AppIcons.arrowUpRight,
                                      width: 2.2,
                                    ),
                                    size: 11,
                                    color: identity.deep,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 38,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.heading(
                                  size: 14.5,
                                  color: c.ink,
                                  letterSpacing: -.2,
                                ),
                              ),
                            ),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: identity.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
              final artSize = constraints.maxHeight < 150 ? 60.0 : 68.0;
              final actionInk = c.dark ? identity.onDark() : identity.deep;
              return Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    _artTile(context, entry, c, size: artSize),
                    const SizedBox(width: AppSpacing.x2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: identity.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                identity.tag,
                                style: context.body(
                                  size: CitroType.small,
                                  color: c.inkSoft,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            entry.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.heading(
                              size: CitroType.titleLg,
                              color: c.ink,
                              height: 1.15,
                              letterSpacing: -.3,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.x1),
                          Container(
                            height: 26,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: identity.primary.withValues(
                                alpha: c.dark ? .22 : .12,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: identity.primary.withValues(alpha: .20),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '开局',
                                  style: context.body(
                                    size: CitroType.micro,
                                    weight: CitroType.medium,
                                    color: actionInk,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                AppIcon(
                                  strokeSvg(AppIcons.arrowRight, width: 2.2),
                                  size: 13,
                                  color: actionInk,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 游戏卡的艺术砖：圆角渐变底 + 居中的小游戏插画。
Widget _artTile(
  BuildContext context,
  GameCardData entry,
  CitroColors c, {
  required double size,
}) {
  final identity = entry.identity;
  return Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(identity.soft, identity.primary, .12)!,
          Color.lerp(identity.soft, identity.primary, .34)!,
        ],
      ),
      borderRadius: BorderRadius.circular(size * .28),
      border: Border.all(
        color: Colors.white.withValues(alpha: c.dark ? .10 : .38),
      ),
      boxShadow: CitroColors.shadows.sm(c),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: -size * .22,
          right: -size * .20,
          child: Container(
            width: size * .62,
            height: size * .62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: c.dark ? .05 : .20),
            ),
          ),
        ),
        Center(
          child: FittedBox(fit: BoxFit.contain, child: entry.art(context)),
        ),
      ],
    ),
  );
}

class HomeResCard extends StatelessWidget {
  final String item;

  const HomeResCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tool = toolByItem(item);
    final driver = driverByItem(item);
    if (tool == null && driver == null) return const SizedBox.shrink();
    final isTool = tool != null;
    // 色场：图标块用块内强调色（随背景取色），不再固定薄荷绿。
    final accentBg = c.accent;
    final accentInk = c.onAccent;
    final label = isTool ? tool.name : driver!.name;
    final kind = isTool ? '工具' : (driver!.client ? '客户端' : '驱动');
    final desc = isTool
        ? tool.desc
        : (driver!.client ? '安装到本机，开箱即用' : '官方驱动，下载安装');
    final action = isTool
        ? (tool.url != null ? '打开页面' : '打开')
        : (driver!.client ? '下载客户端' : '下载驱动');
    return CitroCard(
      padding: EdgeInsets.zero,
      onTap: () => _open(context, tool, driver),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 210;
          final compact = constraints.maxHeight < 130;
          final large =
              constraints.maxWidth >= 330 && constraints.maxHeight >= 168;
          final tile = compact ? 38.0 : (large ? 50.0 : 44.0);
          // 窄卡（手机两列时只有 170 出头）：文字横排会被挤成「玩法…」，
          // 改成图标一行、标题与说明各自占满整宽的竖排。
          if (narrow) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ResIconTile(
                        icon: tool?.icon ?? AppIcons.download,
                        size: 36,
                        background: accentBg,
                        foreground: accentInk,
                      ),
                      const Spacer(),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: accentBg,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.line.withValues(
                              alpha: c.line.a * (140) / 255,
                            ),
                          ),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.arrowUpRight, width: 2.2),
                            size: 12,
                            color: accentInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context
                        .heading(size: 16, color: c.ink, height: 1.15)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 11.5,
                      color: c.inkSoft,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            );
          }
          return Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 12,
              compact ? 8 : 10,
              compact ? 10 : 12,
              compact ? 8 : 10,
            ),
            child: Row(
              children: [
                _ResIconTile(
                  icon: tool?.icon ?? AppIcons.download,
                  size: tile,
                  background: accentBg,
                  foreground: accentInk,
                ),
                SizedBox(width: compact ? 9 : 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context
                                  .heading(
                                    size: narrow
                                        ? 15.5
                                        : (compact ? 18 : (large ? 21 : 19)),
                                    color: c.ink,
                                    height: 1.15,
                                  )
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (!narrow) ...[
                            const SizedBox(width: 5),
                            _ResKindChip(
                              text: kind,
                              background: accentBg,
                              foreground: accentInk,
                            ),
                          ],
                        ],
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 3),
                        Text(
                          desc,
                          maxLines: large ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.body(
                            size: large ? 12.5 : 11.5,
                            color: c.inkSoft,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (large) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accentBg,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: accentInk.withAlpha(46)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                action,
                                style: context.body(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: accentInk,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 11,
                                color: accentInk,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!large) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: compact ? 26 : 30,
                    height: compact ? 26 : 30,
                    decoration: BoxDecoration(
                      color: accentBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c.line.withValues(alpha: c.line.a * (140) / 255),
                      ),
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(AppIcons.arrowUpRight, width: 2.2),
                        size: compact ? 12 : 14,
                        color: accentInk,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    ToolItem? tool,
    DriverItem? driver,
  ) async {
    if (tool != null) {
      openCitroTool(context, tool);
      return;
    }
    await openCitroPage(
      context,
      driver!.url,
      title: driver.name,
      download: driver.client || isDownloadLink(driver.url),
    );
  }
}

/// 资源卡片的图标块：工具用薄荷色，驱动用浅蓝色，和资源库分组呼应。
class _ResIconTile extends StatelessWidget {
  final String icon;
  final double size;
  final Color background;
  final Color foreground;

  const _ResIconTile({
    required this.icon,
    required this.size,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * .3),
        boxShadow: [
          BoxShadow(
            color: foreground.withAlpha(26),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: AppIcon(
          strokeSvg(icon, width: 2),
          size: size * .5,
          color: foreground,
        ),
      ),
    );
  }
}

/// 小类型胶囊：工具 / 驱动 / 客户端。
class _ResKindChip extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;

  const _ResKindChip({
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: context.body(
          size: CitroType.micro,
          weight: CitroType.medium,
          color: foreground,
          height: 1,
        ),
      ),
    );
  }
}
