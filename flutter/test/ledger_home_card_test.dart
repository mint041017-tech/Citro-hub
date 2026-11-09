import 'package:citro/ledger/ledger_models.dart';
import 'package:citro/ledger/ledger_store.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/ledger_home_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => AppScope(
  state: AppState.instance,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: Scaffold(body: Center(child: child)),
  ),
);

Future<void> _pumpCard(WidgetTester tester, Size size) async {
  await tester.pumpWidget(
    _host(SizedBox(width: size.width, height: size.height, child: const LedgerHomeCard())),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final store = LedgerStore.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    store.resetForTest();
    await store.ensureInit();
  });

  setUp(() async {
    store.resetForTest();
    await store.ensureInit();
    final month = LedgerDates.monthKey(DateTime.now());
    final now = DateTime.now();
    store.addEntry(
      kind: LedgerKind.expense,
      amountCents: 123456,
      categoryId: 'food',
      note: '午饭',
      occurredAt: now,
    );
    store.addEntry(
      kind: LedgerKind.expense,
      amountCents: 3800,
      categoryId: 'transport',
      occurredAt: DateTime(now.year, now.month, 2),
    );
    store.addEntry(
      kind: LedgerKind.income,
      amountCents: 800000,
      categoryId: 'salary',
      occurredAt: DateTime(now.year, now.month, 1),
    );
    store.setBudget(month, 500000);
    store.setIncomeTarget(month, 1000000);
  });

  testWidgets('3×2 小卡展示支出、预算、收入与笔数且不溢出', (tester) async {
    await _pumpCard(tester, const Size(175, 108));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('本月'), findsOneWidget);
    expect(find.textContaining('收'), findsWidgets);
  });

  testWidgets('标准档展示结余与日均', (tester) async {
    await _pumpCard(tester, const Size(300, 180));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('结余'), findsOneWidget);
    expect(find.textContaining('日均'), findsOneWidget);
  });

  testWidgets('大卡展示收入、结余、图表分类与进度', (tester) async {
    await _pumpCard(tester, const Size(520, 230));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('结余'), findsWidgets);
    expect(find.textContaining('已用'), findsOneWidget);
    expect(find.textContaining('笔'), findsWidgets);
  });

  testWidgets('宽屏小卡与极窄小卡都不溢出', (tester) async {
    await _pumpCard(tester, const Size(260, 108));
    expect(tester.takeException(), isNull);
    await _pumpCard(tester, const Size(160, 104));
    expect(tester.takeException(), isNull);
  });
}