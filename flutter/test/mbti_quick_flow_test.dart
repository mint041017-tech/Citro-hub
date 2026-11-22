import 'dart:io';

import 'package:citro/mbti/mbti_page.dart';
import 'package:citro/mbti/models.dart';
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

  testWidgets('完整版同选项：触发作答质量提示', (tester) async {
    final bank = await MbtiBank.load();
    await tester.pumpWidget(_wrap(const MbtiPage()));
    await _settle(tester);

    await tester.tap(find.text('开始测试'));
    await _settle(tester);
    expect(find.textContaining('第 1/24 组'), findsOneWidget);

    final qs = bank.questionsFor(MbtiMode.full);
    for (var g = 0; g < 24; g++) {
      final group = qs.sublist(g * 4, g * 4 + 4);
      for (final q in group) {
        await tester.ensureVisible(find.byKey(ValueKey('mbti-${q.id}-7')));
        await tester.tap(find.byKey(ValueKey('mbti-${q.id}-7')));
        await tester.pump();
      }
      final label = g == 23 ? '查看结果' : '下一组';
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await _settle(tester);
    }

    expect(find.textContaining('结果可能不够准'), findsOneWidget);
    final record = MbtiStore.load().first;
    expect(record.result.quality.straightLine, isTrue);
    expect(record.result.quality.fastFinish, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
