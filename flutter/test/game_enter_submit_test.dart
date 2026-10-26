import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gfeihua.dart';
import 'package:citro/games/gidiom.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget view) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildCitroTheme(CitroColors.light),
  home: view,
);

void main() {
  setUpAll(() => GameScaffold.liveEnabled = false);
  tearDownAll(() => GameScaffold.liveEnabled = true);

  testWidgets('idiom input sends Enter to the enter callback', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final input = TextEditingController();
    var enter = 0;
    var button = 0;
    await tester.pumpWidget(
      _host(
        GameIdiomView(
          phase: IdiomPhase.playing,
          input: input,
          need: 'long',
          onSubmit: () => button++,
          onEnter: () => enter++,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '龙凤呈祥');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(enter, 1);
    expect(button, 0);
    input.dispose();
  });

  testWidgets('feihua input sends Enter to the enter callback', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final input = TextEditingController();
    var enter = 0;
    var button = 0;
    await tester.pumpWidget(
      _host(
        GameFeihuaView(
          phase: FeihuaPhase.playing,
          input: input,
          ch: '月',
          onSubmit: () => button++,
          onEnter: () => enter++,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '举头望明月');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(enter, 1);
    expect(button, 0);
    input.dispose();
  });
}
