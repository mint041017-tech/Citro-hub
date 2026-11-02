import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/resources.dart';
import '../games/game_registry.dart';
import '../services/api.dart';
import '../services/platform.dart' as platform;
import '../services/prefs.dart';
import '../state/app_state.dart';

/// 首页可编排的卡片。
///
/// 顺序即内容面板里的展示顺序，默认布局按宽屏 / 窄屏分别定义。
/// [game] / [res] 是一类「可多份」的卡片，具体是小游戏还是资源条目由
/// [HomeSlot.item] 决定，默认不出现在首页，需要手动添加。
enum HomeCardId {
  checkin,
  tingyu,
  fish,
  weather,
  cook,
  calendar,
  zodiac,
  quote,
  game,
  res,
}

/// 两种栅格形态：窄屏（手机 / 窄窗口）与宽屏（iPad / Windows）。
enum HomeForm { compact, wide }

extension HomeFormX on HomeForm {
  int get columns => this == HomeForm.wide ? 12 : 6;

  double get gap => this == HomeForm.wide ? 14 : 10;

  /// 行高按形态固定，卡片高度以「行」为单位，编辑时才能稳定吸附。
  double get rowUnit => this == HomeForm.wide ? 50 : 48;

  /// 允许往下拖出的最大行数，避免误拖后页面无限变长。
  int get maxRows => this == HomeForm.wide ? 30 : 44;
}

/// 横屏 / 竖屏、窄屏 / 宽屏各自独立保存一套布局。
enum HomeLayoutKey {
  compactPortrait,
  compactLandscape,
  widePortrait,
  wideLandscape,
}

HomeLayoutKey homeLayoutKeyFor(HomeForm form, bool landscape) {
  if (form == HomeForm.wide) {
    return landscape ? HomeLayoutKey.wideLandscape : HomeLayoutKey.widePortrait;
  }
  return landscape
      ? HomeLayoutKey.compactLandscape
      : HomeLayoutKey.compactPortrait;
}

extension HomeLayoutKeyX on HomeLayoutKey {
  HomeForm get form =>
      this == HomeLayoutKey.widePortrait || this == HomeLayoutKey.wideLandscape
      ? HomeForm.wide
      : HomeForm.compact;

  bool get landscape =>
      this == HomeLayoutKey.compactLandscape ||
      this == HomeLayoutKey.wideLandscape;

  HomeLayoutKey get portraitEquivalent => homeLayoutKeyFor(form, false);
  HomeLayoutKey get landscapeEquivalent => homeLayoutKeyFor(form, true);
}

class HomeCardInfo {
  final String label;
  final String hint;

  const HomeCardInfo(this.label, this.hint);
}

const Map<HomeCardId, HomeCardInfo> kHomeCardInfo = {
  HomeCardId.checkin: HomeCardInfo('打卡', '连续记录与今日状态'),
  HomeCardId.tingyu: HomeCardInfo('听隅', '白噪音与沉浸声景'),
  HomeCardId.fish: HomeCardInfo('摸鱼日历', '距离休息日还有几天'),
  HomeCardId.weather: HomeCardInfo('天气', '实时天气与体感湿度'),
  HomeCardId.cook: HomeCardInfo('食谱日记', '记录今天吃了什么'),
  HomeCardId.calendar: HomeCardInfo('日历', '月历、农历与节日'),
  HomeCardId.zodiac: HomeCardInfo('今日星象', '本命星座与今日运势'),
  HomeCardId.quote: HomeCardInfo('每日一言', '每天一句，随手可复制'),
  HomeCardId.game: HomeCardInfo('小游戏', '把常玩的小游戏放到首页'),
  HomeCardId.res: HomeCardInfo('资源', '工具与驱动，随手打开'),
};

/// 单张卡片在栅格里的位置与尺寸（单位：列 / 行）。
@immutable
class HomeSlot {
  final HomeCardId id;

  /// 小游戏 key（如 g2048）或资源 key（如 tool:灵敏度 / driver:Steam）。
  /// 普通卡片为 null；它是同一 [HomeCardId] 下多张卡片的身份区分。
  final String? item;
  final int col;
  final int row;
  final int w;
  final int h;
  final bool visible;

