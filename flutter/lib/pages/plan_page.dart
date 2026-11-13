import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_store.dart';
import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/lunar.dart';
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
    // 下面三处排版只在 Windows 生效：手机 / iPad 保持原来的竖排。
    final windows = platform.isWindows;
    return Stack(
      children: [
        // 背景图只在首页展示；其余页面用纯色底，避免抢内容。
        Positioned.fill(child: ColoredBox(color: context.c.bg)),
        CitroBackground(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                side,
                // 与游戏页 / 社区页对齐（宽屏 48）；手机保持原来的 8。
                windows ? AppSpacing.pageTop(width) : 8,
                side,
                sideNav ? 32 : 100,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final w = cons.maxWidth;
                      // 这三张卡原本是 Bento 格子里的固定档位，内部大量用
                      // Expanded / Spacer；竖排时得显式给高度，否则在
                      // 「高度不受限的滚动视图」里会直接报 flex 冲突。
                      return GlassCardsScope(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const CitroPageTitle('计划', '今天的安排，一目了然'),
                            const SizedBox(height: AppSpacing.x3),
                            const _TodayCard(),
                            const SizedBox(height: AppSpacing.x3),
                            if (windows)
                              // Windows 宽屏：待办在左、记账在右，同高并排。
                              SizedBox(
                                height: (w * .72).clamp(300.0, 360.0),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: const TodoHomeCard(
                                        globalAccent: true,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.x2),
                                    Expanded(child: const LedgerHomeCard()),
                                  ],
                                ),
                              )
                            else ...[
                              SizedBox(
                                height: (w * .82).clamp(250.0, 380.0),
                                // 计划页的待办卡用全局品牌色，和下面的记账卡同一套强调色。
                                child: const TodoHomeCard(globalAccent: true),
                              ),
                              const SizedBox(height: AppSpacing.x3),
                              SizedBox(
                                height: (w * .64).clamp(190.0, 280.0),
                                child: const LedgerHomeCard(),
                              ),
                            ],
                          ],
                        ),
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

/// 计划页的「今天」卡：本周 7 天 + 节日 / 节气 / 农历 / 倒数日。
///
/// 以前只放一条日期条，看不出「今天是这一周的第几天」，也看不到邻近几天
/// 有什么节日。现在改成横排一周：每天一格，格下写节日 / 节气 / 农历，
/// 有倒数日 / 纪念日的小圆点也标出来。
class _TodayCard extends StatefulWidget {
  const _TodayCard();

  @override
  State<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<_TodayCard> {
  @override
  void initState() {
    super.initState();
    // 倒数日 / 纪念日本来在日历页才加载，计划页也要拿到才能标出来。
    CalendarStore.instance.ensureInit();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 本周日 → 本周六
    final startOfWeek = today.subtract(Duration(days: today.weekday % 7));
    final fid = festivalIdOf(now);
    final term = termToday(now);
    final headline =
        (fid != null ? festivalName(fid) : null) ?? term ?? weekdayChinese(now);
    //  Store 变化（新增 / 删除纪念日）时重建这一周。
    return ListenableBuilder(
      listenable: CalendarStore.instance,
      builder: (context, _) {
        return CitroCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          onTap: () => Navigator.of(context).pushNamed('/calendar'),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c.accentLt.withAlpha(c.dark ? 70 : 170),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(AppIcons.calendar, width: 2),
                        size: 15,
                        color: c.accentInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  Text(
                    '${now.month} 月 ${now.day} 日 · $headline',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: CitroType.bodyLg,
                      weight: CitroType.medium,
                      color: c.ink,
                    ),
                  ),
                  const Spacer(),
                  AppIcon(
                    strokeSvg(AppIcons.chevronRight, width: 2),
                    size: 16,
                    color: c.inkSoft,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: _WeekCell(
                        date: startOfWeek.add(Duration(days: i)),
                        today: today,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 一周里的一天：日期 + 节日 / 节气 / 农历，今天高亮。
class _WeekCell extends StatelessWidget {
  const _WeekCell({required this.date, required this.today});

  final DateTime date;
  final DateTime today;

  static const _wd = ['日', '一', '二', '三', '四', '五', '六'];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isToday = date == today;
    final fid = festivalIdOf(date);
    final term = termToday(date);
    final lunar = lunarOf(date);
    // 倒数日 / 纪念日优先：用户自己记的日子最重要。
    CalendarMark? mark;
    for (final m in CalendarStore.instance.marks) {
      if (CalendarDates.hits(m, date)) {
        mark = m;
        break;
      }
    }
    String? label;
    Color? labelColor;
    if (mark != null) {
      label = mark.title;
      labelColor = c.stamp;
    } else if (fid != null) {
      label = festivalName(fid);
      labelColor = c.accentInk;
    } else if (term != null) {
      label = term;
      labelColor = c.mintInk;
    } else if (lunar != null) {
      label = lunar.day == 1
          ? lunar.name
          : lunar.name.substring(lunar.name.length - 2);
      labelColor = c.inkSoft;
    }
    final fg = isToday ? c.onAccent : c.ink;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isToday ? c.accent : c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: isToday ? c.accent : c.line),
      ),
      child: Column(
        children: [
          Text(
            _wd[date.weekday % 7],
            style: context.body(
              size: CitroType.micro,
              color: isToday ? c.onAccent.withAlpha(200) : c.inkSoft,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${date.day}',
            style: context
                .heading(size: CitroType.bodyLg, color: fg)
                .copyWith(
                  fontWeight: isToday ? CitroType.strong : CitroType.medium,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.body(
              size: CitroType.micro,
              color: isToday ? c.onAccent : labelColor ?? c.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
