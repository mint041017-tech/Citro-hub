import 'package:flutter_test/flutter_test.dart';
import 'package:citro/games/knockwater/engine.dart';
import 'package:citro/games/knockwater/hud_snapshot.dart';

void main() {
  test('快照是值相等：两个同关同状态的引擎得到相同快照', () {
    final a = GameHudSnapshot.of(Engine(0));
    final b = GameHudSnapshot.of(Engine(0));
    expect(identical(a, b), isFalse);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('时间推进与波前动画不改变 HUD 快照', () {
    final e = Engine(0);
    final before = GameHudSnapshot.of(e);
    e.advance(1.0);
    expect(GameHudSnapshot.of(e), before);
    expect(e.time, greaterThan(0.9));
  });

  test('蓄力比例是逐帧值，不进入 HUD 快照', () {
    final e = Engine(0);
    expect(e.startCharge(), isTrue);
    final charging = GameHudSnapshot.of(e);
    expect(charging.charging, isTrue);
    e.chargeT = 0.6;
    expect(GameHudSnapshot.of(e), charging);
    e.cancelCharge();
    expect(GameHudSnapshot.of(e).charging, isFalse);
  });

  test('走步、撤销只通过铃息/可撤销值触发快照变化', () {
    final e = Engine(0);
    final before = GameHudSnapshot.of(e);
    expect(before.canUndo, isFalse);
    expect(e.step(1, 0), isTrue);
    final afterStep = GameHudSnapshot.of(e);
    expect(afterStep.charges, before.charges - 1);
    expect(afterStep.canUndo, isTrue);
    expect(afterStep, isNot(before));
    expect(e.undo(), isTrue);
    expect(GameHudSnapshot.of(e), before);
  });

  test('花瓣进入湾心后 petalsInBay 进入快照', () {
    final e = Engine(0);
    final before = GameHudSnapshot.of(e);
    final p = e.petals.first;
    p.x = e.bay.x;
    p.y = e.bay.y;
    p.vx = 0;
    p.vy = 0;
    e.advance(1 / 60);
    final after = GameHudSnapshot.of(e);
    expect(after.petalsInBay, 1);
    expect(after.petalCount, before.petalCount);
    expect(after, isNot(before));
  });

  test('胜负状态进入快照，且不依赖 endDelay 的逐帧倒计时', () {
    final e = Engine(0);
    e.charges = 0;
    e.advance(1.4);
    expect(e.status, GameStatus.lost);
    final lost = GameHudSnapshot.of(e);
    expect(lost.status, GameStatus.lost);
    expect(lost.loseReason, LoseReason.empty);
    final delayBefore = e.endDelay;
    e.advance(0.1);
    expect(e.endDelay, lessThan(delayBefore));
    expect(GameHudSnapshot.of(e), lost);
  });
}