  const HomeSlot(
    this.id, {
    this.item,
    required this.col,
    required this.row,
    required this.w,
    required this.h,
    this.visible = true,
  });

  int get right => col + w;
  int get bottom => row + h;

  /// 布局内唯一标识：同一种卡片允许多份（不同的小游戏 / 资源）。
  String get key => item == null ? id.name : '${id.name}:$item';

  static String keyOf(HomeCardId id, [String? item]) =>
      item == null ? id.name : '${id.name}:$item';

  HomeSlot copyWith({int? col, int? row, int? w, int? h, bool? visible}) =>
      HomeSlot(
        id,
        item: item,
        col: col ?? this.col,
        row: row ?? this.row,
        w: w ?? this.w,
        h: h ?? this.h,
        visible: visible ?? this.visible,
      );

  bool overlaps(HomeSlot other) =>
      col < other.right &&
      other.col < right &&
      row < other.bottom &&
      other.row < bottom;

  Map<String, Object?> toJson() => {
    'id': id.name,
    if (item != null) 'item': item,
    'col': col,
    'row': row,
    'w': w,
    'h': h,
    'visible': visible,
  };

  static HomeSlot? fromJson(Object? raw, HomeForm form) {
    if (raw is! Map) return null;
    HomeCardId? id;
    for (final value in HomeCardId.values) {
      if (value.name == raw['id']) {
        id = value;
        break;
      }
    }
    if (id == null) return null;
    final item = raw['item'] is String && (raw['item'] as String).isNotEmpty
        ? raw['item'] as String
        : null;
    // 小游戏 / 资源卡片必须带具体条目，否则无法渲染。
    if ((id == HomeCardId.game || id == HomeCardId.res) && item == null) {
      return null;
    }
    final cols = form.columns;
    final col = _int(raw['col']);
    final row = _int(raw['row']);
    final w = _int(raw['w']);
    final h = _int(raw['h']);
    if (col == null || row == null || w == null || h == null) return null;
    if (w < 1 || w > cols || h < 1) return null;
    if (col < 0 || col + w > cols || row < 0 || row + h > form.maxRows) {
      return null;
    }
    return HomeSlot(
      id,
      item: item,
      col: col,
      row: row,
      w: w,
      h: h,
      visible: raw['visible'] is bool ? raw['visible'] as bool : true,
    );
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}

class HomeCardSpec {
  final int minW;
  final int maxW;
  final int minH;
  final int maxH;

