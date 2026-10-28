import 'package:citro/games/game_ui.dart';
import 'package:citro/games/knockwater/knockwater_page.dart';
import 'package:citro/games/knockwater/progress.dart';
import 'package:citro/games/knockwater/sfx.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpSeconds(WidgetTester tester, double seconds) async {
  final frames = (seconds * 60).round();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _enterFirstLevel(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('kw-start')));
  await _pumpSeconds(tester, 3.2);
}

void main() {
  setUpAll(() {
    GameScaffold.liveEnabled = false;
    Sfx.testMode = true;
  });

  testWidgets('键盘 Q/E/C/V 可以走斜向', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final progress = ProgressStore.memory();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCitroTheme(CitroColors.light),
        home: KnockwaterPage(progress: progress),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _enterFirstLevel(tester);

    final e = KnockwaterPage.debugEngine!;
    expect(e.cellX, 3);
    expect(e.cellY, 13);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();
    expect(e.cellX, 2);
    expect(e.cellY, 12);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('键盘 W+A 组合走斜向', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final progress = ProgressStore.memory();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCitroTheme(CitroColors.light),
        home: KnockwaterPage(progress: progress),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _enterFirstLevel(tester);

    final e = KnockwaterPage.debugEngine!;
    expect(e.cellX, 3);
    expect(e.cellY, 13);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.pump(const Duration(milliseconds: 60));
    expect(e.cellX, 2);
    expect(e.cellY, 12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('真实拖动可以走出斜向一步', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final progress = ProgressStore.memory();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCitroTheme(CitroColors.light),
        home: KnockwaterPage(progress: progress),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await _enterFirstLevel(tester);

    final e = KnockwaterPage.debugEngine!;
    expect(e.cellX, 3);
    expect(e.cellY, 13);
    final center = tester.getCenter(find.byKey(const ValueKey('kw-board')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(50, -50));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(e.cellX, 4, reason: '斜向拖动应走 NE 一格');
    expect(e.cellY, 12, reason: '斜向拖动应走 NE 一格');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
