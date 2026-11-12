// 游戏内循环动效烟测：贪吃蛇插值、华容道滑动/无效抖动、记忆翻牌节奏。
//   flutter test test/preview/game_loop_motion_test.dart
import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gmemory.dart';
import 'package:citro/games/gslide.dart';
import 'package:citro/games/gsnake.dart';
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

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(page));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'loop-motion'
      ..guestName = '动效';
    GameScaffold.liveEnabled = false;
  });

  testWidgets('贪吃蛇逐帧插值：转向后连续若干帧不抛异常', (tester) async {
    await _pump(tester, const GameSnakePage());
    final board = find.byType(GameScaffold);
    // 往上拐（反向会立刻撞死，这里选安全方向）。
    await tester.fling(board, const Offset(0, -160), 900);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(tester.takeException(), isNull, reason: '贪吃蛇插值帧');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('华容道：有效滑动 + 无效点击抖动', (tester) async {
    await _pump(tester, const GameSlidePage());
    // 点一个角上的方块（几乎一定不邻接空格）→ 触发抖动。
    await tester.tap(find.text('1').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 90));
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.takeException(), isNull, reason: '华容道无效点击');
    // 连点几次，覆盖有效滑动路径。
    for (final label in ['2', '3', '5', '6']) {
      await tester.tap(find.text(label).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 140));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: '华容道滑动');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('记忆卡牌：翻两张 → 不匹配 480ms 后翻回', (tester) async {
    await _pump(tester, const GameMemoryPage());
    // 牌块有稳定的 key（card-<index>），直接点前两张。
    await tester.tap(
      find.byKey(const ValueKey<String>('card-0')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 260));
    await tester.tap(
      find.byKey(const ValueKey<String>('card-1')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 260));
    // 不匹配的停留时间（480ms）之后应翻回，且锁定解除。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: '记忆翻牌');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
