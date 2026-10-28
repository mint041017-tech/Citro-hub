import 'package:citro/games/game_ui.dart';
import 'package:citro/games/knockwater/knockwater_page.dart';
import 'package:citro/games/knockwater/sfx.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The generic smoke test builds every game repeatedly in one test. 铃渡 has a
/// continuous water Ticker, so its viewport matrix is covered one size per
/// test here instead; each case still builds and disposes the real page.
void main() {
  setUpAll(() {
    GameScaffold.liveEnabled = false;
    Sfx.testMode = true;
  });

  tearDownAll(() {
    GameScaffold.liveEnabled = true;
    Sfx.testMode = false;
  });

  const sizes = <String, Size>{
    'iphone': Size(390, 844),
    'duo-outer': Size(466, 678),
    'duo-inner': Size(669, 951),
    'duo-inner-landscape': Size(951, 669),
    'ipad-portrait': Size(1024, 1366),
    'ipad-landscape': Size(1366, 1024),
    'ipad-half': Size(678, 1024),
    'ipad-third': Size(478, 1024),
  };

  for (final entry in sizes.entries) {
    testWidgets('铃渡 layout ${entry.key}', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: const KnockwaterPage(),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      final board = tester.getRect(find.byKey(const ValueKey('kw-board')));
      expect(board.left, greaterThanOrEqualTo(0), reason: entry.key);
      expect(board.right, lessThanOrEqualTo(entry.value.width), reason: entry.key);
      expect(board.top, greaterThanOrEqualTo(0), reason: entry.key);
      expect(board.bottom, lessThanOrEqualTo(entry.value.height), reason: entry.key);
      expect(tester.takeException(), isNull, reason: entry.key);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
