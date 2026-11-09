import 'package:citro/ledger/ledger_models.dart';
import 'package:citro/ledger/ledger_store.dart';
import 'package:citro/services/prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = LedgerStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    store.resetForTest();
    await store.ensureInit();
  });

  test('默认分类覆盖支出与收入，空账本结余为 0', () {
    expect(store.expenseCategories.map((c) => c.id), contains('food'));
    expect(store.expenseCategories.map((c) => c.id), contains('other_expense'));
    expect(store.incomeCategories.map((c) => c.id), contains('salary'));
    expect(store.incomeCategories.map((c) => c.id), contains('other_income'));

    final summary = store.summaryFor('2026-11');
    expect(summary.entryCount, 0);
    expect(summary.expenseCents, 0);
    expect(summary.incomeCents, 0);
    expect(summary.balanceCents, 0);
    expect(summary.overBudget, isFalse);
  });

  test('账单写入后月度支出、收入、结余与分类占比正确', () {
    store.addEntry(
      kind: LedgerKind.expense,
      amountCents: 1850,
      categoryId: 'food',
      note: '午饭',
      occurredAt: DateTime(2026, 11, 2, 12),
    );
    store.addEntry(
      kind: LedgerKind.expense,
      amountCents: 1200,
      categoryId: 'transport',
      occurredAt: DateTime(2026, 11, 3, 8),
    );
    store.addEntry(
      kind: LedgerKind.income,
      amountCents: 800000,
      categoryId: 'salary',
      occurredAt: DateTime(2026, 11, 1, 9),
    );

    final summary = store.summaryFor('2026-11');
    expect(summary.expenseCents, 3050);
    expect(summary.incomeCents, 800000);
    expect(summary.balanceCents, 796950);
    expect(summary.entryCount, 3);
    expect(summary.categorySpend['food'], 1850);
    expect(summary.categorySpend['transport'], 1200);

    final daily = store.dailyTotals('2026-11');
    expect(daily.length, 30);
    expect(daily[1].expense, 1850);
    expect(daily[2].expense, 1200);
    expect(daily[0].income, 800000);
  });

  test('总预算、剩余、日均和分类预算超支排序', () {
    store.addEntry(
      kind: LedgerKind.expense,
      amountCents: 1850,
      categoryId: 'food',
      occurredAt: DateTime(2026, 11, 2, 12),
    );
    store.addEntry(
      kind: LedgerKind.expense,
      amountCents: 1200,
      categoryId: 'transport',
      occurredAt: DateTime(2026, 11, 3, 8),
    );
    store.setPlan(
      const LedgerPlan(
        monthKey: '2026-11',
        budgetCents: 10000,
        incomeCents: 500000,
        categoryBudgets: {'food': 1000, 'transport': 5000},
      ),
    );

    final summary = store.summaryFor('2026-11');
    expect(summary.budgetRemainingCents, 6950);
    expect(summary.budgetProgress, closeTo(.305, .001));
    expect(summary.incomeProgress, closeTo(0, .001));
    expect(summary.overBudget, isFalse);

    final budgets = store.categoryBudgets('2026-11');
    expect(budgets.length, 2);
    expect(budgets.first.category.id, 'food');
    expect(budgets.first.spent, 1850);
    expect(budgets.first.spent > budgets.first.budget, isTrue);

    // 收入目标在 summary 里单独统计。
    store.addEntry(
      kind: LedgerKind.income,
      amountCents: 250000,
      categoryId: 'salary',
      occurredAt: DateTime(2026, 11, 5),
    );
    final updated = store.summaryFor('2026-11');
    expect(updated.incomeProgress, .5);
    expect(updated.savingRate, greaterThan(0));
  });

  test('修改、删除与撤销账单', () {
    final entry = store.addEntry(
      kind: LedgerKind.expense,
      amountCents: 1000,
      categoryId: 'food',
      note: '早饭',
      occurredAt: DateTime(2026, 11, 2, 8),
    );
    store.updateEntry(
      entry.copyWith(amountCents: 1200, categoryId: 'transport', note: '打车'),
    );
    final updated = store.entryById(entry.id)!;
    expect(updated.amountCents, 1200);
    expect(updated.categoryId, 'transport');
    expect(store.summaryFor('2026-11').expenseCents, 1200);

    store.removeEntry(entry.id);
    expect(store.entries, isEmpty);
    expect(store.summaryFor('2026-11').expenseCents, 0);

    store.restoreEntry(updated);
    expect(store.entries.length, 1);
    expect(store.summaryFor('2026-11').expenseCents, 1200);
  });

  test('预算按月隔离，并可从上月复制', () {
    store.setPlan(
      const LedgerPlan(
        monthKey: '2026-10',
        budgetCents: 20000,
        incomeCents: 600000,
        categoryBudgets: {'food': 6000},
      ),
    );
    expect(store.planFor('2026-11').budgetCents, 0);
    store.copyPlanFrom('2026-11', '2026-10');
    final plan = store.planFor('2026-11');
    expect(plan.budgetCents, 20000);
    expect(plan.incomeCents, 600000);
    expect(plan.categoryBudgets['food'], 6000);
    // 修改本月不污染上月。
    store.setCategoryBudget('2026-11', 'food', 1000);
    expect(store.planFor('2026-10').categoryBudgets['food'], 6000);
  });

  test('自定义分类删除后账单迁移到其他', () {
    final category = store.addCategory(
      name: '宠物',
      kind: LedgerKind.expense,
      color: 0xFFAA8866,
      iconKey: 'heart',
    );
    store.addEntry(
      kind: LedgerKind.expense,
      amountCents: 5000,
      categoryId: category.id,
      occurredAt: DateTime(2026, 11, 4),
    );
    store.setCategoryBudget('2026-11', category.id, 8000);
    store.removeCategory(category.id);

    expect(store.categories.any((c) => c.id == category.id), isFalse);
    expect(store.entries.single.categoryId, 'other_expense');
    expect(
      store.planFor('2026-11').categoryBudgets.containsKey(category.id),
      isFalse,
    );
  });

  test('内置分类删除等于隐藏，可恢复', () {
    store.removeCategory('food');
    expect(store.expenseCategories.any((c) => c.id == 'food'), isFalse);
    expect(store.categories.firstWhere((c) => c.id == 'food').active, isFalse);

    final hidden = store.categories.firstWhere((c) => c.id == 'food');
    store.updateCategory(hidden.copyWith(active: true));
    expect(store.expenseCategories.any((c) => c.id == 'food'), isTrue);
  });

  test('本地持久化后重新加载，数据不丢', () async {
    store.addEntry(
      kind: LedgerKind.expense,
      amountCents: 3850,
      categoryId: 'food',
      note: '火锅',
      occurredAt: DateTime(2026, 11, 6, 19),
    );
    store.setBudget('2026-11', 30000);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    store.resetForTest();
    await store.ensureInit();
    expect(store.entries.length, 1);
    expect(store.entries.single.amountCents, 3850);
    expect(store.entries.single.note, '火锅');
    expect(store.planFor('2026-11').budgetCents, 30000);
    expect(store.summaryFor('2026-11').expenseCents, 3850);
  });

  test('金额、月份与日期工具', () {
    expect(ledgerParseAmount('18.5'), 1850);
    expect(ledgerParseAmount('¥1,234.50'), 123450);
    expect(ledgerParseAmount('0.05'), 5);
    expect(ledgerParseAmount('abc'), isNull);
    expect(ledgerParseAmount('-1'), isNull);

    expect(ledgerMoney(1850), '¥18.50');
    expect(ledgerMoney(20000), '¥200');
    expect(ledgerMoney(-500), '-¥5');
    expect(ledgerMoney(1200000, compact: true), '¥1.2万');

    expect(LedgerDates.monthKey(DateTime(2026, 11, 9)), '2026-11');
    expect(LedgerDates.monthKeyOfOffset('2026-01', -1), '2025-12');
    expect(LedgerDates.monthKeyOfOffset('2026-12', 1), '2027-01');
    expect(LedgerDates.daysInMonth('2026-02'), 28);
    expect(LedgerDates.monthLabel('2026-11'), '2026 年 11 月');
  });

  test('账单 JSON 往返保持金额与时间', () {
    final entry = LedgerEntry(
      id: 'exp-1',
      kind: LedgerKind.expense,
      amountCents: 1850,
      categoryId: 'food',
      note: '午饭',
      occurredAt: DateTime(2026, 11, 2, 12, 30),
      createdAt: DateTime(2026, 11, 2, 12, 31),
      source: LedgerSource.scan,
    );
    final restored = LedgerEntry.fromJson(entry.toJson());
    expect(restored.amountCents, 1850);
    expect(restored.kind, LedgerKind.expense);
    expect(restored.source, LedgerSource.scan);
    expect(restored.occurredAt, entry.occurredAt);

    const plan = LedgerPlan(
      monthKey: '2026-11',
      budgetCents: 30000,
      incomeCents: 900000,
      categoryBudgets: {'food': 10000},
    );
    final restoredPlan = LedgerPlan.fromJson('2026-11', plan.toJson());
    expect(restoredPlan.budgetCents, 30000);
    expect(restoredPlan.categoryBudgets['food'], 10000);
  });
}
