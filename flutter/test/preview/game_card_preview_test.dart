// 游戏卡视觉基线：flutter test test/preview/game_card_preview_test.dart --update-goldens
import 'package:citro/games/game_identity.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/game_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(rootBundle.load(p));
    }
    await loader.load();
  }

  await load('Kalam', [
    'assets/fonts/kalam-400-app.ttf',
    'assets/fonts/kalam-700-app.ttf',
  ]);
  await load('ZCOOL', ['assets/fonts/zcool-app.ttf']);
  await load('Caveat', ['assets/fonts/caveat-app.ttf']);
  await load('NotoSC', [
    'assets/fonts/noto-sc-400-app.ttf',
    'assets/fonts/noto-sc-700-app.ttf',
  ]);
}

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildCitroTheme(CitroColors.light),
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  testWidgets('grid cards phone 390', (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: .78,
              ),
              itemCount: kGameIdentities.length,
              itemBuilder: (_, i) =>
                  GameCard(identity: kGameIdentities[i]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/game_cards_grid.png'),
    );
  });

  testWidgets('grid cards desktop 7 columns', (tester) async {
    tester.view.physicalSize = const Size(1280, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: .82,
              ),
              itemCount: kGameIdentities.length,
              itemBuilder: (_, i) =>
                  GameCard(identity: kGameIdentities[i], compact: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/game_cards_grid_wide.png'),
    );
  });

  testWidgets('banner cards', (tester) async {
    tester.view.physicalSize = const Size(390, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final i in kGameIdentities.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GameBannerCard(identity: i, height: 120),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/game_cards_banner.png'),
    );
  });
}
