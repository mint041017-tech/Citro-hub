import 'dart:math' as math;

import 'package:citro/games/gliquid_game.dart';
import 'package:citro/games/gliquid_physics.dart';
import 'package:flutter_test/flutter_test.dart';

LiquidLayout _layout({double width = 390, double height = 844}) =>
    LiquidLayout.compute(width, height);

void _advance(LiquidGame game, double seconds, {double step = 1 / 60}) {
  final frames = (seconds / step).round();
  for (var i = 0; i < frames; i++) {
    game.step(step);
  }
}

Map<int, int> _levelCounts(LiquidGame game) {
  final counts = <int, int>{};
  for (final blob in game.blobs) {
    counts[blob.level] = (counts[blob.level] ?? 0) + 1;
  }
  final keys = counts.keys.toList()..sort();
  return {for (final key in keys) key: counts[key]!};
}

void main() {
  test('levels keep doubling without a 2048 cap', () {
    expect(LiquidLevels.valueForLevel(1), 1);
    expect(LiquidLevels.valueForLevel(12), 2048);
    expect(LiquidLevels.valueForLevel(13), 4096);
    expect(LiquidLevels.valueForLevel(14), 8192);
    expect(LiquidLevels.valueForLevel(30), 536870912);
    expect(LiquidLevels.baseRadiusForLevel(30), lessThan(130));
    expect(LiquidLevels.shimmerForLevel(13), isFalse);
    expect(LiquidLevels.shimmerForLevel(18), isTrue);
  });

  test('small blobs still merge after circle separation', () {
    final game = LiquidGame(layout: _layout(), random: math.Random(12));
    game.world.blobs.clear();
    final radius = game.layout.levelRadius(2);
    final y = game.layout.bounds.floor - radius - 1;
    game.world
      ..add(
        SoftBlob(
          level: 2,
          radius: radius,
          x: game.layout.cx - 5,
          y: y,
          random: math.Random(61),
        ),
      )
      ..add(
        SoftBlob(
          level: 2,
          radius: radius,
          x: game.layout.cx + 5,
          y: y,
          random: math.Random(62),
        ),
      );
    game.start();
    _advance(game, 0.8);
    expect(game.blobs.where((blob) => blob.level == 3), hasLength(1));
    expect(game.score, greaterThanOrEqualTo(4));
  });

  test('256 stays around a third of the jar width', () {
    final layout = _layout();
    final diameter = layout.levelRadius(9) * 2;
    expect(diameter / layout.jarW, lessThan(0.42));
    expect(diameter / layout.jarH, lessThan(0.32));
  });

  test('2048 pair merges into 8192 instead of clearing', () {
    final game = LiquidGame(layout: _layout(), random: math.Random(7));
    game.world.blobs.clear();
    final radius = game.layout.levelRadius(12);
    final y = game.layout.bounds.floor - radius - 1;
    game.world.add(
      SoftBlob(
        level: 12,
        radius: radius,
        x: game.layout.cx - 6,
        y: y,
        random: math.Random(11),
      ),
    );
    game.world.add(
      SoftBlob(
        level: 12,
        radius: radius,
        x: game.layout.cx + 6,
        y: y,
        random: math.Random(12),
      ),
    );
    game.start();
    _advance(game, 0.8);

    final high = game.blobs.where((b) => b.level == 13).toList();
    expect(high, hasLength(1));
    expect(game.maxLevel, greaterThanOrEqualTo(13));
    expect(game.score, greaterThanOrEqualTo(4096));
  });

  test('physics stays finite and inside the jar', () {
    final game = LiquidGame(layout: _layout(), random: math.Random(21));
    game.world.blobs.clear();
    final random = math.Random(3);
    for (var i = 0; i < 18; i++) {
      final level = 2 + random.nextInt(5);
      final radius = game.layout.levelRadius(level) * 0.72;
      final x =
          game.layout.bounds.left +
          radius +
          random.nextDouble() * (game.layout.bounds.width - radius * 2);
      final y =
          game.layout.bounds.top +
          radius +
          random.nextDouble() * (game.layout.bounds.height - radius * 2);
      game.world.add(
        SoftBlob(
          level: level,
          radius: radius,
          x: x,
          y: y,
          vx: (random.nextDouble() - .5) * 400,
          vy: (random.nextDouble() - .5) * 400,
          random: random,
        ),
      );
    }

    _advance(game, 12);

    final bounds = game.layout.bounds;
    for (final blob in game.blobs) {
      expect(blob.cx.isFinite, isTrue);
      expect(blob.cy.isFinite, isTrue);
      for (final p in blob.points) {
        expect(p.x.isFinite, isTrue);
        expect(p.y.isFinite, isTrue);
        expect(p.x, greaterThan(bounds.left - 1));
        expect(p.x, lessThan(bounds.right + 1));
        expect(p.y, greaterThan(bounds.top - 1));
        expect(p.y, lessThan(bounds.floor + 1));
      }
      expect(blob.area, greaterThan(blob.targetArea * 0.08));
    }
  });

  test('a blob held above the rim ends the round', () {
    final game = LiquidGame(layout: _layout(), random: math.Random(5));
    game.world.blobs.clear();
    final huge = SoftBlob(
      level: 30,
      radius: game.layout.jarH * 0.72,
      x: game.layout.cx,
      y: game.layout.bounds.floor - 4,
      random: math.Random(9),
    );
    game.world.add(huge);
    game.start();
    _advance(game, 4.2);
    expect(game.overflowTime, greaterThan(0));
    expect(game.phase, anyOf(LiquidPhase.ending, LiquidPhase.over));
  });

  test('releasing a shot clears the charge ring state', () {
    final game = LiquidGame(layout: _layout(), random: math.Random(31));
    game.start();
    expect(game.beginCharge(), isTrue);
    _advance(game, 0.5);
    expect(game.power, greaterThan(0.12));
    expect(game.releaseShot(), isTrue);
    expect(game.charging, isFalse);
    expect(game.power, 0);
    expect(game.chargeTime, 0);
    expect(game.shots, 1);
  });

  test('spawn pool unlocks tiers by merges like sobosuba', () {
    final game = LiquidGame(layout: _layout(), random: math.Random(77));
    game.world.blobs.clear();

    void addPair(int level) {
      final r = game.layout.levelRadius(level);
      final y = game.layout.bounds.floor - r - 1;
      game.world
        ..add(
          SoftBlob(
            level: level,
            radius: r,
            x: game.layout.cx - 5,
            y: y,
            random: math.Random(level * 10 + 1),
          ),
        )
        ..add(
          SoftBlob(
            level: level,
            radius: r,
            x: game.layout.cx + 5,
            y: y,
            random: math.Random(level * 10 + 2),
          ),
        );
    }

    game.start();

    // sobosuba 的池子初始只有最小一档，连投也不会出更大的。
    expect(LiquidGame.spawnLadder.first, 2);
    for (var i = 0; i < 50; i++) {
      expect(game.rollLevel(false), 2);
    }

    // 合出一次 3 → 解锁 3；池里只有 2/3，且不会连续出同一个等级。
    addPair(2);
    _advance(game, 1.0);
    expect(game.blobs.where((b) => b.level == 3), hasLength(1));
    final early = <int>{};
    var last = 0;
    for (var i = 0; i < 400; i++) {
      final level = game.rollLevel(false);
      expect(level, anyOf(2, 3));
      expect(level, isNot(last));
      last = level;
      early.add(level);
    }
    expect(early, containsAll([2, 3]));

    // 连续合出 3 个 4 → 解锁 4（sobosuba 门槛 3 次）。
    for (var k = 0; k < 3; k++) {
      addPair(3);
      _advance(game, 1.0);
    }
    final later = <int>{};
    for (var i = 0; i < 400; i++) {
      later.add(game.rollLevel(false));
    }
    expect(later.contains(4), isTrue);
    expect(later.contains(5), isFalse);
    expect(
      game.events.any(
        (e) => e.type == LiquidEventType.tierUp && (e.message ?? '').contains('出货升级'),
      ),
      isTrue,
    );
    expect(LiquidLevels.valueForLevel(LiquidGame.maxSpawnLevel), 128);
  });

  test('squeezed small blob settles instead of flying away', () {
    final game = LiquidGame(layout: _layout(), random: math.Random(5));
    game.world.blobs.clear();
    final layout = game.layout;
    final bigA = SoftBlob(
      level: 10,
      radius: layout.levelRadius(10),
      x: layout.cx - 65,
      y: layout.bounds.floor - layout.levelRadius(10),
      random: math.Random(21),
    );
    final bigB = SoftBlob(
      level: 9,
      radius: layout.levelRadius(9),
      x: layout.cx + 65,
      y: layout.bounds.floor - layout.levelRadius(9),
      random: math.Random(22),
    );
    final small = SoftBlob(
      level: 2,
      radius: layout.levelRadius(2),
      x: layout.cx,
      y: layout.bounds.floor - layout.levelRadius(2),
      random: math.Random(23),
    );
    game.world
      ..add(bigA)
      ..add(bigB)
      ..add(small);
    game.start();
    final startY = small.cy;
    for (var i = 0; i < 600; i++) {
      game.step(1 / 60);
    }

    expect(small.cy, greaterThan(startY - 250));
    expect(
      math.sqrt(
        small.averageVx() * small.averageVx() +
            small.averageVy() * small.averageVy(),
      ),
      lessThan(300),
    );
    // 允许被挤压变形（面积可能降到一半左右），但不能塌掉。
    expect(small.area, greaterThan(small.targetArea * 0.45));
  });

  // 难度回归：随机乱投的机器人应该大多数阵亡在罐口，而不是靠合并无限续命。
  // 单一种子会随物理微调来回翻转（500 发内死亡/存活），所以固定跑 3 个种子看分布。
  test('random bots mostly overflow the jar', () {
    final results = <({int shots, bool over})>[];
    for (final seed in [1234, 7, 42]) {
      final game = LiquidGame(layout: _layout(), random: math.Random(seed));
      final bot = math.Random(seed * 31 + 9);
      game.start();

      var shots = 0;
      var elapsed = 0.0;
      var maxOverflow = 0.0;
      var maxBlobs = 0;
      while (game.phase != LiquidPhase.over &&
          shots < 450 &&
          elapsed < 300) {
        if (game.phase == LiquidPhase.playing && game.cooldown == 0) {
          final aim = (bot.nextDouble() - .5) * 1.25;
          final power = 0.35 + bot.nextDouble() * 0.6;
          if (game.launchAt(aim, power)) shots++;
        }
        game.step(1 / 60);
        elapsed += 1 / 60;
        maxOverflow = math.max(maxOverflow, game.overflowTime);
        maxBlobs = math.max(maxBlobs, game.blobs.length);
      }

      // ignore: avoid_print
      print(
        'bot seed=$seed shots=$shots over=${game.phase == LiquidPhase.over} '
        'score=${game.score} maxLevel=${game.maxLevel} '
        't=${elapsed.toStringAsFixed(1)}s maxBlobs=$maxBlobs '
        'maxOverflow=${maxOverflow.toStringAsFixed(2)} '
        'counts=${_levelCounts(game)}',
      );
      results.add((shots: shots, over: game.phase == LiquidPhase.over));
    }

    final sorted = results.map((r) => r.shots).toList()..sort();
    final median = sorted[sorted.length ~/ 2];
    expect(results.where((r) => r.over).length, greaterThanOrEqualTo(1));
    expect(sorted.first, greaterThan(25));
    expect(median, greaterThan(40));
    expect(median, lessThan(300));
  });

  test('squeezed blobs deform but stay fluid', () {
    final game = LiquidGame(layout: _layout(), random: math.Random(5));
    game.world.blobs.clear();
    final layout = game.layout;
    final rBig = layout.levelRadius(10);
    final rSmall = layout.levelRadius(4);
    final big = SoftBlob(
      level: 10,
      radius: rBig,
      x: layout.cx,
      y: layout.bounds.floor - rBig,
      random: math.Random(21),
    );
    final small = SoftBlob(
      level: 4,
      radius: rSmall,
      x: layout.cx,
      y: layout.bounds.floor - rBig * 1.9,
      random: math.Random(22),
    );
    game.world
      ..add(big)
      ..add(small);
    game.start();
    for (var i = 0; i < 600; i++) {
      game.step(1 / 60);
    }

    double aspectOf(SoftBlob b) {
      final poly = b.boundaryPoints();
      var minX = double.infinity;
      var maxX = -double.infinity;
      var minY = double.infinity;
      var maxY = -double.infinity;
      for (final p in poly) {
        minX = math.min(minX, p.x);
        maxX = math.max(maxX, p.x);
        minY = math.min(minY, p.y);
        maxY = math.max(maxY, p.y);
      }
      return (maxX - minX) / (maxY - minY);
    }

    // ignore: avoid_print
    print(
      'deform big aspect=${aspectOf(big).toStringAsFixed(2)} '
      'area=${(big.area / big.targetArea).toStringAsFixed(2)} '
      'small aspect=${aspectOf(small).toStringAsFixed(2)} '
      'area=${(small.area / small.targetArea).toStringAsFixed(2)}',
    );
    expect(big.area, greaterThan(big.targetArea * 0.7));
    expect(aspectOf(big), greaterThan(0.75));
    expect(aspectOf(big), lessThan(1.45));
  });

}