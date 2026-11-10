import 'package:flutter/material.dart' show Color;

import '../theme/tokens.dart';

/// 品牌橙（或同明度语义色）实底上的文字 / 图标色。
///
/// 浅色主题里 [CitroColors.onAccent] 是深墨 #2E2C22（橙 #FF8A1F 上约 4.4:1），
/// 深色主题里是 #1A1206，两套都过对比；这里再兜一层，
/// 保证游戏画布即便自定义了强调色，文字也不会压扁在底色上。
extension CitroAccentTextX on CitroColors {
  Color get accentText => dark ? onAccent : ink;
}
