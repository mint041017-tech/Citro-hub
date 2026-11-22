import 'dart:math';

import 'package:citro/data/fortunes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('签池覆盖 8 个等级，每级 6 支，共 48 支', () {
    expect(kSignPools.length, 8);
    for (final pool in kSignPools) {
      expect(pool.length, 6);
    }
    expect(kFortunePoolSize, 48);
  });

  test('每支签都有唯一的 id 与签题', () {
    final ids = <String>{};
    final names = <String>{};
    for (final pool in kSignPools) {
      for (final card in pool) {
        expect(ids.add(card.id), isTrue, reason: 'id 重复：${card.id}');
        expect(names.add(card.name), isTrue, reason: '签题重复：${card.name}');
      }
    }
    expect(ids.length, 48);
  });

  test('签类都在 kFortuneKinds 里，且不是单一一类', () {
    final kinds = <String>{};
    for (final pool in kSignPools) {
      for (final card in pool) {
        expect(kFortuneKinds.containsKey(card.kind), isTrue);
        kinds.add(card.kind);
      }
    }
    // 10 种签类都至少出现一次，签面才不会只剩吉凶一个维度。
    expect(kinds.length, kFortuneKinds.length);
  });

  test('每支签的文本都完整且长度可控', () {
    for (final pool in kSignPools) {
      for (final card in pool) {
        expect(card.poem.length, 2, reason: card.id);
        for (final line in card.poem) {
          expect(line.length, 7, reason: '${card.id} 的诗句不是七字：$line');
        }
        expect(card.desc.length, inInclusiveRange(40, 90), reason: card.id);
        expect(card.yi.isNotEmpty, isTrue, reason: card.id);
        expect(card.ji.isNotEmpty, isTrue, reason: card.id);
        expect(card.step.length, lessThanOrEqualTo(20), reason: card.id);
        expect(card.step.isNotEmpty, isTrue, reason: card.id);
      }
    }
  });

  test('同一天同一等级抽到同一支签', () {
    final day = DateTime(2026, 11, 20);
    final a = fortuneForDay(2, day);
    final b = fortuneForDay(2, day);
    expect(a.name, b.name);
    expect(a.desc, b.desc);
    expect(a.signIndex, b.signIndex);
    expect(a.kind, b.kind);
  });

  test('连续 6 天能把同等级 6 支签轮完', () {
    final names = <String>{};
    for (var i = 0; i < 6; i++) {
      final day = DateTime(2026, 11, 20).add(Duration(days: i));
      names.add(fortuneForDay(3, day).name);
    }
    expect(names.length, 6);
  });

  test('签池序号落在对应等级的区间里', () {
    final day = DateTime(2026, 11, 20);
    for (var lv = 0; lv < kSignPools.length; lv++) {
      final fortune = fortuneForDay(lv, day);
      final low = kSignPools.take(lv).fold(0, (s, p) => s + p.length) + 1;
      final high = low + kSignPools[lv].length - 1;
      expect(fortune.signIndex, inInclusiveRange(low, high), reason: 'lv $lv');
      expect(fortune.lv, kFortunes[lv].lv);
    }
  });

  test('转运 salt 能让同一天同等级换一支签', () {
    var changed = 0;
    for (var lv = 0; lv < 8; lv++) {
      final day = DateTime(2026, 11, 20);
      final a = fortuneForDay(lv, day);
      final b = fortuneForDay(lv, day, salt: 1);
      if (a.name != b.name) changed++;
    }
    expect(changed, greaterThan(0));
  });

  test('越界等级不会崩，夹到首尾', () {
    expect(fortuneForDay(-3, DateTime(2026, 11, 20)).lv, kFortunes.first.lv);
    expect(fortuneForDay(99, DateTime(2026, 11, 20)).lv, kFortunes.last.lv);
  });

  test('随机 200 天的签都能拿到完整字段', () {
    final rng = Random(7);
    final names = <String>{};
    for (var i = 0; i < 200; i++) {
      final day = DateTime(2026, 11, 20).add(Duration(days: i));
      final lv = rng.nextInt(8);
      final fortune = fortuneForDay(lv, day);
      expect(fortune.name.isNotEmpty, isTrue);
      expect(fortune.desc.isNotEmpty, isTrue);
      expect(fortune.kind, isNotNull);
      expect(fortune.step, isNotNull);
      names.add(fortune.name);
    }
    expect(names.length, greaterThan(20));
  });
}
