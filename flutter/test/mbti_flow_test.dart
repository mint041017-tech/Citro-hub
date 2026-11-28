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

/// 背景含循环动画，不能用 pumpAndSettle；用定时 pump 推进异步任务。
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

  Future<void> answerGroup(
    WidgetTester tester,
    List<MbtiQuestion> group,
    int value,
  ) async {
    for (final q in group) {
      await tester.ensureVisible(find.byKey(ValueKey('mbti-${q.id}-$value')));
      await tester.tap(find.byKey(ValueKey('mbti-${q.id}-$value')));
      await tester.pump();
    }
  }

  testWidgets('完整版全流程：全中立作答 → INFP + 贴线校准 + 分享卡片', (tester) async {
    final bank = await MbtiBank.load();
    await tester.pumpWidget(_wrap(const MbtiPage()));
    await _settle(tester);
    expect(find.text('16 型测试'), findsOneWidget);
    expect(find.text('MBTI 测试'), findsOneWidget);
    expect(find.textContaining('完整版'), findsNothing);
    expect(find.text('仅此一版'), findsNothing);

    await tester.tap(find.text('开始测试'));
    await _settle(tester);
    expect(find.textContaining('第 1/24 组'), findsOneWidget);

    final qs = bank.questionsFor(MbtiMode.full);
    for (var g = 0; g < 24; g++) {
      final group = qs.sublist(g * 4, g * 4 + 4);
      await answerGroup(tester, group, 4);
      final label = g == 23 ? '查看结果' : '下一组';
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await _settle(tester);
    }

    // 全中立：右端字母 INFP，维度全部贴线。
    expect(find.textContaining('INFP'), findsWidgets);
    expect(find.text('倾向不明显'), findsNWidgets(5));
    expect(find.text('最后一步：确认一下像不像你'), findsOneWidget);
    expect(find.text('你的专属人格切片'), findsOneWidget);
    expect(find.text('测量效度审计'), findsOneWidget);
    expect(find.text('题对镜像一致性'), findsOneWidget);
    expect(find.text('Longstring 连续同选'), findsOneWidget);
    expect(find.text('分享结果'), findsOneWidget);
    expect(find.text('你的优势'), findsOneWidget);

    final records = MbtiStore.load();
    expect(records, hasLength(1));
    expect(records.first.result.typeRaw, 'INFP');

    // 自评校准：把 EI 从 I 改为 E，类型应变为 ENFP。
    await tester.ensureVisible(find.text('不太像，我更偏 E · 外向'));
    await tester.tap(find.text('不太像，我更偏 E · 外向'));
    await _settle(tester);
    expect(find.textContaining('ENFP'), findsWidgets);
    expect(MbtiStore.load().first.typeConfirmed, 'ENFP');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
