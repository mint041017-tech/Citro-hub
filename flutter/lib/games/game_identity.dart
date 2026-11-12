import 'package:flutter/material.dart';

/// 每个小游戏自己的颜色身份。
///
/// 这些值是**固定**的，不读 `CitroColors.accent`：主题在亮 / 暗之间切换时，
/// 游戏卡仍然是那个颜色——玩家靠颜色和图形就能一眼认出某个游戏。
/// 主题色（accent）只负责 App 自身的按钮、选中态，不负责游戏。
@immutable
class GameIdentity {
  const GameIdentity({
    required this.key,
    required this.title,
    required this.tag,
    required this.primary,
    required this.deep,
    required this.soft,
    required this.ink,
    this.secondary,
  });

  final String key;

  /// 游戏名（卡片与页头共用）。
  final String title;

  /// 分类小标签，例如「逻辑」「反应」。卡片上只出现这一个词。
  final String tag;

  /// 主色：卡片底色、棋盘框、主按钮。
  final Color primary;

  /// 深色端：描边、阴影、深色细节。
  final Color deep;

  /// 浅色端：卡片底、填充面。
  final Color soft;

  /// 图形上的深色墨迹（数字、描线）。
  final Color ink;

  /// 可选的第二色，用于少数需要双色的游戏（果冻、铃渡）。
  final Color? secondary;

  /// 暗色纸面上把主色提亮一点，避免大面积深色把卡片压糊。
  Color onDark() => Color.lerp(primary, const Color(0xFFFFFFFF), 0.18)!;
}

const kGameIdentities = <GameIdentity>[
  GameIdentity(
    key: 'g2048',
    title: '2048',
    tag: '数字',
    primary: Color(0xFFE08A2E),
    deep: Color(0xFFA96417),
    soft: Color(0xFFF8E3C4),
    ink: Color(0xFF4A2C0D),
  ),
  GameIdentity(
    key: 'gmem',
    title: '记忆卡牌',
    tag: '记忆',
    primary: Color(0xFFA9744B),
    deep: Color(0xFF7B4E2C),
    soft: Color(0xFFEDDFCB),
    ink: Color(0xFF3D2817),
  ),
  GameIdentity(
    key: 'gsudoku',
    title: '数独',
    tag: '逻辑',
    primary: Color(0xFF4C6FA8),
    deep: Color(0xFF2E4A7C),
    soft: Color(0xFFDCE4F4),
    ink: Color(0xFF1B2B47),
  ),
  GameIdentity(
    key: 'gnono',
    title: '数织',
    tag: '像素',
    primary: Color(0xFF4C8A68),
    deep: Color(0xFF2C6547),
    soft: Color(0xFFDAEBE0),
    ink: Color(0xFF1A3A2A),
  ),
  GameIdentity(
    key: 'gslide',
    title: '数字华容道',
    tag: '滑块',
    primary: Color(0xFF996747),
    deep: Color(0xFF6B4227),
    soft: Color(0xFFEAD6C7),
    ink: Color(0xFF3A2314),
  ),
  GameIdentity(
    key: 'gsnake',
    title: '贪吃蛇',
    tag: '街机',
    primary: Color(0xFF3E9E5B),
    deep: Color(0xFF1F6E3A),
    soft: Color(0xFFD6EEDB),
    ink: Color(0xFF143C22),
  ),
  GameIdentity(
    key: 'gsheep',
    title: '羊了个羊',
    tag: '消除',
    primary: Color(0xFF85AC5C),
    deep: Color(0xFF587C38),
    soft: Color(0xFFE7F0DA),
    ink: Color(0xFF2C3D1E),
  ),
  GameIdentity(
    key: 'gjump',
    title: '跳一跳',
    tag: '节奏',
    primary: Color(0xFFCD6849),
    deep: Color(0xFF96422A),
    soft: Color(0xFFF6DCCF),
    ink: Color(0xFF471F13),
  ),
  GameIdentity(
    key: 'gpeng',
    title: '淘气小球',
    tag: '物理',
    primary: Color(0xFFE1873B),
    deep: Color(0xFFAC5C1C),
    soft: Color(0xFFF9E2C8),
    ink: Color(0xFF4A290E),
  ),
  GameIdentity(
    key: 'gbrake',
    title: '极限刹车',
    tag: '速度',
    primary: Color(0xFFBE4A33),
    deep: Color(0xFF8A2D1D),
    soft: Color(0xFFF3D6CC),
    ink: Color(0xFF401510),
  ),
  GameIdentity(
    key: 'gidiom',
    title: '成语接龙',
    tag: '文字',
    primary: Color(0xFFB4443C),
    deep: Color(0xFF822A26),
    soft: Color(0xFFF0D6D0),
    ink: Color(0xFF3B1714),
  ),
  GameIdentity(
    key: 'gfeihua',
    title: '飞花令',
    tag: '诗词',
    primary: Color(0xFF3D7B77),
    deep: Color(0xFF235653),
    soft: Color(0xFFD6E9E6),
    ink: Color(0xFF132E2C),
  ),
  GameIdentity(
    key: 'gliquid',
    title: '咕噜果冻',
    tag: '果冻',
    primary: Color(0xFF5FBE9C),
    deep: Color(0xFF368A6C),
    soft: Color(0xFFE0F3EA),
    ink: Color(0xFF1C4636),
    secondary: Color(0xFFF0A8BC),
  ),
  GameIdentity(
    key: 'gknockwater',
    title: '铃渡',
    tag: '音游',
    primary: Color(0xFF2F6A62),
    deep: Color(0xFF123E3B),
    soft: Color(0xFFD3E7E1),
    ink: Color(0xFF0C2321),
    secondary: Color(0xFFE3B878),
  ),
];

/// 各游戏在 [AppState] 里的最佳成绩 key（与排行榜 / 本地最佳一致）。
const kGameBestKeys = <String, String>{
  'g2048': '2048',
  'gmem': 'memory',
  'gsudoku': 'sudoku',
  'gnono': 'nono',
  'gslide': 'slide',
  'gsnake': 'snake',
  'gsheep': 'sheep',
  'gjump': 'jump',
  'gpeng': 'peng',
  'gbrake': 'brake',
  'gidiom': 'idiom',
  'gfeihua': 'feihua',
  'gliquid': 'liquid',
  'gknockwater': 'knockwater',
};

String bestKeyOf(String key) => kGameBestKeys[key] ?? key;

/// 按 key 取身份；缺省时回退到中性纸色，保证未知游戏不炸。
GameIdentity identityOf(String key) {
  for (final i in kGameIdentities) {
    if (i.key == key) return i;
  }
  return const GameIdentity(
    key: 'missing',
    title: '游戏',
    tag: '休闲',
    primary: Color(0xFF9A9184),
    deep: Color(0xFF6E675C),
    soft: Color(0xFFEDE8DC),
    ink: Color(0xFF3A362E),
  );
}
