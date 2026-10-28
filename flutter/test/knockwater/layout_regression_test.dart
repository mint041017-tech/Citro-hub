import 'package:citro/games/game_ui.dart';
import 'package:citro/games/knockwater/knockwater_page.dart';
import 'package:citro/games/knockwater/sfx.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host() => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildCitroTheme(CitroColors.light),
  home: const KnockwaterPage(),
);

Future<void> _pumpPage(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host());
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  setUpAll(() {
    GameScaffold.liveEnabled = false;
    Sfx.testMode = true;
  });

  testWidgets('390×844 board stays above live bar', (tester) async {
    await _pumpPage(tester, const Size(390, 844));
    final board = tester.getRect(find.byKey(const ValueKey('kw-board')));
    final live = tester.getRect(find.byType(GameLiveBar));
    expect(board.left, greaterThanOrEqualTo(0));
    expect(board.right, lessThanOrEqualTo(390));
    expect(board.top, greaterThanOrEqualTo(0));
    expect(board.bottom, lessThanOrEqualTo(live.top));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('1280×800 and 1440×1000 boards stay in viewport',
      (tester) async {
    for (final size in <Size>[
      const Size(1280, 800),
      const Size(1440, 1000),
    ]) {
      await _pumpPage(tester, size);
      final board = tester.getRect(find.byKey(const ValueKey('kw-board')));
      expect(board.left, greaterThanOrEqualTo(0), reason: '$size');
      expect(board.right, lessThanOrEqualTo(size.width), reason: '$size');
      expect(board.top, greaterThanOrEqualTo(0), reason: '$size');
      expect(board.bottom, lessThanOrEqualTo(size.height), reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
