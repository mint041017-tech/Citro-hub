import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'ledger_ai.dart';
import 'ledger_charts.dart';
import 'ledger_entry_sheet.dart';
import 'ledger_models.dart';
import 'ledger_plan_sheet.dart';
import 'ledger_store.dart';
import 'ledger_theme.dart';
import 'ledger_widgets.dart';

/// 记账首页：收支概览、预算进度、cici 洞察与数据看板。
class LedgerHomeTab extends StatefulWidget {
  final String monthKey;
  final ValueChanged<String> onMonthChanged;
  final VoidCallback onOpenAdd;
  final VoidCallback onOpenCici;

  const LedgerHomeTab({
    super.key,
    required this.monthKey,
    required this.onMonthChanged,
    required this.onOpenAdd,
    required this.onOpenCici,
  });

  @override
  State<LedgerHomeTab> createState() => _LedgerHomeTabState();
}

class _LedgerHomeTabState extends State<LedgerHomeTab> {
  /// 0 = 近 7 天，1 = 本月
  int _range = 0;
  String? _insight;
  String? _insightKey;
  Set<String> _insightEntryIds = {};
  String _insightPlanKey = '';
  bool _insightLoading = false;
  bool _insightDirty = false;

  @override
  void initState() {
    super.initState();
    LedgerStore.instance.addListener(_onStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshInsight());
  }

