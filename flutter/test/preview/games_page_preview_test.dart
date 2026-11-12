// 游戏页与游戏卡片的视觉基线：
//   flutter test test/preview/games_page_preview_test.dart --update-goldens
//
// 这个文件是游戏卡片 / 游戏页重设计的验收窗口：手机、双折屏、桌面三种宽度
// 各留一张整页 golden，改完设计后先更新 golden，再逐张打开对比。
import 'package:citro/games/game_ui.dart';
import 'package:citro/pages/games_page.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/home_entries.dart';
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
    'assets/fonts/rounded-500-app.ttf',
    'assets/fonts/rounded-700-app.ttf',
  ]);
  await load('XiaolaiMono', ['assets/fonts/mono-app.ttf']);
}

Widget _host(Widget child) => AppScope(
  state: AppState.instance,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: child,
  ),
);

Future<void> _capture(
  WidgetTester tester,
  Size size,
  Widget child,
  String golden,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(child));
  await tester.pump(const Duration(milliseconds: 450));
  expect(tester.takeException(), isNull, reason: golden);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(golden));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'games-page-preview'
      ..guestName = '视觉测试';
    GameScaffold.liveEnabled = false;
  });

  testWidgets('games page phone 390x844', (tester) async {
    await _capture(
      tester,
      const Size(390, 844),
      const GamesPage(),
      'goldens/games_page_phone.png',
    );
  });

  testWidgets('games page duo 669x951', (tester) async {
    await _capture(
      tester,
      const Size(669, 951),
      const GamesPage(),
      'goldens/games_page_duo.png',
    );
  });

  testWidgets('games page desktop 1280x800', (tester) async {
    await _capture(
      tester,
      const Size(1280, 800),
      const GamesPage(),
      'goldens/games_page_desktop.png',
    );
  });

  testWidgets('home game cards phone 390x844', (tester) async {
    await _capture(
      tester,
      const Size(390, 844),
      const Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: 168, child: HomeGameCard(gameKey: 'g2048')),
              SizedBox(height: 168, child: HomeGameCard(gameKey: 'gsheep')),
              SizedBox(height: 168, child: HomeGameCard(gameKey: 'gliquid')),
            ],
          ),
        ),
      ),
      'goldens/home_game_cards.png',
    );
  });
}
