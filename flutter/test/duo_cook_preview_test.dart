// 手动视觉基线：flutter test test/duo_cook_preview_test.dart --update-goldens
import 'package:citro/pages/cook_page.dart';
import 'package:citro/services/clock.dart';
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

  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'duo-cook-preview'
      ..guestName = '游客·Duo'
      ..user = const User(name: 'Duo 预览用户', profileDone: true);
    // 钉死时钟：与 duo_preview_test 同一固定时刻，避免按时段 / 日期轮换的内容漂移。
    CitroClock.debugNow = DateTime(2026, 6, 18, 21, 30);
  });

  tearDownAll(() {
    CitroClock.debugNow = null;
  });

  for (final form in forms.entries) {
    testWidgets('duo cook ${form.key}', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = form.value;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        AppScope(
          state: AppState.instance,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildCitroTheme(CitroColors.light),
            builder: (context, child) =>
                CitroDuoCornerGuard(child: child ?? const SizedBox.shrink()),
            home: const CookPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('duo_preview/goldens/${form.key}_cook.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
