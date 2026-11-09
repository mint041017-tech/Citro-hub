import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ledger/ledger_charts.dart';
import '../ledger/ledger_models.dart';
import '../ledger/ledger_page.dart';
import '../ledger/ledger_store.dart';
import '../ledger/ledger_theme.dart';
import '../ledger/ledger_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'card_flight.dart';
import 'card_morph.dart';
import 'paper.dart';

/// 首页记账卡：按实际卡片尺寸自动切换小 / 标准 / 大三种内容。
///
/// 小尺寸是默认档：今日支出 + 本月预算剩余；标准档补收入与预算进度；
/// 大档再加近 7 日柱图与 Top 分类。
class LedgerHomeCard extends StatefulWidget {
  const LedgerHomeCard({super.key});

  @override
  State<LedgerHomeCard> createState() => _LedgerHomeCardState();
}

class _LedgerHomeCardState extends State<LedgerHomeCard> {
  @override
  void initState() {
    super.initState();
    LedgerStore.instance.ensureInit();
  }

  void _open(BuildContext context) {
    final rect = CitroCardFlight.rectOf(context);
    if (rect.isEmpty) {
      Navigator.of(context).pushNamed('/ledger');
      return;
    }
    CitroCardMorph.pushPageSoft(
      context,
      source: rect,
      settings: const RouteSettings(name: '/ledger'),
      builder: (_) => const LedgerPage(),
      snapshot: CitroCardFlight.snapshotOf(context, rect),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LedgerScope(
      child: Builder(
        builder: (context) {
          final c = context.c;
          return ListenableBuilder(
            listenable: LedgerStore.instance,
            builder: (context, _) {
              final store = LedgerStore.instance;
              final month = LedgerDates.monthKey(DateTime.now());
              final summary = store.summaryFor(month);
              final plan = store.planFor(month);
              final today = store.todayExpense();
              return PaperCard(
                tapeColor: c.tape3,
                tapeAngle: -1.7,
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                onTap: () => _open(context),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxHeight < 142 ||
                        constraints.maxWidth < 230;
                    final large =
                        constraints.maxWidth >= 300 &&
                        constraints.maxHeight >= 188;
                    if (large) {
                      return _large(context, store, summary, plan, today);
                    }
                    if (compact) {
                      return _compact(context, summary, plan, today);
                    }
                    return _standard(context, summary, plan, today);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _compact(
    BuildContext context,
    LedgerSummary summary,
    LedgerPlan plan,
    int today,
  ) {
    final c = context.c;
    final remaining = summary.budgetRemainingCents;
    final percent = (summary.budgetProgress * 100).round();
    final foot = [
      if (plan.hasBudget)
        (summary.overBudget
            ? '超 ${ledgerMoney(remaining.abs(), compact: true)}'
            : '剩 ${ledgerMoney(remaining, compact: true)}')
      else
        '未设预算',
      '${summary.entryCount} 笔',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            AppIcon(
              strokeSvg(AppIcons.wallet, width: 1.9),
              size: 15,
              color: c.accentInk,
            ),
            const SizedBox(width: 5),
            Text(
              '记账',
              style: context.lheading(size: CitroType.label, color: c.ink),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  today > 0
                      ? '今日 ${ledgerMoney(today, compact: true)}'
                      : '今日 ¥0',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.lui(
                    size: CitroType.small,
                    weight: CitroType.strong,
                    color: today > 0 ? c.stamp : c.inkSoft,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ledgerMoney(summary.expenseCents),
                      style: context.ldisplay(
                        size: 18,
                        weight: FontWeight.w700,
                        color: c.ink,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(
                        '本月',
                        style: context.lui(size: 8.5, color: c.inkSoft),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '收 ${ledgerMoney(summary.incomeCents, compact: true)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.lui(size: CitroType.small, color: c.mintInk),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (plan.hasBudget) ...[
              Expanded(
                child: LedgerProgress(
                  value: summary.budgetProgress,
                  color: ledgerWarm,
                  secondColor: ledgerCoral,
                  height: 4,
                  over: summary.overBudget,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  plan.hasBudget ? '$percent% · $foot' : '点开设置预算 · $foot',
                  maxLines: 1,
                  style: context.lui(
                    size: CitroType.small,
                    color: summary.overBudget ? c.stamp : c.inkSoft,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _standard(
    BuildContext context,
    LedgerSummary summary,
    LedgerPlan plan,
    int today,
  ) {
    final c = context.c;
    final percent = (summary.budgetProgress * 100).round();
    final day = DateTime.now().day.clamp(1, 31);
    final avg = (summary.expenseCents / day).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(
              strokeSvg(AppIcons.wallet, width: 1.9),
              size: 16,
              color: c.accentInk,
            ),
            const SizedBox(width: 5),
            Text(
              '记账',
              style: context.lheading(size: CitroType.label, color: c.ink),
            ),
            const Spacer(),
            Text(
              '今日 ${ledgerMoney(today, compact: true)}',
              style: context.lui(
                size: CitroType.small,
                weight: CitroType.strong,
                color: today > 0 ? c.stamp : c.inkSoft,
              ),
            ),
          ],
        ),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ledgerMoney(summary.expenseCents),
                      style: context.ldisplay(
                        size: 30,
                        weight: FontWeight.w700,
                        color: c.ink,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '本月支出',
                        style: context.lui(size: 9, color: c.inkSoft),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '收入 ${ledgerMoney(summary.incomeCents, compact: true)}',
                  style: context.lui(
                    size: CitroType.small,
                    weight: CitroType.strong,
                    color: c.mintInk,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '结余 ${ledgerMoney(summary.balanceCents, compact: true)}',
                  style: context.lui(
                    size: CitroType.small,
                    color: summary.balanceCents < 0 ? c.stamp : c.inkSoft,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (plan.hasBudget)
          Row(
            children: [
              Expanded(
                child: LedgerProgress(
                  value: summary.budgetProgress,
                  color: ledgerWarm,
                  secondColor: ledgerCoral,
                  height: 5,
                  over: summary.overBudget,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '已用 $percent%',
                maxLines: 1,
                style: context.lui(
                  size: CitroType.small,
                  color: summary.overBudget ? c.stamp : c.inkSoft,
                ),
              ),
            ],
          )
        else
          Text(
            '点开设置预算，cici 会帮你盯着',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.lui(size: CitroType.small, color: c.inkSoft),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            _stat(
              context,
              '预算剩',
              plan.hasBudget
                  ? (summary.overBudget
                        ? '超 ${ledgerMoney(summary.expenseCents - summary.budgetCents, compact: true)}'
                        : ledgerMoney(
                            summary.budgetRemainingCents,
                            compact: true,
                          ))
                  : '未设置',
              color: summary.overBudget ? c.stamp : c.ink,
            ),
            const SizedBox(width: 6),
            _stat(context, '日均', ledgerMoney(avg, compact: true)),
            const SizedBox(width: 6),
            _stat(context, '本月', '${summary.entryCount} 笔'),
          ],
        ),
      ],
    );
  }

  /// 一枚小票式的指标块：浅纸底 + 发丝边，统一各档卡片的信息颗粒度。
  Widget _stat(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    final c = context.c;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.lui(size: 8.5, color: c.inkSoft),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.lui(
                size: 11,
                weight: CitroType.strong,
                color: color ?? c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _large(
    BuildContext context,
    LedgerStore store,
    LedgerSummary summary,
    LedgerPlan plan,
    int today,
  ) {
    final c = context.c;
    final now = DateTime.now();
    final month = LedgerDates.monthKey(now);
    final data = store.dailyTotals(month);
    final recent = data.length > 7 ? data.sublist(data.length - 7) : data;
    final top = summary.categorySpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final percent = (summary.budgetProgress * 100).round();
    final day = now.day.clamp(1, 31);
    final avg = (summary.expenseCents / day).round();
    final incomePercent = (summary.incomeProgress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(
              strokeSvg(AppIcons.wallet, width: 1.9),
              size: 16,
              color: c.accentInk,
            ),
            const SizedBox(width: 5),
            Text(
              '记账',
              style: context.lheading(size: CitroType.label, color: c.ink),
            ),
            const SizedBox(width: 8),
            Text(
              LedgerDates.shortMonthLabel(month),
              style: context.lui(size: CitroType.small, color: c.inkSoft),
            ),
            const Spacer(),
            Text(
              '今日 ${ledgerMoney(today, compact: true)}',
              style: context.lui(
                size: CitroType.small,
                weight: CitroType.strong,
                color: today > 0 ? c.stamp : c.inkSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  ledgerMoney(summary.expenseCents),
                  style: context.ldisplay(
                    size: 30,
                    weight: FontWeight.w700,
                    color: c.ink,
                    height: 1,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '收入 ${ledgerMoney(summary.incomeCents, compact: true)}',
                  style: context.lui(size: CitroType.small, color: c.mintInk),
                ),
                const SizedBox(height: 1),
                Text(
                  '结余 ${ledgerMoney(summary.balanceCents, compact: true)}',
                  style: context.lui(
                    size: CitroType.small,
                    color: summary.balanceCents < 0 ? c.stamp : c.inkSoft,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '近 7 日',
                      style: context.lui(size: 8.5, color: c.inkSoft),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => LedgerBarChart(
                          data: recent,
                          height: math.max(18.0, constraints.maxHeight),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '支出分类',
                      style: context.lui(size: 8.5, color: c.inkSoft),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final rows = constraints.maxHeight >= 58 ? 4 : 3;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final entry in top.take(rows))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: store
                                              .categoryOf(entry.key)
                                              .tint,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          store.categoryOf(entry.key).name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.lui(
                                            size: CitroType.small,
                                            color: c.inkSoft,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        ledgerMoney(
                                          entry.value,
                                          compact: true,
                                          symbol: false,
                                        ),
                                        maxLines: 1,
                                        style: context.lui(
                                          size: CitroType.small,
                                          color: c.inkSoft,
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
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        if (plan.hasBudget) ...[
          Row(
            children: [
              Expanded(
                child: LedgerProgress(
                  value: summary.budgetProgress,
                  color: ledgerWarm,
                  secondColor: ledgerCoral,
                  height: 4,
                  over: summary.overBudget,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '已用 $percent%',
                maxLines: 1,
                style: context.lui(
                  size: CitroType.small,
                  color: summary.overBudget ? c.stamp : c.inkSoft,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                summary.overBudget
                    ? '超 ${ledgerMoney(summary.expenseCents - summary.budgetCents, compact: true)}'
                    : '剩 ${ledgerMoney(summary.budgetRemainingCents, compact: true)}',
                maxLines: 1,
                style: context.lui(
                  size: CitroType.small,
                  color: summary.overBudget ? c.stamp : c.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
        ],
        Row(
          children: [
            if (plan.incomeCents > 0)
              _stat(context, '收入达成', '$incomePercent%', color: c.mintInk)
            else
              _stat(
                context,
                '结余',
                ledgerMoney(summary.balanceCents, compact: true),
                color: summary.balanceCents < 0 ? c.stamp : c.ink,
              ),
            const SizedBox(width: 6),
            _stat(context, '日均', ledgerMoney(avg, compact: true)),
            const SizedBox(width: 6),
            _stat(context, '本月', '${summary.entryCount} 笔'),
          ],
        ),
      ],
    );
  }
}
