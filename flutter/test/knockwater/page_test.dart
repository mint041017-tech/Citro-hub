import 'package:citro/games/game_registry.dart';
import 'package:citro/games/game_ui.dart';
import 'package:citro/games/knockwater/knockwater_page.dart';
import 'package:citro/games/knockwater/sfx.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/global_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 铃渡页面级测试：标题 / 入口、选关锁定、撤销 / 重开、输入方向、HUD 快照，
/// 以及 390×844、1280×800、800×600 三种窗口下的布局。
///
/// 页面里有一个常驻 Ticker（水面动画），因此不能用 pumpAndSettle；
/// 统一用固定时长的 pump，并在每个用例结束把页面卸载以取消计时器。
void main() {
  setUpAll(() {
    GameScaffold.liveEnabled = false;
    Sfx.testMode = true;
  });

  tearDownAll(() {
    GameScaffold.liveEnabled = true;
    Sfx.testMode = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Sfx.muted = false;
    KnockwaterPage.debugEngine = null;
    KnockwaterPage.debugHud = null;
    KnockwaterPage.debugLive = '';
    KnockwaterPage.debugTitleVisible = true;
  });

  Widget host() => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: const KnockwaterPage(),
  );

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    // ProgressStore.load 是异步的；多 pump 几帧让标题按钮就绪。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> startFirstLevel(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('kw-start')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(KnockwaterPage.debugTitleVisible, isFalse);
    expect(KnockwaterPage.debugEngine, isNotNull);
  }

  group('入口与标题', () {
    test('游戏卡片进入注册表', () {
      final card = kGameCards.singleWhere((g) => g.key == 'gknockwater');
      expect(card.title, '铃渡');
      expect(kGameCards.length, greaterThan(1));
    });

    testWidgets('390×844：标准骨架、标题与「入 水」入口', (tester) async {
      await pumpPage(tester);

      expect(find.byType(GameScaffold), findsOneWidget);
      // 服务端约束：正在玩用 gknockwater，榜单/结算用 knockwater。
      final scaffold = tester.widget<GameScaffold>(find.byType(GameScaffold));
      expect(scaffold.gameKey, 'gknockwater');
      expect(scaffold.rankGame, 'knockwater');
      expect(scaffold.liveProgress, isNotNull);
      expect(find.text('游戏空间'), findsOneWidget);
      expect(find.byKey(const ValueKey('kw-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('kw-start')), findsOneWidget);
      expect(find.text('入 水'), findsOneWidget);
      expect(find.text('铃渡'), findsWidgets);
      // 标准动作区必须是骨架提供的排行榜入口。
      expect(find.byKey(const ValueKey('kw-rank')), findsOneWidget);
      expect(find.text('排行榜'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await disposePage(tester);
    });

    testWidgets('排行榜入口打开标准榜单组件', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await Prefs.init();
      AppState.instance
        ..gid = 'knockwater-rank-test'
        ..guestName = '游客·榜单测试';
      await pumpPage(tester);

      await tester.tap(find.byKey(const ValueKey('kw-rank')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('铃渡 · 全站排行'), findsOneWidget);

      await disposePage(tester);
    });

    testWidgets('1280×800：宽屏走 iPad 侧栏与正在玩条', (tester) async {
      await pumpPage(tester, size: const Size(1280, 800));

      expect(find.text('正在玩'), findsOneWidget);
      // 侧栏榜单标题 + 标准动作按钮。
      expect(find.text('排行榜'), findsWidgets);
      expect(find.byKey(const ValueKey('kw-start')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await disposePage(tester);
    });

    testWidgets('800×600：水面板不超出视口', (tester) async {
      await pumpPage(tester, size: const Size(800, 600));

      final board = tester.getRect(find.byKey(const ValueKey('kw-board')));
      expect(board.left, greaterThanOrEqualTo(0));
      expect(board.right, lessThanOrEqualTo(800));
      expect(board.top, greaterThanOrEqualTo(0));
      expect(board.bottom, lessThanOrEqualTo(600));
      // 短窗口使用紧凑标题：入口按钮完整落在水面板里，不靠裁切。
      final start = tester.getRect(find.byKey(const ValueKey('kw-start')));
      expect(start.top, greaterThanOrEqualTo(board.top));
      expect(start.bottom, lessThanOrEqualTo(board.bottom));
      expect(find.textContaining('拖动水面行走'), findsNothing);
      expect(tester.takeException(), isNull);

      await disposePage(tester);
    });

    testWidgets('800×600：提示条不压住关内 HUD', (tester) async {
      await pumpPage(tester, size: const Size(800, 600));
      await startFirstLevel(tester);
      // 让 1.9s 入场结束，提示条显示。
      for (var i = 0; i < 130; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final hint = tester.getRect(find.byKey(const ValueKey('kw-hint')));
      final petals = tester.getRect(find.text('花瓣'));
      final charges = tester.getRect(find.text('铃息'));
      expect(hint.top, greaterThanOrEqualTo(petals.bottom));
      expect(hint.top, greaterThanOrEqualTo(charges.bottom));
      expect(tester.takeException(), isNull);
      await disposePage(tester);
    });

    testWidgets('800×600：结算卡完整落在水面板内', (tester) async {
      await pumpPage(tester, size: const Size(800, 600));
      await startFirstLevel(tester);

      final engine = KnockwaterPage.debugEngine!;
      for (final p in engine.petals) {
        p.stranded = true;
      }
      engine.advance(1.0);
      engine.endDelay = 0;
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('kw-end')), findsOneWidget);

      final board = tester.getRect(find.byKey(const ValueKey('kw-board')));
      final retry = tester.getRect(
        find.byKey(const ValueKey('kw-end-restart')),
      );
      expect(retry.top, greaterThanOrEqualTo(board.top));
      expect(retry.bottom, lessThanOrEqualTo(board.bottom));
      expect(tester.takeException(), isNull);

      await disposePage(tester);
    });

    test('八方向映射与主轴回退', () {
      expect(directionForDrag(const Offset(60, 0)), <int>[1, 0]);
      expect(directionForDrag(const Offset(-60, 0)), <int>[-1, 0]);
      expect(directionForDrag(const Offset(0, 60)), <int>[0, 1]);
      expect(directionForDrag(const Offset(0, -60)), <int>[0, -1]);
      expect(directionForDrag(const Offset(60, 60)), <int>[1, 1]);
      expect(directionForDrag(const Offset(-60, 60)), <int>[-1, 1]);
      expect(directionForDrag(const Offset(60, -60)), <int>[1, -1]);
      expect(directionForDrag(const Offset(-60, -60)), <int>[-1, -1]);
      // 浅斜角退回主轴：横滑仍然只走一步。
      expect(directionForDrag(const Offset(70, 20)), <int>[1, 0]);
      expect(directionForDrag(const Offset(20, -70)), <int>[0, -1]);
      // 低于阈值不触发。
      expect(directionForDrag(const Offset(30, 0)), isNull);
      expect(directionForDrag(const Offset(20, 20)), isNull);
    });
  });

  group('站内入口', () {
    testWidgets('全站搜索能搜到铃渡', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await Prefs.init();
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildCitroTheme(CitroColors.light),
          home: const Scaffold(
            body: Center(
              child: SizedBox(width: 520, child: GlobalSearch(hint: '搜索')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), '铃渡');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('铃渡'), findsWidgets);
      expect(find.text('Citro 小游戏 · 账号同步 · 全站排行'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('选关顺序解锁', () {
    testWidgets('未解锁的关卡点了不进去，第一关可以进', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(const ValueKey('kw-title-select')));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('kw-select')), findsOneWidget);

      // 第二关锁定：点击应该被 IgnorePointer 吃掉，选关层仍然在。
      await tester.tap(
        find.byKey(const ValueKey('kw-level-2')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('kw-select')), findsOneWidget);
      expect(KnockwaterPage.debugTitleVisible, isTrue);

      // 第一关解锁：点击后关掉选关层并进入水面。
      await tester.tap(find.byKey(const ValueKey('kw-level-1')));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('kw-select')), findsNothing);
      expect(KnockwaterPage.debugTitleVisible, isFalse);
      expect(KnockwaterPage.debugEngine!.levelIndex, 0);
      expect(KnockwaterPage.debugHud!.charges, 8);

      await disposePage(tester);
    });
  });

  group('输入 / HUD / 撤销 / 重开', () {
    testWidgets('拖水走一步，HUD 与正在玩文案同步', (tester) async {
      await pumpPage(tester);
      await startFirstLevel(tester);

      final engine = KnockwaterPage.debugEngine!;
      final hud = KnockwaterPage.debugHud!;
      expect(hud.levelIndex, 0);
      expect(hud.charges, 8);
      expect(hud.maxCharges, 8);
      expect(hud.canUndo, isFalse);
      expect(hud.petalCount, 1);
      expect(KnockwaterPage.debugLive, '第 1 关 · 铃息 8 / 8');
      expect(find.text('第 1 关'), findsOneWidget);
      expect(find.text('星数 0/234'), findsOneWidget);
      expect(find.text('花瓣'), findsOneWidget);
      expect(find.text('0/1'), findsOneWidget);

      final startX = engine.cellX;
      await tester.drag(
        find.byKey(const ValueKey('kw-board')),
        const Offset(90, 0),
      );
      await tester.pump();

      expect(engine.steps, 1);
      expect(engine.cellX, startX + 1);
      expect(engine.charges, 7);
      expect(KnockwaterPage.debugHud!.charges, 7);
      expect(KnockwaterPage.debugHud!.canUndo, isTrue);
      expect(KnockwaterPage.debugLive, '第 1 关 · 铃息 7 / 8');

      await disposePage(tester);
    });

    testWidgets('竖向拖动不会被外层滚动吃掉，真实驱动引擎', (tester) async {
      await pumpPage(tester);
      await startFirstLevel(tester);

      final engine = KnockwaterPage.debugEngine!;
      final startY = engine.cellY;
      final boardTop = tester
          .getRect(find.byKey(const ValueKey('kw-board')))
          .top;
      await tester.drag(
        find.byKey(const ValueKey('kw-board')),
        const Offset(0, -90),
      );
      await tester.pump();

      expect(engine.steps, 1);
      expect(engine.cellY, startY - 1);
      // EagerGestureRecognizer 赢下竞技场，页面不应跟着滚。
      expect(
        tester.getRect(find.byKey(const ValueKey('kw-board'))).top,
        closeTo(boardTop, 0.5),
      );
      expect(KnockwaterPage.debugLive, '第 1 关 · 铃息 7 / 8');

      await disposePage(tester);
    });

    testWidgets('撤销回到上一步，重开生成干净的一局', (tester) async {
      await pumpPage(tester);
      await startFirstLevel(tester);

      final engine = KnockwaterPage.debugEngine!;
      final startX = engine.cellX;
      await tester.drag(
        find.byKey(const ValueKey('kw-board')),
        const Offset(90, 0),
      );
      await tester.pump();
      expect(engine.charges, 7);

      await tester.tap(find.byKey(const ValueKey('kw-undo')));
      await tester.pump();
      expect(engine.cellX, startX);
      expect(engine.charges, 8);
      expect(engine.canUndo, isFalse);
      expect(KnockwaterPage.debugLive, '第 1 关 · 铃息 8 / 8');

      // 再走一步后重开。
      await tester.drag(
        find.byKey(const ValueKey('kw-board')),
        const Offset(90, 0),
      );
      await tester.pump();
      expect(engine.steps, 1);

      await tester.tap(find.byKey(const ValueKey('kw-restart')));
      await tester.pump(const Duration(milliseconds: 16));
      final fresh = KnockwaterPage.debugEngine!;
      expect(identical(fresh, engine), isFalse);
      expect(fresh.steps, 0);
      expect(fresh.charges, 8);
      expect(fresh.cellX, startX);
      expect(KnockwaterPage.debugHud!.canUndo, isFalse);

      await disposePage(tester);
    });

    testWidgets('结算浮层出现后可以重开', (tester) async {
      await pumpPage(tester);
      await startFirstLevel(tester);

      final engine = KnockwaterPage.debugEngine!;
      // 让花瓣全部搁浅，走源版的失败结算路径（不走网络提交）。
      for (final p in engine.petals) {
        p.stranded = true;
      }
      engine.advance(1.0);
      engine.endDelay = 0;
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byKey(const ValueKey('kw-end')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('kw-end-restart')));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('kw-end')), findsNothing);
      expect(KnockwaterPage.debugEngine!.steps, 0);

      await disposePage(tester);
    });
  });
}
