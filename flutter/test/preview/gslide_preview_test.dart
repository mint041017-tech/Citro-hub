import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gslide.dart';
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

  testWidgets('gslide render', (tester) async {
    GameScaffold.liveEnabled = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: const GameSlideView(
          size: 4,
          tiles: [13, 2, 15, 5, 10, 6, 12, 11, 8, 4, 14, 3, 9, 0, 1, 7],
          empty: 13,
          moves: 0,
          seconds: 0,
          bestSeconds: 0,
          diff: 'std',
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
      matchesGoldenFile('goldens/gslide.png'),
    );
  });
}
