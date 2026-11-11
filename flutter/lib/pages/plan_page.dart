import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ledger_home_card.dart';
import '../widgets/paper.dart';
import '../widgets/tablet_shell.dart';
import '../widgets/todo_home_card.dart';
import 'home_page.dart';

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
    return CitroBackground(
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
                      const _SectionLabel('日历', '月历 · 农历 · 节日'),
                      const SizedBox(height: AppSpacing.x1),
                      SizedBox(
                        height: (w * .95).clamp(330.0, 470.0),
                        child: const CalendarCard(compact: true),
                      ),
                      const SizedBox(height: AppSpacing.x3),
                      const _SectionLabel('待办', '今天的任务与专注'),
                      const SizedBox(height: AppSpacing.x1),
                      SizedBox(
                        height: (w * .82).clamp(250.0, 380.0),
                        child: const TodoHomeCard(),
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
