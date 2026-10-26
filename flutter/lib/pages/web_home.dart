import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/quotes.dart';
import '../games/game_registry.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/global_search.dart';
import '../widgets/paper.dart';
import 'home_page.dart';
import 'web_scrapbook.dart';

void _noop() {}

class WebHomePage extends StatelessWidget {
  final ValueChanged<int> onSwitchTab;

  const WebHomePage({super.key, required this.onSwitchTab});

  @override
  Widget build(BuildContext context) {
    const header = WebDesktopHeader(onHome: _noop);
    return WebDesktopPaper(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = math.max(900.0, constraints.maxHeight);
          final rowHeight = (height - 64 - 12 * 9) / 8;
          // 搜索框高 44，星象卡顶部与它对齐（再让出 9px 纸胶带）。
          final zodiacTop = (rowHeight - 44) / 2 + 9;
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
                      child: GlobalSearch(hint: '搜索功能 / 游戏 / 页面，回车必应'),
                    ),
                  ),
                  const WebGridCell(1, 3, 3, 2, WeatherCard()),
                  const WebGridCell(1, 5, 3, 4, CalendarCard()),
                  WebGridCell(
                    4,
                    2,
                    3,
                    4,
                    Padding(
                      padding: EdgeInsets.only(top: zodiacTop),
                      child: const ZodiacCard(),
                    ),
                  ),
                  WebGridCell(
                    4,
                    6,
                    3,
                    1,
                    _WebCommunityTicket(
                      unread: context.app.unread,
                      onTap: () => onSwitchTab(2),
                    ),
                  ),
                  WebGridCell(
                    4,
                    7,
                    3,
                    1,
                    _WebRecipeTicket(
                      onTap: () => Navigator.of(context).pushNamed('/cook'),
                    ),
                  ),
                  const WebGridCell(4, 8, 3, 1, FishCard()),
                  const WebGridCell(7, 2, 6, 7, _WebGames()),
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

class _WebGames extends StatelessWidget {
  const _WebGames();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const WebSectionTitle('小游戏', size: 22),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '共 ${kGameCards.length} 款',
                  style: context.hand(size: 13, color: c.inkSoft),
                ),
              ),
              const Spacer(),
              Text(
                '账号同步 · 全站排行',
                style: context.body(size: 10.5, color: c.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: (constraints.maxHeight - 30) / 4,
              ),
              itemCount: kGameCards.length,
              itemBuilder: (context, index) => _WebGameCard(
                entry: kGameCards[index],
                angle: const [-1.2, 0.8, -0.4, 0.5][index % 4],
              ),
            ),
          ),
        ),
      ],
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

class _WebCommunityTicket extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;

  const _WebCommunityTicket({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Transform.rotate(
      angle: -.5 * math.pi / 180,
      child: PaperCard(
        color: c.noteB,
        borderColor: c.line,
        fold: true,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(2),
          topRight: Radius.circular(2),
          bottomLeft: Radius.circular(2),
          bottomRight: Radius.circular(14),
        ),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        tapeColor: c.dark ? const Color(0x44FFCE8E) : const Color(0x99F7BC78),
        tapeWidth: 54,
        tapeHeight: 15,
        tapeTop: -8,
        onTap: onTap,
        child: Row(
          children: [
            _EntryIcon(icon: AppIcons.users),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EntryTitle(first: 'Citro ', second: '社区'),
                  Text(
                    '在清爽的汽水里，与同频的灵魂相遇',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 10.5,
                      color: c.ink2,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _EntryArrow(badge: unread),
          ],
        ),
      ),
    );
  }
}

class _WebRecipeTicket extends StatelessWidget {
  final VoidCallback onTap;

  const _WebRecipeTicket({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Transform.rotate(
      angle: .5 * math.pi / 180,
      child: PaperCard(
        color: c.noteY,
        borderColor: c.line,
        fold: true,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(2),
          topRight: Radius.circular(2),
          bottomLeft: Radius.circular(2),
          bottomRight: Radius.circular(14),
        ),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        tapeColor: c.dark ? const Color(0x44FFCE8E) : const Color(0x99F7BC78),
        tapeWidth: 54,
        tapeHeight: 15,
        tapeTop: -8,
        onTap: onTap,
        child: Row(
          children: [
            _EntryIcon(icon: AppIcons.book),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EntryTitle(first: '食谱 ', second: '日记'),
                  Text(
                    '记录每一道拿手菜，把喜欢的味道收好。',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 10.5,
                      color: c.ink2,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const _EntryArrow(),
          ],
        ),
      ),
    );
  }
}

class _EntryIcon extends StatelessWidget {
  final String icon;

  const _EntryIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: c.surface2.withAlpha(205),
        shape: BoxShape.circle,
        border: Border.all(color: c.line),
      ),
      child: Center(
        child: AppIcon(
          strokeSvg(icon, width: 1.9),
          size: 17,
          color: c.accentInk,
        ),
      ),
    );
  }
}

class _EntryTitle extends StatelessWidget {
  final String first;
  final String second;

  const _EntryTitle({required this.first, required this.second});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: context.display(size: 24, color: c.ink),
        children: [
          TextSpan(text: first),
          TextSpan(
            text: second,
            style: context
                .heading(size: 22, color: c.ink)
                .copyWith(backgroundColor: c.hl, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class _EntryArrow extends StatelessWidget {
  final int badge;

  const _EntryArrow({this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: c.surface2.withAlpha(200),
                shape: BoxShape.circle,
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
          ),
          if (badge > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 15),
                height: 15,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: c.stamp,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Center(
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    style: context.body(
                      size: 8.5,
                      weight: FontWeight.w800,
                      color: c.surface2,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo.webp',
                    width: 34,
                    height: 34,
                    cacheWidth: 102,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Citro',
                    style: context.display(size: 17, color: c.inkSoft),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 120),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxText = math.max(
                    120.0,
                    (constraints.maxWidth - 40) * .48,
                  );
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxText),
                        child: Text(
                          quote.cn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: context.heading(size: 19, color: c.ink),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: c.line2,
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxText),
                        child: Text(
                          quote.en,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: context.hand(
                            size: 18,
                            color: c.inkSoft,
                            style: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
