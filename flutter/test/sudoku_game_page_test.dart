import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gsudoku.dart';
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
      ..gid = 'sudoku-test-device'
      ..guestName = '游客·测试';
    GameScaffold.liveEnabled = false;
  });

  tearDownAll(() {
    GameScaffold.liveEnabled = true;
  });

  testWidgets('mode select starts classic and renders the game shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: const GameSudokuPage(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('选一种数独'), findsOneWidget);

    await tester.tap(find.text('简单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('经典九宫'), findsOneWidget);
    expect(find.text('新游戏'), findsOneWidget);
    expect(find.text('错误'), findsOneWidget);
    expect(find.text('暂停'), findsOneWidget);

    await tester.tap(find.text('1').first);
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 对局页有 1s 计时器；测试结束前主动卸载，避免残留 timer。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
