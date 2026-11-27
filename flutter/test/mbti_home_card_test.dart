import 'dart:io';

import 'package:citro/assessments/tests_hub_page.dart';
import 'package:citro/mbti/home_card.dart';
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
  routes: {
    '/tests': (_) => const TestsHubPage(),
    '/mbti': (_) => const MbtiPage(),
  },
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

  testWidgets('首页卡片：空状态显示引导并可进入测试', (tester) async {
    await tester.pumpWidget(
      _wrap(const SizedBox(width: 320, height: 150, child: MbtiHomeCard())),
    );
    await _settle(tester);

    expect(find.text('测试'), findsOneWidget);
    expect(find.text('两种测试，看见更完整的自己'), findsOneWidget);

    await tester.tap(find.byType(MbtiHomeCard));
    await _settle(tester);
    expect(find.text('16 型测试'), findsOneWidget);
    expect(find.text('十二系亲密关系'), findsOneWidget);

    // 关闭：与听隅一致的退回路径，页面收起后卡片仍在。
    await tester.tap(find.byIcon(Icons.close_rounded));
    await _settle(tester);
    expect(find.text('十二系亲密关系'), findsNothing);
    expect(find.text('测试'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('首页卡片：有历史时显示最近类型与昵称', (tester) async {
    final bank = await MbtiBank.load();
    TypeLibrary library = await TypeLibrary.load();
    final result = MbtiScoring.score(
      bank: bank,
      mode: MbtiMode.standard,
      answers: {
        for (final q in bank.questionsFor(MbtiMode.standard))
          q.id: q.keyed == 'right' ? 7 : 1,
      },
    );
    await MbtiStore.add(result);

    await tester.pumpWidget(
      _wrap(const SizedBox(width: 320, height: 150, child: MbtiHomeCard())),
    );
    await _settle(tester);

    final latest = MbtiStore.load().first;
    final content = library.byCode(latest.result.typeRaw)!;
    expect(find.textContaining(latest.result.typeRaw), findsOneWidget);
    expect(find.textContaining(content.name), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
