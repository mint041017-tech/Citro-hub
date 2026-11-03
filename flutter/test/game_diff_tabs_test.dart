import 'package:citro/games/game_common.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _overlapTabs = <(String, String)>[
  ('overlap-2', '双重叠'),
  ('overlap-3', '三重叠'),
  ('overlap-4', '四重叠'),
  ('overlap-5', '五重叠'),
  ('overlap-8', '八重叠'),
  ('overlap-13', '十三重叠'),
];

void main() {
  testWidgets('六个分榜在手机弹窗宽度内自动换行且完整可见', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var selected = 'overlap-3';
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              // 390 屏宽减去榜单弹窗左右各 16 的边距。
              width: 358,
              child: StatefulBuilder(
                builder: (context, setState) => GameDiffTabs(
                  difficulties: _overlapTabs,
                  selected: selected,
                  onSelect: (key) => setState(() => selected = key),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Row 布局时这里会抛出 RenderFlex overflow。
    expect(tester.takeException(), isNull);

    for (final tab in _overlapTabs) {
      expect(find.text(tab.$2), findsOneWidget);
      final rect = tester.getRect(find.text(tab.$2));
      expect(rect.left, greaterThanOrEqualTo(16));
      expect(rect.right, lessThanOrEqualTo(374));
    }

    // 放不下时必须换行：最后一项落在第二行。
    final firstRowY = tester.getTopLeft(find.text('双重叠')).dy;
    final lastRowY = tester.getTopLeft(find.text('十三重叠')).dy;
    expect(lastRowY, greaterThan(firstRowY));

    await tester.tap(find.text('五重叠'));
    await tester.pump();
    expect(selected, 'overlap-5');
    expect(tester.takeException(), isNull);
  });

  testWidgets('少量分榜仍保持单行，不额外撑高', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const tabs = <(String, String)>[('easy', '简单'), ('med', '中等')];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 358,
              child: GameDiffTabs(
                difficulties: tabs,
                selected: 'easy',
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('简单')).dy,
      tester.getTopLeft(find.text('中等')).dy,
    );
  });
}
