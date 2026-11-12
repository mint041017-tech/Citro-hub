import 'package:citro/games/liquid_board_metrics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('宽度封顶 430，高度按 1.5 折算', () {
    expect(LiquidBoardMetrics.boardWidth(760), 430);
    expect(LiquidBoardMetrics.boardWidth(362), 362);
    expect(
      LiquidBoardMetrics.boardSizeFor(maxWidth: 760),
      const Size(430, 645),
    );
    expect(
      LiquidBoardMetrics.boardSizeFor(maxWidth: 362),
      const Size(362, 543),
    );
  });

  test('宽度折算夹在可玩区间内', () {
    expect(
      LiquidBoardMetrics.boardSizeFor(maxWidth: 200),
      const Size(200, 360),
    );
    expect(
      LiquidBoardMetrics.boardSizeFor(maxWidth: 900),
      const Size(430, 645),
    );
  });

  test('有界高度只收底，不改宽度折算', () {
    // 紧凑壳 Expanded：可用高度小于折算高度时按可用高度。
    expect(
      LiquidBoardMetrics.boardSizeFor(maxWidth: 362, maxHeight: 400),
      const Size(362, 400),
    );
    // 可用高度充足时与无界一致（Web / 紧凑壳同视口）。
    expect(
      LiquidBoardMetrics.boardSizeFor(maxWidth: 362, maxHeight: 800),
      const Size(362, 543),
    );
  });
}
