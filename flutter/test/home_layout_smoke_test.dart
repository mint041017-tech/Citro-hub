import 'package:citro/pages/home_page.dart';
import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/home_layout.dart';
import 'package:citro/widgets/home_entries.dart';
import 'package:citro/widgets/modal.dart';
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

  testWidgets('add sheet filters cards by category', (tester) async {
    tester.view.physicalSize = const Size(1032, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const key = HomeLayoutKey.widePortrait;
    final store = HomeLayoutStore.instance;
    store.reset(key);
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
    await tester.tap(find.byKey(const ValueKey('home-layout-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-content-open')));
    await tester.pumpAndSettle();

    // 默认「全部」：小游戏与工具分组都在，只渲染当前可见的内容。
    expect(find.text('全部'), findsWidgets);
    expect(find.text('常驻卡片'), findsWidgets);
    expect(find.text('小游戏'), findsWidgets);
    expect(find.text('驱动'), findsWidgets);
    expect(find.byKey(const ValueKey('add-game:g2048')), findsOneWidget);

    // 切到「工具」分类后，只剩工具条目。
    await tester.tap(find.text('工具').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-game:g2048')), findsNothing);
    expect(find.byKey(const ValueKey('add-res:tool:灵敏度')), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('添加卡片').first)).pop();
    await tester.pumpAndSettle();
    store.reset(key);
  });

  testWidgets('edit mode shows drag and resize affordances', (tester) async {
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
    expect(find.byKey(const ValueKey('home-layout-edit')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-layout-edit')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.text('拖顶部圆柄换位 · 右上角垃圾桶删除 · 右下角调大小'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full_rounded), findsWidgets);

    // 删除钮在卡片内部右上角，不再压到卡片边线。
    final cardRect = tester.getRect(find.byKey(const ValueKey('card-checkin')));
    final deleteRect = tester.getRect(
      find.byKey(const ValueKey('card-delete-checkin')),
    );
    expect(cardRect.contains(deleteRect.topLeft), isTrue);
    expect(cardRect.contains(deleteRect.bottomRight), isTrue);
    expect(deleteRect.right, greaterThan(cardRect.right - 48));
    expect(deleteRect.top, lessThan(cardRect.top + 48));
  });

  testWidgets('drag repositions and handle resizes', (tester) async {
    tester.view.physicalSize = const Size(1032, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const form = HomeLayoutKey.widePortrait;
    final store = HomeLayoutStore.instance;
    store.reset(form);
    // 清空右上角，给拖动留出明确的目标格。
    for (final id in [
      HomeCardId.tingyu,
      HomeCardId.fish,
      HomeCardId.quote,
      HomeCardId.cook,
      HomeCardId.weather,
      HomeCardId.calendar,
      HomeCardId.zodiac,
    ]) {
      store.setVisible(form, id, false);
    }
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
    await tester.tap(find.byKey(const ValueKey('home-layout-edit')));
    await tester.pump(const Duration(milliseconds: 350));

    const cell = (824 - 14 * 11) / 12 + 14;
    final cardCenter = tester.getCenter(
      find.byKey(const ValueKey('drag-checkin')),
    );
    final drag = await tester.startGesture(cardCenter);
    for (var i = 0; i < 8; i++) {
      await drag.moveBy(const Offset(cell, 0));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 400));
    final moved = store
        .slots(form)
        .firstWhere((s) => s.id == HomeCardId.checkin);
    expect(moved.col, greaterThan(5));
    expect(tester.takeException(), isNull);

    final handle = find.byIcon(Icons.open_in_full_rounded).first;
    final handleDrag = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 4; i++) {
      await handleDrag.moveBy(const Offset(0, 32));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await handleDrag.up();
    await tester.pump(const Duration(milliseconds: 400));
    final resized = store
        .slots(form)
        .firstWhere((s) => s.id == HomeCardId.checkin);
    expect(resized.h, greaterThan(moved.h));
    expect(tester.takeException(), isNull);
    store.reset(form);
  });

  testWidgets('edit delete button and add sheet work', (tester) async {
    tester.view.physicalSize = const Size(1032, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const key = HomeLayoutKey.widePortrait;
    final store = HomeLayoutStore.instance;
    store.reset(key);
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
    await tester.tap(find.byKey(const ValueKey('home-layout-edit')));
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byKey(const ValueKey('card-delete-checkin')));
    await tester.pump(const Duration(milliseconds: 400));
    // 删除需要二次确认，确认前卡片仍然在。
    expect(find.text('删除「打卡」卡片？'), findsOneWidget);
    expect(store.slots(key).any((s) => s.id == HomeCardId.checkin), isTrue);
    await tester.tap(find.widgetWithText(AccentButton, '删除'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.slots(key).any((s) => s.id == HomeCardId.checkin), isFalse);

    await tester.tap(find.byKey(const ValueKey('home-content-open')));
    await tester.pumpAndSettle();
    expect(find.text('添加卡片'), findsWidgets);
    expect(find.byKey(const ValueKey('add-checkin')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-checkin')));
    await tester.pumpAndSettle();
    expect(store.slots(key).any((s) => s.id == HomeCardId.checkin), isTrue);

    // 小游戏按条目出现在「添加卡片」里，点一下就能落到首页。
    expect(find.byKey(const ValueKey('add-game:g2048')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-game:g2048')));
    await tester.pumpAndSettle();
    expect(
      store.slots(key).any((s) => s.id == HomeCardId.game && s.item == 'g2048'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('添加卡片').first)).pop();
    await tester.pumpAndSettle();
  });
}
