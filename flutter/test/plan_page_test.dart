import 'package:citro/pages/plan_page.dart';
import 'package:citro/services/models.dart';
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
      ..gid = 'plan-test'
      ..guestName = '测试'
      ..user = const User(name: '测试用户', profileDone: true);
  });

  for (final size in const [Size(390, 844), Size(824, 1194), Size(1200, 800)]) {
    testWidgets('plan page fits $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppScope(
          state: AppState.instance,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildCitroTheme(CitroColors.light),
            home: const PlanPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });
  }
}
