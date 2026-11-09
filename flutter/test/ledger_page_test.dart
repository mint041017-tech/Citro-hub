import 'package:citro/ledger/ledger_ai.dart';
import 'package:citro/ledger/ledger_models.dart';
import 'package:citro/ledger/ledger_page.dart';
import 'package:citro/ledger/ledger_receipt.dart';
import 'package:citro/ledger/ledger_store.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/ledger_home_card.dart';
import 'package:flutter/material.dart';
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
    // 首页洞察卡会请求 AI；测试里用固定文本，避免真实网络。
    LedgerAi.completer = (prompt, system) async => '· 本月餐饮占比最高。';
  });

  tearDown(() {
    LedgerAi.completer = null;
    LedgerAi.visionCompleter = null;
  });

  Widget app(Widget home) =>
      MaterialApp(theme: buildCitroTheme(CitroColors.light), home: home);

  testWidgets('记账页三栏切换、手动记账与预算设置生效', (tester) async {
    tester.view.physicalSize = const Size(420, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(const LedgerPage()));
    await tester.pumpAndSettle();

    expect(find.text('本月结余'), findsOneWidget);
    expect(find.text('账单'), findsWidgets);

    // 切到「记一笔」。
    await tester.tap(find.byKey(const ValueKey('ledger-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('记下来'), findsOneWidget);
    expect(find.text('手动录入或识别截图'), findsNothing);
    expect(find.byKey(const ValueKey('ledger-date-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-time-button')), findsOneWidget);

    // 日期与时间分开选择。
    await tester.tap(find.byKey(const ValueKey('ledger-date-button')));
    await tester.pumpAndSettle();
    expect(find.text('选择日期'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-time-button')));
    await tester.pumpAndSettle();
    expect(find.text('选择时间'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 填金额、选分类、保存。
    await tester.enterText(find.byType(TextField).first, '25.5');
    await tester.tap(find.text('交通').first);
    await tester.pump();
    await tester.tap(find.text('记下来'));
    await tester.pumpAndSettle();

    expect(store.entries.length, 1);
    expect(store.entries.single.amountCents, 2550);
    expect(store.entries.single.categoryId, 'transport');

    // 回首页，最近账单与概览同步。
    await tester.tap(find.byKey(const ValueKey('ledger-tab-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('25.50'), findsWidgets);

    // 设置本月总预算。
    await tester.tap(find.byKey(const ValueKey('ledger-plan-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1000');
    await tester.ensureVisible(find.text('保存预算'));
    await tester.tap(find.text('保存预算'));
    await tester.pumpAndSettle();

    expect(
      store.planFor(LedgerDates.monthKey(DateTime.now())).budgetCents,
      100000,
    );
    expect(find.textContaining('预算'), findsWidgets);

    // cici 栏可以正常打开，且切页动画后输入区仍在。
    await tester.tap(find.byKey(const ValueKey('ledger-tab-2')));
    await tester.pumpAndSettle();
    expect(find.text('看账、分析、代记账'), findsNothing);
    expect(find.text('可以这样问'), findsOneWidget);
    expect(find.text('这个月花超了吗'), findsOneWidget);
  });

  testWidgets('首页记账卡三档尺寸均不溢出', (tester) async {
    for (final size in const [Size(180, 96), Size(360, 144), Size(600, 200)]) {
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: const LedgerHomeCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '卡面 $size 溢出');
      expect(find.text('记账'), findsOneWidget);
    }
  });

  testWidgets('宽屏显示左侧导航，可从侧栏进入记一笔', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(const LedgerPage()));
    await tester.pumpAndSettle();
    expect(find.text('收支 · 预算 · 复盘'), findsOneWidget);

    // 页头操作组要右对齐，同时保留呼吸间距，不能贴死窗口边缘。
    final addRect = tester.getRect(
      find.byKey(const ValueKey('ledger-header-add')),
    );
    expect(1200 - addRect.right, inInclusiveRange(8, 28));

    await tester.tap(find.text('记一笔').first);
    await tester.pumpAndSettle();
    expect(find.text('记下来'), findsOneWidget);
  });

  testWidgets('截图识别草稿必须确认后才写入账本', (tester) async {
    tester.view.physicalSize = const Size(420, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final drafts = [
      LedgerDraft(
        kind: LedgerKind.expense,
        amountCents: 1850,
        categoryId: 'food',
        note: '瑞幸咖啡',
        occurredAt: now,
        confidence: .92,
      ),
    ];

    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showLedgerDraftsSheet(
                  context,
                  drafts: drafts,
                  source: LedgerSource.scan,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('确认账单'), findsOneWidget);
    expect(store.entries, isEmpty);

    await tester.tap(find.text('确认入账 1 笔'));
    await tester.pumpAndSettle();

    expect(store.entries.length, 1);
    expect(store.entries.single.amountCents, 1850);
    expect(store.entries.single.source, LedgerSource.scan);
  });
}