  @override
  void didUpdateWidget(covariant LedgerHomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.monthKey != widget.monthKey) {
      _insight = null;
      _insightKey = null;
      _insightEntryIds = {};
      _insightPlanKey = '';
      _refreshInsight();
    }
  }

  @override
  void dispose() {
    LedgerStore.instance.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    final store = LedgerStore.instance;
    // 新增本月账单，或本月预算/收入目标变化时，才让 cici 重新观察。
    final ids = _monthEntryIds(store);
    final planChanged =
        _insightKey == widget.monthKey &&
        _monthPlanKey(store) != _insightPlanKey;
    final entryChanged = ids.difference(_insightEntryIds).isNotEmpty;
    if (!entryChanged && !planChanged) return;
    if (_insightLoading) {
      _insightDirty = true;
      return;
    }
    _refreshInsight();
  }

  Set<String> _monthEntryIds(LedgerStore store) =>
      store.entriesInMonth(widget.monthKey).map((e) => e.id).toSet();

  String _monthPlanKey(LedgerStore store) {
    final plan = store.planFor(widget.monthKey);
    final budgets = plan.categoryBudgets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '${plan.budgetCents}:${plan.incomeCents}:'
        '${budgets.map((e) => '${e.key}=${e.value}').join(',')}';
  }

  Future<void> _refreshInsight({bool force = false}) async {
    if (_insightLoading) return;
    final store = LedgerStore.instance;
    final month = widget.monthKey;
    final entryIds = _monthEntryIds(store);
    final planKey = _monthPlanKey(store);
    if (!force &&
        _insightKey == month &&
        _insight != null &&
        entryIds.difference(_insightEntryIds).isEmpty &&
        planKey == _insightPlanKey) {
      return;
    }
    setState(() {
      _insightLoading = true;
      _insightDirty = false;
      // 记住这次分析覆盖的账单与预算；分析期间的变化会在 finally 里补跑。
      _insightEntryIds = entryIds;
      _insightPlanKey = planKey;
    });
    final summary = store.summaryFor(month);
    // 空账本没有可分析的数据，直接用本地提示，省掉一次 AI 请求。
    if (summary.entryCount == 0) {
      setState(() {
        _insight = _fallbackInsight(store, month);
        _insightKey = month;
        _insightLoading = false;
      });
      return;
    }
    try {
      final text = await LedgerAi.analyze(
        monthKey: month,
        summary: summary,
        plan: store.planFor(month),
        budgets: store.categoryBudgets(month),
        recent: store.recentEntries(limit: 8),
        monthEntries: store.entriesInMonth(month),
        categories: store.categories,
      );
      if (!mounted || widget.monthKey != month) return;
      setState(() {
        _insight = text;
        _insightKey = month;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // AI 不可用时也要给出可读的本地判断，不把错误直接甩给用户。
        _insight = _fallbackInsight(store, month);
        _insightKey = month;
      });
    } finally {
      if (mounted) {
        setState(() => _insightLoading = false);
        if (_insightDirty) {
          _insightDirty = false;
          _refreshInsight();
        }
      }
    }
  }

  String _fallbackInsight(LedgerStore store, String month) {
    final summary = store.summaryFor(month);
    if (summary.entryCount == 0) {
      return '· 本月还没有账单，先记一笔，cici 才能看出你的消费习惯。';
    }
    final lines = <String>[];
    if (summary.overBudget) {
      lines.add(
        '· 本月已超预算 ${ledgerMoney(summary.expenseCents - summary.budgetCents)}，'
        '接下来先停掉非必要支出。',
      );
    } else if (summary.budgetCents > 0) {
      final days = LedgerDates.daysInMonth(month) - DateTime.now().day + 1;
      lines.add(
        '· 预算还剩 ${ledgerMoney(summary.budgetRemainingCents)}，'
        '按 ${days.clamp(1, 31)} 天算每天可用 '
        '${ledgerMoney((summary.budgetRemainingCents / days.clamp(1, 31)).round())}。',
      );
    }
    final spend = summary.categorySpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (spend.isNotEmpty) {
      final top = store.categoryOf(spend.first.key);
      final ratio = summary.expenseCents <= 0
          ? 0
          : (spend.first.value / summary.expenseCents * 100).round();
      lines.add(
        '· ${top.name}是本月最大支出，${ledgerMoney(spend.first.value)}，'
        '占 $ratio%。',
      );
    }
    if (lines.isEmpty) {
      lines.add('· 本月收支平稳，保持现在的记录节奏就好。');
    }
    return lines.take(3).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final store = LedgerStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final month = widget.monthKey;
        final summary = store.summaryFor(month);
        final plan = store.planFor(month);
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final side = wide ? 16.0 : 14.0;
            return ListView(
              padding: EdgeInsets.fromLTRB(side, 4, side, 28),
              children: [
                _monthRow(context, summary, plan),
                const SizedBox(height: 10),
                _overview(context, summary, plan),
                const SizedBox(height: 12),
                _insightCard(context),
                const SizedBox(height: 12),
                _chartCard(context, store, summary),
                const SizedBox(height: 12),
                _categoryCard(context, store, summary),
                if (store.categoryBudgets(month).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _budgetCategoryCard(context, store),
                ],
                const SizedBox(height: 12),
                _recentCard(context, store),
              ],
            );
          },
        );
      },
    );
  }

  Widget _monthRow(
    BuildContext context,
    LedgerSummary summary,
    LedgerPlan plan,
  ) {
    return Row(
      children: [
        LedgerMonthSwitcher(
          monthKey: widget.monthKey,
          onChanged: widget.onMonthChanged,
        ),
        const Spacer(),
        _PlanButton(
          label: plan.hasBudget ? '调整预算' : '设置预算',
          onTap: () => showLedgerPlanSheet(context, monthKey: widget.monthKey),
        ),
      ],
    );
  }

  Widget _overview(
    BuildContext context,
    LedgerSummary summary,
    LedgerPlan plan,
  ) {
    final c = context.c;
    final balance = summary.balanceCents;
    final balanceColor = balance >= 0 ? c.mintInk : c.stamp;
    final daysLeft =
        (LedgerDates.daysInMonth(widget.monthKey) - DateTime.now().day + 1)
            .clamp(1, 31);
    final daily = plan.hasBudget
        ? (summary.budgetRemainingCents / daysLeft).round()
        : 0;
    return PaperCard(
      tapeColor: c.tape,
      tapeAngle: -2.1,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LedgerIconTile(iconKey: 'wallet', tint: c.accent, size: 34),
              const SizedBox(width: 9),
              Text(
                '本月结余',
                style: context.lui(
                  size: CitroType.label,
                  weight: CitroType.strong,
                  color: c.inkSoft,
                ),
              ),
              const Spacer(),
              if (summary.entryCount > 0)
                Text(
                  '${summary.entryCount} 笔',
                  style: context.lui(size: CitroType.small, color: c.inkSoft),
                ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              ledgerMoney(balance),
              style: context.ldisplay(
                size: 42,
                weight: FontWeight.w700,
                color: balanceColor,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: LedgerStat(
                  label: '支出',
                  value: ledgerMoney(summary.expenseCents, symbol: false),
                  hint: summary.overBudget ? '已超预算' : null,
                  color: c.stamp,
                ),
              ),
              Container(width: 1, height: 42, color: c.line),
              const SizedBox(width: 10),
              Expanded(
                child: LedgerStat(
                  label: '收入',
                  value: ledgerMoney(summary.incomeCents, symbol: false),
                  hint: plan.hasIncome
                      ? '目标完成 ${(summary.incomeProgress * 100).toStringAsFixed(0)}%'
                      : null,
                  color: c.mintInk,
                ),
              ),
              Container(width: 1, height: 42, color: c.line),
              const SizedBox(width: 10),
              Expanded(
                child: LedgerStat(
                  label: '储蓄率',
                  value: summary.incomeCents > 0
                      ? '${(summary.savingRate * 100).toStringAsFixed(0)}%'
                      : '—',
                  hint: plan.hasIncome
                      ? '目标 ${ledgerMoney(plan.incomeCents, compact: true)}'
                      : null,
                  color: balanceColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (plan.hasBudget) ...[
            Row(
              children: [
                Text(
                  '总预算',
                  style: context.lui(size: CitroType.small, color: c.inkSoft),
                ),
                const Spacer(),
                Text(
                  summary.overBudget
                      ? '超 ${ledgerMoney(summary.expenseCents - summary.budgetCents)}'
                      : '剩余 ${ledgerMoney(summary.budgetRemainingCents)}',
                  style: context.lui(
                    size: CitroType.small,
                    weight: CitroType.strong,
                    color: summary.overBudget ? c.stamp : c.ink2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            LedgerProgress(
              value: summary.budgetProgress,
              color: ledgerWarm,
              secondColor: ledgerCoral,
              over: summary.overBudget,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '已用 ${(summary.budgetProgress * 100).toStringAsFixed(0)}%',
                  style: context.lui(size: CitroType.small, color: c.inkSoft),
                ),
                const Spacer(),
                if (!summary.overBudget)
                  Text(
                    '日均可用 ${ledgerMoney(daily)}',
                    style: context.lui(size: CitroType.small, color: c.inkSoft),
                  ),
              ],
            ),
          ] else
            Pressable(
              onTap: () =>
                  showLedgerPlanSheet(context, monthKey: widget.monthKey),
              scale: .98,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.hl.withAlpha(120),
                  borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.trendUp, width: 2),
                      size: 15,
                      color: c.accentInk,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '设置本月预算与收入，cici 才能提醒你超支',
                        style: context.lui(
                          size: CitroType.caption,
                          color: c.ink2,
                        ),
                      ),
                    ),
                    AppIcon(
                      strokeSvg(AppIcons.arrowRight, width: 2),
                      size: 14,
                      color: c.inkSoft,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _insightCard(BuildContext context) {
    final c = context.c;
    final lines = (_insight ?? '')
        .split('\n')
        .map((e) => e.replaceFirst(RegExp(r'^[·\-\*]\s*'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return PaperCard(
      tapeColor: c.tape2,
      tapeAngle: 1.9,
      color: c.noteB,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(
                strokeSvg(AppIcons.sparkle, width: 2),
                size: 16,
                color: c.accentInk,
              ),
              const SizedBox(width: 6),
              Text(
                'cici 的观察',
                style: context.lheading(size: CitroType.title, color: c.ink),
              ),
              const Spacer(),
              Pressable(
                onTap: _insightLoading ? null : () => _refreshInsight(force: true),
                scale: .9,
                hoverLift: 0,
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line),
                  ),
                  child: Center(
                    child: _insightLoading
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: c.accent,
                            ),
                          )
                        : AppIcon(
                            strokeSvg(AppIcons.refresh, width: 2),
                            size: 14,
                            color: c.inkSoft,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (lines.isEmpty)
            Text(
              _insightLoading ? '正在翻你的账本…' : '记两笔之后，cici 会在这里给出观察。',
              style: context.lui(
                size: CitroType.meta,
                color: c.inkSoft,
                height: 1.6,
              ),
            )
          else
            for (final line in lines.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 6),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ledgerCoral,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: context.lui(
                          size: CitroType.meta,
                          color: c.ink2,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: LedgerChip(
              text: '找 cici 细聊',
              icon: AppIcons.arrowRight,
              onTap: widget.onOpenCici,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard(BuildContext context, LedgerStore store, LedgerSummary s) {
    final c = context.c;
    var data = store.dailyTotals(widget.monthKey);
    if (_range == 0) {
      final now = DateTime.now();
      final isCurrent =
          DateTime(now.year, now.month) ==
          LedgerDates.monthStart(widget.monthKey);
      final cutoff = isCurrent ? now.day : data.length;
      data = data.sublist(0, cutoff.clamp(1, data.length));
      if (data.length > 7) data = data.sublist(data.length - 7);
    }
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LedgerSectionTitle(
                  title: '每日支出',
                  hint: _range == 0 ? '最近 7 天' : '本月每天',
                ),
              ),
              SizedBox(
                width: 116,
                height: 30,
                child: Row(
                  children: [
                    for (final item in const [(0, '7 天'), (1, '本月')])
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _range = item.$1),
                          child: AnimatedContainer(
                            duration: CitroMotion.reduced(context)
                                ? Duration.zero
                                : CitroMotion.hover,
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: _range == item.$1
                                  ? c.accent.withAlpha(40)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Center(
                              child: Text(
                                item.$2,
                                style: context.lui(
                                  size: CitroType.small,
                                  weight: _range == item.$1
                                      ? CitroType.strong
                                      : CitroType.regular,
                                  color: _range == item.$1
                                      ? c.accentInk
                                      : c.inkSoft,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LedgerBarChart(data: data, height: 128),
          const SizedBox(height: 4),
          Row(
            children: [
              _legendDot(context, c.accent, '支出'),
              const SizedBox(width: 12),
              _legendDot(context, c.mintInk, '收入'),
              const Spacer(),
              Text(
                '合计 ${ledgerMoney(s.expenseCents)}',
                style: context.lui(size: CitroType.small, color: c.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(BuildContext context, Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        text,
        style: context.lui(size: CitroType.small, color: context.c.inkSoft),
      ),
    ],
  );

  Widget _categoryCard(
    BuildContext context,
    LedgerStore store,
    LedgerSummary summary,
  ) {
    final c = context.c;
    final spend = summary.categorySpend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final segments = <({String label, int value, Color color})>[];
    var other = 0;
    for (var i = 0; i < spend.length; i++) {
      final category = store.categoryOf(spend[i].key);
      if (i < 5) {
        segments.add((
          label: category.name,
          value: spend[i].value,
          color: category.tint,
        ));
      } else {
        other += spend[i].value;
      }
    }
    if (other > 0) {
      segments.add((
        label: '其他分类',
        value: other,
        color: c.inkSoft.withAlpha(150),
      ));
    }
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LedgerSectionTitle(title: '分类占比', hint: '本月支出结构'),
          const SizedBox(height: 8),
          if (segments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  '还没有支出，记一笔就能看到分布',
                  style: context.lui(size: CitroType.meta, color: c.inkSoft),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                final chart = LedgerDonutChart(
                  segments: segments,
                  size: compact ? 112 : 132,
                  centerValue: ledgerMoney(
                    summary.expenseCents,
                    symbol: false,
                    compact: true,
                  ),
                  centerLabel: '本月支出',
                );
                final legend = Column(
                  children: [
                    for (final segment in segments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: segment.color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                segment.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.lui(
                                  size: CitroType.caption,
                                  color: c.ink2,
                                ),
                              ),
                            ),
                            Text(
                              '${(segment.value / summary.expenseCents * 100).toStringAsFixed(0)}%',
                              style: context.lui(
                                size: CitroType.small,
                                weight: CitroType.strong,
                                color: c.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                if (compact) {
                  return Column(
                    children: [
                      Center(child: chart),
                      const SizedBox(height: 10),
                      legend,
                    ],
                  );
                }
                return Row(
                  children: [
                    chart,
                    const SizedBox(width: 18),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _budgetCategoryCard(BuildContext context, LedgerStore store) {
    final c = context.c;
    final rows = store.categoryBudgets(widget.monthKey);
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LedgerSectionTitle(
            title: '分类预算',
            hint: '超支的分类会排在最前',
            trailing: LedgerChip(
              text: '调整',
              onTap: () =>
                  showLedgerPlanSheet(context, monthKey: widget.monthKey),
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Column(
                children: [
                  Row(
                    children: [
                      LedgerIconTile(
                        iconKey: row.category.iconKey,
                        tint: row.category.tint,
                        size: 26,
                        filled: true,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          row.category.name,
                          style: context.lui(
                            size: CitroType.meta,
                            weight: CitroType.strong,
                            color: c.ink,
                          ),
                        ),
                      ),
                      Text(
                        '${ledgerMoney(row.spent, compact: true)} / ${ledgerMoney(row.budget, compact: true)}',
                        style: context.lui(
                          size: CitroType.small,
                          color: row.spent > row.budget ? c.stamp : c.inkSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  LedgerProgress(
                    value: row.budget <= 0 ? 0 : row.spent / row.budget,
                    color: row.category.tint,
                    secondColor: c.accent2,
                    height: 5,
                    over: row.spent > row.budget,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _recentCard(BuildContext context, LedgerStore store) {
    final c = context.c;
    final recent = store.recentEntries(limit: 5);
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LedgerSectionTitle(
            title: '最近账单',
            hint: recent.isEmpty ? '还没有记录' : '点一行可以修改',
            trailing: recent.isEmpty
                ? null
                : LedgerChip(
                    text: '记一笔',
                    icon: AppIcons.plus,
                    onTap: widget.onOpenAdd,
                  ),
          ),
          const SizedBox(height: 4),
          if (recent.isEmpty)
            LedgerEmptyState(
              title: '从第一笔开始',
              hint: '手动记一笔，或者截一张支付截图让 cici 帮你识别。',
              action: '去记一笔',
              onAction: widget.onOpenAdd,
            )
          else
            for (final entry in recent) ...[
              LedgerEntryRow(
                entry: entry,
                category: store.categoryOf(entry.categoryId, kind: entry.kind),
                onTap: () => showLedgerEntrySheet(context, entry: entry),
              ),
              if (entry != recent.last)
                Divider(height: 1, color: c.line.withAlpha(140)),
            ],
        ],
      ),
    );
  }
}

/// 首页右上角的预算入口：圆形图标按钮，长按可看到「设置预算 / 调整预算」。
class _PlanButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PlanButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Pressable(
          key: const ValueKey('ledger-plan-button'),
          onTap: onTap,
          scale: .94,
          hoverLift: 0,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.accentLt, ledgerWarm.withAlpha(c.dark ? 50 : 34)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: c.accent2.withAlpha(110)),
            ),
            child: Center(
              child: AppIcon(
                strokeSvg(AppIcons.trendUp, width: 2),
                size: 18,
                color: c.accentInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
