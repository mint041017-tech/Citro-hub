import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/quotes.dart';
import '../games/game_registry.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/home_entries.dart';
import '../widgets/motion_widgets.dart';
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
          final rowHeight = (height - 64 - 16 * 9) / 8;
          // 搜索框高 44，星象卡顶部与它对齐。
          final zodiacTop = (rowHeight - 44) / 2;
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: CitroReveal(
              rise: 6,
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
                    // 日历 / 待办 / 记账已经收进「计划」页，桌面首页不再重复。
                    const WebGridCell(1, 5, 3, 2, FishCard()),
                    const WebGridCell(1, 7, 3, 2, CheckinCard(compact: true)),
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
                      2,
                      _WebRecipeTicket(
                        onTap: () => Navigator.of(context).pushNamed('/cook'),
                      ),
                    ),
                    const WebGridCell(7, 2, 6, 7, _WebGames()),
                    const WebGridCell(1, 9, 12, 1, _WebQuoteStrip()),
                  ],
                ),
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
              const SizedBox(width: AppSpacing.x1),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '共 ${kGameCards.length} 款',
                  style: context.body(size: CitroType.small, color: c.inkSoft),
                ),
              ),
              const Spacer(),
              Text(
                '账号同步 · 全站排行',
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
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
              itemBuilder: (context, index) =>
                  _WebGameCard(entry: kGameCards[index]),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
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
        title: '听隅',
        desc: '白噪音混音',
        icon: AppIcons.wave,
        background: c.tintGreen,
        foreground: c.mintInk,
        onTap: () => Navigator.of(context).pushNamed('/tingyu'),
      ),
      _WebGameTool(
        title: '玩法抽签',
        desc: '无畏契约整活',
        icon: AppIcons.sparkle,
        background: c.tintYellow,
        foreground: c.accentInk,
        onTap: () => Navigator.of(context).pushNamed('/play'),
      ),
      _WebGameTool(
        title: '瞬投',
        desc: '投掷物点位',
        icon: AppIcons.location,
        background: c.tintGreen,
        foreground: c.mintInk,
        onTap: () =>
            openCitroPage(context, 'https://shuntou.top/', title: '瞬投'),
      ),
      _WebGameTool(
        title: '屏幕分享',
        desc: '网页共享演示',
        icon: AppIcons.monitor,
        background: c.tintBlue,
        foreground: c.accentInk,
        onTap: () =>
            openCitroPage(context, 'https://demo.piik.tv/', title: '屏幕分享'),
      ),
      _WebGameTool(
        title: '视野live',
        desc: '实时视野直播',
        icon: AppIcons.eye,
        background: c.tintGreen,
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
        icon: '<circle cx="12" cy="12" r="8"/><path d="M12 8v4l2.5 1.5"/><path d="M12 1v3M12 20v3M1 12h3M20 12h3"/>',
        background: c.tintBlue,
        foreground: c.accentInk,
        onTap: () =>
            openCitroPage(context, 'https://mslab.gg/', title: 'MsLab'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 84,
          child: Row(
            children: [
              for (var i = 0; i < tools.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.x1),
                Expanded(child: _WebGameToolCard(tool: tools[i])),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
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
      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.surface2,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tool.background,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(tool.icon, width: 2),
                  size: 18,
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
                size: CitroType.meta,
                weight: CitroType.medium,
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
                size: CitroType.micro,
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
      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.mintSoft,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.mintSoft,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          border: Border.all(color: c.mintLine),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.download, width: 2),
                  size: 16,
                  color: c.onAccent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
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
                          size: CitroType.meta,
                          weight: CitroType.medium,
                          color: c.mintInk,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(
                            CitroColors.radii.chip,
                          ),
                        ),
                        child: Text(
                          '官方',
                          style: context.body(
                            size: CitroType.micro,
                            weight: CitroType.medium,
                            color: c.onAccent,
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
                      size: CitroType.micro,
                      color: c.mintInk,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '直达',
                    style: context.body(
                      size: CitroType.micro,
                      weight: CitroType.medium,
                      color: c.mintInk,
                    ),
                  ),
                  const SizedBox(width: 2),
                  AppIcon(
                    strokeSvg(AppIcons.arrowUpRight, width: 2),
                    size: 11,
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
  const _WebGameCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => Navigator.of(context).pushNamed('/${entry.key}'),
      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      hoverOverlayColor: c.surface2,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
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
                  borderRadius: BorderRadius.circular(CitroColors.radii.small),
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
                  style: context.heading(size: CitroType.bodyLg),
                ),
              ),
            ),
          ],
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
    return _EntryTile(
      tint: c.tintBlue,
      icon: AppIcons.users,
      title: 'Citro 社区',
      desc: '在清爽的汽水里，与同频的灵魂相遇',
      badge: unread,
      onTap: onTap,
    );
  }
}

class _WebRecipeTicket extends StatelessWidget {
  final VoidCallback onTap;

  const _WebRecipeTicket({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _EntryTile(
      tint: context.c.tintYellow,
      icon: AppIcons.book,
      title: '食谱日记',
      desc: '记录每一道拿手菜，把喜欢的味道收好。',
      onTap: onTap,
    );
  }
}

/// 首页入口卡：粉彩底 + 白色圆角 + 图标与标题。
class _EntryTile extends StatelessWidget {
  final Color tint;
  final String icon;
  final String title;
  final String desc;
  final int badge;
  final VoidCallback onTap;

  const _EntryTile({
    required this.tint,
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CitroColors.radii.card),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.surface.withAlpha(120),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(CitroColors.radii.card),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(icon, width: 1.9),
                  size: 18,
                  color: c.accentInk,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.heading(size: CitroType.bodyLg),
                  ),
                  Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: CitroType.small,
                      color: c.ink2,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            _EntryArrow(badge: badge),
          ],
        ),
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
                color: c.surface,
                shape: BoxShape.circle,
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
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: c.stamp,
                  borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                  border: Border.all(color: c.surface, width: 2),
                ),
                child: Center(
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    style: context.body(
                      size: CitroType.micro,
                      weight: CitroType.medium,
                      color: c.surface,
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
    return Pressable(
      onTap: () => copyText(
        '${quote.cn} — ${quote.en}',
        context: context,
        tip: '已复制每日一言',
      ),
      borderRadius: BorderRadius.circular(CitroColors.radii.card),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.surface2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.card),
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
                    width: 30,
                    height: 30,
                    cacheWidth: 90,
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Text(
                    'Citro',
                    style: context.heading(
                      size: CitroType.body,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 96),
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
                          style: context.heading(size: 20),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 20,
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
                          style: context.body(
                            size: CitroType.body,
                            color: c.inkSoft,
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
