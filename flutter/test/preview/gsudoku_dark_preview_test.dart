import 'package:citro/games/sudoku/sudoku_mode_select.dart';
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
      'assets/fonts/rounded-500-app.ttf',
      'assets/fonts/rounded-700-app.ttf',
    ]);
    await _loadFont('XiaolaiMono', ['assets/fonts/mono-app.ttf']);
  });

  testWidgets('sudoku mode select is readable in dark theme', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.darkColors),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: SudokuModeSelect(
              onStart: (mode, difficulty) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gsudoku_mode_dark.png'),
    );
  });
}