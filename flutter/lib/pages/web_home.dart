import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/quotes.dart';
import '../data/resources.dart';
import '../games/game_registry.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/global_search.dart';
import '../widgets/paper.dart';
import 'home_page.dart';
import 'web_resource_actions.dart';
import 'web_scrapbook.dart';

class WebHomePage extends StatelessWidget {
  final ValueChanged<int> onSwitchTab;

  const WebHomePage({super.key, required this.onSwitchTab});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final header = WebDesktopHeader(
      resources: false,
      onHome: () {},
      // RootShell's fourth destination is the resource page.
      onResources: () => onSwitchTab(3),
    );
    return WebDesktopPaper(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = math.max(900.0, constraints.maxHeight);
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              height: height,
              child: WebDesktopGrid(
                rows: 9,
                children: [
                  ...header.cells(context),
                  const WebGridCell(
                    1,
                    2,
                    3,
                    1,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GlobalSearch(),
                    ),
                  ),
                  const WebGridCell(1, 3, 3, 2, WeatherCard()),
                  const WebGridCell(1, 5, 3, 4, CalendarCard()),
                  const WebGridCell(4, 3, 3, 1, FishCard()),
                  const WebGridCell(4, 4, 3, 3, ZodiacCard()),
                  WebGridCell(
                    4,
                    7,
                    3,
                    1,
                    WebTicket(
                      title: 'Citro ',
                      accent: '社区',
                      trailing: context.app.unread > 0
                          ? '${context.app.unread} 条新消息'
                          : '0 条动态',
                      rotate: -1.2,
                      backgroundColor: c.noteB,
                      trailingWidget: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${context.app.unread}',
                            style: context.display(
                              size: 27,
                              weight: FontWeight.w700,
                              color: c.accentInk,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            context.app.unread > 0 ? '条新消息' : '条动态',
                            style: context.body(size: 9.5, color: c.inkSoft),
                          ),
                        ],
                      ),
                      cornerAction: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.surface2.withAlpha(210),
                          border: Border.all(color: c.accentInk.withAlpha(60)),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.bell, width: 1.8),
                            size: 13,
                            color: c.accentInk,
                          ),
                        ),
                      ),
                      onTap: () => onSwitchTab(2),
                    ),
                  ),
                  WebGridCell(
                    4,
                    8,
                    3,
                    1,
                    WebTicket(
                      title: '食谱 ',
                      accent: '日记',
                      trailing: '',
                      rotate: 1.1,
                      backgroundColor: c.noteY,
                      trailingWidget: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.surface2.withAlpha(170),
                          border: Border.all(color: c.line2),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.arrowRight, width: 2),
                            size: 15,
                            color: c.accentInk,
                          ),
                        ),
                      ),
                      onTap: () => Navigator.of(context).pushNamed('/cook'),
                    ),
                  ),
                  const WebGridCell(7, 2, 6, 7, _WebModsAndGames()),
                  const WebGridCell(
                    1,
                    9,
                    2,
                    1,
                    Align(alignment: Alignment.centerLeft, child: AccountCap()),
                  ),
                  const WebGridCell(3, 9, 10, 1, _WebQuoteStrip()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WebModsAndGames extends StatelessWidget {
  const _WebModsAndGames();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 9),
                  child: WebSectionTitle('游戏 Mod', size: 18),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: (constraints.maxHeight - 20) / 3,
                      ),
                      itemCount: kMods.length,
                      itemBuilder: (context, index) =>
                          _WebModCard(mod: kMods[index], odd: index.isOdd),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(horizontal: 17),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.line2.withAlpha(170))),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [WebSectionTitle('小游戏', size: 18), Spacer()],
                ),
              ),
              Text(
                '账号同步 · 全站排行',
                style: context.body(size: 10.5, color: c.inkSoft),
              ),
              const SizedBox(height: 7),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 9,
                      mainAxisSpacing: 9,
                      mainAxisExtent: (constraints.maxHeight - 45) / 6,
                    ),
                    itemCount: kGameCards.length,
                    itemBuilder: (context, index) => _WebGameCard(
                      entry: kGameCards[index],
                      angle: const [-1.2, 0.8, -0.4][index % 3],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WebModCard extends StatelessWidget {
  final ModItem mod;
  final bool odd;

  const _WebModCard({required this.mod, required this.odd});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Transform.rotate(
      angle: (odd ? .7 : -.7) * math.pi / 180,
      child: Pressable(
        onTap: () => openCitroResource(context, '《${mod.name}》Mod', mod.url),
        borderRadius: BorderRadius.circular(14),
        hoverOverlayColor: c.hl.withAlpha(24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
          decoration: BoxDecoration(
            color: c.dark ? const Color(0xFF262320) : const Color(0xFFFFFDF8),
            borderRadius: BorderRadius.circular(14),
            boxShadow: CitroColors.shadows.paper(c),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        mod.image,
                        fit: BoxFit.cover,
                        cacheWidth: 480,
                        errorBuilder: (_, _, _) => Container(color: c.noteG),
                      ),
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface2.withAlpha(235),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            mod.tag,
                            style: context.body(size: 9, color: c.accentInk),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                mod.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.heading(size: 16, color: c.ink),
              ),
              Text(
                mod.desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: 9.5, color: c.inkSoft, height: 1.35),
              ),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: c.hl.withAlpha(120),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.accentInk.withAlpha(75)),
                    boxShadow: [
                      BoxShadow(
                        color: c.accent.withAlpha(18),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        strokeSvg(AppIcons.download, width: 2),
                        size: 10,
                        color: c.accentInk,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '网盘下载',
                        style: context.body(
                          size: 10,
                          weight: FontWeight.w700,
                          color: c.accentInk,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '↗',
                        style: context.body(
                          size: 10,
                          weight: FontWeight.w700,
                          color: c.accentInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebGameCard extends StatelessWidget {
  final GameCardData entry;
  final double angle;

  const _WebGameCard({required this.entry, this.angle = 0});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => Navigator.of(context).pushNamed('/${entry.key}'),
      borderRadius: BorderRadius.circular(14),
      hoverOverlayColor: c.hl.withAlpha(24),
      child: Transform.rotate(
        angle: angle * math.pi / 180,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
          decoration: BoxDecoration(
            color: c.dark ? const Color(0xFF262320) : const Color(0xFFFFFDF8),
            borderRadius: BorderRadius.circular(14),
            boxShadow: CitroColors.shadows.paper(c),
          ),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: entry.gradient(c),
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: entry.art(context),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 28,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.heading(size: 16, color: c.ink),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebQuoteStrip extends StatelessWidget {
  const _WebQuoteStrip();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final quote = kQuotes[dayOfYear % kQuotes.length];
    return Transform.rotate(
      angle: .35 * math.pi / 180,
      child: PaperCard(
        color: c.dark ? const Color(0xFF201E19) : const Color(0xFFFBF3E1),
        borderColor: c.accent.withAlpha(70),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        tapeColor: c.tape3,
        tapeWidth: 42,
        tapeHeight: 14,
        tapeTop: -8,
        onTap: () => copyText(
          '${quote.cn} — ${quote.en}',
          context: context,
          tip: '已复制每日一言',
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/images/logo.webp',
              width: 34,
              height: 34,
              cacheWidth: 102,
            ),
            const SizedBox(width: 8),
            Text('Citro', style: context.display(size: 17, color: c.inkSoft)),
            const SizedBox(width: 18),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    flex: 5,
                    child: Text(
                      quote.cn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.heading(size: 19, color: c.ink),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    flex: 6,
                    child: Text(
                      quote.en,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.hand(
                        size: 18,
                        color: c.inkSoft,
                        style: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
