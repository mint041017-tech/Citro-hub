import 'dart:math' as math;

import 'package:citro/games/gliquid_game.dart';
import 'package:citro/games/gliquid_physics.dart';
import 'package:flutter_test/flutter_test.dart';

/// 55 发随机投喂是一个很激进的场景：大液滴互相挤压、在角里堆叠。
/// 这组回归确认软体不会把液滴甩到罐外，也不会留下长期塌缩的薄片。
void main() {
  test('random barrage keeps blobs finite, contained and inflated', () {
    final game = LiquidGame(
      layout: LiquidLayout.compute(390, 844, topInset: 96),
      random: math.Random(42),
    );
    game.start();
    final bot = math.Random(51);
    final bounds = game.layout.bounds;
    var shots = 0;
    var elapsed = 0.0;

    while (shots < 55 && elapsed < 90) {
      if (game.phase == LiquidPhase.playing && game.cooldown == 0) {
        final aim = (bot.nextDouble() - .5) * 1.1;
        final power = 0.4 + bot.nextDouble() * 0.5;
        if (game.launchAt(aim, power)) shots++;
      }
      game.step(1 / 60);
      for (final blob in game.blobs) {
        expect(blob.cx.isFinite, isTrue);
        expect(blob.cy.isFinite, isTrue);
        for (final point in blob.points) {
          expect(point.x.isFinite, isTrue);
          expect(point.y.isFinite, isTrue);
          expect(point.x, greaterThanOrEqualTo(bounds.left - 1));
          expect(point.x, lessThanOrEqualTo(bounds.right + 1));
          // 罐口上方是开放区：溢出的液滴允许高过罐口，但不能漏过罐底。
          expect(point.y, lessThanOrEqualTo(bounds.floor + 1));
          expect(point.y, greaterThanOrEqualTo(0));
        }
      }
      elapsed += 1 / 60;
    }

    for (var i = 0; i < 900; i++) {
      game.step(1 / 60);
    }

    expect(game.blobs, isNotEmpty);
    for (final blob in game.blobs) {
      expect(blob.area, greaterThan(blob.targetArea * 0.3));
      final speed = math.sqrt(
        blob.averageVx() * blob.averageVx() +
            blob.averageVy() * blob.averageVy(),
      );
      // 小球必须收住；大球是液体，允许更慢的翻滚/沉降。
      expect(
        speed,
        lessThan(blob.isSmall ? 300 : 900),
        reason: 'level ${blob.level} still moving',
      );
    }
  });

  // 用户要求“完全不会重叠”：按实际画出来的轮廓验收（渲染只会在
  // 物理半径内做向内涟漪），而不是用未形变时的标称圆。
  test('settled blobs never overlap visually', () {
    final game = LiquidGame(
      layout: LiquidLayout.compute(390, 844, topInset: 96),
      random: math.Random(42),
    );
    game.start();
    final bot = math.Random(51);
    var shots = 0;
    var elapsed = 0.0;
    var worst = 0.0;
    var worstInfo = '';

    List<Vec2> clamped(SoftBlob b) {
      final poly = b.boundaryPoints();
      final cap = b.radius * 0.985;
      return [
        for (final p in poly)
          (() {
            final dx = p.x - b.cx;
            final dy = p.y - b.cy;
            final d = math.sqrt(dx * dx + dy * dy);
            if (d <= cap || d < 1e-6) return p;
            return Vec2(b.cx + dx / d * cap, b.cy + dy / d * cap);
          })(),
      ];
    }

    double insideDepth(List<Vec2> poly, double x, double y) {
      var inside = false;
      var best = double.infinity;
      for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        final a = poly[j];
        final b = poly[i];
        if ((a.y > y) != (b.y > y)) {
          final xint = ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x;
          if (x < xint) inside = !inside;
        }
        final ex = b.x - a.x;
        final ey = b.y - a.y;
        final len2 = ex * ex + ey * ey;
        var t = len2 > 0 ? ((x - a.x) * ex + (y - a.y) * ey) / len2 : 0.0;
        t = t < 0 ? 0 : (t > 1 ? 1 : t);
        final px = a.x + ex * t;
        final py = a.y + ey * t;
        final d = math.sqrt(math.pow(x - px, 2) + math.pow(y - py, 2));
        best = math.min(best, d);
      }
      return inside ? best : -best;
    }

    while (shots < 55 && elapsed < 90) {
      if (game.phase == LiquidPhase.playing && game.cooldown == 0) {
        final aim = (bot.nextDouble() - .5) * 1.1;
        final power = 0.4 + bot.nextDouble() * 0.5;
        if (game.launchAt(aim, power)) shots++;
      }
      game.step(1 / 60);
      elapsed += 1 / 60;

      final blobs = game.blobs;
      for (var i = 0; i < blobs.length; i++) {
        for (var j = i + 1; j < blobs.length; j++) {
          final a = blobs[i];
          final b = blobs[j];
          if (a.age < 0.35 || b.age < 0.35) continue;
          final pb = clamped(b);
          for (final p in clamped(a)) {
            final depth = insideDepth(pb, p.x, p.y);
            if (depth > worst) {
              worst = depth;
              worstInfo =
                  'lvl${a.level}->lvl${b.level} depth=${depth.toStringAsFixed(2)} '
                  'c=(${a.cx.toStringAsFixed(0)},${a.cy.toStringAsFixed(0)})';
            }
          }
        }
      }
    }

    // ignore: avoid_print
    print('worst visual overlap=${worst.toStringAsFixed(2)}px $worstInfo');
    expect(worst, lessThan(1.5));
  });
}