import 'package:citro/games/game_ui.dart';
import 'package:citro/games/knockwater/knockwater_page.dart';
import 'package:citro/games/knockwater/painter.dart';
import 'package:citro/games/knockwater/progress.dart';
import 'package:citro/games/knockwater/sfx.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _enterFirstLevel(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('kw-start')));
  await tester.pump();
  await _pumpFrames(tester, 200);
}

void main() {
  setUpAll(() {
    GameScaffold.liveEnabled = false;
    Sfx.testMode = true;
  });

  testWidgets('空闲 1 秒：水面继续重绘，页面与 HUD 都不重建', (tester) async {
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

    KnockwaterPage.debugBuildCount = 0;
    KnockwaterPage.debugHudBuildCount = 0;
    PondPainter.debugPaintCount = 0;
    await _pumpFrames(tester, 60);

    expect(KnockwaterPage.debugBuildCount, 0, reason: '逐帧 Ticker 不应触发整页 setState');
    expect(KnockwaterPage.debugHudBuildCount, 0, reason: 'HUD 快照未变化时不应重建');
    expect(PondPainter.debugPaintCount, greaterThan(0), reason: '水面必须继续按帧重绘');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('走步只更新 HUD 快照，不触发整页重建', (tester) async {
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

    KnockwaterPage.debugBuildCount = 0;
    KnockwaterPage.debugHudBuildCount = 0;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 60));

    expect(KnockwaterPage.debugHudBuildCount, greaterThan(0));
    expect(KnockwaterPage.debugBuildCount, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
