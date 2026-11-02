import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
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
      ..gid = 'hero-test'
      ..guestName = '共享元素测试';
  });

  Widget host(Widget home, {bool reduce = false}) => AppScope(
    state: AppState.instance,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCitroTheme(CitroColors.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
    ),
  );

  testWidgets('hero flies between routes without errors', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Stack(
            children: [
              const Positioned(
                left: 20,
                top: 20,
                child: CitroHero(
                  tag: 'shared-card',
                  child: SizedBox(width: 60, height: 60),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: Center(
                          child: CitroHero(
                            tag: 'shared-card',
                            child: SizedBox(width: 220, height: 220),
                          ),
                        ),
                      ),
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
    expect(find.byType(CitroHero), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // 飞行期间不应抛异常（重复 tag、找不到目标等都会在这里炸）。
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    // 进场完成后旧路由离台，只剩目标路由里的 Hero。
    expect(find.byType(CitroHero), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion skips the hero wrapper', (tester) async {
    await tester.pumpWidget(
      host(
        const Center(
          child: CitroHero(
            tag: 'shared-card',
            child: SizedBox(width: 40, height: 40),
          ),
        ),
        reduce: true,
      ),
    );
    await tester.pump();
    expect(find.byType(Hero), findsNothing);
    expect(find.byType(CitroHero), findsOneWidget);
  });
}
