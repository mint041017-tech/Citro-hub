import 'package:citro/pages/web_home.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'web-desktop-test'
      ..guestName = '游客·桌面';
  });

  Future<void> pumpToolsRow(WidgetTester tester, double width) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = Size(width, 180);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: const Scaffold(body: WebGameToolsRow()),
        ),
      ),
    );
    await tester.pump();
  }

  for (final width in <double>[700, 480]) {
    testWidgets('desktop game tools row fits at ${width.toInt()}px', (
      tester,
    ) async {
      await pumpToolsRow(tester, width);

      expect(find.text('玩法抽签'), findsOneWidget);
      expect(find.text('瞬投'), findsOneWidget);
      expect(find.text('屏幕分享'), findsOneWidget);
      expect(find.text('视野live'), findsOneWidget);
      expect(find.text('下载站'), findsOneWidget);
      expect(find.text('官方'), findsOneWidget);
      expect(find.text('App、Mod 与工具下载 · 官方直链'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