  const HomeCardSpec({
    required this.minW,
    required this.maxW,
    required this.minH,
    required this.maxH,
  });
}

HomeCardSpec homeCardSpec(HomeForm form, HomeCardId id) {
  final cols = form.columns;
  // 宽屏把最小宽度从 1/3 降到 1/4，让「小卡」真正可用；
  // 窄屏最小仍是一半宽度，再小就会失去可读性。
  const half = 3;
  return switch (id) {
    HomeCardId.checkin ||
    HomeCardId.tingyu => HomeCardSpec(minW: half, maxW: cols, minH: 2, maxH: 3),
    HomeCardId.fish => HomeCardSpec(minW: half, maxW: cols, minH: 2, maxH: 4),
    HomeCardId.weather ||
    HomeCardId.cook => HomeCardSpec(minW: half, maxW: cols, minH: 3, maxH: 6),
    HomeCardId.calendar => HomeCardSpec(
      // 日历支持 3×3 起的迷你尺寸：卡片内的日期格会自动等比缩小。
      minW: 3,
      maxW: cols,
      minH: 3,
      maxH: 10,
    ),
    HomeCardId.zodiac => HomeCardSpec(
      // 星象卡支持从迷你到整宽高卡的多档尺寸：
      // 3 列 × 3 行的迷你档由卡片内的 micro 布局承接，保证信息仍可读。
      minW: 3,
      maxW: cols,
      minH: 3,
      maxH: 12,
    ),
    HomeCardId.quote => HomeCardSpec(minW: half, maxW: cols, minH: 2, maxH: 4),
    HomeCardId.game => HomeCardSpec(minW: half, maxW: cols, minH: 2, maxH: 5),
    HomeCardId.res => HomeCardSpec(minW: half, maxW: cols, minH: 2, maxH: 4),
  };
}

/// 默认布局：宽屏按「动作条 → 天气/食谱 → 日历/星象 → 一言」四段；
/// 窄屏保持双卡并排 + 信息卡整宽，缩短滚动长度。
List<HomeSlot> defaultHomeLayout(HomeLayoutKey key) {
  if (key.form == HomeForm.wide) {
    return const [
      HomeSlot(HomeCardId.checkin, col: 0, row: 0, w: 4, h: 2),
      HomeSlot(HomeCardId.tingyu, col: 4, row: 0, w: 4, h: 2),
      HomeSlot(HomeCardId.fish, col: 8, row: 0, w: 4, h: 2),
      HomeSlot(HomeCardId.weather, col: 0, row: 2, w: 6, h: 4),
      HomeSlot(HomeCardId.cook, col: 6, row: 2, w: 6, h: 4),
      HomeSlot(HomeCardId.calendar, col: 0, row: 6, w: 6, h: 5),
      HomeSlot(HomeCardId.zodiac, col: 6, row: 6, w: 6, h: 5),
      HomeSlot(HomeCardId.quote, col: 0, row: 11, w: 12, h: 3),
    ];
  }
  return const [
    HomeSlot(HomeCardId.checkin, col: 0, row: 0, w: 3, h: 2),
    HomeSlot(HomeCardId.tingyu, col: 3, row: 0, w: 3, h: 2),
    HomeSlot(HomeCardId.weather, col: 0, row: 2, w: 3, h: 4),
    HomeSlot(HomeCardId.cook, col: 3, row: 2, w: 3, h: 4),
    HomeSlot(HomeCardId.fish, col: 0, row: 6, w: 6, h: 2),
    HomeSlot(HomeCardId.calendar, col: 0, row: 8, w: 6, h: 6),
    HomeSlot(HomeCardId.zodiac, col: 0, row: 14, w: 6, h: 5),
    HomeSlot(HomeCardId.quote, col: 0, row: 19, w: 6, h: 4),
  ];
}

HomeSlot? defaultHomeSlotFor(HomeLayoutKey key, HomeCardId id) {
  for (final slot in defaultHomeLayout(key)) {
    if (slot.id == id) return slot;
  }
  return null;
}

/// 默认布局里没有的卡片（小游戏 / 资源）第一次添加时用的初始尺寸。
HomeSlot initialHomeSlotFor(HomeLayoutKey key, HomeCardId id, {String? item}) {
  final base = defaultHomeSlotFor(key, id);
  if (base != null) return base;
  final wide = key.form == HomeForm.wide;
  final (w, h) = switch (id) {
    HomeCardId.game => wide ? (4, 3) : (3, 3),
    HomeCardId.res => wide ? (4, 2) : (6, 2),
    _ => (key.form.columns, 2),
  };
  return HomeSlot(
    id,
    item: item,
    col: 0,
    row: 0,
    w: w.clamp(1, key.form.columns),
    h: h,
  );
}

GameCardData? gameCardByKey(String? key) {
  for (final game in kGameCards) {
    if (game.key == key) return game;
  }
  return null;
}

ToolItem? toolByItem(String? item) {
  if (item == null || !item.startsWith('tool:')) return null;
  final name = item.substring(5);
  for (final tool in kTools) {
    if (tool.name == name) return tool;
  }
  return null;
}

DriverItem? driverByItem(String? item) {
  if (item == null || !item.startsWith('driver:')) return null;
  final name = item.substring(7);
  for (final driver in [...kDriversWeb, ...kDriversClient]) {
    if (driver.name == name) return driver;
  }
  return null;
}

String homeCardLabel(HomeSlot slot) {
  switch (slot.id) {
    case HomeCardId.game:
      return gameCardByKey(slot.item)?.title ?? kHomeCardInfo[slot.id]!.label;
    case HomeCardId.res:
      final tool = toolByItem(slot.item);
      if (tool != null) return tool.name;
      return driverByItem(slot.item)?.name ?? kHomeCardInfo[slot.id]!.label;
    default:
      return kHomeCardInfo[slot.id]!.label;
  }
}

/// 「添加卡片」页里的分类：常驻卡片、小游戏、工具、驱动。
enum HomeCardCategory { core, game, tool, driver }

extension HomeCardCategoryX on HomeCardCategory {
  String get label => switch (this) {
    HomeCardCategory.core => '常驻卡片',
    HomeCardCategory.game => '小游戏',
    HomeCardCategory.tool => '工具',
    HomeCardCategory.driver => '驱动',
  };

