import 'dart:async';

import 'package:flutter/material.dart';

import '../data/resources.dart';
import '../games/game_loader.dart';
import '../overlays/extra_sheets.dart';
import '../pages/in_app_web.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
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
    final streak = state.checkinStreak;
    final done = state.checkedInToday;
    if (compact) {
      return PaperCard(
        tapeColor: c.tape,
        tapeAngle: 2.4,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        onTap: () => showCheckinOverlay(context),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.hl,
                shape: BoxShape.circle,
                border: Border.all(color: c.line),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.calendar, width: 2),
                  size: 18,
                  color: c.accentInk,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '打卡',
                    style: context.heading(size: 13, color: c.accentInk),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    done ? '今天已完成 · 连续 $streak 天' : '连续 $streak 天 · 轻轻一点记录今天',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(size: 10.5, color: c.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StatePill(done: done),
          ],
        ),
      );
    }
    return PaperCard(
      tapeColor: c.tape,
      tapeAngle: 2.4,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      onTap: () => showCheckinOverlay(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(
                strokeSvg(AppIcons.calendar, width: 2),
                size: 17,
                color: c.accentInk,
              ),
              const SizedBox(width: 5),
              Text(
                '打卡',
                style: context.heading(
                  size: 13,
                  color: c.accentInk,
                  letterSpacing: .3,
                ),
              ),
              const Spacer(),
              _StatePill(done: done),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$streak',
                style: context.display(
                  size: 32,
                  weight: FontWeight.w700,
                  color: c.ink,
                  height: .9,
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '天',
                  style: context.body(
                    size: 11,
                    weight: FontWeight.w600,
                    color: c.inkSoft,
                  ),
                ),
              ),
              const Spacer(),
              _ArrowBadge(
                icon: AppIcons.arrowUpRight,
                tint: c.hl,
                ink: c.accentInk,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            done ? '今天已完成，明天继续' : '轻轻一点，记录今天',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.body(size: 10.5, color: c.inkSoft),
          ),
        ],
      ),
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
          CitroCardMorph.pushPageSoft(
            context,
            source: rect,
            settings: const RouteSettings(name: '/tingyu'),
            builder: (_) => const TingyuPage(),
            snapshot: CitroCardFlight.snapshotOf(context, rect),
          );
        }

        return PaperCard(
          tapeColor: c.tape2,
          tapeAngle: -2.2,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          onTap: openPage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.wave, width: 2),
                    size: 17,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '听隅',
                    style: context.heading(
                      size: 13,
                      color: c.accentInk,
                      letterSpacing: .3,
                    ),
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
                style: context
                    .heading(size: 17, color: c.ink, height: 1.2)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                playing
                    ? '正在播放 · 卡片上可暂停'
                    : (player.tracks.isEmpty ? '给自己，留一小片安静' : '已就绪，点右上角开始'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: 11, color: c.inkSoft),
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
            color: playing ? c.accent : c.mintSoft,
            shape: BoxShape.circle,
            border: Border.all(color: c.line),
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 19,
            color: playing ? const Color(0xFF2E2C34) : c.mintInk,
          ),
        ),
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  final bool done;

  const _StatePill({required this.done});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bg = done ? c.mintSoft : c.hl;
    final fg = done ? c.mintInk : c.accentInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done)
            Text(
              '✓',
              style: context.body(
                size: 9,
                weight: FontWeight.w700,
                color: fg,
                height: 1,
              ),
            ),
          if (done) const SizedBox(width: 3),
          Text(
            done ? '已完成' : '待打卡',
            style: context.body(
              size: 9.5,
              weight: FontWeight.w700,
              color: fg,
              height: 1,
              letterSpacing: .2,
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
    return PaperCard(
      tapeColor: c.tape,
      tapeAngle: -1.6,
      padding: EdgeInsets.zero,
      onTap: () {
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) {
          Navigator.of(context).pushNamed('/${entry.key}');
          return;
        }
        final rect = box.localToGlobal(Offset.zero) & box.size;
        CitroCardMorph.pushPage(
          context,
          source: rect,
          snapshot: CitroCardFlight.snapshotOf(context, rect),
          settings: RouteSettings(name: '/${entry.key}'),
          builder: (_) => buildGamePage(entry.key),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 150;
          return Column(
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(1),
                  padding: EdgeInsets.all(compact ? 5 : 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: entry.gradient(c),
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: const Radius.circular(12),
                      bottom: Radius.circular(compact ? 10 : 9),
                    ),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: entry.art(context),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  compact ? 3 : 5,
                  10,
                  compact ? 4 : 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.heading(
                          size: compact ? 12.5 : 15,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 4),
                      Text(
                        '开局',
                        style: context.body(size: 9.5, color: c.inkSoft),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 首页资源卡片：小工具 / 驱动的一条快捷入口。
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
    final accentBg = isTool ? c.mintSoft : c.noteB;
    final accentInk = isTool ? c.mintInk : c.accentInk;
    final label = isTool ? tool.name : driver!.name;
    final kind = isTool ? '工具' : (driver!.client ? '客户端' : '驱动');
    final desc = isTool
        ? tool.desc
        : (driver!.client ? '安装到本机，开箱即用' : '官方驱动，下载安装');
    final action = isTool
        ? (tool.url != null ? '打开页面' : '打开')
        : (driver!.client ? '下载客户端' : '下载驱动');
    return PaperCard(
      tapeColor: isTool ? c.tape2 : c.tape,
      tapeAngle: isTool ? 1.8 : -1.6,
      padding: EdgeInsets.zero,
      onTap: () => _open(context, tool, driver),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 210;
          final compact = constraints.maxHeight < 130;
          final large =
              constraints.maxWidth >= 330 && constraints.maxHeight >= 168;
          final tile = compact ? 38.0 : (large ? 50.0 : 44.0);
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
                            horizontal: 9,
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
                                  size: 11.5,
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
                      border: Border.all(color: c.line.withAlpha(140)),
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
      if (tool.name == '灵敏度') {
        Navigator.of(context).pushNamed('/sens');
        return;
      }
      if (tool.hash == '#/play' || tool.name == '玩法抽签') {
        Navigator.of(context).pushNamed('/play');
        return;
      }
      if (tool.url != null) {
        await openCitroPage(context, tool.url!, title: tool.name);
      }
      return;
    }
    if (driver != null) {
      await openCitroPage(
        context,
        driver.url,
        title: driver.name,
        download: driver.client || isDownloadLink(driver.url),
      );
    }
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            background,
            Color.alphaBlend(Colors.white.withAlpha(70), background),
          ],
        ),
        borderRadius: BorderRadius.circular(size * .3),
        border: Border.all(color: foreground.withAlpha(42)),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: foreground.withAlpha(38)),
      ),
      child: Text(
        text,
        style: context.body(
          size: 10,
          weight: FontWeight.w700,
          color: foreground,
          height: 1,
        ),
      ),
    );
  }
}
