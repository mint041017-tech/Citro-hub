import 'package:citro/overlays/auth_modal.dart';
import 'package:citro/pages/legal_page.dart';
import 'package:citro/pages/me_page.dart';
import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'test-device'
      ..guestName = '游客·测试';
  });

  tearDown(() {
    AppState.instance.user = null;
  });

  Widget host(Widget child) => AppScope(
    state: AppState.instance,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCitroTheme(CitroColors.light),
      home: child,
    ),
  );

  testWidgets('register dialog requires agreement', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAuthModal(ctx, mode: 'register'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('我已阅读并同意'), findsOneWidget);
    expect(find.text('《用户协议》'), findsWidgets);
    expect(find.text('《隐私政策》'), findsWidgets);
  });

  testWidgets('privacy page renders key sections', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const LegalPage(doc: LegalDoc.privacy)));
    await tester.pumpAndSettle();
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.textContaining('注销账号'), findsWidgets);
    expect(find.textContaining('第三方 AI'), findsWidgets);
  });

  testWidgets('me page exposes deletion and legal entries', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AppState.instance.user = const User(name: '测试用户', profileDone: true);

    await tester.pumpWidget(host(const MePage()));
    await tester.pumpAndSettle();
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('注销账号（永久删除）'), findsOneWidget);

    await tester.tap(find.text('注销账号（永久删除）'));
    await tester.pumpAndSettle();
    expect(find.text('登录密码'), findsOneWidget);
    expect(find.text('永久注销'), findsOneWidget);
  });

  testWidgets('local block list persists and clears', (tester) async {
    await AppState.instance.blockUser('拉黑对象');
    expect(AppState.instance.isBlocked('拉黑对象'), isTrue);
    expect(Prefs.getStringList(PrefKeys.blockedUsers), contains('拉黑对象'));
    await AppState.instance.unblockUser('拉黑对象');
    expect(AppState.instance.isBlocked('拉黑对象'), isFalse);
    expect(Prefs.getStringList(PrefKeys.blockedUsers), isEmpty);
  });

  testWidgets('account data cleanup keeps device preferences', (tester) async {
    await Prefs.setString(PrefKeys.token, 'token');
    await Prefs.setString(PrefKeys.zodiacSign, 'aries');
    await Prefs.setString('citro_zodiac_ai_aries_2026-10-24', '{}');
    await Prefs.setStringList(PrefKeys.playRecords, ['record']);
    await Prefs.setString(PrefKeys.fishConfig, '{"x":1}');
    await Prefs.setBool(PrefKeys.notificationsEnabled, true);
    await Prefs.clearAccountData();
    expect(Prefs.getString(PrefKeys.token), isNull);
    expect(Prefs.getString(PrefKeys.zodiacSign), isNull);
    expect(Prefs.getString('citro_zodiac_ai_aries_2026-10-24'), isNull);
    expect(Prefs.getStringList(PrefKeys.playRecords), isEmpty);
    expect(Prefs.getString(PrefKeys.fishConfig), isNull);
    expect(Prefs.getBool(PrefKeys.notificationsEnabled, false), isTrue);
  });
}
