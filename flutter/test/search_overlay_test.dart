import 'package:citro/services/prefs.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/global_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('search suggestions sit below and align with the field', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCitroTheme(CitroColors.light),
        home: const Scaffold(
          body: Center(
            child: SizedBox(width: 520, child: GlobalSearch(hint: '搜索')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(TextField));
    final panel = tester.getRect(
      find.byKey(const ValueKey('globalSearchPanel')),
    );
    expect(panel.left, closeTo(field.left, 1));
    expect(panel.width, closeTo(field.width, 1));
    expect(panel.top, greaterThanOrEqualTo(field.bottom));
    expect(panel.bottom, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });
}
