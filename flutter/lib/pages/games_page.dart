import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../games/game_registry.dart';
import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
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
        ? (width >= 820 ? 5 : (width >= 520 ? 4 : 3))
        : (width >= 1040 ? 5 : (width >= 760 ? 4 : 3));
    final games = kGameCards;
    final gameTools = <_GameToolLink>[
      _GameToolLink(
        title: '玩法抽签',
        desc: '无畏契约整活玩法',
        icon: AppIcons.sparkle,
        background: c.hl,
        foreground: c.accentInk,
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
        background: c.noteB,
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
      _GameToolLink(
        title: 'MsLab',
        desc: '毫秒灵敏度调试',
        icon:
            '<circle cx="12" cy="12" r="8"/><path d="M12 8v4l2.5 1.5"/><path d="M12 1v3M12 20v3M1 12h3M20 12h3"/>',
        background: c.noteG,
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
            background: c.noteG,
            foreground: c.mintInk,
            onTap: () => openCitroPage(
              context,
              'https://dl.chimu-claw.xyz/',
              title: 'Citro 下载站',
            ),
          )
        : null;
    final showGameTools = kIsWeb || platform.isAndroid || platform.isIOS;
    final content = PaperBackground(
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(side, 8, side, wideDesktop ? 32 : 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  PaperCard(
                    color: c.surface2,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -18,
                          bottom: -34,
                          child: IgnorePointer(
                            child: Transform.rotate(
                              angle: -9 * math.pi / 180,
                              child: Opacity(
                                opacity: .08,
                                child: Image.asset(
                                  'assets/images/logo.webp',
                                  width: 170,
                                  cacheWidth: 340,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: HighlightedText(
                                '游戏',
                                style: context.heading(
                                  size: 33.4,
                                  color: c.ink,
                                  letterSpacing: 4,
                                ),
                                highlight: c.hl,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Center(
                              child: Text(
                                '账号同步 · 全站排行',
                                style: context.body(
                                  size: 13,
                                  weight: FontWeight.w500,
                                  color: c.inkSoft,
                                  letterSpacing: .78,
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Center(
                              child: Transform.rotate(
                                angle: -1 * math.pi / 180,
                                child: Container(
                                  width: 56,
                                  height: 6,
                                  color: c.hl,
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: gameColumns,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 107.66 / 112,
                                  ),
                              itemCount: games.length,
                              itemBuilder: (_, i) => _GameCard(entry: games[i]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: -9,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Transform.rotate(
                        angle: -2.5 * math.pi / 180,
                        child: ClipPath(
                          clipper: _TapeClip(),
                          child: Container(
                            width: 110,
                            height: 26,
                            color: c.tape2,
                          ),
                        ),
                      ),
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
                PaperCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () => _openRes(context),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c.hl,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.monitor, width: 2),
                            size: 19,
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
    return PaperCard(
      rotate: .35,
      tapeColor: c.tape2,
      tapeAngle: 2.2,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SectionTitle('小工具', size: 21),
              const Spacer(),
              Text(
                kIsWeb ? '在线工具 · 下载' : '在线工具',
                style: context.body(size: 10.5, color: c.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 9),
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
      hoverColor: c.hl.withAlpha(c.dark ? 20 : 48),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
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
                size: 11.5,
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
      hoverColor: c.hl.withAlpha(c.dark ? 20 : 48),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
            const SizedBox(width: 9),
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
                      size: 12.5,
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
                      size: 9.5,
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

class _TapeClip extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .02, size.height * .06)
    ..lineTo(size.width, 0)
    ..lineTo(size.width * .97, size.height * .94)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
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
      onTap: () => Navigator.of(context).pushNamed('/${entry.key}'),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
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
              padding: EdgeInsets.symmetric(horizontal: large ? 12 : 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              alignment: Alignment.centerLeft,
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
          ],
        ),
      ),
    );
  }
}
