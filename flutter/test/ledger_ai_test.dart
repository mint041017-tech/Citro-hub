import 'package:citro/ledger/ledger_ai.dart';
import 'package:citro/ledger/ledger_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _food = LedgerCategory(
  id: 'food',
  name: '餐饮',
  kind: LedgerKind.expense,
  color: 0xFFC08A4A,
  iconKey: 'fork',
  builtIn: true,
);
const _transport = LedgerCategory(
  id: 'transport',
  name: '交通',
  kind: LedgerKind.expense,
  color: 0xFF6F8CA8,
  iconKey: 'location',
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
const _salary = LedgerCategory(
  id: 'salary',
  name: '工资',
  kind: LedgerKind.income,
  color: 0xFF6E9A78,
  iconKey: 'note',
  builtIn: true,
);
const _otherIncome = LedgerCategory(
  id: 'other_income',
  name: '其他',
  kind: LedgerKind.income,
  color: 0xFF8A7F6A,
  iconKey: 'flag',
  builtIn: true,
);

const _categories = [_food, _transport, _otherExpense, _salary, _otherIncome];

void main() {
  group('识别结果解析', () {
    test('金额从元转分、分类按名称匹配、时间可解析', () {
      const raw = '''
{"entries":[
 {"kind":"expense","amount":18.50,"category":"餐饮","note":"瑞幸咖啡","at":"2026-11-08 08:30","confidence":0.92}
]}
''';
      final drafts = LedgerAi.parseDrafts(
        raw,
        categories: _categories,
        now: DateTime(2026, 11, 9, 10),
      );
      expect(drafts.length, 1);
      expect(drafts.single.amountCents, 1850);
      expect(drafts.single.categoryId, 'food');
      expect(drafts.single.kind, LedgerKind.expense);
      expect(drafts.single.note, '瑞幸咖啡');
      expect(drafts.single.occurredAt, DateTime(2026, 11, 8, 8, 30));
      expect(drafts.single.confidence, closeTo(.92, .001));
    });

    test('收入分类、未知分类回退与无效金额被跳过', () {
      const raw = '''
```json
{"entries":[
 {"kind":"income","amount":8000,"category":"工资","note":"九月工资","at":"2026-11-01 09:00"},
 {"kind":"expense","amount":32,"category":"宠物","note":"猫粮","at":"2026-11-02"},
 {"kind":"expense","amount":0,"category":"餐饮"},
 {"kind":"expense","amount":"abc","category":"餐饮"}
]}
```
''';
      final drafts = LedgerAi.parseDrafts(
        raw,
        categories: _categories,
        now: DateTime(2026, 11, 9),
      );
      expect(drafts.length, 2);
      final salary = drafts.firstWhere((d) => d.kind == LedgerKind.income);
      expect(salary.categoryId, 'salary');
      expect(salary.amountCents, 800000);
      final unknown = drafts.firstWhere((d) => d.kind == LedgerKind.expense);
      expect(unknown.categoryId, 'other_expense');
      expect(unknown.amountCents, 3200);
      expect(unknown.confidence, .8);
    });

    test('缺失日期回退到今天，只有时间时补今天日期', () {
      const raw = '''
{"entries":[
 {"kind":"expense","amount":10,"category":"交通"},
 {"kind":"expense","amount":12,"category":"餐饮","at":"18:20"}
]}
''';
      final now = DateTime(2026, 11, 9, 10, 30);
      final drafts = LedgerAi.parseDrafts(
        raw,
        categories: _categories,
        now: now,
      );
      expect(drafts.length, 2);
      expect(
        drafts.every(
          (d) =>
              d.occurredAt.year == 2026 &&
              d.occurredAt.month == 11 &&
              d.occurredAt.day == 9,
        ),
        isTrue,
      );
      expect(drafts.any((d) => d.occurredAt.hour == 18), isTrue);
    });

    test('代码块里的动作从正文移除，并支持无代码块 JSON', () {
      const raw =
          '好的，已经理解。\n```ledger\n'
          '{"entries":[{"kind":"expense","amount":18,"category":"餐饮","note":"奶茶","at":"2026-11-09 15:00"}]}\n'
          '```';
      final (clean, drafts) = LedgerAi.parseReply(
        raw,
        categories: _categories,
        now: DateTime(2026, 11, 9),
      );
      expect(clean, '好的，已经理解。');
      expect(drafts.length, 1);
      expect(drafts.single.amountCents, 1800);

      final (clean2, drafts2) = LedgerAi.parseReply(
        '记一下 {"entries":[{"kind":"income","amount":100,"category":"工资"}]}',
        categories: _categories,
      );
      expect(clean2, '记一下');
      expect(drafts2.single.categoryId, 'salary');
      expect(drafts2.single.amountCents, 10000);
    });

    test('截图识别走注入的多模态钩子', () async {
      LedgerAi.visionCompleter = (prompt, system, dataUrl) async {
        expect(prompt.contains('餐饮'), isTrue);
        expect(dataUrl.startsWith('data:image/jpeg'), isTrue);
        return '{"entries":[{"kind":"expense","amount":25.5,"category":"餐饮","note":"外卖"}]}';
      };
      addTearDown(() => LedgerAi.visionCompleter = null);

      final drafts = await LedgerAi.parseReceipt(
        'data:image/jpeg;base64,abc',
        categories: _categories,
        now: DateTime(2026, 11, 9),
      );
      expect(drafts.single.amountCents, 2550);
      expect(drafts.single.note, '外卖');
    });
  });

  group('账本上下文', () {
    test('摘要包含预算、分类与最近账单', () {
      final context = LedgerAi.contextFor(
        monthKey: '2026-11',
        summary: const LedgerSummary(
          monthKey: '2026-11',
          expenseCents: 3050,
          incomeCents: 800000,
          budgetCents: 10000,
          incomeTargetCents: 0,
          entryCount: 3,
          categorySpend: {'food': 1850, 'transport': 1200},
        ),
        plan: const LedgerPlan(
          monthKey: '2026-11',
          budgetCents: 10000,
          categoryBudgets: {'food': 1000},
        ),
        budgets: [(category: _food, spent: 1850, budget: 1000)],
        recent: [
          LedgerEntry(
            id: 'exp-1',
            kind: LedgerKind.expense,
            amountCents: 1850,
            categoryId: 'food',
            note: '午饭',
            occurredAt: DateTime(2026, 11, 2, 12),
            createdAt: DateTime(2026, 11, 2, 12),
          ),
        ],
        monthEntries: [
          LedgerEntry(
            id: 'exp-1',
            kind: LedgerKind.expense,
            amountCents: 1850,
            categoryId: 'food',
            note: '午饭',
            occurredAt: DateTime(2026, 11, 2, 12),
            createdAt: DateTime(2026, 11, 2, 12),
          ),
        ],
        categories: _categories,
        now: DateTime(2026, 11, 9),
      );
      expect(context.contains('2026 年 11 月'), isTrue);
      expect(context.contains('总预算'), isTrue);
      expect(context.contains('餐饮'), isTrue);
      expect(context.contains('已超支'), isTrue);
      expect(context.contains('午饭'), isTrue);
      expect(context.contains('日均可用'), isTrue);
    });
  });
}
