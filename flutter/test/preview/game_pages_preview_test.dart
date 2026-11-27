// 游戏页整页视觉基线（按游戏逐个进程跑，避免测试进程内存被整批页面顶满）：
//   flutter test test/preview/game_pages_preview_test.dart \
//     --update-goldens --dart-define=GAME_KEY=g2048 --dart-define=SIZES=phone,landscape,desktop
//
// GAME_KEY 留空 = 跑全部游戏（可能因为内存死掉，建议逐个跑）。
import 'package:citro/games/game_loader.dart';
import 'package:citro/games/game_random.dart';
import 'package:citro/games/game_registry.dart';
import 'package:citro/games/game_ui.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/services/clock.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/home_background.dart';
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
    // 固定播种：所有游戏初始牌面 / 盘面确定性复现，整页 golden 不随随机种子漂移。
    GameRandom.debugSeed = 7;
    // 钉死背景时段图：空卡面时背景原本进程内随机四选一，横屏 / 桌面整页基线会随
    // 抽图漂移；测试专用，生产 debugTimeAsset 保持 null。phone 基线维持现状不钉。
    if (_sizeSpec != 'phone') {
      CitroAmbientBackground.debugTimeAsset = CitroTimeBackground.assets[1];
      // 冻结时钟：羊了个羊初始帧的用时原本读真实墙钟，跨进程 0.1s/0.4s 抖动；
      // 与背景图同一思路收口，测试专用。
      CitroClock.debugNow = DateTime(2026, 6, 18, 21, 30);
    }
  });

  tearDownAll(() {
    GameRandom.debugSeed = null;
    CitroAmbientBackground.debugTimeAsset = null;
    CitroClock.debugNow = null;
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
