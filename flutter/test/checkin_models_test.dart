import 'package:citro/checkin/checkin_models.dart';
import 'package:citro/checkin/daily_actions.dart';
import 'package:flutter_test/flutter_test.dart';

CheckinDayEntry _entry(
  String date, {
  String kind = 'study',
  bool done = false,
  bool reflected = false,
}) {
  final now = DateTime(2026, 11, 21).millisecondsSinceEpoch;
  return CheckinDayEntry(
    date: date,
    signId: 'sign-01',
    signTitle: '测试签',
    levelIndex: 0,
    kind: kind,
    actionText: '专注十分钟',
    actionType: CheckinActionType.focus,
    actionStatus: done ? CheckinActionStatus.done : CheckinActionStatus.pending,
    createdAt: now,
    updatedAt: now,
    reflectionMood: reflected ? CheckinMood.same : null,
    reflectionText: reflected ? '今天还算稳' : '',
    reflectionUpdatedAt: reflected ? now : null,
  );
}

void main() {
  group('七日成卷', () {
    test('每七条一卷，不要求连续日期', () {
      final days = [
        _entry('2026-11-01'),
        _entry('2026-11-03'),
        _entry('2026-11-05'),
        _entry('2026-11-08'),
        _entry('2026-11-12'),
        _entry('2026-11-15'),
        _entry('2026-11-20'),
        _entry('2026-11-21'),
      ];
      final volumes = buildCheckinVolumes(days);
      expect(volumes, hasLength(2));
      expect(volumes.first.entries, hasLength(7));
      expect(volumes.first.full, isTrue);
      expect(volumes.first.startDate, '2026-11-01');
      expect(volumes.first.endDate, '2026-11-20');
      expect(volumes.last.entries, hasLength(1));
      expect(volumes.last.title, '第 2 卷');
    });

    test('同日期的重复记录不会增加格子（由调用方 Map 保证）', () {
      final days = {'2026-11-21': _entry('2026-11-21')};
      expect(buildCheckinVolumes(days.values.toList()), hasLength(1));
      expect(buildCheckinVolumes(days.values.toList()).first.filled, 1);
    });
  });

  group('首页状态机', () {
    test('未打卡是待打卡', () {
      final view = checkinHomeView(
        today: null,
        now: DateTime(2026, 11, 21, 19),
        streak: 3,
      );
      expect(view.phase, CheckinHomePhase.notChecked);
      expect(view.pill, '待打卡');
      expect(view.subtitle, '翻开今天的签');
    });

    test('18 点前行动未完成，提示今日一小步', () {
      final view = checkinHomeView(
        today: _entry('2026-11-21'),
        now: DateTime(2026, 11, 21, 17),
        streak: 3,
      );
      expect(view.phase, CheckinHomePhase.actionPending);
      expect(view.pill, '已打卡');
      expect(view.subtitle, '今日一小步还等着你');
    });

    test('18 点后未回签，即使行动没做也切到待回签', () {
      final view = checkinHomeView(
        today: _entry('2026-11-21'),
        now: DateTime(2026, 11, 21, 19),
        streak: 3,
      );
      expect(view.phase, CheckinHomePhase.pendingReflection);
      expect(view.pill, '待回签');
      expect(view.subtitle, '给今天收个尾');
    });

    test('行动完成、18 点前是已打卡，18 点后是待回签', () {
      final before = checkinHomeView(
        today: _entry('2026-11-21', done: true),
        now: DateTime(2026, 11, 21, 17),
        streak: 3,
      );
      expect(before.phase, CheckinHomePhase.actionDone);
      expect(before.subtitle, '今天已经留下了脚印');

      final after = checkinHomeView(
        today: _entry('2026-11-21', done: true),
        now: DateTime(2026, 11, 21, 19),
        streak: 3,
      );
      expect(after.phase, CheckinHomePhase.pendingReflection);
      expect(after.pill, '待回签');
      expect(after.subtitle, '给今天收个尾');
    });

    test('已回签优先于时间状态', () {
      final view = checkinHomeView(
        today: _entry('2026-11-21', done: true, reflected: true),
        now: DateTime(2026, 11, 21, 19),
        streak: 7,
      );
      expect(view.phase, CheckinHomePhase.reflected);
      expect(view.pill, '已收好');
      expect(view.subtitle, '今天收好了 · 连续 7 天');
    });
  });

  group('文本与日期', () {
    test('按码点截断，不切坏 emoji', () {
      final text = '今天🌿很好';
      expect(checkinClampText(text, 3), '今天🌿');
      expect(checkinClampText('  abc  ', 10), 'abc');
    });

    test('日期标签与严格校验', () {
      expect(checkinDateLabel('2026-11-21'), '11 月 21 日 · 周六');
      expect(checkinDateLabel('2026-11-21', withWeekday: false), '11 月 21 日');
      expect(isCheckinDate('2026-11-21'), isTrue);
      expect(isCheckinDate('2026-02-30'), isFalse);
      expect(checkinParseDate('2026-02-30'), isNull);
    });
  });

  group('行动映射', () {
    test('十类签都有按钮与提示', () {
      for (final kind in [
        'career',
        'study',
        'heart',
        'social',
        'body',
        'action',
        'money',
        'rest',
        'idea',
        'tiny',
      ]) {
        final plan = checkinPlanForKind(kind);
        expect(plan.primaryLabel, isNotEmpty);
        expect(plan.hint, isNotEmpty);
      }
      expect(checkinPlanForKind('study').type, CheckinActionType.focus);
      expect(checkinPlanForKind('study').thresholdMinutes, 10);
      expect(checkinPlanForKind('heart').opensReflection, isTrue);
      expect(checkinPlanForKind('idea').opensReflection, isTrue);
      expect(checkinPlanForKind('tiny').hasPrimary, isFalse);
    });
  });

  test('本地字段不会进入服务端快照', () {
    final entry = _entry('2026-11-21')
        .copyWith(pendingSync: true, actionStartedAt: 123);
    final server = entry.toJson(includeLocal: false);
    expect(server.containsKey('pendingSync'), isFalse);
    expect(server.containsKey('actionStartedAt'), isFalse);
    expect(entry.creationPayload().containsKey('pendingSync'), isFalse);
  });
}
