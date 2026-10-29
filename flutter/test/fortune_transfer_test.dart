import 'dart:io';

import 'package:citro/overlays/fortune_sheet.dart';
import 'package:citro/services/ai.dart';
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

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'fortune-transfer-test'
      ..guestName = '游客·转运';
    AiService.goodDeedReviewer = ({required text, image}) async => (
      pass: true,
      reply: '嗯，这件事确实帮到了别人，转运机会给你。',
    );
  });

  tearDown(() {
    HttpOverrides.global = null;
    AiService.goodDeedReviewer = null;
  });

  testWidgets('bad fortune grants a transfer via CiCi and rerolls once', (
    tester,
  ) async {
    final today = _dayKey(DateTime.now());
    await Prefs.setString(PrefKeys.checkinFortune, '$today:7');
    await Prefs.setString(PrefKeys.checkinTransfer, null);
    await Prefs.setString(PrefKeys.checkinTransferUsed, null);

    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: Builder(
            builder: (context) => Scaffold(
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
    await tester.pumpAndSettle();

    expect(find.text('抽到下签了？还有一次转运机会'), findsOneWidget);
    await tester.ensureVisible(find.text('找 CiCi 分享好事 · 换一签'));
    await tester.tap(find.text('找 CiCi 分享好事 · 换一签'));
    await tester.pumpAndSettle();

    expect(find.textContaining('跟我说说你今天做的一件好事'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '今天帮室友带了早饭');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('转运机会已经到账'), findsOneWidget);
    expect(AppState.instance.fortuneTransferReady, isTrue);

    Navigator.of(tester.element(find.byType(TextField).first)).pop();
    await tester.pumpAndSettle();
    expect(find.text('转运 · 再抽一签'), findsOneWidget);

    HttpOverrides.global = _OfflineHttpOverrides();
    await tester.ensureVisible(find.text('转运 · 再抽一签'));
    await tester.tap(find.text('转运 · 再抽一签'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(AppState.instance.fortuneTransferUsed, isTrue);
    final raw = Prefs.getString(PrefKeys.checkinFortune) ?? '';
    expect(raw.endsWith(':6') || raw.endsWith(':7'), isFalse);
    expect(find.text('抽到下签了？还有一次转运机会'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('vague good deed is rejected without a transfer', (tester) async {
    final today = _dayKey(DateTime.now());
    await Prefs.setString(PrefKeys.checkinFortune, '$today:7');
    await Prefs.setString(PrefKeys.checkinTransfer, null);
    await Prefs.setString(PrefKeys.checkinTransferUsed, null);
    AiService.goodDeedReviewer = ({required text, image}) async => (
      pass: false,
      reply: '这件事还没看出实际帮到别人，再想想有没有具体的小事？',
    );

    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: Builder(
            builder: (context) => Scaffold(
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
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('找 CiCi 分享好事 · 换一签'));
    await tester.tap(find.text('找 CiCi 分享好事 · 换一签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '我今天给自己买了杯奶茶');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('还没看出实际帮到别人'), findsOneWidget);
    expect(find.textContaining('转运机会已经到账'), findsNothing);
    expect(AppState.instance.fortuneTransferReady, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
