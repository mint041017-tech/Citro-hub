import 'dart:io';

import 'package:citro/checkin/checkin_store.dart';
import 'package:citro/overlays/fortune_sheet.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('offline');
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'fortune-layout-preview'
      ..guestName = '游客·预览';
  });

  tearDown(() {
    HttpOverrides.global = null;
    CheckinStore.instance.resetForTest();
  });

  testWidgets('wide fortune layout preview', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    HttpOverrides.global = _OfflineHttpOverrides();
    final today = DateTime.now();
    final day =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await Prefs.setString(PrefKeys.checkinFortune, '$day:7:guest');

    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: Builder(
            builder: (context) => Scaffold(
              backgroundColor: const Color(0xFFE8E2D5),
              body: Center(
                child: TextButton(
                  onPressed: () => showFortuneOverlay(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1500));

    expect(tester.takeException(), isNull);
    expect(find.text('今日小事'), findsOneWidget);
    expect(find.text('今日一小步'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CheckinStore.instance.resetForTest();
  });

  testWidgets('phone fortune pages preview', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    HttpOverrides.global = _OfflineHttpOverrides();
    final today = DateTime.now();
    final day =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await Prefs.setString(PrefKeys.checkinFortune, '$day:7:guest');

    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: Builder(
            builder: (context) => Scaffold(
              backgroundColor: const Color(0xFFE8E2D5),
              body: Center(
                child: TextButton(
                  onPressed: () => showFortuneOverlay(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 2000));

    expect(tester.takeException(), isNull);
    expect(find.text('签文'), findsOneWidget);
    expect(find.text('今日小事'), findsOneWidget);
    await tester.tap(find.text('今日小事'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('今日一小步'), findsOneWidget);
    expect(find.text('晚间回签'), findsOneWidget);
    expect(find.text('抽到下签了？还有一次转运机会'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CheckinStore.instance.resetForTest();
  });
}
