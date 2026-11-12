// 游戏页整页视觉基线（按游戏逐个进程跑，避免测试进程内存被整批页面顶满）：
//   flutter test test/preview/game_pages_preview_test.dart \
//     --update-goldens --dart-define=GAME_KEY=g2048 --dart-define=SIZES=phone,landscape,desktop
//
// GAME_KEY 留空 = 跑全部游戏（可能因为内存死掉，建议逐个跑）。
import 'package:citro/games/game_loader.dart';
import 'package:citro/games/game_registry.dart';
import 'package:citro/games/game_ui.dart';
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

const _gameKey = String.fromEnvironment('GAME_KEY', defaultValue: '');
const _sizeSpec = String.fromEnvironment('SIZES', defaultValue: 'phone');

Map<String, Size> _parseSizes() {
  const all = <String, Size>{
    'phone': Size(390, 844),
    'landscape': Size(844, 390),
    'desktop': Size(1200, 760),
  };
  final wanted = _sizeSpec.split(',').map((s) => s.trim()).toSet();
  return Map.fromEntries(
    all.entries.where((e) => wanted.contains(e.key)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'game-pages-preview'
      ..guestName = '视觉测试';
    GameScaffold.liveEnabled = false;
  });

  for (final size in _parseSizes().entries) {
    for (final game in kGameCards) {
      if (_gameKey.isNotEmpty && game.key != _gameKey) continue;
      // gbrake 内嵌 WebView，测试环境没有平台实现，交给 gbrake_preview_test。
      if (game.key == 'gbrake') continue;
      testWidgets('${game.key} ${size.key}', (tester) async {
        addTearDown(tester.view.reset);
        tester.view.physicalSize = size.value;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          AppScope(
            state: AppState.instance,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildCitroTheme(CitroColors.light),
              home: buildGamePage(game.key),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 450));
        final exception = tester.takeException();
        expect(exception, isNull, reason: '${game.key} ${size.key}');
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/pages/${game.key}_${size.key}.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
