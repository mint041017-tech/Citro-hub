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

  testWidgets('landscape splash keeps the brand block', (tester) async {
    addTearDown(tester.view.reset);
    await pumpAt(tester, const Size(951, 669));
    expect(find.text('今天也要开心'), findsOneWidget);
    expect(find.text('Citro'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('portrait splash keeps the brand block', (tester) async {
    addTearDown(tester.view.reset);
    await pumpAt(tester, const Size(466, 678));
    expect(find.text('今天也要开心'), findsOneWidget);
    expect(find.text('Citro'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
