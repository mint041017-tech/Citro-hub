// 手动视觉基线：flutter test test/duo_games_preview_test.dart --update-goldens
import 'package:citro/games/game_loader.dart';
import 'package:citro/games/game_random.dart';
import 'package:citro/games/game_ui.dart';
import 'package:citro/services/clock.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(rootBundle.load(p));
    }
    await loader.load();
  }

  await load('RoundedCN', [
    'assets/fonts/rounded-400-app.ttf',
    'assets/fonts/rounded-400-app.ttf',
    'assets/fonts/rounded-700-app.ttf',
  ]);
  await load('XiaolaiMono', ['assets/fonts/mono-app.ttf']);
}

void main() {
  const forms = <String, Size>{
    'closed': Size(466, 678),
    'open-portrait': Size(669, 951),
    'open-landscape': Size(951, 669),
  };
  const games = ['g2048', 'gnono', 'gsudoku', 'gpeng', 'gsheep', 'gsnake'];

  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance.gid = 'duo-games-preview';
    GameScaffold.liveEnabled = false;
    // 固定播种：与 game_pages_preview_test 一致，让各游戏初始牌面 / 盘面确定性
    // 复现，整页 golden 不随随机种子漂移。
    GameRandom.debugSeed = 7;
    // 钉死时钟：与 duo_preview_test 同一固定时刻，避免按时段 / 日期轮换的内容漂移。
    CitroClock.debugNow = DateTime(2026, 6, 18, 21, 30);
  });

  tearDownAll(() {
    GameRandom.debugSeed = null;
    CitroClock.debugNow = null;
  });

  for (final form in forms.entries) {
    testWidgets('duo games ${form.key}', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = form.value;
      tester.view.devicePixelRatio = 1;
      for (final key in games) {
        await tester.pumpWidget(
          AppScope(
            state: AppState.instance,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildCitroTheme(CitroColors.light),
              home: buildGamePage(key),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('duo_preview/goldens/${form.key}_$key.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }
}
