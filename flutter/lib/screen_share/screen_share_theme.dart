import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 「一起看」的暖黑剧场配色。
///
/// 只在屏幕分享 / 一起看的页面里用，App 其他页面保持原来的奶米浅色。
/// 底与卡片抄自 web 观看端（screen-share/public/index.html），两边改色时
/// 一起改；强调色是 logo 的橙，在线 / 麦克风用青瓷薄荷。
final CitroColors shareColors = CitroColors.darkColors.copyWith(
  bg: const Color(0xFF221C19),
  bg2: const Color(0xFF17120F),
  surface: const Color(0xFF2C2521),
  surface2: const Color(0xFF3A302B),
  ink: const Color(0xFFFFF6EA),
  ink2: const Color(0xFFD9C9BC),
  inkSoft: const Color(0xFFBFAFA2),
  line: const Color(0x1AFFF6EA),
  line2: const Color(0x33FFF6EA),
  accent: const Color(0xFFE8703A),
  accent2: const Color(0xFFF28B57),
  accentLt: const Color(0xFF3A261B),
  accentInk: const Color(0xFFF28B57),
  // 橙底上的文字用深棕，对比度约 5.7:1。
  onAccent: const Color(0xFF2A1508),
  mint: const Color(0xFF8FD3C7),
  mintInk: const Color(0xFFBDE6DE),
  mintSoft: const Color(0xFF22302D),
  mintLine: const Color(0xFF33443F),
  stamp: const Color(0xFFE8703A),
  danger: const Color(0xFFE08A7A),
  dangerSoft: const Color(0xFF3A2320),
  dark: true,
);

/// 包一层就能让页面里所有 `context.c` / 现有组件变成暖黑剧场。
final ThemeData shareTheme = buildCitroTheme(shareColors);

/// 顶部 / 底部弹层走的是根 Navigator，不会继承页面里那层 Theme。
///
/// 所以分享相关的 dialog / sheet 要在自己的 builder 里再包一次。
class ShareTheme extends StatelessWidget {
  const ShareTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(data: shareTheme, child: child);
}
