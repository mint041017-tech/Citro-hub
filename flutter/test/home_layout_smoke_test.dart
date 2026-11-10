import 'package:citro/pages/home_page.dart';
import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/home_entries.dart';
import 'package:citro/widgets/home_layout.dart';
import 'package:citro/widgets/negative_screen.dart';
import 'package:citro/widgets/tablet_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _noop(int _) {}

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
    expect(
      find.text('拖顶部圆柄换位 · 右上角垃圾桶删除 · 右下角调大小'),
      findsNothing,
    );
    expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull-down reveals the negative screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const HomePage(onSwitchTab: _noop)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(NegativeScreen), findsNothing);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 320),
    );
    await tester.pump();
    expect(find.byType(NegativeScreen), findsOneWidget);
    expect(find.text('资源库 · 小工具'), findsOneWidget);
    expect(find.text('游戏 Mod'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
