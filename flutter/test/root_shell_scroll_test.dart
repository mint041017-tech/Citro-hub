import 'package:citro/pages/root_shell.dart';
import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首页滚动位置。每次重新找，避免页面被重建后还读到旧的 position。
double _homeOffset(WidgetTester tester) {
  final scrollable = find
      .descendant(
        of: find.byKey(const ValueKey('home-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  return tester.state<ScrollableState>(scrollable).position.pixels;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'root-shell-scroll-test'
      ..guestName = '滚动测试'
      ..user = const User(name: '滚动测试用户', profileDone: true);
  });

  testWidgets('预热后台 Tab 不会重建首页、不会把滚动拉回顶部', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: const RootShell(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -300),
    );
    await tester.pump();
    final scrolled = _homeOffset(tester);
    expect(scrolled, greaterThan(150), reason: '首页应当能正常滚动');

    // 启动后 1.2s / 2.0s / 2.8s 依次预热计划 / 游戏 / 社区页。
    // 这三页会插到首页前面，若页面层没有稳定 key，首页会被整棵重建。
    await tester.pump(const Duration(milliseconds: 1250));
    expect(_homeOffset(tester), scrolled, reason: '预热计划页后首页滚动位置不应变化');
    await tester.pump(const Duration(milliseconds: 800));
    expect(_homeOffset(tester), scrolled, reason: '预热游戏页后首页滚动位置不应变化');
    await tester.pump(const Duration(milliseconds: 800));
    expect(_homeOffset(tester), scrolled, reason: '预热社区页后首页滚动位置不应变化');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