  String get hint => switch (this) {
    HomeCardCategory.core => '首页常用入口',
    HomeCardCategory.game => '点开直接开局',
    HomeCardCategory.tool => '资源库小工具',
    HomeCardCategory.driver => '外设与客户端',
  };
}

/// 「添加卡片」面板里的一项：普通卡片一条，小游戏 / 资源按具体条目展开。
class HomeCardOption {
  final HomeCardId id;
  final String? item;
  final String label;
  final String hint;

  /// 资源库工具自带 svg 图标；为空时按 [id] 使用默认图标。
  final String? icon;

  final HomeCardCategory category;

  const HomeCardOption(
    this.id, {
    this.item,
    required this.label,
    required this.hint,
    this.icon,
    this.category = HomeCardCategory.core,
  });

  String get key => HomeSlot.keyOf(id, item);
}

/// 与资源库一致：手机上这四项已经并进「游戏」页，不再重复出现在资源库。
const Set<String> _kToolsMovedToGames = {'玩法抽签', '瞬投', '屏幕分享', '视野live'};

/// 首页布局的单一数据源：负责读写偏好、移动 / 缩放 / 显隐。
class HomeLayoutStore extends ChangeNotifier {
  HomeLayoutStore._();

  static final HomeLayoutStore instance = HomeLayoutStore._();

  static const String prefsKey = PrefKeys.homeLayout;

  final Map<HomeLayoutKey, List<HomeSlot>> _slots = {};
  final Set<HomeLayoutKey> _loaded = {};
  Map<String, Object?> _raw = const {};
  Timer? _pushTimer;
  static bool _accountSynced = false;

  bool get _signedIn =>
      AppState.instance.user != null && (Api.token?.isNotEmpty ?? false);

  List<HomeSlot> slots(HomeLayoutKey key) {
    _ensureLoaded(key);
    return List.unmodifiable(_slots[key]!);
  }

  List<HomeSlot> visibleSlots(HomeLayoutKey key) =>
      slots(key).where((s) => s.visible).toList(growable: false);

  void _ensureLoaded(HomeLayoutKey key) {
    if (_loaded.contains(key)) return;
    _loaded.add(key);
    final defaults = defaultHomeLayout(key);
    List<HomeSlot>? stored;
    try {
      final raw = Prefs.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _raw = {
            for (final entry in decoded.entries)
              if (entry.key is String) entry.key as String: entry.value,
          };
          // 兼容旧版仅按 compact / wide 保存的数据：
          // 首次升级时把它当作竖屏布局迁移过来。
          final list = decoded[key.name] ?? decoded[key.form.name];
          if (list is List) {
            final parsed = <HomeSlot>[];
            for (final item in list) {
              final slot = HomeSlot.fromJson(item, key.form);
              if (slot != null && parsed.every((e) => e.key != slot.key)) {
                parsed.add(slot);
              }
            }
            if (parsed.isNotEmpty) stored = parsed;
          }
        }
      }
    } catch (_) {
      // 旧版本或损坏数据都静默回退到默认布局。
    }

