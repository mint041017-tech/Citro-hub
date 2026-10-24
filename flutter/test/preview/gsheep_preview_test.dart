import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gsheep.dart';
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

/// 第 1 关的固定盘面（与 web 参考图一致：3 行底牌 + 中间一层 3 张）。
List<SheepTile> _previewTiles() => <SheepTile>[
  SheepTile(id: 0, gx: 0, gy: 0, layer: 0, type: 1),
  SheepTile(id: 1, gx: 1, gy: 0, layer: 0, type: 2),
  SheepTile(id: 2, gx: 2, gy: 0, layer: 0, type: 2),
  SheepTile(id: 3, gx: 0, gy: 1, layer: 0, type: 0),
  SheepTile(id: 4, gx: 1, gy: 1, layer: 0, type: 0),
  SheepTile(id: 5, gx: 2, gy: 1, layer: 0, type: 0),
  SheepTile(id: 6, gx: 0, gy: 2, layer: 0, type: 0),
  SheepTile(id: 7, gx: 1, gy: 2, layer: 0, type: 0),
  SheepTile(id: 8, gx: 2, gy: 2, layer: 0, type: 0),
  SheepTile(id: 9, gx: 0.5, gy: 1.5, layer: 1, type: 1),
  SheepTile(id: 10, gx: 1.5, gy: 1.5, layer: 1, type: 1),
  SheepTile(id: 11, gx: 2.5, gy: 1.5, layer: 1, type: 2),
];

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

  testWidgets('gsheep render', (tester) async {
    GameScaffold.liveEnabled = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: GameSheepView(
          tiles: _previewTiles(),
          levelText: '1 / 2',
          timeText: '3.8s',
          bestText: '--',
          shuffleLeft: 2,
          undoLeft: 3,
          removeLeft: 1,
          shuffleEnabled: true,
          undoEnabled: false,
          removeEnabled: false,
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
      matchesGoldenFile('goldens/gsheep.png'),
    );
  });
}
