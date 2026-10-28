import 'package:citro/games/game_ui.dart';
import 'package:citro/games/knockwater/knockwater_page.dart';
import 'package:citro/games/knockwater/sfx.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpSeconds(WidgetTester tester, double seconds) async {
  final frames = (seconds * 60).round();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUpAll(() {
    GameScaffold.liveEnabled = false;
    Sfx.testMode = true;
  });

  testWidgets('完整流程：入水 → 两次重叩 → 结算 → 下一关', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
    AppState.instance
      ..gid = 'knockwaterflow01'
      ..guestName = '游客·流程测试';
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: const KnockwaterPage(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('kw-start')));
    await _pumpSeconds(tester, 3.2);

    for (var i = 0; i < 2; i++) {
      final center = tester.getCenter(find.byKey(const ValueKey('kw-knock')));
      final gesture = await tester.startGesture(center);
      await _pumpSeconds(tester, 1.4);
      await gesture.up();
      await _pumpSeconds(tester, 4.2);
    }
    await _pumpSeconds(tester, 4.0);

    expect(find.byKey(const ValueKey('kw-end')), findsOneWidget);
    expect(find.text('湾心已满'), findsOneWidget);
    expect(find.text('下一关'), findsOneWidget);
    expect(Prefs.getStringList('kw_completed'), contains('1'));

    await tester.tap(find.byKey(const ValueKey('kw-next')));
    await _pumpSeconds(tester, 2.5);
    expect(KnockwaterPage.debugEngine!.levelIndex, 1);
    expect(find.text('第 2 关'), findsOneWidget);
    expect(find.text('听水'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
