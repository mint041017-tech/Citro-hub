import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gjump.dart';
import 'package:citro/games/gpeng.dart';
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
      ..gid = 'test'
      ..guestName = '测试';
    GameScaffold.liveEnabled = false;
  });

  Widget host(Widget child) => AppScope(
    state: AppState.instance,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCitroTheme(CitroColors.light),
      home: child,
    ),
  );

  testWidgets('gjump ticker frames + press/release', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const GameJumpPage()));
    await tester.pump(const Duration(milliseconds: 320));
    expect(tester.takeException(), isNull);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GameJumpView).first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('gpeng ticker frames + drag', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const GamePengPage()));
    await tester.pump(const Duration(milliseconds: 320));
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(GamePengView).first, const Offset(48, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
