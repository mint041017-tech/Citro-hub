import 'package:citro/games/game_ui.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildCitroTheme(CitroColors.light),
  home: Scaffold(body: child),
);

void main() {
  setUpAll(() => GameScaffold.liveEnabled = false);

  testWidgets('GameHover scales on mouse hover', (tester) async {
    await tester.pumpWidget(
      _host(
        const Center(
          child: GameHover(
            child: SizedBox(
              key: ValueKey<String>('hover-target'),
              width: 120,
              height: 42,
            ),
          ),
        ),
      ),
    );

    double scale() => tester
        .widget<AnimatedScale>(
          find.descendant(
            of: find.byType(GameHover),
            matching: find.byType(AnimatedScale),
          ),
        )
        .scale;

    expect(scale(), 1);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey<String>('hover-target'))),
    );
    await tester.pumpAndSettle();
    expect(scale(), 1.02);

    await gesture.moveTo(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(scale(), 1);
  });

  testWidgets('landscape hides GameRankAction', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        GameScaffold(
          gameKey: 'game-ui-test',
          title: '测试',
          showLive: false,
          actions: [
            GameActionButton(label: '重开', onTap: () {}),
            GameRankAction(
              child: GameActionButton(label: '排行榜', onTap: () {}),
            ),
          ],
          board: const SizedBox(width: 200, height: 200),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('重开'), findsOneWidget);
    expect(find.widgetWithText(GameActionButton, '排行榜'), findsNothing);
  });
}
