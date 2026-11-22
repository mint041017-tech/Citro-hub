import 'dart:io';

import 'package:citro/mbti/mbti_page.dart';
import 'package:citro/mbti/models.dart';
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

  testWidgets('图鉴入口与类型详情可打开', (tester) async {
    await MbtiBank.load();
    await TypeLibrary.load();
    await tester.pumpWidget(_wrap(const MbtiPage()));
    await _settle(tester);
    expect(find.text('MBTI 测试'), findsOneWidget);

    await tester.tap(find.text('16 型图鉴'));
    await _settle(tester);
    expect(find.text('没有好坏的类型，只有不同的默认设置。'), findsOneWidget);
    expect(find.text('INTJ'), findsOneWidget);

    await tester.tap(find.text('INTJ'));
    await _settle(tester);
    expect(find.textContaining('布局者'), findsWidgets);
    expect(find.text('你的内在工作方式（进阶）'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
