import 'package:citro/calendar/calendar_ai.dart';
import 'package:citro/calendar/calendar_models.dart';
import 'package:citro/ledger/ledger_ai.dart';
import 'package:citro/ledger/ledger_models.dart';
import 'package:citro/todo/todo_ai.dart';
import 'package:flutter_test/flutter_test.dart';

const _food = LedgerCategory(
  id: 'food',
  name: '餐饮',
  kind: LedgerKind.expense,
  color: 0xFFC08A4A,
  iconKey: 'fork',
  builtIn: true,
);
const _otherExpense = LedgerCategory(
  id: 'other_expense',
  name: '其他',
  kind: LedgerKind.expense,
  color: 0xFF8A7F6A,
  iconKey: 'flag',
  builtIn: true,
);

const _categories = [_food, _otherExpense];

void main() {
  group('日历指令解析', () {
    test('倒数日与纪念日字段解析、正文去掉指令', () {
      const raw =
          '好的，我记下了。\n'
          '[[CAL]]{"title":"考研初试","date":"2026-12-20","kind":"countdown","yearly":false,"note":"带准考证"}\n'
          '[[CAL]]{"title":"在一起","date":"2023-05-20","kind":"anniversary","yearly":true}';
      final (clean, drafts) = CalendarAi.parseReply(raw);
      expect(clean, '好的，我记下了。');
      expect(drafts.length, 2);

      final exam = drafts.firstWhere((d) => d.title == '考研初试');
      expect(exam.kind, CalendarMarkKind.countdown);
      expect(exam.yearly, isFalse);
      expect(exam.date, DateTime(2026, 12, 20));
      expect(exam.note, '带准考证');

      final together = drafts.firstWhere((d) => d.title == '在一起');
      expect(together.kind, CalendarMarkKind.anniversary);
      expect(together.yearly, isTrue);
      expect(together.date, DateTime(2023, 5, 20));
    });

    test('缺标题 / 缺日期 / 脏日期被跳过，非法 kind 回退倒数日', () {
      const raw =
          '[[CAL]]{"title":"","date":"2026-12-20"}\n'
          '[[CAL]]{"title":"没有日期","kind":"anniversary"}\n'
          '[[CAL]]{"title":"2 月 30 日","date":"2026-02-30"}\n'
          '[[CAL]]{"title":"国庆","date":"2026/10/01","kind":"unknown"}';
      final (clean, drafts) = CalendarAi.parseReply(raw);
      expect(clean, isEmpty);
      expect(drafts.length, 1);
      expect(drafts.single.title, '国庆');
      expect(drafts.single.date, DateTime(2026, 10, 1));
      expect(drafts.single.kind, CalendarMarkKind.countdown);
    });

    test('yearly 支持字符串与 repeat 别名，没有指令时正文原样保留', () {
      const raw =
          '记好了。\n'
          '[[CAL]]{"title":"生日","date":"2026-12-05","yearly":"true"}\n'
          '[[CAL]]{"title":"结婚纪念","date":"2019-06-01","kind":"anniversary","repeat":"yearly"}';
      final (clean, drafts) = CalendarAi.parseReply(raw);
      expect(clean, '记好了。');
      expect(drafts.every((d) => d.yearly), isTrue);

      final (plain, none) = CalendarAi.parseReply('今天想聊点什么？');
      expect(plain, '今天想聊点什么？');
      expect(none, isEmpty);
    });
  });

  group('首页 CiCi 三类指令共存', () {
    test('待办 / 日历 / 账单依次剥离，互不吞噬', () {
      const raw =
          '好的，都记下了。\n'
          '[[TODO]]{"title":"交论文","kind":"task","at":"2026-11-20 18:00"}\n'
          '[[CAL]]{"title":"交论文截止","date":"2026-11-20","kind":"countdown"}\n'
          '```ledger\n'
          '{"entries":[{"kind":"expense","amount":18.5,"category":"餐饮","note":"咖啡"}]}\n'
          '```';
      final (afterTodo, todoDrafts) = TodoAi.parseReply(raw);
      final (afterCalendar, markDrafts) = CalendarAi.parseReply(afterTodo);
      final (clean, ledgerDrafts) = LedgerAi.parseReply(
        afterCalendar,
        categories: _categories,
        now: DateTime(2026, 11, 9, 10),
      );

      expect(todoDrafts.single.title, '交论文');
      expect(markDrafts.single.title, '交论文截止');
      expect(ledgerDrafts.single.amountCents, 1850);
      expect(ledgerDrafts.single.categoryId, 'food');
      expect(clean, '好的，都记下了。');
    });
  });

  group('日历上下文', () {
    test('空列表提示与当前日期', () {
      final context = CalendarAi.contextFor(
        marks: const [],
        now: DateTime(2026, 11, 16, 9),
      );
      expect(context.contains('2026-11-16'), isTrue);
      expect(context.contains('还没有记录'), isTrue);
    });

    test('已有标记按临近程度排序并带天数文案', () {
      final context = CalendarAi.contextFor(
        marks: [
          CalendarMark(
            id: 'cal-1',
            title: '远方的旅行',
            date: DateTime(2027, 3, 1),
            kind: CalendarMarkKind.countdown,
          ),
          CalendarMark(
            id: 'cal-2',
            title: '在一起',
            date: DateTime(2023, 5, 20),
            kind: CalendarMarkKind.anniversary,
            yearly: true,
          ),
        ],
        now: DateTime(2026, 11, 16),
      );
      expect(context.contains('已有 2 个'), isTrue);
      expect(context.contains('在一起'), isTrue);
      expect(context.contains('纪念日'), isTrue);
      expect(context.contains('每年重复'), isTrue);
      expect(context.contains('远方的旅行'), isTrue);
      expect(context.contains('还有'), isTrue);
      // 更近的标记排在前面。
      expect(context.indexOf('远方的旅行') < context.indexOf('在一起'), isTrue);
    });
  });
}
