// 手机竖屏顶栏预览：读数收进顶栏（A），以及长标题 / 大数值时自动折行（B）。
//
//   flutter test test/preview/compact_hud_preview_test.dart --update-goldens
import 'package:citro/games/game_ui.dart';
import 'package:citro/games/sudoku/sudoku_board_view.dart';
import 'package:citro/games/sudoku/sudoku_modes.dart';
import 'package:citro/games/sudoku/sudoku_puzzle.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

List<int> _classicSolution() => [
  for (var r = 0; r < 9; r++)
    for (var c = 0; c < 9; c++) (r * 3 + r ~/ 3 + c) % 9 + 1,
];

List<int> _classicRegions() => [
  for (var r = 0; r < 9; r++)
    for (var c = 0; c < 9; c++) (r ~/ 3) * 3 + c ~/ 3,
];

List<List<int>> _classicUnits() => [
  for (var r = 0; r < 9; r++) [for (var c = 0; c < 9; c++) r * 9 + c],
  for (var c = 0; c < 9; c++) [for (var r = 0; r < 9; r++) r * 9 + c],
  for (var br = 0; br < 3; br++)
    for (var bc = 0; bc < 3; bc++)
      [
        for (var r = 0; r < 3; r++)
          for (var c = 0; c < 3; c++) (br * 3 + r) * 9 + bc * 3 + c,
      ],
];

SudokuPuzzle _classicPuzzle() {
  final solution = _classicSolution();
  final givens = List<int>.from(solution);
  for (final i in [0, 4, 8, 12, 20, 31, 45, 56, 67, 78]) {
    givens[i] = 0;
  }
  return SudokuPuzzle(
    variant: SudokuVariant.classic,
    difficulty: SudokuDifficulty.medium,
    overlapCount: 0,
    rows: 9,
    cols: 9,
    layers: 1,
    solution: solution,
    givens: givens,
    regionOf: _classicRegions(),
    active: List<bool>.filled(81, true),
    grids: const [],
    units: _classicUnits(),
  );
}

Widget _modeBar(BuildContext context) {
  final c = context.c;
  return Center(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.line2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '经典九宫',
                style: context.body(
                  size: 12,
                  weight: CitroType.strong,
                  color: c.ink2,
                ),
              ),
              const SizedBox(width: 4),
              gameIcon(GameIcons.arrowLeft, size: 11, color: c.inkSoft),
              Text('换', style: context.body(size: 10, color: c.inkSoft)),
            ],
          ),
        ),
        const SizedBox(width: 9),
        GameSegTabs<String>(
          items: const [
            ('easy', '简单'),
            ('medium', '中等'),
            ('hard', '困难'),
            ('expert', '专家'),
          ],
          value: 'medium',
          onChanged: (_) {},
        ),
      ],
    ),
  );
}

Widget _key(BuildContext context, int n) {
  final c = context.c;
  return SizedBox(
    width: 56,
    height: 56,
    child: Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(CitroColors.radii.small),
              border: Border.all(color: c.line2),
            ),
          ),
        ),
        Center(
          child: Text(
            '$n',
            style: context.hand(
              size: 23.5,
              weight: CitroType.strong,
              color: c.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _tool(BuildContext context, String label, String icon) {
  final c = context.c;
  return Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: c.line),
      boxShadow: CitroColors.shadows.sm(c),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        gameIcon(icon, size: 15, color: c.ink2),
        const SizedBox(width: 6),
        Text(
          label,
          style: context.body(
            size: CitroType.meta,
            weight: CitroType.strong,
            color: c.ink2,
          ),
        ),
      ],
    ),
  );
}

Widget _sudokuBoard(BuildContext context) {
  const side = 358.0;
  final puzzle = _classicPuzzle();
  Widget keyRow(int n, int start) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < n; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        _key(context, start + i),
      ],
    ],
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: side,
        height: side,
        child: SudokuBoardView(
          puzzle: puzzle,
          board: List<int>.from(puzzle.givens),
          notes: List.generate(81, (_) => <int>{}),
          conflicts: const {},
          selected: -1,
          layer: 0,
          focusGrid: -1,
          revision: 0,
          maxSide: side,
          interactive: false,
          paused: false,
          over: false,
        ),
      ),
      const SizedBox(height: 10),
      keyRow(5, 1),
      const SizedBox(height: 10),
      keyRow(4, 6),
      const SizedBox(height: 10),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tool(context, '撤销', GameIcons.undo),
          const SizedBox(width: 8),
          _tool(context, '擦除', GameIcons.eraser),
          const SizedBox(width: 8),
          _tool(context, '笔记', GameIcons.pencil),
        ],
      ),
    ],
  );
}

Widget _fallbackBoard(BuildContext context) {
  final c = context.c;
  return Center(
    child: Container(
      width: 300,
      height: 300,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
        border: Border.all(color: c.line),
      ),
      child: Text(
        '数字华容道 · 棋盘',
        style: context.body(size: CitroType.meta, color: c.inkSoft),
      ),
    ),
  );
}

Widget _page({
  required Widget Function(BuildContext) board,
  required String title,
  required String game,
  bool modeBar = false,
  List<Widget> pills = const [],
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.darkColors),
    home: Builder(
      builder: (context) => GameScaffold(
        gameKey: game,
        title: title,
        rankGame: game,
        above: modeBar ? [_modeBar(context)] : const [],
        pills: pills,
        actions: [
          GameActionButton(
            label: '新游戏',
            icon: GameIcons.refresh,
            primary: true,
            onTap: () {},
          ),
          GameActionButton(
            label: '暂停',
            icon: GameIcons.pause,
            onTap: () {},
          ),
          GameActionButton(
            label: '排行榜',
            icon: GameIcons.trophy,
            onTap: () {},
          ),
        ],
        board: board(context),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    GameScaffold.liveEnabled = false;
  });

  testWidgets('phone top hud', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _page(
        game: 'gsudoku',
        title: '数独',
        modeBar: true,
        pills: const [
          GameScorePill(label: '错误', value: '0/5'),
          GameScorePill(label: '用时', value: '0:06'),
          GameScorePill(label: '最佳', value: '--'),
        ],
        board: _sudokuBoard,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/compact_hud_phone_dark.png'),
    );
  });

  testWidgets('long title falls back below the title', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _page(
        game: 'gslide',
        title: '数字华容道',
        pills: const [
          GameScorePill(label: '步数', value: '123456'),
          GameScorePill(label: '用时', value: '99:59'),
          GameScorePill(label: '最佳', value: '123456'),
        ],
        board: _fallbackBoard,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/compact_hud_fallback_dark.png'),
    );
  });
}
