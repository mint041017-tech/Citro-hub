import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/motion.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/shared_element.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'hero-flight-test'
      ..guestName = '飞行测试';
  });

  Widget host(Widget home) => AppScope(
    state: AppState.instance,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCitroTheme(CitroColors.light),
      home: home,
    ),
  );

  testWidgets('hero really flies on a transparent page route', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Stack(
            children: [
              const Positioned(
                left: 16,
                bottom: 16,
                child: CitroHero(
                  tag: 'avatar',
                  child: SizedBox(width: 38, height: 38),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    PageRouteBuilder<void>(
                      opaque: false,
                      barrierColor: const Color(0x8A23211C),
                      barrierDismissible: true,
                      transitionDuration: CitroMotion.modal,
                      pageBuilder: (_, __, ___) => const Center(
                        child: CitroHero(
                          tag: 'avatar',
                          key: ValueKey('dest-hero'),
                          child: SizedBox(
                            key: ValueKey('dest-child'),
                            width: 120,
                            height: 120,
                          ),
                        ),
                      ),
                      transitionsBuilder: (ctx, animation, _, child) =>
                          FadeTransition(opacity: animation, child: child),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    CitroHero.debugFlightCount = 0;
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // 飞行中，shuttle 里会再渲染一份目标 child（不算 offstage）。
    expect(CitroHero.debugFlightCount, greaterThan(0));
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
