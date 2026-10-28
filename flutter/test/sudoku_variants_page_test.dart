import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gsudoku.dart';
import 'package:citro/games/sudoku/sudoku_modes.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => AppScope(
  state: AppState.instance,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: child,
  ),
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'sudoku-variants-device'
      ..guestName = '游客·测试';
    GameScaffold.liveEnabled = false;
  });

  tearDownAll(() {
    GameScaffold.liveEnabled = true;
  });

  final cases = <String, String>{
    'jigsaw': '异形宫',
    'windmill': '共享 3×6 同数',
    'overlap-4': '共享格同数',
    'overlap-13': '共享格同数',
    'evenodd': '圆形',
    'diag': '主对角线',
    'ineq': '箭头',
    'killer': '浅色笼',
    'cube3d': '共享边',
  };

  for (final entry in cases.entries) {
    testWidgets('variant ${entry.key} renders', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final mode = sudokuModeByKey(entry.key);
      await tester.pumpWidget(
        _host(
          GameSudokuPage(
            initialModeKey: entry.key,
            initialDifficulty: mode.defaultDifficulty,
            initialSeed: 2026,
          ),
        ),
      );
      await tester.pump();
      try {
        for (var i = 0; i < 80; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('新游戏').evaluate().isNotEmpty) break;
        }
        expect(tester.takeException(), isNull);
        expect(find.text(mode.title), findsOneWidget);
        expect(find.textContaining(entry.value), findsWidgets);
        if (entry.key == 'cube3d') {
          expect(find.text('面'), findsOneWidget);
          expect(find.text('顶面'), findsOneWidget);
          expect(find.text('左面'), findsOneWidget);
          expect(find.text('右面'), findsOneWidget);
        }
        if (entry.key == 'overlap-13') {
          expect(find.text('盘'), findsOneWidget);
        }
      } finally {
        // 卸载页面，取消计时器/RefreshRate，避免并发测试间的“did not complete”。
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  }
}
