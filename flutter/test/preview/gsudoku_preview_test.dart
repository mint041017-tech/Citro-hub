import 'package:citro/games/sudoku/sudoku_mode_select.dart';
import 'package:citro/games/sudoku/sudoku_modes.dart';
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

  testWidgets('sudoku mode select renders all groups', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final started = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: SudokuModeSelect(
              onStart: (mode, difficulty) {
                started.add('${mode.key}:${difficulty.key}');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('选一种数独'), findsOneWidget);
    expect(find.text('经典九宫'), findsOneWidget);
    expect(find.text('九宫异形'), findsOneWidget);
    expect(find.text('风车数独'), findsOneWidget);
    expect(find.text('双重叠'), findsOneWidget);
    expect(find.text('十三重叠'), findsOneWidget);
    expect(find.text('奇偶数独'), findsOneWidget);
    expect(find.text('3D 数独'), findsOneWidget);

    await tester.tap(find.text('困难').first);
    await tester.pump();
    expect(started, isNotEmpty);
  });
}
