import 'dart:convert';

import 'package:citro/data/fortunes.dart';
import 'package:citro/fortune/ai_sign.dart';
import 'package:flutter_test/flutter_test.dart';

const _good = {
  'title': '先递一句话',
  'poem': ['案头积了三日的稿', '今日先发第一版'],
  'read':
      '你今天大概会把那封邮件改到第四遍。改到第三遍时，问题已经不在措辞，而在你还没决定要不要发。先把第一版发出去，附一句细节我再补，比继续磨更省力。',
  'keywords': ['先发初版', '少改两遍', '留补的余地'],
  'do': '把初稿发出去',
  'dont': '再改第四遍',
  'note': '稿子怕的不是粗，是停在手里。',
};

void main() {
  test('解析严格 JSON', () {
    final sign = parseAiSign(jsonEncode(_good))!;
    expect(sign.title, '先递一句话');
    expect(sign.poem.length, 2);
    expect(sign.keywords.length, 3);
    expect(sign.doText, '把初稿发出去');
    expect(sign.dontText, '再改第四遍');
    expect(sign.isComplete, isTrue);
  });

  test('容忍代码围栏和前后解释', () {
    final raw = '好的，这一签我这样写：\n```json\n${jsonEncode(_good)}\n```\n希望合今天的意。';
    final sign = parseAiSign(raw)!;
    expect(sign.title, '先递一句话');
    expect(sign.read.contains('```'), isFalse);
  });

  test('poem / keywords 退化成字符串也能读', () {
    final j = Map<String, dynamic>.from(_good)
      ..['poem'] = '案头积了三日的稿｜今日先发第一版'
      ..['keywords'] = '先发初版、少改两遍、留补的余地';
    final sign = parseAiSign(jsonEncode(j))!;
    expect(sign.poem.length, 2);
    expect(sign.keywords.length, 3);
  });

  test('缺签题或读签太短就判为无效', () {
    final noTitle = Map<String, dynamic>.from(_good)..remove('title');
    expect(parseAiSign(jsonEncode(noTitle)), isNull);
    final shortRead = Map<String, dynamic>.from(_good)..['read'] = '今天还好。';
    expect(parseAiSign(jsonEncode(shortRead)), isNull);
  });

  test('不是 JSON 就返回 null，不抛异常', () {
    expect(parseAiSign('今天宜早睡。'), isNull);
    expect(parseAiSign(''), isNull);
    expect(parseAiSign('{}'), isNull);
  });

  test('清洗掉模型手写的 Markdown 符号', () {
    final j = Map<String, dynamic>.from(_good)
      ..['title'] = '**先递一句话**'
      ..['note'] = '`稿子怕的不是粗`';
    final sign = parseAiSign(jsonEncode(j))!;
    expect(sign.title, '先递一句话');
    expect(sign.note.contains('`'), isFalse);
  });

  test('分段文本协议能解析完整七段', () {
    final raw =
        '''
@@签题
先递一句话
@@诗
案头积了三日的稿
今日先发第一版
@@读签
${_good['read']}
@@关键词
先发初版、少改两遍、留补的余地
@@今日一小步
把桌角的三张纸叠好
@@忌
再改第四遍
@@便签
稿子怕的不是粗，是停在手里。
''';
    final sign = parseSegmentedSign(raw)!;
    expect(sign.title, '先递一句话');
    expect(sign.poem.length, 2);
    expect(sign.keywords.length, 3);
    expect(sign.doText, '把桌角的三张纸叠好');
    expect(sign.dontText, '再改第四遍');
    expect(sign.note, '稿子怕的不是粗，是停在手里。');
    expect(sign.isComplete, isTrue);
  });

  test('分段流里读签先出现，半截动作不提前显示', () {
    final raw =
        '''
@@签题
先递一句话
@@诗
案头积了三日的稿
今日先发第一版
@@读签
${_good['read']}
@@关键词
先发初版、少改两遍、留补的余地
@@今日一小步
把桌角的三张纸叠好
''';
    final beforeStep = raw.substring(0, raw.indexOf('@@今日一小步'));
    final partial = parseSegmentedSign(beforeStep, partial: true)!;
    expect(partial.read, contains('第四遍'));
    expect(partial.doText, isEmpty);
    expect(partial.note, isEmpty);

    final writingStep = parseSegmentedSign(raw, partial: true)!;
    expect(writingStep.doText, isEmpty, reason: '「忌」还没出现，动作可能只写了一半');
  });

  test('分段协议不成立时仍能回退旧 JSON', () {
    final raw = '这一签我写成这样：\n${jsonEncode(_good)}';
    expect(parseSegmentedSign(raw), isNull);
    expect(parseAiSign(raw)?.title, '先递一句话');
  });

  test('今日一小步拒绝要人、要出门、要买东西的动作', () {
    expect(isReasonableStep('给妈妈发一句今天到家了'), isFalse);
    expect(isReasonableStep('把清单上最小的一件事交给同事'), isFalse);
    expect(isReasonableStep('下楼走十分钟再回来'), isFalse);
    expect(isReasonableStep('点一份外卖当晚饭'), isFalse);
    expect(isReasonableStep('调整心态'), isFalse);
    expect(isReasonableStep('把桌面上三个杯子洗掉'), isTrue);
    expect(isReasonableStep('把桌角的三张纸叠好'), isTrue);
  });

  test('兜底动作池全部通过校验', () {
    for (final step in kFortuneFallbackSteps) {
      expect(isReasonableStep(step), isTrue, reason: step);
    }
  });

  test('缓存键按天按等级区分，转运后不会读到旧解', () {
    final day = DateTime(2026, 11, 20);
    final a = fortuneForDay(6, day);
    final b = fortuneForDay(1, day);
    expect(FortuneAi.cacheKey(a, day), 'citro_fortune_ai_2026-11-20_6');
    expect(FortuneAi.cacheKey(b, day), 'citro_fortune_ai_2026-11-20_1');
  });
}
