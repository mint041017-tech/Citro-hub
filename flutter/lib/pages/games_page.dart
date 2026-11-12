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
          [for (final key in group.$2) kGameCards.firstWhere((g) => g.key == key)],
        ),
    ];
    // 最外层必须是 Material：没有它，Flutter 的 Text 会退回「未包 Material」
    // 的兜底样式（黄色下划线 + 警告 debugLabel），整页文字都会带着一条黄线。
    final content = Material(
      color: c.bg,
      child: Stack(
        children: [
          // 背景图只在首页展示；其余页面用纯色底，避免抢内容。
          Positioned.fill(child: ColoredBox(color: context.c.bg)),
          CitroBackground(
            color: Colors.transparent,
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
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.x1),
                      child: CitroPageTitle('游戏', '挑一个，玩一会儿'),
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    for (final group in gameGroups) ...[
                      _GroupHeader(
                        title: group.$1,
                        count: group.$2.length,
                        games: group.$2,
                      ),
                      const SizedBox(height: AppSpacing.x2),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gameColumns,
                          crossAxisSpacing: AppSpacing.x2,
                          mainAxisSpacing: AppSpacing.x2,
                          childAspectRatio: .8,
                        ),
                        itemCount: group.$2.length,
                        itemBuilder: (_, i) => _GameCard(entry: group.$2[i]),
                      ),
                      const SizedBox(height: AppSpacing.x4),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
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
    final desktopWeb = kIsWeb && CitroLayoutScope.widthOf(context) >= 1025;
    final large = (tablet || desktopWeb) && !compact;
    final identity = entry.identity;
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
      // 卡片底用实心表面（玻璃已全线取消，仅 Tab 栏保留）。
      child: CitroCard(
        radius: 18,
        padding: EdgeInsets.zero,
        clip: Clip.antiAlias,
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
                    bottomLeft: Radius.circular(11),
                    bottomRight: Radius.circular(11),
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
                border: Border(top: BorderSide(color: identity.primary.withAlpha(40))),
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
