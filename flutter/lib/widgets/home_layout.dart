import 'dart:math' as math;

import '../data/resources.dart';
import '../games/game_registry.dart';

/// 首页栅格上的卡片种类。
///
/// [game] / [res] 是「可多份」的卡片，具体是小游戏还是资源条目由
/// [HomeSlot.item] 决定。
enum HomeCardId {
  checkin,
  todo,
  mood,
  ledger,
  tingyu,
  weather,
  cook,
  calendar,
  quote,
  cardCollection,
  mbti,
  game,
  res,
}

/// 两种栅格形态：窄屏（手机 / 窄窗口）与宽屏（iPad / Windows）。
enum HomeForm { compact, wide }

extension HomeFormX on HomeForm {
  /// 列数：窄屏 6 列，宽屏 12 列。
  int get columns => this == HomeForm.wide ? 12 : 6;

  /// 卡片之间的间隙。
  /// 和首页卡片区四周留白（14）一致：卡片之间、卡片到面板边缘一样宽。
  double get gap => 14;

  /// 行高：卡片高度以「行」为单位。
  double get rowUnit => 50;
}

/// 单张卡片在栅格里的位置与尺寸（单位：列 / 行）。
class HomeSlot {
  final HomeCardId id;

  /// 小游戏 key（如 g2048）或资源 key（如 tool:玩法抽签 / driver:Steam）。
  /// 普通卡片为 null；它是同一 [HomeCardId] 下多张卡片的身份区分。
  final String? item;
  final int col;
  final int row;
  final int w;
  final int h;

  const HomeSlot(
    this.id, {
    this.item,
    required this.col,
    required this.row,
    required this.w,
    required this.h,
  });

  int get right => col + w;
  int get bottom => row + h;
}

/// 同一行里最高的卡片高度：同行的卡片一律拉齐到这一档，
/// 避免出现「左卡短、右卡长」的锯齿边。
int rowHeightOf(List<HomeSlot> slots, HomeSlot slot) => slots.fold(
  slot.h,
  (h, other) => other.row == slot.row && other.h > h ? other.h : h,
);

/// 固定的首页布局（不可编辑），两种形态顺序一致、每排两张：
/// 打卡 + 天气、心情 + 听隅、食谱日记整宽、测试 + 卡面收藏、
/// 视野live + 玩法抽签，每日一言长条收底。
/// 宽屏 12 列每张占 6 格，窄屏 6 列每张占 3 格。
List<HomeSlot> homeSlots(HomeForm form) =>
    form == HomeForm.wide ? _wideSlots : _compactSlots;

const List<HomeSlot> _wideSlots = [
  HomeSlot(HomeCardId.checkin, col: 0, row: 0, w: 6, h: 3),
  HomeSlot(HomeCardId.weather, col: 6, row: 0, w: 6, h: 3),
  HomeSlot(HomeCardId.mood, col: 0, row: 3, w: 6, h: 3),
  HomeSlot(HomeCardId.tingyu, col: 6, row: 3, w: 6, h: 3),
  // 整宽的两张只占两行（约 112 高），内容本身只有一行标题 + 一句话。
  HomeSlot(HomeCardId.cook, col: 0, row: 6, w: 12, h: 2),
  HomeSlot(HomeCardId.mbti, col: 0, row: 8, w: 6, h: 2),
  HomeSlot(HomeCardId.cardCollection, col: 6, row: 8, w: 6, h: 2),
  HomeSlot(HomeCardId.res, item: 'tool:视野live', col: 0, row: 10, w: 6, h: 2),
  HomeSlot(HomeCardId.res, item: 'tool:玩法抽签', col: 6, row: 10, w: 6, h: 2),
  HomeSlot(HomeCardId.quote, col: 0, row: 12, w: 12, h: 2),
];

const List<HomeSlot> _compactSlots = [
  HomeSlot(HomeCardId.checkin, col: 0, row: 0, w: 3, h: 3),
  HomeSlot(HomeCardId.weather, col: 3, row: 0, w: 3, h: 3),
  HomeSlot(HomeCardId.mood, col: 0, row: 3, w: 3, h: 3),
  HomeSlot(HomeCardId.tingyu, col: 3, row: 3, w: 3, h: 3),
  HomeSlot(HomeCardId.cook, col: 0, row: 6, w: 6, h: 2),
  HomeSlot(HomeCardId.mbti, col: 0, row: 8, w: 3, h: 2),
  HomeSlot(HomeCardId.cardCollection, col: 3, row: 8, w: 3, h: 2),
  HomeSlot(HomeCardId.res, item: 'tool:视野live', col: 0, row: 10, w: 3, h: 2),
  HomeSlot(HomeCardId.res, item: 'tool:玩法抽签', col: 3, row: 10, w: 3, h: 2),
  HomeSlot(HomeCardId.quote, col: 0, row: 12, w: 6, h: 2),
];

/// 栅格总高度：最后一行卡片的下缘。
double homeGridHeight(HomeForm form, List<HomeSlot> slots) {
  if (slots.isEmpty) return 180;
  var bottom = 0;
  for (final slot in slots) {
    bottom = math.max(bottom, slot.row + rowHeightOf(slots, slot));
  }
  return math.max(80, bottom * (form.rowUnit + form.gap) - form.gap);
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
