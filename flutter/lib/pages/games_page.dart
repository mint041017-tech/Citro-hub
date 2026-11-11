import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../games/game_loader.dart';
import '../games/game_registry.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/card_flight.dart';
import '../widgets/card_morph.dart';
import '../widgets/home_background.dart';
import '../widgets/liquid_glass.dart';
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
    final content = Stack(
      children: [
        const Positioned.fill(
          child: CitroAmbientBackground(blurred: true, blurSigma: 18),
        ),
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
                  const SizedBox(height: AppSpacing.x2),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CitroCard(
                        glass: true,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                                itemBuilder: (_, i) =>
                                    _GameCard(entry: group.$2[i]),
                              ),
                              const SizedBox(height: AppSpacing.x3),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
      // 卡片底改成液态玻璃：透出底下模糊的背景，和全站玻璃语言一致。
      child: CitroLiquidGlass(
        radius: 14,
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
