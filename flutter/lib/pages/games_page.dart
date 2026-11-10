import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../games/game_loader.dart';
import '../games/game_registry.dart';
import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/card_flight.dart';
import '../widgets/card_morph.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/paper.dart';
import '../widgets/shared_element.dart';
import '../widgets/tablet_shell.dart';
import 'in_app_web.dart';
import 'web_scrapbook.dart';

class GamesPage extends StatelessWidget {
  const GamesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final layout = CitroLayoutScope.maybeOf(context);
    final width = layout?.contentWidth ?? MediaQuery.sizeOf(context).width;
    final tabletNav = layout?.tabletNav ?? false;
    // 宽屏网页与桌面端一致：更宽的画布、同样大的游戏卡，不再附赠资源库入口。
    final desktopWeb = kIsWeb && width >= 1025;
    final wideDesktop = tabletNav || desktopWeb;
    final maxWidth = wideDesktop ? 1120.0 : 840.0;
    final side = math.max(8.0, (width - maxWidth) / 2);
    final duo = layout?.duo == true;
    final gameColumns = duo
        ? (width >= 900 ? 6 : (width >= 640 ? 5 : (width >= 460 ? 4 : 3)))
        : (width >= 1180 ? 7 : (width >= 920 ? 6 : (width >= 680 ? 5 : 3)));
    final games = kGameCards;
    // 分类重排：按玩法类型分组，不再是一整坨平铺。
    final gameGroups = <(String, List<GameCardData>)>[
      for (final group in const <(String, List<String>)>[
        ('益智', ['g2048', 'gmem', 'gsudoku', 'gnono', 'gslide']),
        ('休闲', ['gsnake', 'gsheep', 'gjump', 'gpeng', 'gbrake']),
        ('文字', ['gidiom', 'gfeihua']),
        ('创意', ['gliquid', 'gknockwater']),
      ])
        (
          group.$1,
          [for (final key in group.$2) games.firstWhere((g) => g.key == key)],
        ),
    ];
    final mobileApp = !kIsWeb && (platform.isAndroid || platform.isIOS);
    final gameTools = <_GameToolLink>[
      _GameToolLink(
        title: '玩法抽签',
        desc: '无畏契约整活玩法',
        icon: AppIcons.sparkle,
        background: c.tintPink,
        foreground: c.stamp,
        onTap: () => Navigator.of(context).pushNamed('/play'),
      ),
      _GameToolLink(
        title: '瞬投',
        desc: '投掷物点位地图',
        icon: AppIcons.location,
        background: c.mintSoft,
        foreground: c.mintInk,
        onTap: () =>
            openCitroPage(context, 'https://shuntou.top/', title: '瞬投'),
      ),
      _GameToolLink(
        title: '屏幕分享',
        desc: '网页共享与远程演示',
        icon: AppIcons.monitor,
        background: c.tintBlue,
        foreground: c.accentInk,
        onTap: () =>
            openCitroPage(context, 'https://demo.piik.tv/', title: '屏幕分享'),
      ),
      _GameToolLink(
        title: '视野live',
        desc: '实时视野 · 在线直播',
        icon: AppIcons.eye,
        background: c.mintSoft,
        foreground: c.mintInk,
        onTap: () => openCitroPage(
          context,
          'https://shijiao.xingpaste.com/',
          title: '视野live',
        ),
      ),
      if (!mobileApp)
        _GameToolLink(
          title: 'MsLab',
          desc: '毫秒灵敏度调试',
          icon: '<circle cx="12" cy="12" r="8"/><path d="M12 8v4l2.5 1.5"/><path d="M12 1v3M12 20v3M1 12h3M20 12h3"/>',
          background: c.tintGreen,
          foreground: c.mintInk,
          onTap: () =>
              openCitroPage(context, 'https://mslab.gg/', title: 'MsLab'),
        ),
    ];
    final downloadSite = kIsWeb
        ? _GameToolLink(
            title: '下载站',
            desc: 'App、Mod 与工具下载',
            icon: AppIcons.download,
            background: c.tintGreen,
            foreground: c.mintInk,
            onTap: () => openCitroPage(
              context,
              'https://dl.chimu-claw.xyz/',
              title: 'Citro 下载站',
            ),
          )
        : null;
    final showGameTools = kIsWeb || platform.isAndroid || platform.isIOS;
    final content = CitroBackground(
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            side,
            AppSpacing.pageTop(width),
            side,
            wideDesktop ? 32 : 100,
          ),
          child: CitroStagger(
            step: const Duration(milliseconds: 28),
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CitroCard(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CitroSectionHeader(
                          '游戏',
                          subtitle: '账号同步 · 全站排行',
                        ),
                        const SizedBox(height: AppSpacing.x3),
                        for (final group in gameGroups) ...[
                          Text(
                            group.$1,
                            style: context.body(
                              size: CitroType.label,
                              weight: CitroType.medium,
                              color: c.ink2,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.x1),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: gameColumns,
                              crossAxisSpacing: AppSpacing.x1,
                              mainAxisSpacing: AppSpacing.x1,
                              childAspectRatio: 1.06,
                            ),
                            itemCount: group.$2.length,
                            itemBuilder: (_, i) => _GameCard(entry: group.$2[i]),
                          ),
                          const SizedBox(height: AppSpacing.x3),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (showGameTools) ...[
                const SizedBox(height: 12),
                _GameToolSection(links: gameTools, download: downloadSite),
              ],
              if (!platform.isWindows && !kIsWeb) ...[
                const SizedBox(height: 12),
                CitroCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () => _openRes(context),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.tintBlue,
                          borderRadius: BorderRadius.circular(CitroColors.radii.small),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.monitor, width: 2),
                            size: 20,
                            color: c.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '更多 Mod / 工具 / 外设驱动',
                              style: context
                                  .heading(size: 15, color: c.ink, height: 1.35)
                                  .copyWith(letterSpacing: .1),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '打开资源库',
                              style: context.body(
                                size: 12,
                                color: c.accentInk,
                                letterSpacing: .48,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AppIcon(
                        strokeSvg(AppIcons.arrowUpRight, width: 2.2),
                        size: 15,
                        color: c.accentInk,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () => _openRes(context),
                    child: Text(
                      '资源库 · Mod / 工具 / 外设驱动',
                      style: context.body(size: 11, color: c.inkSoft),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!desktopWeb) return content;
    return Stack(
      children: [
        Positioned.fill(child: content),
        Positioned(
          left: 18,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
          child: const WebHomeBackPill(),
        ),
      ],
    );
  }

  void _openRes(BuildContext context) {
    Navigator.of(context).pushNamed('/res');
  }
}

class _GameToolLink {
  final String title;
  final String desc;
  final String icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _GameToolLink({
    required this.title,
    required this.desc,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });
}

class _GameToolSection extends StatelessWidget {
  final List<_GameToolLink> links;
  final _GameToolLink? download;

  const _GameToolSection({required this.links, this.download});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '小工具',
                style: context.heading(size: CitroType.titleLg, color: c.ink),
              ),
              const Spacer(),
              Text(
                kIsWeb ? '在线工具 · 下载' : '在线工具',
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: links.length <= 3 ? 3 : 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        mainAxisExtent: 72,
                      ),
                      itemCount: links.length,
                      itemBuilder: (_, i) =>
                          _GameToolCompactCard(link: links[i]),
                    ),
                    if (download != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 60,
                        child: _GameToolCard(link: download!),
                      ),
                    ],
                  ],
                );
              }
              final all = [...links, ?download];
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: all.length,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 60,
                ),
                itemCount: all.length,
                itemBuilder: (_, i) => _GameToolCard(link: all[i]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GameToolCompactCard extends StatelessWidget {
  final _GameToolLink link;

  const _GameToolCompactCard({required this.link});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: link.onTap,
      borderRadius: BorderRadius.circular(12),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.accent.withAlpha(c.dark ? 44 : 46),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: link.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(link.icon, width: 2),
                  size: 15,
                  color: link.foreground,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              link.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.body(
                size: 12,
                weight: FontWeight.w700,
                color: c.ink,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameToolCard extends StatelessWidget {
  final _GameToolLink link;

  const _GameToolCard({required this.link});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: link.onTap,
      borderRadius: BorderRadius.circular(12),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.accent.withAlpha(c.dark ? 44 : 46),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: link.background,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(link.icon, width: 2),
                  size: 16,
                  color: link.foreground,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 13,
                      weight: FontWeight.w700,
                      color: c.ink,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    link.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 10,
                      color: c.inkSoft,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            AppIcon(
              strokeSvg(AppIcons.arrowUpRight, width: 2.2),
              size: 11,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameCardData entry;
  const _GameCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final layout = CitroLayoutScope.maybeOf(context);
    final tablet = layout?.tabletNav ?? false;
    final compact =
        (layout?.duo ?? false) && CitroLayoutScope.widthOf(context) < 520;
    final desktopWeb = kIsWeb && CitroLayoutScope.widthOf(context) >= 1025;
    final large = (tablet || desktopWeb) && !compact;
    return Pressable(
      onTap: () {
        // 和听隅一致：纸页从第一帧轻沉淡入，卡片快照抬起，退出时反向收回。
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) {
          Navigator.of(context).pushNamed('/${entry.key}');
          return;
        }
        final rect = box.localToGlobal(Offset.zero) & box.size;
        CitroCardMorph.pushPageSoft(
          context,
          source: rect,
          snapshot: CitroCardFlight.snapshotOf(context, rect),
          settings: RouteSettings(name: '/${entry.key}'),
          builder: (_) => buildGamePage(entry.key),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.card(c),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(1),
                padding: EdgeInsets.all(compact ? 6 : 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: entry.gradient(c),
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(9),
                    bottomRight: Radius.circular(9),
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
            Container(
              height: large ? 48 : (compact ? 36 : 39),
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: large ? 12 : 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              alignment: Alignment.centerLeft,
              child: CitroHero(
                tag: CitroHero.tagOf('game-title', entry.key),
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.heading(
                    size: large ? 19 : 15.5,
                    color: c.ink,
                    letterSpacing: .27,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
