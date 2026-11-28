import 'dart:math';

import 'package:citro/mbti/models.dart';
import 'package:citro/mbti/scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MbtiBank bank;
  late TypeLibrary library;

  setUpAll(() async {
    bank = await MbtiBank.load();
    library = await TypeLibrary.load();
  });

  /// 按目标画像作答：target 为各维期望字母所在端（'left'/'right'）。
  Map<String, int> answersFor(
    MbtiMode mode,
    Map<String, String> target, {
    int agree = 7,
  }) {
    final answers = <String, int>{};
    for (final q in bank.questionsFor(mode)) {
      final side = target[q.dim] ?? 'right';
      final match = q.keyed == side;
      // 与目标同向时给"很同意"，反向时给"很不同意"。
      answers[q.id] = match ? agree : 8 - agree;
    }
    return answers;
  }

  group('题库结构', () {
    test('各版本题量与维度分布正确', () {
      expect(bank.questionsFor(MbtiMode.quick), hasLength(28));
      expect(bank.questionsFor(MbtiMode.standard), hasLength(64));
      expect(bank.questionsFor(MbtiMode.full), hasLength(96));
      for (final dim in ['EI', 'SN', 'TF', 'JP']) {
        expect(
          bank.questionsFor(MbtiMode.standard).where((q) => q.dim == dim),
          hasLength(16),
          reason: '$dim 标准版应为 16 题',
        );
        expect(
          bank.questionsFor(MbtiMode.quick).where((q) => q.dim == dim),
          hasLength(7),
          reason: '$dim 快速版应为 7 题',
        );
      }
      expect(
        bank.questionsFor(MbtiMode.full).where((q) => q.dim == 'AT'),
        hasLength(16),
      );
      expect(
        bank.questionsFor(MbtiMode.standard).any((q) => q.dim == 'AT'),
        isFalse,
      );
    });

    test('题目 id 唯一，题对双向有效，keyed 合法', () {
      final ids = bank.questions.map((q) => q.id).toSet();
      expect(ids, hasLength(bank.questions.length));
      for (final q in bank.questions) {
        expect(['left', 'right'], contains(q.keyed));
        if (q.pair != null) {
          final other = bank.questions.firstWhere((e) => e.id == q.pair);
          expect(other.dim, q.dim);
          expect(other.pair, q.id, reason: '${q.id} 的题对未互指');
        }
      }
    });

    test('每维正反向题均衡（反向占 30%~60%）', () {
      for (final dim in ['EI', 'SN', 'TF', 'JP', 'AT']) {
        final qs = bank.questions.where((q) => q.dim == dim).toList();
        final left = qs.where((q) => q.keyed == 'left').length;
        final ratio = left / qs.length;
        expect(
          ratio,
          inInclusiveRange(0.3, 0.6),
          reason: '$dim 反向题占比 $ratio 不均衡',
        );
      }
    });

    test('作答顺序四维交错', () {
      final qs = bank.questionsFor(MbtiMode.standard);
      for (var i = 0; i + 4 < qs.length; i += 4) {
        final dims = qs.sublist(i, i + 4).map((q) => q.dim).toSet();
        expect(dims, hasLength(4), reason: '第 $i 组应覆盖四个维度');
      }
    });
  });

  group('16 型内容包', () {
    test('16 型齐全且字段完整', () {
      expect(library.types, hasLength(16));
      for (final t in library.types.values) {
        expect(t.code, hasLength(4));
        expect(t.stack, hasLength(4));
        expect(t.strengths, hasLength(4));
        expect(t.pitfalls, hasLength(4));
        expect(t.growth, hasLength(3));
        for (final key in ['work', 'love', 'social', 'stress']) {
          expect(t.scenes[key]?.isNotEmpty, isTrue, reason: '${t.code} 缺 $key');
        }
      }
    });
  });

  group('计分', () {
    test('16 种极端画像得出对应类型', () {
      const lefts = ['E', 'S', 'T', 'J'];
      const rights = ['I', 'N', 'F', 'P'];
      for (var mask = 0; mask < 16; mask++) {
        final expected = <String>[];
        final target = <String, String>{};
        final dims = ['EI', 'SN', 'TF', 'JP'];
        for (var i = 0; i < 4; i++) {
          final right = mask & (1 << i) != 0;
          expected.add(right ? rights[i] : lefts[i]);
          target[dims[i]] = right ? 'right' : 'left';
        }
        final result = MbtiScoring.score(
          bank: bank,
          mode: MbtiMode.standard,
          answers: answersFor(MbtiMode.standard, target),
        );
        expect(result.typeRaw, expected.join(), reason: '画像 mask=$mask');
        for (final s in result.scores.values) {
          expect(s.value.abs(), closeTo(1.0, 1e-9));
          expect(s.band, DimBand.clear);
        }
      }
    });

    test('极端作答的百分比与后缀', () {
      final allLeft = answersFor(MbtiMode.full, {
        'EI': 'left',
        'SN': 'left',
        'TF': 'left',
        'JP': 'left',
        'AT': 'left',
      });
      final r1 = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.full,
        answers: allLeft,
      );
      expect(r1.typeRaw, 'ESTJ');
      expect(r1.displayType, 'ESTJ-A');
      expect(r1.scores['EI']!.pctLeft, 100);
      expect(r1.scores['EI']!.pctRight, 0);

      final allRight = answersFor(MbtiMode.full, {
        'EI': 'right',
        'SN': 'right',
        'TF': 'right',
        'JP': 'right',
        'AT': 'right',
      });
      final r2 = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.full,
        answers: allRight,
      );
      expect(r2.displayType, 'INFP-T');
      expect(r2.scores['AT']!.pctRight, 100);
    });

    test('全中立作答：贴线、值域为 0', () {
      final answers = {
        for (final q in bank.questionsFor(MbtiMode.standard)) q.id: 4,
      };
      final result = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.standard,
        answers: answers,
      );
      for (final s in result.scores.values) {
        expect(s.value, 0);
        expect(s.band, DimBand.center);
        expect(s.pctLeft, 50);
      }
    });

    test('快速版贴线阈值更宽', () {
      // 构造 D≈0.17：快速版 7 题中，5 题 +1 分、2 题 -1 分 → 3/21≈0.143。
      // 直接用 6 题 +1、1 题 -2 → 4/21≈0.19，落在 quick center、std mild 之间。
      final qs = bank.questionsFor(MbtiMode.quick).where((q) => q.dim == 'EI');
      final answers = <String, int>{};
      for (final q in bank.questionsFor(MbtiMode.quick)) {
        answers[q.id] = 4;
      }
      var i = 0;
      for (final q in qs) {
        final a = i < 6 ? 5 : 2;
        answers[q.id] = q.keyed == 'right' ? a : 8 - a;
        i++;
      }
      final result = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.quick,
        answers: answers,
      );
      final d = result.scores['EI']!.value;
      expect(d, closeTo(4 / 21, 1e-9));
      expect(result.scores['EI']!.band, DimBand.center);
    });

    test('缺答与越界会抛错', () {
      expect(
        () => MbtiScoring.score(
          bank: bank,
          mode: MbtiMode.standard,
          answers: {},
        ),
        throwsArgumentError,
      );
      final answers = answersFor(MbtiMode.standard, {});
      answers[bank.questionsFor(MbtiMode.standard).first.id] = 9;
      expect(
        () => MbtiScoring.score(
          bank: bank,
          mode: MbtiMode.standard,
          answers: answers,
        ),
        throwsArgumentError,
      );
    });

    test('快速版与标准版同画像结果一致', () {
      final target = {'EI': 'left', 'SN': 'right', 'TF': 'left', 'JP': 'right'};
      final quick = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.quick,
        answers: answersFor(MbtiMode.quick, target),
      );
      final std = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.standard,
        answers: answersFor(MbtiMode.standard, target),
      );
      expect(quick.typeRaw, std.typeRaw);
    });

    test('随机作答 500 次：值域与类型合法', () {
      final random = Random(42);
      final letters = {'E', 'I', 'S', 'N', 'T', 'F', 'J', 'P'};
      for (var i = 0; i < 500; i++) {
        final answers = {
          for (final q in bank.questionsFor(MbtiMode.standard))
            q.id: random.nextInt(7) + 1,
        };
        final result = MbtiScoring.score(
          bank: bank,
          mode: MbtiMode.standard,
          answers: answers,
        );
        expect(result.typeRaw, hasLength(4));
        expect(letters.containsAll(result.typeRaw.split('')), isTrue);
        for (final s in result.scores.values) {
          expect(s.value, inInclusiveRange(-1.0, 1.0));
          expect(s.pctLeft + s.pctRight, 100);
        }
      }
    });
  });

  group('作答质检', () {
    test('作答过快被标记', () {
      final result = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.standard,
        answers: answersFor(MbtiMode.standard, {}),
        durationSec: 20,
      );
      expect(result.quality.fastFinish, isTrue);
      expect(result.quality.hasWarning, isTrue);
    });

    test('直线作答被标记', () {
      final answers = {
        for (final q in bank.questionsFor(MbtiMode.standard)) q.id: 5,
      };
      final result = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.standard,
        answers: answers,
      );
      expect(result.quality.straightLine, isTrue);
    });

    test('一致性题对：矛盾作答被识别，一致作答不误报', () {
      // 矛盾：EI-04（边说边想，偏E）很同意，EI-14（先想清楚，偏I）也很同意。
      final bad = answersFor(MbtiMode.standard, {});
      bad['EI-04'] = 7;
      bad['EI-14'] = 7;
      final r1 = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.standard,
        answers: bad,
      );
      expect(r1.quality.inconsistentPairs, greaterThanOrEqualTo(1));

      final good = answersFor(MbtiMode.standard, {'EI': 'left'});
      final r2 = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.standard,
        answers: good,
      );
      expect(r2.quality.inconsistentPairs, 0);
    });

    test('结果可序列化往返', () {
      final result = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.full,
        answers: answersFor(MbtiMode.full, {}),
      );
      final restored = MbtiResult.fromJson(result.toJson());
      expect(restored.typeRaw, result.typeRaw);
      expect(restored.atSuffix, result.atSuffix);
      expect(restored.scores.length, result.scores.length);
      expect(restored.mode, result.mode);
      expect(restored.audit, isNotNull);
      expect(restored.audit!.antonymScore, result.audit!.antonymScore);
      expect(restored.audit!.validityStatus, result.audit!.validityStatus);
    });

    test('效度审计识别高质量作答、极速作答与旧版记录兼容', () {
      final goodAnswers = answersFor(MbtiMode.full, {
        'EI': 'left',
        'SN': 'right',
        'TF': 'left',
        'JP': 'right',
        'AT': 'left',
      }, agree: 6);
      final good = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.full,
        answers: goodAnswers,
        durationSec: 300,
        timingsMs: List<int>.filled(96, 3000),
      );
      expect(good.audit, isNotNull);
      expect(good.audit!.antonymScore, 100);
      expect(good.audit!.validityStatus, '高可靠');
      expect(good.audit!.validityWarn, isFalse);

      final fastBad = MbtiScoring.score(
        bank: bank,
        mode: MbtiMode.full,
        answers: {for (final q in bank.questionsFor(MbtiMode.full)) q.id: 7},
        durationSec: 25,
        timingsMs: List<int>.filled(96, 500),
      );
      expect(fastBad.audit!.longstring, 96);
      expect(fastBad.audit!.ersPct, 100);
      expect(fastBad.audit!.medianSec, 0.5);
      expect(fastBad.audit!.validityStatus, '建议重测');
      expect(fastBad.audit!.validityWarn, isTrue);

      final legacyJson = good.toJson()..remove('audit');
      final legacy = MbtiResult.fromJson(legacyJson);
      expect(legacy.audit, isNull);
      expect(legacy.typeRaw, good.typeRaw);
    });
  });
}
