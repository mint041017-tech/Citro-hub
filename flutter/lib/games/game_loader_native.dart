import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'g2048.dart';
import 'gbrake_web.dart';
import 'gfeihua.dart';
import 'gidiom.dart';
import 'gjump.dart';
import 'gliquid.dart';
import 'gmemory.dart';
import 'gnono.dart';
import 'gpeng.dart';
import 'gsheep.dart';
import 'gslide.dart';
import 'gsnake.dart';
import 'gsudoku.dart';
import 'game_common.dart';

Widget buildGamePage(String key) {
  return switch (key) {
    'g2048' => const Game2048Page(),
    'gmem' => const GameMemoryPage(),
    'gsudoku' => const GameSudokuPage(),
    'gnono' => const GameNonoPage(),
    'gslide' => const GameSlidePage(),
    'gsnake' => const GameSnakePage(),
    'gsheep' => const GameSheepPage(),
    'gjump' => const GameJumpPage(),
    'gpeng' => const GamePengPage(),
    // v1.7.0：极限刹车改为内嵌原始版（WebView + three.js 构建产物）
    'gbrake' => const GameBrakeWebPage(),
    'gidiom' => const GameIdiomPage(),
    'gfeihua' => const GameFeihuaPage(),
    'gliquid' => const GameLiquidPage(),
    _ => const _MissingGame(),
  };
}

class _MissingGame extends StatelessWidget {
  const _MissingGame();
  @override
  Widget build(BuildContext context) {
    return GamePageShell(
      gameKey: 'missing',
      title: '游戏',
      subtitle: '这个游戏还没准备好',
      note: '',
      child: Center(child: Text('敬请期待', style: context.heading(size: 22))),
    );
  }
}
