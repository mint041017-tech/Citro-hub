import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'ledger_models.dart';
import 'ledger_store.dart';
import 'ledger_theme.dart';
import 'ledger_widgets.dart';

/// 月度预算 / 收入设置。总预算与分类预算在同一个弹层里保存，
/// 避免用户要在两个入口之间来回跳。
Future<void> showLedgerPlanSheet(
  BuildContext context, {
  required String monthKey,
}) {
  return showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => LedgerScope(child: LedgerPlanSheet(monthKey: monthKey)),
  );
}

class LedgerPlanSheet extends StatefulWidget {
  final String monthKey;

  const LedgerPlanSheet({super.key, required this.monthKey});

  @override
  State<LedgerPlanSheet> createState() => _LedgerPlanSheetState();
}

class _LedgerPlanSheetState extends State<LedgerPlanSheet> {
  late final TextEditingController _budget;
  late final TextEditingController _income;
  final Map<String, TextEditingController> _category = {};

  @override
  void initState() {
    super.initState();
    final plan = LedgerStore.instance.planFor(widget.monthKey);
    _budget = TextEditingController(text: _editText(plan.budgetCents));
    _income = TextEditingController(text: _editText(plan.incomeCents));
    for (final category in LedgerStore.instance.expenseCategories) {
      _category[category.id] = TextEditingController(
        text: _editText(plan.budgetFor(category.id)),
      );
    }
  }

  @override
  void dispose() {
    _budget.dispose();
    _income.dispose();
    for (final controller in _category.values) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _editText(int cents) {
    if (cents <= 0) return '';
    return cents % 100 == 0
        ? '${cents ~/ 100}'
        : (cents / 100).toStringAsFixed(2);
  }

  void _copyLastMonth() {
    final source = LedgerDates.monthKeyOfOffset(widget.monthKey, -1);
    final plan = LedgerStore.instance.planFor(source);
    if (!plan.hasBudget && !plan.hasIncome && plan.categoryBudgets.isEmpty) {
      ledgerToast(context, '上个月还没有设置预算');
      return;
    }
    _budget.text = _editText(plan.budgetCents);
    _income.text = _editText(plan.incomeCents);
    for (final entry in _category.entries) {
      entry.value.text = _editText(plan.budgetFor(entry.key));
    }
    setState(() {});
    ledgerToast(context, '已填入 ${LedgerDates.shortMonthLabel(source)} 的预算');
  }

  void _save() {
    final store = LedgerStore.instance;
    final budget = ledgerParseAmount(_budget.text) ?? 0;
    final income = ledgerParseAmount(_income.text) ?? 0;
    // 从旧预算表出发，只更新界面里出现的分类，保留隐藏分类的配置。
    final budgets = Map<String, int>.of(
      store.planFor(widget.monthKey).categoryBudgets,
    );
    for (final entry in _category.entries) {
      final value = ledgerParseAmount(entry.value.text) ?? 0;
      if (value > 0) {
        budgets[entry.key] = value;
      } else {
        budgets.remove(entry.key);
      }
    }
    store.setPlan(
      LedgerPlan(
        monthKey: widget.monthKey,
        budgetCents: budget,
        incomeCents: income,
        categoryBudgets: budgets,
      ),
    );
    ledgerToast(context, '本月预算已保存');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = LedgerStore.instance;
    final plan = store.planFor(widget.monthKey);
    final budget = ledgerParseAmount(_budget.text) ?? 0;
    final sum = _category.values.fold<int>(
      0,
      (total, controller) => total + (ledgerParseAmount(controller.text) ?? 0),
    );
    final over = budget > 0 && sum > budget;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .82,
          minChildSize: .5,
          maxChildSize: .96,
          builder: (context, scroll) {
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: c.line2,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '预算与收入',
                                  style: context.lheading(
                                    size: CitroType.subtitle,
                                    color: c.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  LedgerDates.monthLabel(widget.monthKey),
                                  style: context.lui(
                                    size: CitroType.caption,
                                    color: c.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          LedgerChip(
                            text: '沿用上月',
                            icon: AppIcons.refresh,
                            onTap: _copyLastMonth,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MoneyField(
                        label: '本月总预算',
                        hint: '还没设置',
                        controller: _budget,
                        icon: AppIcons.wallet,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      _MoneyField(
                        label: '本月收入目标',
                        hint: '用于计算储蓄率',
                        controller: _income,
                        icon: AppIcons.trendUp,
                      ),
                      const SizedBox(height: 18),
                      LedgerSectionTitle(
                        title: '分类预算',
                        hint: '只统计支出分类，留空表示不限',
                        trailing: Text(
                          '合计 ${ledgerMoney(sum)}',
                          style: context.lui(
                            size: CitroType.caption,
                            color: over ? c.stamp : c.inkSoft,
                          ),
                        ),
                      ),
                      if (over) ...[
                        const SizedBox(height: 6),
                        Text(
                          '分类预算合计超过总预算 ${ledgerMoney(sum - budget)}，保存后仍可继续使用。',
                          style: context.lui(
                            size: CitroType.caption,
                            color: c.stamp,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      for (final category in store.expenseCategories)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _CategoryBudgetRow(
                            category: category,
                            spent:
                                store
                                    .summaryFor(widget.monthKey)
                                    .categorySpend[category.id] ??
                                0,
                            controller: _category[category.id]!,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AccentButton(text: '保存预算', onTap: _save),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          plan.hasBudget
                              ? '当前总预算 ${ledgerMoney(plan.budgetCents)}'
                              : '设置后，首页会显示预算进度与日均可用',
                          style: context.lui(
                            size: CitroType.small,
                            color: c.inkSoft,
                          ),
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
    );
  }
}

class _MoneyField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final String icon;
  final ValueChanged<String>? onChanged;

  const _MoneyField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          LedgerIconTile(iconKey: icon, tint: c.accent, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: context.lui(
                    size: CitroType.caption,
                    weight: CitroType.strong,
                    color: c.inkSoft,
                  ),
                ),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: onChanged,
                  style: context.ldisplay(
                    size: 22,
                    weight: FontWeight.w700,
                    color: c.ink,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    prefixText: '¥ ',
                    prefixStyle: context.ldisplay(
                      size: 16,
                      weight: FontWeight.w700,
                      color: c.inkSoft,
                    ),
                    hintText: hint,
                    hintStyle: context.lui(
                      size: CitroType.meta,
                      color: c.inkSoft.withAlpha(160),
                    ),
                    contentPadding: const EdgeInsets.only(top: 2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBudgetRow extends StatelessWidget {
  final LedgerCategory category;
  final int spent;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _CategoryBudgetRow({
    required this.category,
    required this.spent,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          LedgerIconTile(
            iconKey: category.iconKey,
            tint: category.tint,
            size: 32,
            filled: true,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  category.name,
                  style: context.lui(
                    size: CitroType.meta,
                    weight: CitroType.strong,
                    color: c.ink,
                  ),
                ),
                Text(
                  '已用 ${ledgerMoney(spent)}',
                  style: context.lui(size: CitroType.small, color: c.inkSoft),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 104,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.right,
              onChanged: (_) => onChanged(),
              style: context.lui(
                size: CitroType.meta,
                weight: CitroType.strong,
                color: c.ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                prefixText: '¥ ',
                prefixStyle: context.lui(
                  size: CitroType.caption,
                  color: c.inkSoft,
                ),
                hintText: '不限',
                hintStyle: context.lui(
                  size: CitroType.caption,
                  color: c.inkSoft.withAlpha(150),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
