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
import 'in_app_web.dart';
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
        const SizedBox(height: 9),
        const WebGameToolsRow(),
      ],
    );
  }
}

/// 桌面首页游戏面板底部的小工具卡：与 Web 手机端游戏页同款，
/// 工具卡加大、下载站单独一条高亮卡，游戏网格自动让出空间。
class WebGameToolsRow extends StatelessWidget {
  const WebGameToolsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tools = <_WebGameTool>[
      _WebGameTool(
        title: '玩法抽签',
        desc: '无畏契约整活',
        icon: AppIcons.sparkle,
        background: c.hl,
        foreground: c.accentInk,
        onTap: () => Navigator.of(context).pushNamed('/play'),
      ),
      _WebGameTool(
        title: '瞬投',
        desc: '投掷物点位',
        icon: AppIcons.location,
        background: c.mintSoft,
        foreground: c.mintInk,
        onTap: () =>
            openCitroPage(context, 'https://shuntou.top/', title: '瞬投'),
      ),
      _WebGameTool(
        title: '屏幕分享',
        desc: '网页共享演示',
        icon: AppIcons.monitor,
        background: c.noteB,
        foreground: c.accentInk,
        onTap: () =>
            openCitroPage(context, 'https://demo.piik.tv/', title: '屏幕分享'),
      ),
      _WebGameTool(
        title: '视野live',
        desc: '实时视野直播',
        icon: AppIcons.eye,
        background: c.mintSoft,
        foreground: c.mintInk,
        onTap: () => openCitroPage(
          context,
          'https://shijiao.xingpaste.com/',
          title: '视野live',
        ),
      ),
      _WebGameTool(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 80,
          child: Row(
            children: [
              for (var i = 0; i < tools.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _WebGameToolCard(tool: tools[i])),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        _WebDownloadCard(
          onTap: () => openCitroPage(
            context,
            'https://dl.chimu-claw.xyz/',
            title: 'Citro 下载站',
          ),
        ),
      ],
    );
  }
}

class _WebGameTool {
  final String title;
  final String desc;
  final String icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _WebGameTool({
    required this.title,
    required this.desc,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });
}

class _WebGameToolCard extends StatelessWidget {
  final _WebGameTool tool;

  const _WebGameToolCard({required this.tool});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: tool.onTap,
      borderRadius: BorderRadius.circular(12),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.hl.withAlpha(c.dark ? 20 : 48),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tool.background,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(tool.icon, width: 2),
                  size: 17,
                  color: tool.foreground,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              tool.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.body(
                size: 12.5,
                weight: FontWeight.w700,
                color: c.ink,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              tool.desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.body(
                size: 9.5,
                color: c.inkSoft,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 下载站单独一条，薄荷底 + 「官方」标注 + 直达按钮，明显区别于普通工具卡。
class _WebDownloadCard extends StatelessWidget {
  final VoidCallback onTap;

  const _WebDownloadCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.mintLine.withAlpha(c.dark ? 30 : 80),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: c.dark
                ? const [Color(0x2AC9D3B2), Color(0x0DC9D3B2)]
                : const [Color(0xFFE4EFDC), Color(0xFFFBF7EC)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.mintLine, width: 1.2),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.mint,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.download, width: 2),
                  size: 16,
                  color: Color(0xFF2E2C22),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '下载站',
                        style: context.body(
                          size: 13,
                          weight: FontWeight.w800,
                          color: c.mintInk,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '官方',
                          style: context.body(
                            size: 8.5,
                            weight: FontWeight.w800,
                            color: const Color(0xFF2E2C22),
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'App、Mod 与工具下载 · 官方直链',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 9.5,
                      color: c.mintInk.withAlpha(190),
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: c.mintLine),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '直达',
                    style: context.body(
                      size: 10,
                      weight: FontWeight.w700,
                      color: c.mintInk,
                    ),
                  ),
                  const SizedBox(width: 2),
                  AppIcon(
                    strokeSvg(AppIcons.arrowUpRight, width: 2),
                    size: 10,
                    color: c.mintInk,
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
