import 'package:citro/widgets/home_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// 明细里的卡片是否和已摆放的卡片重叠（同一行同列区间相交）。
bool _overlapsAny(List<HomeSlot> slots, HomeSlot target) {
  for (final other in slots) {
    if (identical(other, target)) continue;
    if (other.row < target.bottom &&
        target.row < other.bottom &&
        other.col < target.right &&
        target.col < other.right) {
      return true;
    }
  }
  return false;
}

void main() {
  test('默认布局覆盖常驻卡片且互不重叠', () {
    for (final form in HomeForm.values) {
      final slots = homeSlots(form);
      // 小游戏 / 资源是按条目挂的卡片，不在默认布局里；
      // 日历 / 待办 / 记账已经搬去「计划」页。
      const skip = {
        HomeCardId.game,
        HomeCardId.calendar,
        HomeCardId.todo,
        HomeCardId.ledger,
      };
      final core = HomeCardId.values.where((id) => !skip.contains(id)).toSet();
      expect(slots.map((s) => s.id).toSet(), core);
      for (final slot in slots) {
        expect(slot.col, greaterThanOrEqualTo(0));
        expect(slot.row, greaterThanOrEqualTo(0));
        expect(slot.right, lessThanOrEqualTo(form.columns));
        expect(_overlapsAny(slots, slot), isFalse, reason: '${slot.id} 重叠');
      }
    }
  });

  test('人格测试与卡面收藏和其他卡片同宽、两行高，不单独缩放', () {
    for (final form in HomeForm.values) {
      final slots = homeSlots(form);
      final checkin = slots.firstWhere((s) => s.id == HomeCardId.checkin);
      for (final id in const [HomeCardId.mbti, HomeCardId.cardCollection]) {
        final slot = slots.firstWhere((s) => s.id == id);
        expect(slot.w, checkin.w, reason: '$form $id 宽度应与打卡卡一致');
        expect(slot.h, 2, reason: '$form $id 应压到两行高');
        expect(slot.h, lessThan(checkin.h), reason: '$form $id 应比打卡卡矮');
      }
    }
  });

  test('玩法抽签与视野 live 作为首页卡片留在栅格内', () {
    for (final form in HomeForm.values) {
      final slots = homeSlots(form);
      for (final item in const ['tool:玩法抽签', 'tool:视野live']) {
        final slot = slots.firstWhere(
          (s) => s.id == HomeCardId.res && s.item == item,
        );
        expect(slot.bottom, lessThanOrEqualTo(15), reason: '$form $item');
      }
    }
  });

  test('栅格总高度等于最后一行卡片的下缘', () {
    for (final form in HomeForm.values) {
      final slots = homeSlots(form);
      final rows = slots.map((s) => s.bottom).reduce((a, b) => a > b ? a : b);
      expect(
        homeGridHeight(form, slots),
        rows * (form.rowUnit + form.gap) - form.gap,
      );
    }
  });
}
