import 'package:citro/calendar/calendar_models.dart';
import 'package:citro/calendar/calendar_store.dart';
import 'package:citro/services/prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CalendarMark _mark({
  String id = 'cal-1',
  String title = '出发去大理',
  required DateTime date,
  CalendarMarkKind kind = CalendarMarkKind.countdown,
  bool yearly = false,
  String note = '',
}) => CalendarMark(
  id: id,
  title: title,
  date: date,
  kind: kind,
  yearly: yearly,
  note: note,
  createdAt: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = CalendarStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    store.resetForTest();
    await store.ensureInit();
  });

  test('单次倒数日按目标日计算天数与文案', () {
    final today = DateTime(2026, 11, 9);
    final mark = _mark(date: DateTime(2026, 11, 20));
    expect(CalendarDates.daysFor(mark, today), 11);
    expect(CalendarDates.labelFor(mark, today), '还有 11 天');
    expect(CalendarDates.unitFor(mark, today), '还有');
  });

  test('每年重复的倒数日过了当天会顺延到下一年', () {
    final today = DateTime(2026, 11, 9);
    final mark = _mark(date: DateTime(2020, 11, 1), yearly: true);
    expect(CalendarDates.daysFor(mark, today), 357);
    expect(CalendarDates.labelFor(mark, today), '还有 357 天');
    expect(CalendarDates.occurrence(mark, today), DateTime(2027, 11, 1));
  });

  test('纪念日按起始日累计天数，并给出年度周年', () {
    final today = DateTime(2026, 11, 9);
    final mark = _mark(
      kind: CalendarMarkKind.anniversary,
      date: DateTime(2020, 11, 9),
      yearly: true,
    );
    expect(CalendarDates.daysFor(mark, today), 2191);
    expect(CalendarDates.labelFor(mark, today), '已经 2191 天');
    expect(CalendarDates.yearCount(mark, today), 7);
    expect(
      CalendarDates.yearCount(
        _mark(kind: CalendarMarkKind.anniversary, date: DateTime(2020, 11, 9)),
        today,
      ),
      isNull,
    );
    expect(
      CalendarDates.yearCount(
        _mark(date: DateTime(2020, 11, 9), yearly: true),
        today,
      ),
      isNull,
    );
  });

  test('年度标记按月日命中，单次标记要求年月日一致', () {
    final yearly = _mark(
      kind: CalendarMarkKind.anniversary,
      date: DateTime(2020, 5, 20),
      yearly: true,
    );
    final single = _mark(date: DateTime(2026, 5, 20));
    expect(CalendarDates.hits(yearly, DateTime(2026, 5, 20)), isTrue);
    expect(CalendarDates.hits(single, DateTime(2026, 5, 20)), isTrue);
    expect(CalendarDates.hits(single, DateTime(2027, 5, 20)), isFalse);
    expect(CalendarDates.hits(yearly, DateTime(2026, 5, 21)), isFalse);
  });

  test('今天是纪念日时文案显示「就是今天」', () {
    final today = DateTime(2026, 11, 9);
    final mark = _mark(
      kind: CalendarMarkKind.anniversary,
      date: DateTime(2026, 11, 9),
    );
    expect(CalendarDates.daysFor(mark, today), 0);
    expect(CalendarDates.labelFor(mark, today), '就是今天');
  });

  test('保存与删除会同步写进本地缓存', () async {
    final mark = _mark(date: DateTime(2026, 12, 1));
    await store.saveMark(mark);
    expect(store.marks.length, 1);
    expect(store.marks.first.title, '出发去大理');

    store.resetForTest();
    await store.ensureInit();
    expect(store.marks.length, 1);
    expect(store.marks.first.date, DateTime(2026, 12, 1));

    await store.removeMark(mark.id);
    expect(store.marks, isEmpty);
  });

  test('列表按倒数日在前、纪念日在后，且各自按临近程度排序', () async {
    final today = DateTime(2026, 11, 9);
    await store.saveMark(
      _mark(id: 'a', title: '远一点的倒数', date: DateTime(2026, 12, 20)),
    );
    await store.saveMark(
      _mark(id: 'b', title: '近一点的倒数', date: DateTime(2026, 11, 12)),
    );
    await store.saveMark(
      _mark(
        id: 'c',
        title: '纪念日',
        kind: CalendarMarkKind.anniversary,
        date: DateTime(2025, 1, 1),
      ),
    );
    final sorted = store.sorted(today);
    expect(sorted.map((m) => m.id), ['b', 'a', 'c']);
    expect(store.todayMarks(today), isEmpty);
  });
}
