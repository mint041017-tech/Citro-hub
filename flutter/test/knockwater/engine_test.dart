import 'package:flutter_test/flutter_test.dart';
import 'package:citro/games/knockwater/engine.dart';
import 'package:citro/games/knockwater/levels.dart';

void main() {
  test('第一关：两次重叩可以入湾', () {
    final e = Engine(0);
    for (var i = 0; i < 2; i++) {
      expect(e.startCharge(), isTrue);
      e.chargeT = 1.2;
      expect(e.releaseCharge(), isNotNull);
      e.advance(3.4);
      final p = e.petals.first;
      // ignore: avoid_print
      print(
        'knock $i charges=${e.charges} '
        'petal=(${p.x.toStringAsFixed(2)}, ${p.y.toStringAsFixed(2)}) '
        'inBay=${p.inBay} settled=${p.settled} status=${e.status.name}',
      );
    }
    expect(e.status, GameStatus.won);
  });

  test('撤销恢复铃息与花瓣位置', () {
    final e = Engine(0);
    final x0 = e.petals.first.x;
    final y0 = e.petals.first.y;
    final charges0 = e.charges;
    expect(e.step(1, -1), isTrue);
    e.advance(2.0);
    expect(e.charges, charges0 - 1);
    expect(e.undo(), isTrue);
    expect(e.charges, charges0);
    expect(e.petals.first.x, closeTo(x0, 1e-9));
    expect(e.petals.first.y, closeTo(y0, 1e-9));
    expect(e.waves, isEmpty);
  });

  test('铃息耗尽且花瓣未入湾时判负', () {
    final e = Engine(0);
    e.charges = 1;
    expect(e.step(-1, 0), isTrue);
    e.advance(5.0);
    expect(e.status, GameStatus.lost);
    expect(e.loseReason, LoseReason.empty);
  });

  test('零铃息时，即使花瓣被暗流持续推动也会判负', () {
    final currentLevel = kLevels.indexWhere(
      (level) => level.currents.isNotEmpty,
    );
    expect(currentLevel, isNonNegative);
    final e = Engine(currentLevel);
    e.charges = 0;
    e.petals.first.x = 6.0;
    e.petals.first.y = 10.0;
    e.advance(4.5);
    expect(e.status, GameStatus.lost);
    expect(e.loseReason, LoseReason.empty);
  });

  test('回音石不会自激，回音关零铃息仍会判负', () {
    final echoLevel = kLevels.indexWhere((level) => level.echoes.isNotEmpty);
    expect(echoLevel, isNonNegative);
    final e = Engine(echoLevel);
    e.charges = 3;
    expect(e.startCharge(), isTrue);
    e.chargeT = 1.2;
    expect(e.releaseCharge(), isNotNull);
    e.charges = 0;
    e.advance(20);
    expect(e.status, GameStatus.lost);
    expect(e.loseReason, LoseReason.empty);
    expect(e.waves, isEmpty);
    expect(e.pending, isEmpty);
  });

  test('水铃可以走到贴近池岸的格子', () {
    final e = Engine(0);
    expect(e.canWalkCell(6, 1), isTrue);
    expect(e.canWalkCell(1, 10), isTrue);
    expect(e.canWalkCell(6, 0), isFalse);
  });
}
