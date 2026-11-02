import 'dart:convert';

import 'package:citro/services/prefs.dart';
import 'package:citro/widgets/home_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _overlapsAny(List<HomeSlot> slots, HomeSlot target) {
  for (final other in slots) {
    if (other.key == target.key || !other.visible) continue;
    if (other.overlaps(target)) return true;
  }
  return false;
}

void main() {
  final store = HomeLayoutStore.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  setUp(() {
    store.reset(HomeLayoutKey.widePortrait);
    store.reset(HomeLayoutKey.compactPortrait);
  });

  test('默认布局覆盖全部常驻卡片且互不重叠', () {
    // 小游戏 / 资源卡片默认收起，需要手动添加，不在默认布局里。
    final core = HomeCardId.values
        .where((id) => id != HomeCardId.game && id != HomeCardId.res)
        .toSet();
    for (final form in HomeLayoutKey.values) {
      final slots = store.slots(form);
      expect(slots.map((s) => s.id).toSet(), core);
      for (final slot in slots) {
        expect(slot.col, greaterThanOrEqualTo(0));
        expect(slot.col + slot.w, lessThanOrEqualTo(form.form.columns));
        expect(_overlapsAny(slots, slot), isFalse, reason: '${slot.id} 重叠');
      }
    }
  });

  test('小游戏与资源卡片按条目区分并可添加', () {
    const key = HomeLayoutKey.widePortrait;
    expect(store.add(key, HomeCardId.game, item: 'g2048'), isTrue);
    expect(store.add(key, HomeCardId.game, item: 'gsnake'), isTrue);
    expect(store.add(key, HomeCardId.res, item: 'tool:灵敏度'), isTrue);
    // 同一条目不能重复添加，不同条目可以共存。
    expect(store.add(key, HomeCardId.game, item: 'g2048'), isFalse);
    final keys = store.slots(key).map((s) => s.key).toSet();
    expect(
      keys.containsAll({'game:g2048', 'game:gsnake', 'res:tool:灵敏度'}),
      isTrue,
    );
    // 已添加的条目不再出现在「可添加」里。
    final options = store.available(key);
    expect(options.any((o) => o.item == 'g2048'), isFalse);
    expect(options.any((o) => o.item == 'tool:灵敏度'), isFalse);
    // 分类齐全：小游戏 / 工具 / 驱动都能在面板里找到。
    expect(
      options.where((o) => o.category == HomeCardCategory.game),
      isNotEmpty,
    );
    expect(
      options.where((o) => o.category == HomeCardCategory.tool),
      isNotEmpty,
    );
    expect(
      options.where((o) => o.category == HomeCardCategory.driver),
      isNotEmpty,
    );
    // 条目随布局一起序列化，刷新后还能还原。
    final decoded = jsonDecode(jsonEncode(store.exportLayout()));
    final raw = (decoded[key.name] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((e) => e['id'] == 'game');
    expect(raw['item'], 'g2048');
    // 删除只删对应条目，另一张小游戏仍在。
    store.remove(key, HomeCardId.game, item: 'g2048');
    final ids = store
        .slots(key)
        .where((s) => s.id == HomeCardId.game)
        .map((s) => s.item)
        .toSet();
    expect(ids.contains('g2048'), isFalse);
    expect(ids.contains('gsnake'), isTrue);
  });

  test('移动卡片到空位后位置与持久化同步', () {
    // 先腾空右上角，打卡卡移过去应当精确落位。
    store.setVisible(HomeLayoutKey.widePortrait, HomeCardId.fish, false);
    expect(
      store.move(HomeLayoutKey.widePortrait, HomeCardId.checkin, 8, 0),
      isTrue,
    );
    final after = store
        .slots(HomeLayoutKey.widePortrait)
        .firstWhere((s) => s.id == HomeCardId.checkin);
    expect(after.col, 8);
    expect(after.row, 0);
    expect(
      _overlapsAny(store.visibleSlots(HomeLayoutKey.widePortrait), after),
      isFalse,
    );
  });

  test('移动到被占用的位置时会换到最近的空位而不是重叠', () {
    expect(
      store.move(HomeLayoutKey.widePortrait, HomeCardId.checkin, 0, 4),
      isTrue,
    );
    final after = store
        .slots(HomeLayoutKey.widePortrait)
        .firstWhere((s) => s.id == HomeCardId.checkin);
    expect(
      _overlapsAny(store.visibleSlots(HomeLayoutKey.widePortrait), after),
      isFalse,
    );
  });

  test('缩放到与相邻卡片冲突时会被拒绝', () {
    // 天气卡在 0–3 列，食谱卡占据 6–11 列，拉成整宽一定会撞上。
    expect(
      store.resize(HomeLayoutKey.widePortrait, HomeCardId.weather, 12, 6),
      isFalse,
    );
  });

  test('隐藏其它卡片后可以放大到整宽', () {
    for (final id in HomeCardId.values) {
      if (id != HomeCardId.checkin) {
        store.setVisible(HomeLayoutKey.widePortrait, id, false);
      }
    }
    expect(store.visibleSlots(HomeLayoutKey.widePortrait).length, 1);
    expect(
      store.resize(HomeLayoutKey.widePortrait, HomeCardId.checkin, 12, 3),
      isTrue,
    );
    final slot = store.visibleSlots(HomeLayoutKey.widePortrait).single;
    expect(slot.w, 12);
    expect(slot.h, 3);
  });

  test('显隐与布局都会写入本地偏好', () async {
    store.move(HomeLayoutKey.widePortrait, HomeCardId.quote, 0, 0);
    store.setVisible(HomeLayoutKey.widePortrait, HomeCardId.fish, false);
    final raw = Prefs.getString(HomeLayoutStore.prefsKey);
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    final wide = decoded['widePortrait'] as List<dynamic>;
    final fish = wide.firstWhere((item) => item['id'] == 'fish');
    expect(fish['visible'], isFalse);
    expect(decoded.containsKey('compactPortrait'), isTrue);
  });

  test('拖动到已占用位置会推动原卡片自动避让', () {
    expect(
      store.move(HomeLayoutKey.widePortrait, HomeCardId.fish, 0, 0),
      isTrue,
    );
    final slots = store.slots(HomeLayoutKey.widePortrait);
    final fish = slots.firstWhere((s) => s.id == HomeCardId.fish);
    final checkin = slots.firstWhere((s) => s.id == HomeCardId.checkin);
    expect(fish.col, 0);
    expect(fish.row, 0);
    expect(checkin.col == 0 && checkin.row == 0, isFalse);
    for (final slot in slots) {
      expect(_overlapsAny(slots, slot), isFalse, reason: '${slot.id} 重叠');
    }
  });

  test('横竖屏布局分别存储，互不覆盖', () {
    store.setVisible(HomeLayoutKey.wideLandscape, HomeCardId.fish, false);
    final portrait = store.slots(HomeLayoutKey.widePortrait);
    final landscape = store.slots(HomeLayoutKey.wideLandscape);
    expect(portrait.firstWhere((s) => s.id == HomeCardId.fish).visible, isTrue);
    expect(
      landscape.firstWhere((s) => s.id == HomeCardId.fish).visible,
      isFalse,
    );
    final decoded = jsonDecode(
      Prefs.getString(HomeLayoutStore.prefsKey)!,
    ) as Map<String, dynamic>;
    expect(decoded.containsKey('widePortrait'), isTrue);
    expect(decoded.containsKey('wideLandscape'), isTrue);
  });

  test('恢复默认会回到初始位置', () {
    store.move(HomeLayoutKey.widePortrait, HomeCardId.calendar, 6, 0);
    store.reset(HomeLayoutKey.widePortrait);
    expect(
      store.slots(HomeLayoutKey.widePortrait),
      defaultHomeLayout(HomeLayoutKey.widePortrait),
    );
  });
}
