import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gnono.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(rootBundle.load(p));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('RoundedCN', [
      'assets/fonts/rounded-400-app.ttf',
      'assets/fonts/rounded-400-app.ttf',
      'assets/fonts/rounded-700-app.ttf',
    ]);
    await _loadFont('XiaolaiMono', ['assets/fonts/mono-app.ttf']);
  });

  testWidgets('nonogram dark board keeps hints readable', (tester) async {
    GameScaffold.liveEnabled = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const rowHints = <List<int>>[
      [1, 1, 1, 2, 1],
      [3, 2],
      [3, 2, 1],
      [4, 2],
      [1, 4],
      [1, 1, 1, 1],
      [4, 2],
      [2, 1, 3],
      [1, 2, 1],
      [2, 2, 2],
    ];
    const colHints = <List<int>>[
      [1, 1, 1],
      [2, 1, 2],
      [1, 2, 3, 1],
      [3, 3],
      [2, 1, 1],
      [1, 1, 1, 1],
      [1, 1, 1, 1, 1],
      [3, 1, 4],
      [1, 3, 1, 1],
      [1, 3, 2],
    ];
    final grid = List<List<int>>.generate(10, (_) => List.filled(10, 0));
    final marks = List<List<int>>.generate(10, (_) => List.filled(10, 0));
    // 留几格已填 / 已标记，方便检查深色纸面上的三种墨色。
    grid[0][0] = 1;
    grid[0][1] = 1;
    grid[1][0] = 1;
    marks[0][3] = 1;
    marks[1][4] = 1;
    marks[2][5] = 1;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.darkColors),
        home: GameNonoView(
          diff: 'std',
          size: 10,
          grid: grid,
          marks: marks,
          rowHints: rowHints,
          colHints: colHints,
          seconds: 0,
          bestSeconds: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gnono_dark.png'),
    );
  });
}