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

void main() {
  setUpAll(() {
    GameScaffold.liveEnabled = false;
    Sfx.testMode = true;
  });

  testWidgets('继续会恢复局内稳定检查点', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('kw-start')));
    await _pumpSeconds(tester, 3.2);

    final first = KnockwaterPage.debugEngine!;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _pumpSeconds(tester, 3.5);
    expect(progress.hasCheckpoint, isTrue);
    final cx = first.cellX;
    final cy = first.cellY;
    final charges = first.charges;

    // 卸载后用同一 ProgressStore 重新进入，标题应显示「继 续」。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCitroTheme(CitroColors.light),
        home: KnockwaterPage(key: UniqueKey(), progress: progress),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('继 续'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kw-start')));
    await _pumpSeconds(tester, 3.2);

    final restored = KnockwaterPage.debugEngine!;
    expect(restored.cellX, cx);
    expect(restored.cellY, cy);
    expect(restored.charges, charges);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
