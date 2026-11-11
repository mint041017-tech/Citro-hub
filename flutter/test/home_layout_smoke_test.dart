import 'package:citro/pages/home_page.dart';
import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/home_entries.dart';
import 'package:citro/widgets/home_layout.dart';
import 'package:citro/widgets/tablet_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _noop(int _) {}

/// 首页整体下移的距离，用来判断抽屉有没有被拉开。
double _drawerShift(WidgetTester tester) {
  final t = tester.widget<Transform>(
    find.byKey(const ValueKey('home-drawer-shift')),
  );
  return t.transform.getTranslation().y;
}

Widget _host(Widget child) => AppScope(
  state: AppState.instance,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: child,
  ),
);

Future<void> _pumpHome(
  WidgetTester tester,
  Size size, {
  double? contentWidth,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final page = contentWidth == null
      ? const HomePage(onSwitchTab: _noop)
      : CitroLayoutScope(
          contentWidth: contentWidth,
          tabletNav: true,
          child: const HomePage(onSwitchTab: _noop),
        );
  await tester.pumpWidget(_host(page));
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull, reason: 'home at $size');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'home-bento-test'
      ..guestName = '布局测试'
      ..user = const User(name: '布局测试用户', profileDone: true);
  });

  testWidgets('phone home fits 390x844', (tester) async {
    await _pumpHome(tester, const Size(390, 844));
  });

  testWidgets('duo home fits 669x951', (tester) async {
    await _pumpHome(tester, const Size(669, 951));
  });

  testWidgets('ipad portrait home fits 824x1366', (tester) async {
    await _pumpHome(tester, const Size(1032, 1366), contentWidth: 824);
  });

  testWidgets('windows home fits 1200x800', (tester) async {
    await _pumpHome(tester, const Size(1208, 800), contentWidth: 1000);
  });

  testWidgets('game and resource cards render on home', (tester) async {
    tester.view.physicalSize = const Size(1032, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const key = HomeLayoutKey.widePortrait;
    final store = HomeLayoutStore.instance;
    store.reset(key);
    expect(store.available(key).any((o) => o.id == HomeCardId.game), isTrue);
    expect(store.available(key).any((o) => o.id == HomeCardId.res), isTrue);
    expect(store.add(key, HomeCardId.game, item: 'g2048'), isTrue);
    expect(store.add(key, HomeCardId.res, item: 'tool:灵敏度'), isTrue);
    expect(
      store.slots(key).any((s) => s.id == HomeCardId.game && s.item == 'g2048'),
      isTrue,
    );
    expect(
      store
          .slots(key)
          .any((s) => s.id == HomeCardId.res && s.item == 'tool:灵敏度'),
      isTrue,
    );
    await tester.pumpWidget(
      _host(
        const CitroLayoutScope(
          contentWidth: 824,
          tabletNav: true,
          child: HomePage(onSwitchTab: _noop),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HomeGameCard), findsOneWidget);
    expect(find.byType(HomeResCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    store.reset(key);
  });

  testWidgets('home uses the fixed layout without edit affordances', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1032, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        const CitroLayoutScope(
          contentWidth: 824,
          tabletNav: true,
          child: HomePage(onSwitchTab: _noop),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // 固定布局：不再有编辑入口、拖拽圆柄和添加卡片面板。
    expect(find.byKey(const ValueKey('home-layout-edit')), findsNothing);
    expect(find.text('拖顶部圆柄换位 · 右上角垃圾桶删除 · 右下角调大小'), findsNothing);
    expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero pull-down reveals the negative screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const HomePage(onSwitchTab: _noop)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_drawerShift(tester), 0);

    // 在上半屏（背景图区域）往下拖，首页整体跟着走，抽屉从下面露出来。
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 260),
    );
    await tester.pump();
    expect(_drawerShift(tester), greaterThan(0));
    await tester.pumpAndSettle();
    expect(_drawerShift(tester), greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull-down reveals the negative screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const HomePage(onSwitchTab: _noop)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_drawerShift(tester), 0);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 320));
    await tester.pump();
    expect(_drawerShift(tester), greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.text('快捷工具'), findsOneWidget);
    expect(find.text('灵敏度'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe up anywhere closes the negative screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const HomePage(onSwitchTab: _noop)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_drawerShift(tester), 0);

    // 先下拉把抽屉拉开。
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 320));
    await tester.pumpAndSettle();
    expect(_drawerShift(tester), greaterThan(0));

    // 抽屉开着时，在首页任意位置（这里取下半屏）上滑都把它推回去。
    final gesture = await tester.startGesture(const Offset(195, 700));
    await gesture.moveBy(const Offset(0, -240));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_drawerShift(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('negative screen follows the finger and snaps open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const HomePage(onSwitchTab: _noop)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_drawerShift(tester), 0);

    // 下拉 100px：抽屉跟手走 1:1（封顶在抽屉高度）。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SingleChildScrollView)),
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    final follow = _drawerShift(tester);
    expect(follow, greaterThan(0));
    expect(follow, lessThanOrEqualTo(100));

    // 继续下拉越过自动弹开点（带阻尼，实际行程更短）。
    await gesture.moveBy(const Offset(0, 400));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_drawerShift(tester), greaterThan(200));
    expect(tester.takeException(), isNull);
  });
}
