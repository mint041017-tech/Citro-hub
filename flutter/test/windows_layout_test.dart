import 'package:citro/pages/games_page.dart';
import 'package:citro/pages/res_page.dart';
import 'package:citro/services/platform.dart' as platform;
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/state/custom_tab.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/paper.dart';
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
    expect(find.textContaining('Windows 桌面'), findsNothing);
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

  testWidgets('desktop sidebar exposes the four destinations', (tester) async {
    tester.view.physicalSize = const Size(208, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        CitroTabletSidebar(
          index: 3,
          customModule: CustomTabModule.todo,
          onChanged: _noop,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('游戏'), findsOneWidget);
    expect(find.text('社区'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
    // 资源库已收进首页下拉负一屏，不再占侧栏一格。
    expect(find.text('资源库'), findsNothing);
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

  testWidgets('desktop tab bar exposes four destinations plus CICI', (
    tester,
  ) async {
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
            children: [
              CitroTabBar(
                index: 3,
                customModule: CustomTabModule.todo,
                onChanged: _noop,
                onCustomTabLongPress: _noopVoid,
                onCiciTap: _noopVoid,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final semantics = tester.ensureSemantics();
    for (final label in ['首页', '游戏', '社区', '待办', 'CICI 智能助手']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    // 文字直接画在玻璃条上，不再只靠 Semantics 暴露。
    expect(find.text('首页'), findsOneWidget);
    // 四格各一个图标；右侧 CICI 用的是头像图片，不是 AppIcon。
    expect(
      find.descendant(
        of: find.byType(CitroTabBar),
        matching: find.byType(AppIcon),
      ),
      findsNWidgets(4),
    );
    expect(
      find.descendant(
        of: find.byType(CitroTabBar),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}

void _noop(int _) {}
void _noopVoid() {}
