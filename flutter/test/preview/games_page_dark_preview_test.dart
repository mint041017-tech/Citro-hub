import 'package:citro/pages/games_page.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/games/game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) { loader.addFont(rootBundle.load(p)); }
    await loader.load();
  }
  await load('RoundedCN', [
    'assets/fonts/rounded-400-app.ttf',
    'assets/fonts/rounded-500-app.ttf',
    'assets/fonts/rounded-700-app.ttf',
  ]);
  await load('XiaolaiMono', ['assets/fonts/mono-app.ttf']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance..gid = 'dark-check'..guestName = '暗色';
    GameScaffold.liveEnabled = false;
  });
  testWidgets('dark games page + page', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      state: AppState.instance,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.darkColors),
        home: const GamesPage(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/dark_games_page.png'));
  });
}
