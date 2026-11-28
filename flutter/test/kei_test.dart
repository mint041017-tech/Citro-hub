import 'dart:io';

import 'package:citro/kei/models.dart';
import 'package:citro/kei/scoring.dart';
import 'package:citro/kei/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late KeiBank bank;

  setUpAll(() {
    bank = KeiBank.parse(File('assets/kei/kei.json').readAsStringSync());
  });

  test('十二系题库与类型完整', () {
    expect(bank.dimensions.length, 5);
    expect(bank.questions.length, 40);
    expect(bank.prototypes.length, 12);
    expect(bank.prototypes.map((e) => e.name), contains('月光系'));
  });

  test('中立作答得到均衡概率', () {
    final result = KeiScoring.analyze(
      bank: bank,
      answers: List<int>.filled(40, 0),
    );
    expect(result.ranked.length, 12);
    expect(
      result.ranked.fold<double>(0, (s, e) => s + e.prob),
      closeTo(1, 1e-6),
    );
    expect(result.ranked.first.pct, closeTo(100 / 12, .05));
    expect(result.vec.every((v) => v.abs() < 1e-9), isTrue);
  });

  test('极端正向作答收敛到单一原型', () {
    final answers = [
      for (var i = 0; i < bank.questions.length; i++) bank.questions[i].dir * 3,
    ];
    final result = KeiScoring.analyze(bank: bank, answers: answers);
    expect(result.typeName, isNotEmpty);
    expect(result.stabilityPct, greaterThan(60));
    expect(result.dimensions.every((d) => d.mean > .8), isTrue);
    expect(result.compatBest, hasLength(3));
    expect(result.compatHard, hasLength(2));
    expect(result.synthesis, isNotEmpty);
  });

  test('固定答案与原版 HTML 结果一致', () {
    final answers = List.generate(40, (i) => ((i * 3 + 1) % 7) - 3);
    final result = KeiScoring.analyze(bank: bank, answers: answers);
    expect(result.dimensions.map((d) => d.mean).toList(), [
      closeTo(.0417, .0002),
      closeTo(-.25, .0002),
      closeTo(.3333, .0002),
      closeTo(.5417, .0002),
      closeTo(-.2917, .0002),
    ]);
    expect(result.ranked.first.name, '守护系');
    expect(result.ranked.first.pct, closeTo(22.1, .05));
    expect(result.ranked[1].name, '浮力系');
    expect(result.ranked[2].name, '重力系');
    expect(result.norm, closeTo(.7442, .0002));
  });

  test('效度审计识别过快作答并随记录序列化', () {
    final answers = List<int>.filled(40, 0);
    final result = KeiScoring.analyze(
      bank: bank,
      answers: answers,
      timings: List<int>.filled(40, 500),
    );
    final audit = result.audit!;
    expect(audit.longstring, 40);
    expect(audit.medianSec, .5);
    expect(audit.validityStatus, anyOf('需留意', '建议重测'));
    expect(audit.validityWarn, isTrue);
    expect(audit.warnings.join(), contains('阅读过快'));

    final record = KeiRecord(id: 'audit', takenAtMs: 1, result: result);
    final restored = KeiRecord.fromJson(
      Map<String, dynamic>.from(record.toJson()),
    );
    expect(restored.result.audit!.antonymScore, audit.antonymScore);
    expect(restored.result.audit!.validityStatus, audit.validityStatus);
  });

  test('旧版记录没有审计数据时保持兼容', () {
    final result = KeiScoring.analyze(
      bank: bank,
      answers: List<int>.filled(40, 0),
    );
    final json = result.toJson()..remove('audit');
    final restored = KeiResult.fromJson(Map<String, dynamic>.from(json));
    expect(restored.audit, isNull);
    expect(restored.typeId, result.typeId);
  });

  test('档案合并保留较新的同 id 记录', () {
    final result = KeiScoring.analyze(
      bank: bank,
      answers: List<int>.filled(40, 0),
    );
    final local = KeiRecord(
      id: 'same',
      takenAtMs: 100,
      updatedAtMs: 100,
      result: result,
    );
    final remote = KeiRecord(
      id: 'same',
      takenAtMs: 100,
      updatedAtMs: 200,
      result: result,
    );
    final merged = KeiStore.mergeRecords([local], [remote]);
    expect(merged, hasLength(1));
    expect(merged.first.effectiveUpdatedAt, 200);
  });

  test('KeiRecord 序列化与 copyWith 支持 aiInsight', () {
    final result = KeiScoring.analyze(
      bank: bank,
      answers: List<int>.filled(40, 0),
    );
    final record = KeiRecord(id: 'ai-1', takenAtMs: 100, result: result);
    final updated = record.copyWith(
      aiInsight: '你在亲密关系中倾向于温和靠近并保持觉察。',
      updatedAtMs: 250,
    );
    final restored = KeiRecord.fromJson(
      Map<String, dynamic>.from(updated.toJson()),
    );
    expect(restored.aiInsight, '你在亲密关系中倾向于温和靠近并保持觉察。');
    expect(restored.effectiveUpdatedAt, 250);
  });
}
