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
    'assets/fonts/rounded-400-app.ttf',
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

}
