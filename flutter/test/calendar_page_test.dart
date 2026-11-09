import 'package:citro/calendar/calendar_page.dart';
import 'package:citro/calendar/calendar_store.dart';
import 'package:citro/pages/home_page.dart';
import 'package:citro/routes.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/utils/lunar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => AppScope(
  state: AppState.instance,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: child,
    onGenerateRoute: CitroRoutes.onGenerateRoute,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    CalendarStore.instance.resetForTest();
    await CalendarStore.instance.ensureInit();
  });

  testWidgets('迷你日历卡只显示今天，不铺整月网格', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    await tester.pumpWidget(
      _host(
        Center(
          child: SizedBox(width: 170, height: 164, child: const CalendarCard()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final lunar = lunarOf(now);
    final lunarDay = lunar == null ? '' : kLunarDayNames[lunar.day - 1];
    final yearMonth =
        '${now.year}/${now.month.toString().padLeft(2, '0')}'
        '${lunarDay.isEmpty ? '' : ' · $lunarDay'}';
    expect(find.text(yearMonth), findsOneWidget);
    expect(find.text('${now.day}'), findsOneWidget);
    // 农历放在顶部年月行，事件卡里不再重复「农历」字样。
    expect(find.textContaining('农历'), findsNothing);
    // 整月网格才有的星期表头不应出现。
    expect(find.text('日'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击日历卡进入日历详情页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        Center(
          child: SizedBox(width: 300, height: 320, child: const CalendarCard()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(CalendarCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('倒数日 & 纪念日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日历详情页窄屏可以正常渲染', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const CalendarPage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('日历'), findsOneWidget);
    expect(find.text('倒数日 & 纪念日'), findsOneWidget);
    expect(find.text('记录一个日子'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日历详情页宽屏双栏可以正常渲染', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const CalendarPage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('日历'), findsOneWidget);
    expect(find.text('倒数日 & 纪念日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新增弹层可以保存一个倒数日', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const CalendarPage()));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('添加倒数日或纪念日'));
    await tester.pumpAndSettle();
    expect(find.text('记录一个日子'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '出发去大理');
    await tester.pump();
    await tester.tap(find.text('添加'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(CalendarStore.instance.count, 1);
    expect(find.text('出发去大理'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
