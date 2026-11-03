import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gsudoku.dart';
import 'package:citro/games/sudoku/sudoku_resume.dart';
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

  testWidgets('system back returns to mode select instead of leaving sudoku', (
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
    await tester.tap(find.text('简单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('新游戏'), findsOneWidget);

    // 系统返回：应回到模式选择，而不是退出整个数独页面。
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('选一种数独'), findsOneWidget);
    expect(find.text('新游戏'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('paused game survives back navigation and resumes within 2h', (
    tester,
  ) async {
    await SudokuResumeStore.clear();
    // 竖屏手机底部 tab bar 会盖住 HUD 的暂停按钮，这里用平板尺寸验证流程。
    tester.view.physicalSize = const Size(1200, 900);
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
    await tester.tap(find.text('简单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('新游戏'), findsOneWidget);

    // 暂停后系统返回：不弹“放弃进度”，回模式页并留下“继续上一局”。
    await tester.tap(find.text('暂停'));
    await tester.pump();
    expect(find.text('继续游戏'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('选一种数独'), findsOneWidget);
    expect(find.text('继续上一局'), findsOneWidget);
    expect(find.text('新游戏'), findsNothing);

    // 从存档恢复：题目与计时都回到暂停态，需要手动点“继续游戏”。
    await tester.tap(find.text('继续'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('新游戏'), findsOneWidget);
    expect(find.text('继续游戏'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
