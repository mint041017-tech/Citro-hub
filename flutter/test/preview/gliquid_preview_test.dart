import 'dart:math' as math;

import 'package:citro/games/gliquid.dart';
import 'package:citro/games/gliquid_game.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(rootBundle.load(path));
  }
  await loader.load();
}

LiquidGame _midGame(double width, double height, {int seed = 42}) {
  final game = LiquidGame(
    layout: LiquidLayout.compute(width, height, topInset: 96),
    random: math.Random(seed),
  );
  game.start();
  final bot = math.Random(seed + 9);
  var shots = 0;
  var elapsed = 0.0;
  while (shots < 55 && elapsed < 90) {
    if (game.phase == LiquidPhase.playing && game.cooldown == 0) {
      final aim = (bot.nextDouble() - .5) * 1.1;
      final power = 0.4 + bot.nextDouble() * 0.5;
      if (game.launchAt(aim, power)) shots++;
    }
    game.step(1 / 60);
    elapsed += 1 / 60;
  }
  for (var i = 0; i < 90; i++) {
    game.step(1 / 60);
  }
  game.overflowTime = 0;
  game.overflowWarned = false;
  game.shake = 0;
  game.hintVisible = false;
  game.charging = false;
  game.power = 0;
  game.cooldown = 0;
  game.aim = 0.12;
  game.floats.clear();
  game.effects.clear();
  game.ghosts.clear();
  return game;
}

void main() {
  setUpAll(() async {
    await _loadFont('Kalam', [
      'assets/fonts/kalam-400-app.ttf',
      'assets/fonts/kalam-700-app.ttf',
    ]);
    await _loadFont('ZCOOL', ['assets/fonts/zcool-app.ttf']);
    await _loadFont('Caveat', ['assets/fonts/caveat-app.ttf']);
    await _loadFont('NotoSC', [
      'assets/fonts/noto-sc-400-app.otf',
      'assets/fonts/noto-sc-700-app.otf',
    ]);
  });

  testWidgets('gliquid phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = _midGame(390, 844);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: Scaffold(
          body: GameLiquidView(game: game, best: 98765, interactive: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gliquid.png'),
    );
  });

  testWidgets('gliquid intro', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = LiquidGame(
      layout: LiquidLayout.compute(390, 844, topInset: 96),
      random: math.Random(8),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: Scaffold(
          body: GameLiquidView(game: game, best: 98765, interactive: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gliquid_intro.png'),
    );
  });

  testWidgets('gliquid over', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = _midGame(390, 844, seed: 6);
    game.phase = LiquidPhase.over;
    game.score = 42890;
    game.shots = 87;
    game.maxLevel = 13;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: Scaffold(
          body: GameLiquidView(
            game: game,
            best: 98765,
            newBest: true,
            interactive: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gliquid_over.png'),
    );
  });

  testWidgets('gliquid desktop', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = _midGame(1280, 800, seed: 77);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: Scaffold(
          body: GameLiquidView(game: game, best: 98765, interactive: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/gliquid_desktop.png'),
    );
  });
}
