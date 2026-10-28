import 'package:citro/games/liquid_board_metrics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('竖屏下标准壳与紧凑壳棋盘同尺寸', () {
    const phone = Size(390, 844);
    const pad = EdgeInsets.only(top: 47, bottom: 34);
    expect(
      LiquidBoardMetrics.standardBoardHeight(phone, pad),
      LiquidBoardMetrics.compactBoardHeight(phone, pad),
    );
    expect(LiquidBoardMetrics.standardBoardHeight(phone, pad), closeTo(572.3, 0.001));
  });

  test('横屏顶到 720 上限，宽度封顶 430', () {
    const desktop = Size(1920, 1080);
    expect(
      LiquidBoardMetrics.standardBoardHeight(desktop, EdgeInsets.zero),
      720,
    );
    expect(LiquidBoardMetrics.boardWidth(760), 430);
    expect(LiquidBoardMetrics.boardWidth(362), 362);
  });

  test('极小窗口仍留出可用高度', () {
    const tiny = Size(320, 480);
    expect(
      LiquidBoardMetrics.compactBoardHeight(tiny, EdgeInsets.zero),
      360,
    );
  });
}
