import 'package:citro/pages/games_page.dart';
import 'package:citro/pages/res_page.dart';
import 'package:citro/services/platform.dart' as platform;
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/tablet_shell.dart';
import 'package:citro/widgets/tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => AppScope(
  state: AppState.instance,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'windows-layout-test'
      ..guestName = '游客·Windows';
  });

  testWidgets('resource grid expands to three columns on wide desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        const CitroLayoutScope(
          contentWidth: 992,
          tabletNav: true,
          child: ResPage(embedded: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
    expect(find.text('首页'), findsOneWidget);
    expect(find.textContaining('Windows 桌面版'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resource grid stays two columns in a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        const CitroLayoutScope(
          contentWidth: 760,
          tabletNav: false,
          child: ResPage(embedded: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sidebar exposes the resource library', (tester) async {
    tester.view.physicalSize = const Size(208, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        CitroTabletSidebar(
          index: 3,
          showResources: true,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('资源库'), findsOneWidget);
    expect(find.text('全站搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('games page no longer embeds tool cards', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        const CitroLayoutScope(
          contentWidth: 992,
          tabletNav: true,
          child: GamesPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('记忆卡牌'), findsOneWidget);
    expect(find.text('小工具'), findsNothing);
    expect(find.text('图吧工具箱'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop tab bar exposes four destinations', (tester) async {
    if (!platform.isWindows) return;
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 800,
          height: 600,
          child: Stack(
            children: [CitroTabBar(index: 3, onChanged: _noop)],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    for (final label in ['首页', '游戏', '社区', '资源']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.takeException(), isNull);
  });
}

void _noop(int _) {}
