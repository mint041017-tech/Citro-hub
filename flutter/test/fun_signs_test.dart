import 'package:citro/data/fun_signs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('80 支趣签，16 个签种，每种 5 支', () {
    expect(kFunSigns.length, 80);
    expect(kFunSignKinds.length, 16);
    for (final kind in kFunSignKinds) {
      expect(funSignsOf(kind).length, 5, reason: '$kind 应正好 5 支');
    }
    expect(kFunSigns.map((s) => s.kind).toSet(), kFunSignKinds.toSet());
  });

  test('id 与签题都不重复，方便「不摇到同一支」', () {
    expect(kFunSigns.map((s) => s.id).toSet().length, kFunSigns.length);
    expect(kFunSigns.map((s) => s.name).toSet().length, kFunSigns.length);
  });

  test('签题 4 字，诗句两行，注解长度可控', () {
    for (final s in kFunSigns) {
      expect(s.name.length, inInclusiveRange(3, 5), reason: s.id);
      expect(s.poem1.trim(), isNotEmpty, reason: s.id);
      expect(s.poem2.trim(), isNotEmpty, reason: s.id);
      expect(s.poem1.length, lessThanOrEqualTo(10), reason: s.id);
      expect(s.poem2.length, lessThanOrEqualTo(10), reason: s.id);
      expect(s.note.length, inInclusiveRange(20, 60), reason: s.id);
      expect(s.yi.length, lessThanOrEqualTo(14), reason: s.id);
      expect(s.ji.length, lessThanOrEqualTo(14), reason: s.id);
    }
  });

  test('宜忌都给了具体动作，不是空话', () {
    for (final s in kFunSigns) {
      expect(s.yi.trim(), isNotEmpty, reason: s.id);
      expect(s.ji.trim(), isNotEmpty, reason: s.id);
      expect(s.yi, isNot(s.ji), reason: s.id);
    }
  });

  test('同一天打开签筒拿到同一支，第二天换一支', () {
    final day = DateTime(2026, 11, 20);
    final a = funSignOfDay(day);
    final b = funSignOfDay(DateTime(2026, 11, 20, 23, 59));
    expect(a.id, b.id);
    final next = funSignOfDay(DateTime(2026, 11, 21));
    expect(next.id, isNot(a.id));
  });

  test('连续 80 天能把整筒轮完一遍，不重复', () {
    final seen = <String>{};
    for (var i = 0; i < kFunSignCount; i++) {
      seen.add(funSignOfDay(DateTime(2026, 1, 1).add(Duration(days: i))).id);
    }
    expect(seen.length, kFunSignCount);
  });

  test('再摇一签会避开刚刚那支', () {
    final first = kFunSigns.first;
    for (var i = 0; i < 200; i++) {
      expect(randomFunSign(avoidId: first.id).id, isNot(first.id));
    }
  });

  test('16 个签种在文案上互不串味：每种至少有一支提到自己的关键词', () {
    const marks = {
      '摸鱼签': ['摸鱼', '发呆', '会议', '午休', '偷'],
      '早八签': ['早八', '闹钟', '通勤', '起床', '迟到'],
      '干饭签': ['吃饭', '汤', '蛋', '饭', '拼桌'],
      '熬夜签': ['夜', '灯', '睡', '刷'],
      '猫缘签': ['猫'],
      '社恐签': ['群', '社恐', '社交', '拒', '朋友'],
      '打工人签': ['周报', '述职', '加班', '团建', '下班'],
      '出门签': ['车', '酒店', '房', '拍', '路', '行李'],
      '手机签': ['电', '消息', '缓存', '照片', '屏幕'],
      '学生签': ['作业', '错题', '课间', '背', '放学'],
      '财迷签': ['余额', '钱', 'AA', '买', '闲置'],
      '灵感签': ['灵感', '想法', '草稿', '版', '念头'],
      '断舍离签': ['抽屉', '群', '扔', '桌面', '囤'],
      '天气签': ['伞', '雨', '太阳', '天', '冷'],
      '废话签': ['话', '问题', '下次', '凡事'],
      '反内耗签': ['内耗', '完美', '复盘', '情绪', '努力'],
    };
    for (final entry in marks.entries) {
      final group = funSignsOf(entry.key);
      final hit = group.any((s) {
        final all = '${s.name}${s.poem1}${s.poem2}${s.note}';
        return entry.value.any(all.contains);
      });
      expect(hit, isTrue, reason: '${entry.key} 至少一支该提到主题词');
    }
  });
}
