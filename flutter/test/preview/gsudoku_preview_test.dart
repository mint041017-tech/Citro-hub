import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gsudoku.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(rootBundle.load(p));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await loadFont('Kalam', [
      'assets/fonts/kalam-400-app.ttf',
      'assets/fonts/kalam-700-app.ttf',
    ]);
    await loadFont('ZCOOL', ['assets/fonts/zcool-app.ttf']);
    await loadFont('Caveat', ['assets/fonts/caveat-app.ttf']);
    await loadFont('NotoSC', [
      'assets/fonts/noto-sc-400-app.otf',
      'assets/fonts/noto-sc-700-app.otf',
    ]);
  });

  testWidgets('gsudoku render', (tester) async {
    GameScaffold.liveEnabled = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 复刻 web 截图（#gsudokuPage · 中等 · 0:23 · 错误 0/5）
    const board = <int>[
      6, 0, 1, 9, 7, 0, 3, 0, 4, //
      4, 0, 0, 0, 1, 0, 0, 0, 9, //
      7, 0, 0, 5, 0, 0, 6, 0, 0, //
      9, 0, 5, 0, 0, 0, 0, 0, 0, //
      8, 0, 6, 0, 4, 0, 7, 5, 0, //
      3, 4, 0, 1, 0, 0, 0, 0, 6, //
      0, 3, 9, 8, 6, 7, 0, 4, 0, //
      1, 0, 4, 0, 5, 0, 0, 6, 0, //
      5, 0, 0, 0, 0, 0, 2, 0, 0, //
    ];
    final given = [for (final v in board) v != 0];
    final notes = List<Set<int>>.generate(81, (_) => <int>{});

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: GameSudokuView(
          diff: 'med',
          board: board,
          given: given,
          notes: notes,
          solution: board,
          errors: 0,
          seconds: 23,
          bestSeconds: 0,
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/logo.webp'),
        tester.element(find.byType(MaterialApp)),
      );
    });
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gsudoku.png'),
    );
  });
}
