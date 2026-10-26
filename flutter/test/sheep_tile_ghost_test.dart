import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gsheep.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => GameScaffold.liveEnabled = false);
  tearDown(() => GameScaffold.liveEnabled = true);

  testWidgets('picked tile leaves a fading ghost', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final tiles = <SheepTile>[
      SheepTile(id: 0, gx: 0, gy: 0, layer: 0, type: 0),
      SheepTile(id: 1, gx: 1, gy: 0, layer: 0, type: 1),
    ];
    var picked = 0;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: GameSheepView(
          tiles: tiles,
          onPick: (tile, geom) {
            tile.picked = true;
            picked++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('sheepTile0')));
    await tester.pump();
    expect(picked, 1);
    expect(find.byKey(const ValueKey<String>('sheepTile0')), findsNothing);
    expect(find.byKey(const ValueKey<String>('sheepGhost0')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey<String>('sheepGhost0')), findsNothing);
  });

  testWidgets('exposed tile in a blurred lower band still receives taps', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final tiles = <SheepTile>[
      SheepTile(id: 0, gx: 0, gy: 0, layer: 0, type: 0),
      SheepTile(id: 1, gx: 1, gy: 0, layer: 1, type: 1),
    ];
    var picked = 0;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: GameSheepView(
          tiles: tiles,
          onPick: (tile, geom) {
            tile.picked = true;
            picked++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('sheepTile0')));
    await tester.pump();
    expect(picked, 1);
    expect(find.byKey(const ValueKey<String>('sheepGhost0')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('locked tile does not spawn a ghost', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final tiles = <SheepTile>[
      SheepTile(id: 0, gx: 0, gy: 0, layer: 0, type: 0),
      SheepTile(id: 1, gx: 0.5, gy: 0, layer: 1, type: 1),
    ];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: GameSheepView(
          tiles: tiles,
          onPick: (tile, geom) => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(
      find.byKey(const ValueKey<String>('sheepTile0')),
    );
    await tester.tapAt(Offset(rect.left + 4, rect.center.dy));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('sheepGhost0')), findsNothing);
    expect(find.byKey(const ValueKey<String>('sheepTile0')), findsOneWidget);
  });
}
