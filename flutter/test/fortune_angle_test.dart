import 'package:citro/fortune/prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 11, 23);

  test('同一人同一天同一签，切口不变', () {
    final a = fortuneAngleFor(owner: '阿桃', day: day, idx: 5);
    final b = fortuneAngleFor(owner: '阿桃', day: day, idx: 5);
    expect(a, b);
    expect(kFortuneAngles, contains(a));
  });

  test('换个人撞同一支签，切口会散开', () {
    const owners = ['阿桃', '青禾', '小满', '阿竹', '十七', '阿远', '南南', '阿松', '阿雪', '鹿'];
    final angles = {
      for (final o in owners) fortuneAngleFor(owner: o, day: day, idx: 5),
    };
    expect(angles.length, greaterThanOrEqualTo(3));
  });

  test('同一个人换一天，切口也可能换', () {
    final angles = {
      for (var i = 0; i < 10; i++)
        fortuneAngleFor(owner: '阿桃', day: DateTime(2026, 11, 14 + i), idx: 5),
    };
    expect(angles.length, greaterThanOrEqualTo(2));
  });

  test('切口写进了提示词', () {
    final prompt = buildFortunePrompt(
      day: day,
      weekday: '周一',
      streak: 3,
      level: '上上签',
      kindLabel: '心事签',
      baseName: '松绑',
      baseDesc: '心事晾在日头下',
      baseYi: '写下来',
      baseJi: '反复复盘',
      angle: '手上的那件事',
    );
    expect(prompt, contains('手上的那件事'));
  });
}
