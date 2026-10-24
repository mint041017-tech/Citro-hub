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

  testWidgets('smoke render', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '2048 游戏空间',
                  style: const TextStyle(
                    fontFamily: 'Kalam',
                    fontSize: 32,
                    color: Color(0xFF23211C),
                  ),
                ),
                Text(
                  '记忆卡牌 · 数独 · 数织',
                  style: const TextStyle(
                    fontFamily: 'ZCOOL',
                    fontSize: 22,
                    color: Color(0xFF23211C),
                  ),
                ),
                Text(
                  '正在玩 · 还没有人在玩',
                  style: const TextStyle(
                    fontFamily: 'NotoSC',
                    fontSize: 13,
                    color: Color(0xFF6E6858),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/smoke.png'),
    );
  });
}
