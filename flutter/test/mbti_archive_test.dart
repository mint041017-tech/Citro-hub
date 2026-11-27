import 'dart:io';

import 'package:citro/mbti/mbti_page.dart';
import 'package:citro/mbti/models.dart';
import 'package:citro/mbti/scoring.dart';
import 'package:citro/mbti/store.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(extensions: const [CitroSkin(CitroColors.light)]),
  home: child,
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    MbtiBank.debugRaw = await File('assets/mbti/questions.json').readAsString();
    TypeLibrary.debugRaw = await File('assets/mbti/types.json').readAsString();
  });

  testWidgets('测试档案内联展示并可打开历史报告', (tester) async {
    final bank = await MbtiBank.load();
    final library = await TypeLibrary.load();
    final result = MbtiScoring.score(
      bank: bank,
      mode: MbtiMode.standard,
      answers: {
        for (final q in bank.questionsFor(MbtiMode.standard))
          q.id: q.keyed == 'right' ? 7 : 1,
      },
    );
    await MbtiStore.add(result);

    await tester.pumpWidget(_wrap(const MbtiPage()));
    await _settle(tester);

    expect(find.text('16 型测试'), findsOneWidget);
    expect(find.text('MBTI 测试'), findsOneWidget);
    expect(find.text('测试档案'), findsOneWidget);
    expect(find.text('1 次 · 云端同步'), findsOneWidget);

    final latest = MbtiStore.load().first;
    final content = library.byCode(latest.result.typeRaw)!;
    final label = find.textContaining(latest.result.typeRaw).first;
    await tester.ensureVisible(label);
    await tester.tap(label);
    await _settle(tester);

    expect(find.textContaining(content.name), findsWidgets);
    expect(find.text('分享结果'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
