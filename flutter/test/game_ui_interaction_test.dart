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

  testWidgets('phone portrait moves readouts into the top bar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        GameScaffold(
          gameKey: 'gsudoku',
          title: '数独',
          showLive: false,
          showSidePanels: false,
          pills: const [
            GameScorePill(label: '错误', value: '0/5'),
            GameScorePill(label: '用时', value: '0:06'),
            GameScorePill(label: '最佳', value: '--'),
          ],
          actions: [GameActionButton(label: '新游戏', onTap: () {})],
          board: const SizedBox(width: 300, height: 300),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // HUD 卡整块收起，读数只出现在顶栏。
    expect(find.byType(GameScorePill), findsNothing);
    expect(find.text('错误'), findsOneWidget);
    expect(find.text('0/5'), findsOneWidget);
    expect(find.text('最佳'), findsOneWidget);
  });

  testWidgets('long title / wide values fall back below the title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        GameScaffold(
          gameKey: 'gslide',
          title: '数字华容道',
          showLive: false,
          showSidePanels: false,
          pills: const [
            GameScorePill(label: '步数', value: '123456'),
            GameScorePill(label: '用时', value: '99:59'),
            GameScorePill(label: '最佳', value: '123456'),
          ],
          board: const SizedBox(width: 300, height: 300),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('数字华容道'), findsOneWidget);
    expect(find.text('123456'), findsNWidgets(2));
  });
}
