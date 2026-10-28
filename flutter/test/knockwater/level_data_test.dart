import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:citro/games/knockwater/engine.dart';
import 'package:citro/games/knockwater/levels.dart';

double _dist(double x1, double y1, double x2, double y2) {
  final dx = x1 - x2;
  final dy = y1 - y2;
  return math.sqrt(dx * dx + dy * dy);
}

void main() {
  test('78 关初始状态合法', () {
    expect(
      kLevels.map((level) => level.pondVariant).toSet(),
      containsAll(<int>[0, 1, 2, 3, 4, 5]),
      reason: '6 种池塘轮廓都应在关卡中轮换使用',
    );
    for (var i = 0; i < kLevels.length; i++) {
      final lv = kLevels[i];
      final e = Engine(i);
      expect(
        e.canWalkCell(lv.bellX, lv.bellY),
        isTrue,
        reason: 'L${i + 1} ${lv.name}: 水铃初始格不可走',
      );

      // The bay must be entirely in water.
      for (var k = 0; k < 360; k++) {
        final a = k / 360 * kTau;
        final x = lv.bay.x + math.cos(a) * lv.bay.r;
        final y = lv.bay.y + math.sin(a) * lv.bay.r;
        expect(
          inWater(x, y, 0, lv.pondVariant),
          isTrue,
          reason: 'L${i + 1} ${lv.name}: 湾心边界出水',
        );
      }

      for (var j = 0; j < lv.petals.length; j++) {
        final p = lv.petals[j];
        final m = pondMetric(p.x, p.y, lv.pondVariant);
        expect(
          m.len <= m.limit - 0.035,
          isTrue,
          reason: 'L${i + 1} ${lv.name}: 花瓣 $j 预搁浅',
        );
        expect(
          _dist(p.x, p.y, lv.bay.x, lv.bay.y),
          greaterThanOrEqualTo(lv.bay.r - 0.05),
          reason: 'L${i + 1} ${lv.name}: 花瓣 $j 初始在湾心',
        );
      }

      for (final r in lv.rocks) {
        expect(
          _dist(r.x, r.y, lv.bay.x, lv.bay.y),
          greaterThanOrEqualTo(r.r + lv.bay.r),
          reason: 'L${i + 1} ${lv.name}: 墨石与湾心重叠',
        );
      }
      for (final r in lv.reeds) {
        expect(
          _dist(r.x, r.y, lv.bay.x, lv.bay.y),
          greaterThanOrEqualTo(r.r + lv.bay.r),
          reason: 'L${i + 1} ${lv.name}: 芦苇与湾心重叠',
        );
      }
      for (final r in lv.echoes) {
        expect(
          _dist(r.x, r.y, lv.bay.x, lv.bay.y),
          greaterThanOrEqualTo(r.r + lv.bay.r),
          reason: 'L${i + 1} ${lv.name}: 回音石与湾心重叠',
        );
      }
      for (final v in lv.vortices) {
        expect(
          inWater(v.x, v.y, 0, lv.pondVariant),
          isTrue,
          reason: 'L${i + 1} ${lv.name}: 涡流中心出水',
        );
      }
    }
  });
}