    if (stored == null) {
      _slots[key] = List<HomeSlot>.of(defaults);
      return;
    }
    // 版本升级新增的卡片补到末尾，不覆盖用户已保存的位置。
    for (final slot in defaults) {
      if (stored.every((e) => e.id != slot.id)) stored.add(slot);
    }
    _slots[key] = _normalizeAll(key, stored);
  }

  List<HomeSlot> _normalizeAll(HomeLayoutKey key, List<HomeSlot> input) {
    final out = <HomeSlot>[];
    for (final raw in input) {
      if (!raw.visible) continue;
      var slot = _normalizeSlot(key, raw);
      if (!_isFree(out, slot)) {
        final moved = _nearestFree(out, slot, key.form);
        if (moved != null) slot = moved;
      }
      out.add(slot);
    }
    return out;
  }

  /// 旧版本可能保存过小于当前最小尺寸的卡片；读入时统一收进合法范围，
  /// 避免小到放不下内容而出现整页溢出。
  HomeSlot _normalizeSlot(HomeLayoutKey key, HomeSlot slot) {
    final form = key.form;
    final spec = homeCardSpec(form, slot.id);
    final w = slot.w.clamp(spec.minW, form.columns);
    final h = slot.h.clamp(spec.minH, spec.maxH);
    final col = slot.col.clamp(0, form.columns - w);
    final row = slot.row.clamp(0, form.maxRows - h);
    return slot.copyWith(col: col, row: row, w: w, h: h);
  }

  /// 返回 false 表示附近没有可放置的空位。
  ///
  /// 目标位置被占用时优先「自动避让」：把挡路的卡片推到最近的空位，
  /// 让被拖动的卡片落在用户想要的位置；推不开才回退到最近空位。
  bool move(
    HomeLayoutKey key,
    HomeCardId id,
    int col,
    int row, {
    String? item,
  }) {
    _ensureLoaded(key);
    final list = _slots[key]!;
    final index = list.indexWhere((s) => s.id == id && s.item == item);
    if (index < 0) return false;
    final slot = list[index];
    final cols = key.form.columns;
    final c = col.clamp(0, cols - slot.w);
    final r = row.clamp(0, key.form.maxRows - slot.h);
    final target = slot.copyWith(col: c, row: r);

    final next = List<HomeSlot>.of(list);
    next[index] = target;
    var pushed = false;
    for (var i = 0; i < next.length; i++) {
      final other = next[i];
      if (other.key == target.key ||
          !other.visible ||
          !other.overlaps(target)) {
        continue;
      }
      final moved = _nearestFree(next, other, key.form);
      if (moved == null) {
        pushed = false;
        next.clear();
        break;
      }
      next[i] = moved;
      pushed = true;
    }
    if (next.isNotEmpty && (pushed || _isFree(list, target))) {
      _slots[key] = next;
      _persist(key);
      return true;
    }
    // 自动避让失败：不强行重叠，退回到拖动卡自己的最近空位。
    final fallback = _nearestFree(list, target, key.form);
    if (fallback == null) return false;
    list[index] = fallback;
    _persist(key);
    return true;
  }

  bool resize(HomeLayoutKey key, HomeCardId id, int w, int h, {String? item}) {
    _ensureLoaded(key);
    final list = _slots[key]!;
    final index = list.indexWhere((s) => s.id == id && s.item == item);
    if (index < 0) return false;
    final slot = list[index];
    final form = key.form;
    final spec = homeCardSpec(form, id);
    var nextW = w.clamp(spec.minW, spec.maxW);
    var nextH = h.clamp(spec.minH, spec.maxH);
    final widthLimit = form.columns - slot.col;
    final heightLimit = form.maxRows - slot.row;
    if (nextW > widthLimit) nextW = widthLimit;
    if (nextH > heightLimit) nextH = heightLimit;
    final next = slot.copyWith(w: nextW, h: nextH);
    if (!_isFree(list, next)) return false;
    list[index] = next;
    _persist(key);
    return true;
  }

  /// 0=小、1=标准、2=大。返回 false 表示当前空位放不下。
  bool applyPreset(
    HomeLayoutKey key,
    HomeCardId id,
    int level, {
    String? item,
  }) {
    final size = presetSize(key, id, level, item: item);
    if (size == null) return false;
    return resize(key, id, size.$1, size.$2, item: item);
  }

  (int, int)? presetSize(
    HomeLayoutKey key,
    HomeCardId id,
    int level, {
    String? item,
  }) {
    final form = key.form;
    final spec = homeCardSpec(form, id);
    final base =
        defaultHomeSlotFor(key, id) ?? initialHomeSlotFor(key, id, item: item);
    return switch (level) {
      0 => (spec.minW, spec.minH),
      1 => (base.w, base.h),
      _ => (
        (base.w + 3).clamp(spec.minW, form.columns),
        (base.h + 1).clamp(spec.minH, spec.maxH),
      ),
    };
  }

  int presetLevel(HomeLayoutKey key, HomeSlot slot) {
    for (var level = 0; level < 3; level++) {
      final size = presetSize(key, slot.id, level, item: slot.item);
      if (size != null && size.$1 == slot.w && size.$2 == slot.h) {
        return level;
      }
    }
    return -1;
  }

  void setVisible(
    HomeLayoutKey key,
    HomeCardId id,
    bool visible, {
    String? item,
  }) {
    _ensureLoaded(key);
    final list = _slots[key]!;
    final index = list.indexWhere((s) => s.id == id && s.item == item);
    if (index < 0) return;
    list[index] = list[index].copyWith(visible: visible);
    _persist(key);
  }

  void reset(HomeLayoutKey key) {
    _loaded.add(key);
    _slots[key] = List<HomeSlot>.of(defaultHomeLayout(key));
    _persist(key);
  }

  /// 从当前布局里删除一张卡片；之后可在「可添加」里加回来。
  void remove(HomeLayoutKey key, HomeCardId id, {String? item}) {
    _ensureLoaded(key);
    final list = _slots[key]!;
    list.removeWhere((s) => s.id == id && s.item == item);
    _persist(key);
  }

  /// 把一张被删除的卡片加回布局：优先放默认位置，占用时自动避让。
  bool add(HomeLayoutKey key, HomeCardId id, {String? item}) {
    _ensureLoaded(key);
    final list = _slots[key]!;
    if (list.any((s) => s.id == id && s.item == item)) return false;
    final base = initialHomeSlotFor(key, id, item: item);
    var slot = _normalizeSlot(key, base.copyWith(visible: true));
    if (!_isFree(list, slot)) {
      final moved = _nearestFree(list, slot, key.form);
      if (moved == null) return false;
      slot = moved;
    }
    list.add(slot);
    _persist(key);
    return true;
  }

  /// 还能添加到首页的卡片：普通卡片一条，小游戏 / 资源按具体条目展开。
  List<HomeCardOption> available(HomeLayoutKey key) {
    final list = slots(key);
    bool taken(HomeCardId id, [String? item]) =>
        list.any((s) => s.id == id && s.item == item);

    final out = <HomeCardOption>[];
    for (final id in const [
      HomeCardId.checkin,
      HomeCardId.tingyu,
      HomeCardId.fish,
      HomeCardId.weather,
      HomeCardId.cook,
      HomeCardId.calendar,
      HomeCardId.zodiac,
      HomeCardId.quote,
    ]) {
      if (taken(id)) continue;
      final info = kHomeCardInfo[id]!;
      out.add(
        HomeCardOption(
          id,
          label: info.label,
          hint: info.hint,
          category: HomeCardCategory.core,
        ),
      );
    }
    for (final game in kGameCards) {
      if (taken(HomeCardId.game, game.key)) continue;
      out.add(
        HomeCardOption(
          HomeCardId.game,
          item: game.key,
          label: game.title,
          hint: '点按直接开局',
          category: HomeCardCategory.game,
        ),
      );
    }
    final tools = (platform.isAndroid || platform.isIOS)
        ? kTools.where((t) => !_kToolsMovedToGames.contains(t.name))
        : kTools;
    for (final tool in tools) {
      final item = 'tool:${tool.name}';
      if (taken(HomeCardId.res, item)) continue;
      out.add(
        HomeCardOption(
          HomeCardId.res,
          item: item,
          label: tool.name,
          hint: tool.desc,
          icon: tool.icon,
          category: HomeCardCategory.tool,
        ),
      );
    }
    for (final driver in [...kDriversWeb, ...kDriversClient]) {
      final item = 'driver:${driver.name}';
      if (taken(HomeCardId.res, item)) continue;
      out.add(
        HomeCardOption(
          HomeCardId.res,
          item: item,
          label: driver.name,
          hint: driver.client ? '客户端 · 下载安装' : '驱动 · 下载安装',
          category: HomeCardCategory.driver,
        ),
      );
    }
    return out;
  }

  bool _isFree(List<HomeSlot> list, HomeSlot target) {
    for (final other in list) {
      if (other.key == target.key || !other.visible) continue;
      if (other.overlaps(target)) return false;
    }
    return true;
  }

  HomeSlot? _nearestFree(List<HomeSlot> list, HomeSlot target, HomeForm form) {
    final cols = form.columns;
    for (var distance = 1; distance <= 30; distance++) {
      for (var dr = -distance; dr <= distance; dr++) {
        final dcLimit = distance - (dr.abs() - distance).abs();
        for (var dc = -dcLimit; dc <= dcLimit; dc++) {
          final c = target.col + dc;
          final r = target.row + dr;
          if (c < 0 || r < 0 || c + target.w > cols) continue;
          if (r + target.h > form.maxRows) continue;
          final candidate = target.copyWith(col: c, row: r);
          if (_isFree(list, candidate)) return candidate;
        }
      }
    }
    return null;
  }

  Map<String, Object?> exportLayout() => {
    for (final key in HomeLayoutKey.values)
      if (_slots[key] != null)
        key.name: _slots[key]!.map((s) => s.toJson()).toList(growable: false),
  };

  void _persist(HomeLayoutKey key) {
    try {
      final payload = <String, Object?>{..._raw, ...exportLayout()};
      Prefs.setString(prefsKey, jsonEncode(payload));
    } catch (_) {
      // 持久化失败不影响当前会话。
    }
    notifyListeners();
    _schedulePush();
  }

  /// 编辑时用来判断尺寸是否可行（不落盘）。
  bool canPlace(HomeLayoutKey key, HomeSlot target) {
    _ensureLoaded(key);
    return _isFree(_slots[key]!, target);
  }

  // ---------------------------------------------------------------------------
  // 账号同步
  // ---------------------------------------------------------------------------

  /// 登录后拉取云端布局；远端为空时保留本地，并把本地推上去。
  Future<void> syncFromAccount({bool force = false}) async {
    if (!force && _accountSynced) return;
    if (!_signedIn) return;
    _accountSynced = true;
    try {
      final json = await Api.homeLayoutGet();
      final remote = json['layout'];
      if (remote is Map && remote.isNotEmpty) {
        _applyRemote(remote);
        return;
      }
      _schedulePush(immediate: true);
    } catch (_) {
      // 离线或旧服务端：继续使用本地布局。
    }
  }

  void _applyRemote(Map remote) {
    var changed = false;
    for (final key in HomeLayoutKey.values) {
      final list = remote[key.name];
      if (list is! List) continue;
      final parsed = <HomeSlot>[];
      for (final item in list) {
        final slot = HomeSlot.fromJson(item, key.form);
        if (slot != null && parsed.every((e) => e.key != slot.key)) {
          parsed.add(slot);
        }
      }
      if (parsed.isEmpty) continue;
      for (final slot in defaultHomeLayout(key)) {
        if (parsed.every((e) => e.id != slot.id)) parsed.add(slot);
      }
      _loaded.add(key);
      _slots[key] = _normalizeAll(key, parsed);
      changed = true;
    }
    if (!changed) return;
    try {
      Prefs.setString(prefsKey, jsonEncode(exportLayout()));
    } catch (_) {}
    notifyListeners();
  }

  void _schedulePush({bool immediate = false}) {
    if (!_signedIn) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 900),
      _pushRemote,
    );
  }

  Future<void> _pushRemote() async {
    if (!_signedIn) return;
    try {
      await Api.homeLayoutSave(exportLayout());
    } catch (_) {
      // 网络恢复后下一次编辑会再次尝试。
    }
  }
}
