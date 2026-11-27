import 'dart:io';

import 'package:citro/kei/kei_page.dart';
import 'package:citro/kei/models.dart';
import 'package:citro/kei/scoring.dart';
import 'package:citro/kei/store.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap() => MaterialApp(
  theme: ThemeData(extensions: const [CitroSkin(CitroColors.light)]),
  home: const KeiPage(),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _pumpResult(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap());
  await _settle(tester);
  await tester.tap(find.textContaining('· 稳定率').first);
  await _settle(tester);
  expect(tester.takeException(), isNull);
  expect(find.text('画像与占比'), findsOneWidget);
  expect(find.text('五维与效度'), findsOneWidget);
  expect(find.text('关系动力学'), findsOneWidget);
  expect(find.text('主辅动力学解读'), findsOneWidget);
  expect(find.byType(CustomPaint), findsWidgets);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    KeiBank.debugRaw = await File('assets/kei/kei.json').readAsString();
    final bank = await KeiBank.load();
    final answers = [
      for (var i = 0; i < bank.questions.length; i++) ((i * 5 + 2) % 7) - 3,
    ];
    final result = KeiScoring.analyze(bank: bank, answers: answers);
    await KeiStore.add(result);
  });

  testWidgets('十二系结果：宽屏三 Tab 排版无溢出', (tester) async {
    await _pumpResult(tester, const Size(1280, 900));
    await tester.tap(find.text('五维与效度'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('成人依恋平面'), findsOneWidget);
    expect(find.text('测量效度审计'), findsOneWidget);
    expect(find.text('反义镜像一致性'), findsOneWidget);
    await tester.tap(find.text('关系动力学'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('低摩擦协同组合'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('十二系结果：窄屏排版无溢出', (tester) async {
    await _pumpResult(tester, const Size(375, 667));
    await tester.tap(find.text('五维与效度'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('成人依恋平面'), findsOneWidget);
    expect(find.text('测量效度审计'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
