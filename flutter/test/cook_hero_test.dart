import 'package:citro/pages/cook_page.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/cover_flight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'cook-hero-test'
      ..guestName = '测试';
  });

  testWidgets('cover flight grows between two rects over the overlay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext host;
    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                host = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(coverFlightKey), findsNothing);

    final flying = CitroCoverFlight.fly(
      host,
      from: const Rect.fromLTWH(20, 120, 96, 96),
      to: const Rect.fromLTWH(14, 40, 402, 226),
      child: const ColoredBox(color: Color(0xFFFFF3C4)),
    );
    await tester.pump();
    expect(find.byKey(coverFlightKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 400));
    await flying;
    expect(find.byKey(coverFlightKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cook page still opens with a plain route', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(name: 'cook'),
                      builder: (_) => const CookPage(),
                    ),
                  ),
                  child: const SizedBox(
                    width: 200,
                    height: 160,
                    child: ColoredBox(color: Color(0xFFFFF3C4)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CookPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
