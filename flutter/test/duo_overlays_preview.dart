// 手动视觉基线：flutter test test/duo_overlays_preview.dart --update-goldens
import 'package:citro/overlays/ai_chat.dart';
import 'package:citro/overlays/cook_editor.dart';
import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/corner_guard.dart';
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
    'assets/fonts/noto-sc-400-app.otf',
    'assets/fonts/noto-sc-700-app.otf',
  ]);
}

void main() {
  const forms = <String, Size>{
    'closed': Size(466, 678),
    'open-portrait': Size(669, 951),
    'open-landscape': Size(951, 669),
  };

  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'duo-overlay-preview'
      ..guestName = '游客·Duo'
      ..user = const User(name: 'Duo 预览用户', profileDone: true);
  });

  Widget host() => AppScope(
    state: AppState.instance,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCitroTheme(CitroColors.light).copyWith(
        bottomSheetTheme: const BottomSheetThemeData(
          constraints: BoxConstraints(maxWidth: double.infinity),
        ),
      ),
      builder: (context, child) =>
          CitroDuoCornerGuard(child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => showAiChat(context),
                  child: const Text('AI'),
                ),
                TextButton(
                  onPressed: () => showFoodSheet(context, const []),
                  child: const Text('FOOD'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  for (final form in forms.entries) {
    testWidgets('duo overlay ${form.key}', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = form.value;
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(host());
      await tester.tap(find.text('AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('duo_preview/goldens/${form.key}_ai.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await tester.pumpWidget(host());
      await tester.tap(find.text('FOOD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('duo_preview/goldens/${form.key}_food.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
