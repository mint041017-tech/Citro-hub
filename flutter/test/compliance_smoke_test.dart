import 'package:citro/overlays/auth_modal.dart';
import 'package:citro/pages/legal_page.dart';
import 'package:citro/pages/me_page.dart';
import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/auth_form_kit.dart';
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

  testWidgets('login account auto-detects email', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? submittedAccount;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: AuthFormKit(
            login: (account, password) async {
              submittedAccount = account;
            },
            register: ({
              phone,
              email,
              required name,
              required password,
            }) async {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('auth-method-phone')), findsNothing);
    expect(find.byKey(const ValueKey('auth-method-email')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('auth-account')),
      'player@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'secret123',
    );
    await tester.tap(find.text('登录').last);
    await tester.pumpAndSettle();
    expect(submittedAccount, 'player@example.com');
  });

  testWidgets('register confirms password and submits temporary name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? submittedPhone;
    String? submittedName;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: AuthFormKit(
            initialMode: 'register',
            login: (account, password) async {},
            register: ({phone, email, required name, required password}) async {
              submittedPhone = phone;
              submittedName = name;
            },
          ),
        ),
      ),
    );

    expect(find.text('昵称'), findsNothing);
    expect(find.byKey(const ValueKey('auth-password-confirm')), findsOneWidget);
    final methodSelector = find.descendant(
      of: find.byKey(const ValueKey('auth-account')),
      matching: find.byKey(const ValueKey('auth-method-select')),
    );
    expect(methodSelector, findsOneWidget);
    expect(tester.getSize(methodSelector).height, lessThanOrEqualTo(48));
    final accountRect = tester.getRect(
      find.byKey(const ValueKey('auth-account')),
    );
    final selectorRect = tester.getRect(methodSelector);
    expect(accountRect.right - selectorRect.right, greaterThanOrEqualTo(4));

    await tester.tap(methodSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auth-method-option-email')));
    await tester.pumpAndSettle();
    expect(find.text('name@example.com'), findsOneWidget);

    await tester.tap(methodSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auth-method-option-phone')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('auth-account')),
      '13800138000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'secret123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-confirm')),
      'secret124',
    );
    await tester.tap(find.byKey(const ValueKey('auth-agree')));
    await tester.tap(find.text('创建账号'));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(submittedPhone, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('auth-password-confirm')),
      'secret123',
    );
    await tester.tap(find.text('创建账号'));
    await tester.pumpAndSettle();
    expect(submittedPhone, '13800138000');
    expect(submittedName, startsWith('新友'));
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

    // 注销入口现在排在用户协议之后，小屏上要先滚进视野才能点。
    await tester.ensureVisible(find.text('注销账号（永久删除）'));
    await tester.pumpAndSettle();
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
    await Prefs.setString('citro_checkin_days_v1_2026-10-24', '{}');
    await Prefs.setStringList(PrefKeys.playRecords, ['record']);
    await Prefs.setString(PrefKeys.checkinFortune, '{"x":1}');
    await Prefs.setBool(PrefKeys.notificationsEnabled, true);
    await Prefs.clearAccountData();
    expect(Prefs.getString(PrefKeys.token), isNull);
    expect(Prefs.getString('citro_checkin_days_v1_2026-10-24'), isNull);
    expect(Prefs.getStringList(PrefKeys.playRecords), isEmpty);
    expect(Prefs.getString(PrefKeys.checkinFortune), isNull);
    expect(Prefs.getBool(PrefKeys.notificationsEnabled, false), isTrue);
  });
}
