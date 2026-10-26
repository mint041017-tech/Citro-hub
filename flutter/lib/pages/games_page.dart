import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../games/game_registry.dart';
import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import '../widgets/tablet_shell.dart';
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
