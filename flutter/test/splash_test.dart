import 'package:citro/main.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: child,
  );

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(host(const SplashScreen()));
    await tester.pump();
  }

  testWidgets('landscape splash uses the wide artwork and no version', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpAt(tester, const Size(951, 669));
    expect(find.byKey(const ValueKey('splash-landscape')), findsOneWidget);
    expect(find.text('vdev'), findsNothing);
    expect(find.text('Citro'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('portrait splash keeps the portrait artwork and no version', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpAt(tester, const Size(466, 678));
    expect(find.byKey(const ValueKey('splash-portrait')), findsOneWidget);
    expect(find.text('vdev'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
