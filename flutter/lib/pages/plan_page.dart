import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/lunar.dart';
import '../widgets/home_background.dart';
import '../widgets/ledger_home_card.dart';
import '../widgets/paper.dart';
import '../widgets/tablet_shell.dart';
import '../widgets/todo_home_card.dart';

/// 计划页：把原来散在首页的「日历 / 待办 / 记账」收成一页。
///
/// 竖排而不是 Bento 栅格——这三张卡本身就是列表式的，
/// 竖排能给出更宽松的高度，待办尤其需要。
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = CitroLayoutScope.maybeOf(context);
    final media = MediaQuery.sizeOf(context);
    final width = layout?.contentWidth ?? media.width;
    final maxWidth = width >= 780 ? 1120.0 : 760.0;
    final side = math.max(8.0, (width - maxWidth) / 2);
    final sideNav = layout?.tabletNav ?? false;
    return Stack(
      children: [
        const Positioned.fill(
          child: CitroAmbientBackground(blurred: true, blurSigma: 18),
        ),
        CitroBackground(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(side, 8, side, sideNav ? 32 : 100),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final w = cons.maxWidth;
                      // 这三张卡原本是 Bento 格子里的固定档位，内部大量用
                      // Expanded / Spacer；竖排时得显式给高度，否则在
                      // 「高度不受限的滚动视图」里会直接报 flex 冲突。
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _SectionLabel('日历', '今天 · 农历 · 节日'),
                          const SizedBox(height: AppSpacing.x1),
                          const _TodayCard(),
                          const SizedBox(height: AppSpacing.x3),
                          const _SectionLabel('待办', '今天的任务与专注'),
                          const SizedBox(height: AppSpacing.x1),
                          SizedBox(
                            height: (w * .82).clamp(250.0, 380.0),
                            // 计划页的待办卡用全局橙，和下面的记账卡同一套强调色。
                            child: const TodoHomeCard(globalAccent: true),
                          ),
                          const SizedBox(height: AppSpacing.x3),
                          const _SectionLabel('记账', '本月收支'),
                          const SizedBox(height: AppSpacing.x1),
                          SizedBox(
                            height: (w * .64).clamp(190.0, 280.0),
                            child: const LedgerHomeCard(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final String hint;

  const _SectionLabel(this.title, this.hint);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: context.heading(size: CitroType.titleLg, color: c.ink),
          ),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(size: CitroType.small, color: c.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// 计划页的「今天」卡：只显示当天，不铺整月格子。
///
/// 横排布局：左边大日期，右边星期 / 农历 / 节日，整卡固定 108 高，
/// 点一下进完整月历。以前这里塞的是整宽月历（330–470 高），
/// 在竖排计划页里过于抢戏，现在收缩成一条日期条。
class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    final lunar = lunarOf(now);
    final fid = festivalIdOf(now);
    final term = termToday(now);
    final weekday = weekdayChinese(now);
    final headline = fid != null ? festivalName(fid) : (term ?? weekday);
    final lunarText = lunar?.name ?? '';
    final sub = [weekday, lunarText].where((s) => s.isNotEmpty).join(' · ');
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => Navigator.of(context).pushNamed('/calendar'),
      child: SizedBox(
        height: 84,
        child: Row(
          children: [
            // 和记账卡一样用一枚品牌橙的图标开场，颜色语言统一。
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.accentLt.withAlpha(c.dark ? 70 : 170),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.calendar, width: 2),
                  size: 17,
                  color: c.accentInk,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            SizedBox(
              width: 88,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${now.day}',
                    style: context.hand(
                      size: 44,
                      weight: CitroType.strong,
                      color: c.ink,
                      height: .95,
                    ),
                  ),
                  Text(
                    '${now.year} / ${now.month}',
                    style: context.body(
                      size: CitroType.micro,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: CitroType.bodyLg,
                      weight: CitroType.medium,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: CitroType.small,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            AppIcon(
              strokeSvg(AppIcons.chevronRight, width: 2),
              size: 18,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}
