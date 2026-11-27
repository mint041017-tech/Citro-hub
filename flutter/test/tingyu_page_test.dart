import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/tingyu/tingyu_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'tingyu-test-device'
      ..guestName = '游客·听隅'
      ..user = const User(name: '听隅测试', profileDone: true);
    Future<void> loadFont(String family, List<String> paths) async {
      final loader = FontLoader(family);
      for (final p in paths) {
        loader.addFont(rootBundle.load(p));
      }
      await loader.load();
    }

    final nook = FontLoader('NookUI')
      ..addFont(rootBundle.load('assets/tingyu/fonts/nook-ui.ttf'));
    await nook.load();
    await loadFont('RoundedCN', [
      'assets/fonts/rounded-400-app.ttf',
      'assets/fonts/rounded-400-app.ttf',
      'assets/fonts/rounded-700-app.ttf',
    ]);
    await loadFont('XiaolaiMono', ['assets/fonts/mono-app.ttf']);
  });

  Widget host() => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.darkColors),
    home: const TingyuPage(),
  );

  testWidgets('tingyu page renders in phone and desktop widths', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('听隅'), findsWidgets);
    expect(find.text('此刻'), findsWidgets);
    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('此刻'), findsWidgets);
    expect(find.byType(AppBar), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
