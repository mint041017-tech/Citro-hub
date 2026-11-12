// 2048 合并动效：滑动 / 合并 / 幽灵块清理 / 无效滑动抖动。
//   flutter test test/preview/g2048_motion_test.dart
import 'package:citro/games/game_ui.dart';
import 'package:citro/games/g2048.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(rootBundle.load(p));
    }
    await loader.load();
  }

  await load('RoundedCN', [
    'assets/fonts/rounded-400-app.ttf',
    'assets/fonts/rounded-500-app.ttf',
    'assets/fonts/rounded-700-app.ttf',
  ]);
  await load('XiaolaiMono', ['assets/fonts/mono-app.ttf']);
}

Widget _host(Widget child) => AppScope(
  state: AppState.instance,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: child,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'g2048-motion'
      ..guestName = '动效';
    GameScaffold.liveEnabled = false;
  });

  testWidgets('连续滑动 + 合并后棋盘保持一致', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const Game2048Page()));
    await tester.pump();

    final board = find.byType(GameScaffold);
    for (final d in const [
      Offset(-220, 0),
      Offset(220, 0),
      Offset(0, -220),
      Offset(0, 220),
      Offset(-220, 0),
      Offset(0, 220),
    ]) {
      await tester.drag(board, d);
      // 幽灵块清理（200ms）与飘分（720ms）都要跑完。
      await tester.pump(const Duration(milliseconds: 260));
    }
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull, reason: '连续滑动后棋盘状态应保持一致');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('合并瞬间：幽灵块滑入 + 飘分（中段帧）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        const Game2048View(
          score: 128,
          best: 256,
          tiles: {
            1: (value: 64, index: 0, pop: true, spawn: false, ghost: false),
            2: (value: 64, index: 0, pop: false, spawn: false, ghost: true),
            3: (value: 2, index: 5, pop: false, spawn: false, ghost: false),
            4: (value: 2, index: 9, pop: false, spawn: true, ghost: false),
          },
          floats: [(index: 0, delta: 128)],
        ),
      ),
    );
    // 只走 80ms：滑动与飘分都在半途，幽灵块还没完全淡出。
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/g2048_merge_mid.png'),
    );
  });
}
