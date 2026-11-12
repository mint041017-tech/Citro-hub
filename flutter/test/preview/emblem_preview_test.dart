// 徽标视觉基线：flutter test test/preview/emblem_preview_test.dart --update-goldens
import 'package:citro/games/game_identity.dart';
import 'package:citro/widgets/game_emblem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _sheet(Brightness brightness) {
  final bg = brightness == Brightness.light
      ? const Color(0xFFFBF7EC)
      : const Color(0xFF191920);
  return Container(
    color: bg,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            for (final i in kGameIdentities)
              SizedBox(
                width: 92,
                height: 92,
                child: GameEmblem(identity: i, size: 88),
              ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('emblem sheet light', (tester) async {
    tester.view.physicalSize = const Size(560, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      home: Scaffold(body: _sheet(Brightness.light)),
    ));
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/emblem_sheet_light.png'),
    );
  });

  testWidgets('emblem sheet dark', (tester) async {
    tester.view.physicalSize = const Size(560, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(body: _sheet(Brightness.dark)),
    ));
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/emblem_sheet_dark.png'),
    );
  });
}
