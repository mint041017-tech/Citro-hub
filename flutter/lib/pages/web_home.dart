import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/quotes.dart';
import '../games/game_registry.dart';
import '../mbti/home_card.dart';
import '../overlays/card_collection.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/native.dart';
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
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: CitroReveal(
              rise: 6,
              child: SizedBox(
                height: height,
                // 底部留一条边距：最后一行的卡片不贴着纸边被切掉。
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: WebDesktopGrid(
                    rows: 9,
                    children: [
                      ...header.cells(context),
                      const WebGridCell(
                        1,
                        2,
                        4,
                        1,
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GlobalSearch(hint: '搜索功能 / 游戏 / 页面，回车必应'),
                        ),
                      ),
                      // 三栏等宽（各 4 格）：左栏搜索 + 天气 + 打卡 + 抽签；
                      // 中栏社区 + 测试 + 卡面收藏 + 食谱日记，四张卡同尺寸；
                      // 右栏小游戏两列七排。底部一行横带收尾。
                      const WebGridCell(1, 3, 4, 2, WeatherCard()),
                      // 日历 / 待办 / 记账已经收进「计划」页，桌面首页不再重复。
                      const WebGridCell(1, 5, 4, 2, CheckinCard()),
                      const WebGridCell(
                        1,
                        7,
                        4,
                        2,
                        HomeResCard(item: 'tool:玩法抽签'),
                      ),
                      WebGridCell(
                        5,
                        2,
                        4,
                        1,
                        _WebCommunityTicket(
                          unread: context.app.unread,
                          onTap: () => onSwitchTab(2),
                        ),
                      ),
                      const WebGridCell(5, 3, 4, 2, MbtiHomeCard()),
                      const WebGridCell(5, 5, 4, 2, CardCollectionEntry()),
                      WebGridCell(
                        5,
                        7,
                        4,
                        2,
                        _WebRecipeTicket(
                          onTap: () => Navigator.of(context).pushNamed('/cook'),
                        ),
                      ),
                      const WebGridCell(9, 2, 4, 7, _WebGames()),
                      // 底部：每日一言 + 视野 live + 下载站，一条横带收尾。
                      const WebGridCell(1, 9, 6, 1, _WebQuoteStrip()),
                      const WebGridCell(
                        7,
                        9,
                        3,
                        1,
                        HomeResCard(item: 'tool:视野live'),
                      ),
                      WebGridCell(
                        10,
                        9,
                        3,
                        1,
                        _WebDownloadCard(
                          onTap: () => openCitroPage(
                            context,
                            'https://dl.chimu-claw.xyz/',
                            title: 'Citro 下载站',
                          ),
                        ),
                      ),
                    ],
                  ),
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
                // 面板只占 4 格宽：两列排七排，14 款刚好铺满。
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: (constraints.maxHeight - 60) / 7,
              ),
              itemCount: kGameCards.length,
              itemBuilder: (context, index) =>
                  _WebGameCard(entry: kGameCards[index]),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
      ],
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
    final identity = entry.identity;
    final radius = BorderRadius.circular(CitroColors.radii.inner);
    return Semantics(
      button: true,
      label: '${entry.title}，${identity.tag}',
      child: Pressable(
        onTap: () => Navigator.of(context).pushNamed('/${entry.key}'),
        scale: .98,
        hoverLift: 2,
        hoverShadow: false,
        hoverOverlayColor: Colors.white.withValues(alpha: c.dark ? .04 : .10),
        borderRadius: radius,
        child: CitroGlass(
          borderRadius: radius,
          tint: c.surface,
          borderColor: Colors.white.withValues(alpha: c.dark ? .12 : .42),
          highlight: true,
          shadow: CitroColors.shadows.sm(c),
          padding: const EdgeInsets.all(6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontal =
                  constraints.maxWidth >= 148 && constraints.maxHeight >= 72;
              if (!horizontal) {
                return Column(
                  children: [
                    Expanded(
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(identity.soft, identity.primary, .12)!,
                              Color.lerp(identity.soft, identity.primary, .34)!,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: entry.art(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 28,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.heading(
                                  size: CitroType.bodyLg,
                                  color: c.ink,
                                ),
                              ),
                            ),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: identity.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
              final artSize = constraints.maxHeight < 84 ? 52.0 : 60.0;
              return Row(
                children: [
                  Container(
                    width: artSize,
                    height: artSize,
                    clipBehavior: Clip.antiAlias,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(identity.soft, identity.primary, .12)!,
                          Color.lerp(identity.soft, identity.primary, .34)!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(artSize * .28),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: c.dark ? .10 : .38,
                        ),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned(
                          top: -artSize * .22,
                          right: -artSize * .20,
                          child: Container(
                            width: artSize * .62,
                            height: artSize * .62,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(
                                alpha: c.dark ? .05 : .20,
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: entry.art(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: identity.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                identity.tag,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.body(
                                  size: CitroType.small,
                                  color: c.inkSoft,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            AppIcon(
                              strokeSvg(AppIcons.arrowUpRight, width: 2.2),
                              size: 12,
                              color: c.ink2,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.heading(
                            size: CitroType.bodyLg,
                            color: c.ink,
                            letterSpacing: -.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
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
      hoverColor: c.surface.withValues(alpha: c.surface.a * (120) / 255),
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
                // 圆形角标：宽度跟着字数走，保证正圆。
                width: badge > 9 ? 22.0 : 16.0,
                height: 16,
                decoration: BoxDecoration(
                  color: c.stamp,
                  shape: BoxShape.circle,
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
