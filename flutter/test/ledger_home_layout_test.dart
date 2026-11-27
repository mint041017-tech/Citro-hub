import 'package:citro/widgets/home_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('记账卡与日历卡已搬去计划页，不占默认布局', () {
    for (final form in HomeForm.values) {
      final slots = homeSlots(form);
      expect(
        slots.any(
          (s) => s.id == HomeCardId.ledger || s.id == HomeCardId.calendar,
        ),
        isFalse,
        reason: '$form 首页不该再有记账 / 日历卡',
      );
    }
  });

  test('每日一言只有一张且整宽，食谱日记整宽，两者一起收尾', () {
    for (final form in HomeForm.values) {
      final slots = homeSlots(form);
      final quote = slots.where((s) => s.id == HomeCardId.quote);
      expect(quote.length, 1);
      final cook = slots.firstWhere((s) => s.id == HomeCardId.cook);
      expect(cook.w, form.columns);
      expect(quote.single.w, form.columns);
      expect(
        quote.single.bottom,
        slots.map((s) => s.bottom).reduce((a, b) => a > b ? a : b),
      );
    }
  });
}
