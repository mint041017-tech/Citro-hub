import 'package:citro/services/prefs.dart';
import 'package:citro/widgets/home_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final store = HomeLayoutStore.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  setUp(() {
    store.reset(HomeLayoutKey.widePortrait);
    store.reset(HomeLayoutKey.compactPortrait);
    store.reset(HomeLayoutKey.compactLandscape);
    store.reset(HomeLayoutKey.wideLandscape);
  });

  test('记账卡已搬去计划页，不再占默认布局', () {
    for (final key in HomeLayoutKey.values) {
      expect(
        store.slots(key).any((s) => s.id == HomeCardId.ledger),
        isFalse,
        reason: '$key 不该再有记账卡',
      );
    }
    final options = store.available(HomeLayoutKey.compactPortrait);
    expect(options.any((o) => o.id == HomeCardId.ledger), isFalse);
  });

  test('记账卡三档尺寸：小 3×2、标准 6×3、大卡整宽 4 行', () {
    const wide = HomeLayoutKey.widePortrait;
    const compact = HomeLayoutKey.compactPortrait;
    expect(store.presetSize(wide, HomeCardId.ledger, 0), (3, 2));
    expect(store.presetSize(wide, HomeCardId.ledger, 1), (6, 3));
    expect(store.presetSize(wide, HomeCardId.ledger, 2), (12, 4));
    expect(store.presetSize(compact, HomeCardId.ledger, 0), (3, 2));
    expect(store.presetSize(compact, HomeCardId.ledger, 1), (6, 3));
    expect(store.presetSize(compact, HomeCardId.ledger, 2), (6, 4));
  });

  test('删除后可加回，加回后仍在布局内且不重叠', () {
    // 记账卡已经搬去「计划」页、不再在首页的可选列表里，
    // 这里改用仍在首页的打卡卡来验证「删掉还能加回来」。
    const key = HomeLayoutKey.compactPortrait;
    store.remove(key, HomeCardId.checkin);
    expect(store.slots(key).any((s) => s.id == HomeCardId.checkin), isFalse);
    expect(store.available(key).any((o) => o.id == HomeCardId.checkin), isTrue);

    expect(store.add(key, HomeCardId.checkin), isTrue);
    final slots = store.slots(key);
    final checkin = slots.firstWhere((s) => s.id == HomeCardId.checkin);
    expect(checkin.w, 3);
    // 默认布局里打卡卡是 3×2（和听隅同高，同行卡片高度成对）。
    expect(checkin.h, 2);
    for (final other in slots) {
      if (other.key == checkin.key) continue;
      expect(checkin.overlaps(other), isFalse);
    }
  });

  test('记账卡支持自由缩放，尺寸受 spec 约束', () {
    const key = HomeLayoutKey.widePortrait;
    expect(store.add(key, HomeCardId.ledger), isTrue);
    final slot = store.slots(key).firstWhere((s) => s.id == HomeCardId.ledger);
    // 先挪到默认布局下方的空白行，再扩到 6×6：高度上限为 5 行。
    expect(store.move(key, HomeCardId.ledger, 0, 19), isTrue);
    expect(store.resize(key, HomeCardId.ledger, 6, 6), isTrue);
    final resized = store
        .slots(key)
        .firstWhere((s) => s.id == HomeCardId.ledger);
    expect(resized.w, 6);
    expect(resized.h, 5);
    expect(slot.id, HomeCardId.ledger);
  });
}
