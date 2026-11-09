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

  test('记账卡默认出现在窄屏与宽屏布局里，且尺寸为小档', () {
    for (final key in HomeLayoutKey.values) {
      final slot = store
          .slots(key)
          .firstWhere((s) => s.id == HomeCardId.ledger);
      expect(slot.w, 3);
      expect(slot.h, 2);
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
    const key = HomeLayoutKey.compactPortrait;
    store.remove(key, HomeCardId.ledger);
    expect(store.slots(key).any((s) => s.id == HomeCardId.ledger), isFalse);
    expect(store.available(key).any((o) => o.id == HomeCardId.ledger), isTrue);

    expect(store.add(key, HomeCardId.ledger), isTrue);
    final slots = store.slots(key);
    final ledger = slots.firstWhere((s) => s.id == HomeCardId.ledger);
    expect(ledger.w, 3);
    expect(ledger.h, 2);
    for (final other in slots) {
      if (other.key == ledger.key) continue;
      expect(ledger.overlaps(other), isFalse);
    }
  });

  test('记账卡支持自由缩放，尺寸受 spec 约束', () {
    const key = HomeLayoutKey.widePortrait;
    final slot = store.slots(key).firstWhere((s) => s.id == HomeCardId.ledger);
    // 先挪到下方空白区域，再扩到 6×6：高度上限为 5 行。
    expect(store.move(key, HomeCardId.ledger, 0, 18), isTrue);
    expect(store.resize(key, HomeCardId.ledger, 6, 6), isTrue);
    final resized = store
        .slots(key)
        .firstWhere((s) => s.id == HomeCardId.ledger);
    expect(resized.w, 6);
    expect(resized.h, 5);
    expect(slot.id, HomeCardId.ledger);
  });
}
