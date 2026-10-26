import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/windows_title_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('titlebar shows Citro brand and exposes window controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCitroTheme(CitroColors.darkColors),
        builder: (context, child) => Column(
          children: [
            const Material(
              type: MaterialType.transparency,
              child: CitroWindowTitleBar(height: 38),
            ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
        home: const Scaffold(backgroundColor: Colors.black),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('迟暮'), findsNothing);
    expect(find.text('Citro'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '最小化',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '关闭',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
