import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../games/game_loader.dart';
import '../games/game_identity.dart';
import '../games/game_registry.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/card_flight.dart';
import '../widgets/card_morph.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/paper.dart';
import '../widgets/shared_element.dart';
import '../widgets/tablet_shell.dart';
import 'web_scrapbook.dart';

class GamesPage extends StatelessWidget {
  const GamesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = CitroLayoutScope.maybeOf(context);
    final width = layout?.contentWidth ?? MediaQuery.sizeOf(context).width;
    final tabletNav = layout?.tabletNav ?? false;
    // 宽屏网页与桌面端一致：更宽的画布、同样大的游戏卡，不再附赠资源库入口。
    // 已经进了桌面壳（tabletNav，Web 横屏 / Windows / 平板横屏）时不再挂网页返回胶囊。
    final desktopWeb = kIsWeb && !tabletNav && width >= 1025;
    final wideDesktop = tabletNav || desktopWeb;
    final maxWidth = wideDesktop ? 1120.0 : 840.0;
    final side = AppSpacing.pageSide(width, maxWidth);
    final duo = layout?.duo == true;
    final gameColumns = duo
        ? (width >= 900 ? 6 : (width >= 640 ? 5 : (width >= 460 ? 4 : 3)))
        : (width >= 1180 ? 7 : (width >= 920 ? 6 : (width >= 680 ? 5 : 3)));
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
          [
            for (final key in group.$2)
              kGameCards.firstWhere((g) => g.key == key),
          ],
        ),
    ];
    // 最外层必须是 Material：没有它，Flutter 的 Text 会退回「未包 Material」
    // 的兜底样式（黄色下划线 + 警告 debugLabel），整页文字都会带着一条黄线。
    // 透明 Material：只为文字提供默认样式，不铺底色——背景由壳层的沉浸背景
    // 统一提供（之前这里是不透明的页面底色，把背景整块盖住了）。
    final content = Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          CitroBackground(
            color: Colors.transparent,
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  side,
                  AppSpacing.pageTopRoomy(width),
                  side,
                  AppSpacing.pageBottom(floatingNav: !wideDesktop),
                ),
                child: CitroStagger(
                  step: const Duration(milliseconds: 28),
                  children: [
                    // 标题与卡片左缘对齐（页边距已经够宽，不再额外内缩）。
                    const CitroPageTitle('游戏', ''),
                    const SizedBox(height: AppSpacing.block),
                    for (final group in gameGroups) ...[
                      _GroupHeader(
                        title: group.$1,
                        count: group.$2.length,
                        games: group.$2,
                      ),
                      const SizedBox(height: 14),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gameColumns,
                          crossAxisSpacing: AppSpacing.grid,
                          mainAxisSpacing: AppSpacing.grid + 2,
                          childAspectRatio: .8,
                        ),
                        itemCount: group.$2.length,
                        itemBuilder: (_, i) => _GameCard(entry: group.$2[i]),
                      ),
                      // 分组之间多留一档，像杂志的章节。
                      const SizedBox(height: AppSpacing.x4 + 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
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
}

/// 分组标题：分类名 + 这一组的游戏色点 + 数量。
class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;
  final List<GameCardData> games;

  const _GroupHeader({
    required this.title,
    required this.count,
    required this.games,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // 左缘与标题、卡片对齐；只留一点右内边距给色点。
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        children: [
          Text(
            title,
            style: context.heading(size: CitroType.title, color: c.ink),
          ),
          const SizedBox(width: AppSpacing.x1),
          // 这一组游戏里出现次数最多的身份色，作为分组的小标记。
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              border: Border.all(color: c.line),
            ),
            child: Text(
              '$count 款',
              style: context.body(
                size: CitroType.micro,
                weight: CitroType.medium,
                color: c.inkSoft,
              ),
            ),
          ),
          const Spacer(),
          for (final g in games.take(5))
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: g.identity.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
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
    final desktopWeb =
        kIsWeb && !tablet && CitroLayoutScope.widthOf(context) >= 1025;
    final large = (tablet || desktopWeb) && !compact;
    final identity = entry.identity;
    const shape = BorderRadius.all(Radius.circular(18));
    return Pressable(
      onTap: () {
        // 和听隅一致：纸页从第一帧轻沉淡入，卡片快照抬起，退出时反向收回。
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
      borderRadius: shape,
      hoverShadow: false,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: shape,
          boxShadow: CitroColors.shadows.card(c),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(1),
                padding: EdgeInsets.all(compact ? 6 : 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: entry.gradient,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: entry.art(context),
                        ),
                      ),
                    ),
                    // 分类小标签：贴在封面右上角，颜色跟身份色走。
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: GameIdentity.paper.withValues(alpha: .94),
                          borderRadius: BorderRadius.circular(
                            CitroColors.radii.chip,
                          ),
                          border: Border.all(
                            color: identity.primary.withValues(alpha: .5),
                          ),
                        ),
                        child: Text(
                          identity.tag,
                          style: TextStyle(
                            fontFamily: AppFonts.rounded,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .4,
                            color: identity.deep,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              height: large ? 50 : (compact ? 38 : 42),
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: large ? 12 : 10),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(
                  top: BorderSide(color: identity.primary.withAlpha(40)),
                ),
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
