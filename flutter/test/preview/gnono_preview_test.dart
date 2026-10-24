import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gnono.dart';
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

  testWidgets('gnono render', (tester) async {
    GameScaffold.liveEnabled = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 复刻 web 截图（#gnonoPage · 标准 10×10 · 0:00 · 全新题面）。
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

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
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
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/logo.webp'),
        tester.element(find.byType(MaterialApp)),
      );
    });
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gnono.png'),
    );
  });
}
