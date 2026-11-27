import 'package:citro/pages/home_page.dart';
import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/home_entries.dart';
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

  testWidgets('抽签与视野 live 作为资源卡渲染在首页', (tester) async {
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
    // 快捷工具栏已取消，玩法抽签 / 视野 live 以卡片形式留在首屏。
    expect(find.text('玩法抽签'), findsOneWidget);
    expect(find.text('视野live'), findsOneWidget);
    expect(find.byType(HomeResCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页没有布局编辑入口，也没有旧版快捷工具与便签', (tester) async {
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
    expect(find.byKey(const ValueKey('home-layout-edit')), findsNothing);
    expect(find.text('拖顶部圆柄换位 · 右上角垃圾桶删除 · 右下角调大小'), findsNothing);
    expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
    expect(find.text('快捷工具'), findsNothing);
    expect(find.text('便签'), findsNothing);
    expect(find.text('灵敏度'), findsNothing);
    expect(find.text('一起看'), findsNothing);
    expect(find.text('摸鱼日历'), findsNothing);
    expect(find.text('今日星象'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('下拉越界时内容回弹且背景图放大', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const HomePage(onSwitchTab: _noop)));
    await tester.pump(const Duration(milliseconds: 400));

    final scroll = find.byType(SingleChildScrollView);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.minScrollExtent, 0);
    expect(position.pixels, 0);

    // 从顶部继续往下拖：ClampingScrollPhysics 会硬停，Bouncing 会越界回弹。
    final gesture = await tester.startGesture(tester.getCenter(scroll));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(position.pixels, lessThan(0));
    // 越界量驱动背景等比缩放：Transform.scale 出现过放大。
    expect(_maxBackgroundScale(tester), greaterThan(1.0));

    await gesture.up();
    await tester.pumpAndSettle();
    // 松手后弹回原位。
    expect(position.pixels, 0);
    expect(tester.takeException(), isNull);
  });
}

/// 首页背景层当前的最大缩放比例（没有 Transform.scale 时返回 1）。
double _maxBackgroundScale(WidgetTester tester) {
  var scale = 1.0;
  for (final element in find.byType(Transform).evaluate()) {
    final transform = (element.widget as Transform).transform;
    final values = transform.storage;
    // 只认等比放大（x 轴缩放 > 1，且不是动画里的位移矩阵）。
    if (values[0] > scale && values[0] == values[5]) scale = values[0];
  }
  return scale;
}
