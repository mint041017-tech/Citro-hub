import 'package:flutter_test/flutter_test.dart';
import 'package:citro/games/knockwater/progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('进度顺序解锁与星级合并', () async {
    final p = ProgressStore.memory();
    expect(p.highestUnlocked, 1);
    expect(p.isUnlocked(0), isTrue);
    expect(p.isUnlocked(1), isFalse);
    expect(p.completedCount, 0);

    await p.markPlayed(1); // 未解锁关不能成为继续位置
    expect(p.lastPlayed, 1);

    await p.complete(0, 3);
    expect(p.isCompleted(0), isTrue);
    expect(p.starsFor(0), 3);
    expect(p.isUnlocked(1), isTrue);
    expect(p.lastPlayed, 2);
    expect(p.isUnlocked(2), isFalse);

    await p.complete(1, 2);
    expect(p.isUnlocked(2), isTrue);
    expect(p.lastPlayed, 3);
    expect(p.isUnlocked(3), isFalse);

    // 重玩低星不会覆盖已有高星。
    await p.complete(0, 1);
    expect(p.starsFor(0), 3);
    expect(p.completedCount, 2);
  });

  test('进度持久化后可重新加载', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final first = await ProgressStore.load();
    expect(first.isUnlocked(1), isFalse);
    await first.complete(0, 3);
    await first.complete(1, 2);

    final second = await ProgressStore.load();
    expect(second.isCompleted(0), isTrue);
    expect(second.isCompleted(1), isTrue);
    expect(second.starsFor(0), 3);
    expect(second.starsFor(1), 2);
    expect(second.isUnlocked(2), isTrue);
    expect(second.isUnlocked(3), isFalse);
    expect(second.lastPlayed, 3);
  });

  test('检查点保存、重载与清除', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final first = await ProgressStore.load();
    expect(first.hasCheckpoint, isFalse);
    await first.saveCheckpoint('{"v":1,"level":1}');
    expect(first.hasCheckpoint, isTrue);

    final second = await ProgressStore.load();
    expect(second.hasCheckpoint, isTrue);
    expect(second.checkpoint, '{"v":1,"level":1}');

    await second.clearCheckpoint();
    final third = await ProgressStore.load();
    expect(third.hasCheckpoint, isFalse);

    final memory = ProgressStore.memory();
    await memory.saveCheckpoint('{"v":1,"level":2}');
    await memory.complete(0, 3);
    expect(memory.hasCheckpoint, isFalse, reason: '通关后应清除局内检查点');
  });
}
