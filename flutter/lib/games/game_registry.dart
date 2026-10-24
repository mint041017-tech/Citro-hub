import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'game_common.dart';
import 'g2048.dart';
import 'gmemory.dart';
import 'gsudoku.dart';
import 'gnono.dart';
import 'gslide.dart';
import 'gsnake.dart';
import 'gsheep.dart';
import 'gjump.dart';
import 'gpeng.dart';
import 'gbrake_web.dart';
import 'gidiom.dart';
import 'gfeihua.dart';

class GameCardData {
  final String key;
  final String title;
  final List<Color> Function(CitroColors c) gradient;
  final Widget Function(BuildContext context) art;
  const GameCardData({
    required this.key,
    required this.title,
    required this.gradient,
    required this.art,
  });
}

const kGameCards = <GameCardData>[
  GameCardData(key: 'g2048', title: '2048', gradient: _gOrange, art: _art2048),
  GameCardData(key: 'gmem', title: '记忆卡牌', gradient: _gBrown, art: _artMem),
  GameCardData(
    key: 'gsudoku',
    title: '数独',
    gradient: _gOrange,
    art: _artSudoku,
  ),
  GameCardData(key: 'gnono', title: '数织', gradient: _gGreen, art: _artNono),
  GameCardData(
    key: 'gslide',
    title: '数字华容道',
    gradient: _gBrown,
    art: _artSlide,
  ),
  GameCardData(key: 'gsnake', title: '贪吃蛇', gradient: _gOrange, art: _artSnake),
  GameCardData(
    key: 'gsheep',
    title: '羊了个羊',
    gradient: _gOrange,
    art: _artSheep,
  ),
  GameCardData(key: 'gjump', title: '跳一跳', gradient: _gBrown, art: _artJump),
  GameCardData(key: 'gpeng', title: '淘气小球', gradient: _gOrange, art: _artPeng),
  GameCardData(
    key: 'gbrake',
    title: '极限刹车',
    gradient: _gOrange,
    art: _artBrake,
  ),
  GameCardData(key: 'gidiom', title: '成语接龙', gradient: _gRed, art: _artIdiom),
  GameCardData(key: 'gfeihua', title: '飞花令', gradient: _gTeal, art: _artFeihua),
];

List<Color> _gOrange(CitroColors c) => const [
  Color(0x28FE923B),
  Color(0x14B8924A),
];
List<Color> _gBrown(CitroColors c) => const [
  Color(0x28B8924A),
  Color(0x14FE923B),
];
List<Color> _gGreen(CitroColors c) => const [
  Color(0x2A568C74),
  Color(0x14B8924A),
];
List<Color> _gRed(CitroColors c) => const [
  Color(0x24B04A36),
  Color(0x14B8924A),
];
List<Color> _gTeal(CitroColors c) => const [
  Color(0x242E6B73),
  Color(0x1AA89154),
];

Widget _tile(
  String text,
  Color bg,
  Color fg, {
  double w = 26,
  double h = 26,
  double radius = 7,
  double fontSize = 11,
  double angle = 0,
}) {
  return Transform.rotate(
    angle: angle,
    child: Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332A211C),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppFonts.noto,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: fg,
          height: 1,
        ),
      ),
    ),
  );
}

Widget _art2048(BuildContext context) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    _tile(
      '2',
      const Color(0xFFEBE7E1),
      const Color(0xFF5C524A),
      w: 20,
      h: 24,
      fontSize: 9,
    ),
    const SizedBox(width: 2),
    _tile(
      '4',
      const Color(0xFFE8B98A),
      const Color(0xFF5C3A1E),
      w: 20,
      h: 24,
      fontSize: 9,
    ),
    const SizedBox(width: 2),
    _tile(
      '8',
      const Color(0xFFD97E4A),
      const Color(0xFF3A1C0B),
      w: 20,
      h: 24,
      fontSize: 9,
    ),
    const SizedBox(width: 2),
    _tile(
      '2048',
      context.c.accent,
      const Color(0xFF2A211C),
      w: 26,
      h: 24,
      fontSize: 6.5,
    ),
  ],
);

Widget _artMem(BuildContext context) => SizedBox(
  width: 62,
  height: 46,
  child: Stack(
    alignment: Alignment.center,
    children: [
      Positioned(
        left: 8,
        child: _tile(
          '柑',
          context.c.accent,
          const Color(0xFF2A211C),
          w: 26,
          h: 34,
          radius: 6,
          fontSize: 13,
          angle: -8 * math.pi / 180,
        ),
      ),
      Positioned(
        right: 8,
        child: _tile(
          '橘',
          context.c.surface2,
          context.c.accentInk,
          w: 26,
          h: 34,
          radius: 6,
          fontSize: 13,
          angle: 6 * math.pi / 180,
        ),
      ),
    ],
  ),
);

Widget _artSudoku(BuildContext context) {
  final colors = [context.c.accent, context.c.accentLt, context.c.surface2];
  const values = ['5', '3', '', '', '7', '', '', '', ''];
  return Container(
    width: 40,
    height: 40,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: context.c.surface2.withAlpha(160),
      borderRadius: BorderRadius.circular(5),
    ),
    child: GridView.count(
      crossAxisCount: 3,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      children: [
        for (var i = 0; i < 9; i++)
          Container(
            decoration: BoxDecoration(
              color: i == 4
                  ? const Color(0xFFE8B98A)
                  : (i == 0 ? colors[0] : const Color(0xFFEBE7E1)),
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.center,
            child: Text(
              values[i],
              style: TextStyle(
                fontSize: 6,
                color: i == 0
                    ? const Color(0xFF2A211C)
                    : const Color(0xFF5C524A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    ),
  );
}

Widget _artNono(BuildContext context) {
  const filled = [1, 0, 1, 0, 1, 0, 1, 0, 1];
  return Container(
    width: 40,
    height: 40,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: context.c.surface2.withAlpha(160),
      borderRadius: BorderRadius.circular(5),
    ),
    child: GridView.count(
      crossAxisCount: 3,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      children: [
        for (var i = 0; i < 9; i++)
          Container(
            decoration: BoxDecoration(
              color: filled[i] == 1
                  ? const Color(0xFF568C74)
                  : const Color(0xFFEBE7E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    ),
  );
}

Widget _artSlide(BuildContext context) => Container(
  width: 40,
  height: 40,
  padding: const EdgeInsets.all(2),
  decoration: BoxDecoration(
    color: context.c.surface2.withAlpha(160),
    borderRadius: BorderRadius.circular(4),
  ),
  child: GridView.count(
    crossAxisCount: 3,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 2,
    crossAxisSpacing: 2,
    children: [
      for (var i = 1; i <= 8; i++)
        Container(
          decoration: BoxDecoration(
            color: i == 8 ? context.c.accent : const Color(0xFFEBE7E1),
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.center,
          child: Text(
            '$i',
            style: TextStyle(
              fontSize: 6.5,
              fontWeight: FontWeight.w800,
              color: i == 8 ? const Color(0xFF2A211C) : const Color(0xFF5C524A),
            ),
          ),
        ),
      const SizedBox.shrink(),
    ],
  ),
);

Widget _artSnake(BuildContext context) => SizedBox(
  width: 38,
  height: 38,
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tile(
            '',
            const Color(0xFF568C74),
            Colors.white,
            w: 16,
            h: 16,
            radius: 3,
            angle: 0,
          ),
          const SizedBox(width: 3),
          _tile(
            '',
            const Color(0xFF568C74),
            Colors.white,
            w: 16,
            h: 16,
            radius: 3,
          ),
        ],
      ),
      const SizedBox(height: 3),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tile(
            '',
            const Color(0xFF568C74),
            Colors.white,
            w: 16,
            h: 16,
            radius: 3,
          ),
          const SizedBox(width: 3),
          _tile('', context.c.accent, Colors.white, w: 16, h: 16, radius: 3),
        ],
      ),
    ],
  ),
);

Widget _artSheep(BuildContext context) => SizedBox(
  width: 74,
  height: 44,
  child: Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (var i = 0; i < 6; i++)
        Container(
          width: 22,
          height: 20,
          decoration: BoxDecoration(
            color: [
              const Color(0xFFDDE7C9),
              const Color(0xFFC8D8B2),
              const Color(0xFFE7E2C4),
            ][i % 3],
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0x66A8B88C)),
          ),
        ),
    ],
  ),
);

Widget _artJump(BuildContext context) => SizedBox(
  width: 70,
  height: 44,
  child: Stack(
    children: [
      Positioned(left: 6, top: 24, child: _block(context, 22, 20)),
      Positioned(left: 38, top: 8, child: _block(context, 26, 22)),
      Positioned(left: 24, top: 8, child: _ball(context, 12)),
    ],
  ),
);

Widget _block(BuildContext context, double w, double h) => Container(
  width: w,
  height: h,
  decoration: BoxDecoration(
    color: const Color(0xFFE8B98A),
    borderRadius: BorderRadius.circular(4),
    boxShadow: const [
      BoxShadow(color: Color(0x332A211C), blurRadius: 4, offset: Offset(0, 2)),
    ],
  ),
);

Widget _ball(BuildContext context, double s) => Container(
  width: s,
  height: s,
  decoration: BoxDecoration(
    color: context.c.accent,
    shape: BoxShape.circle,
    border: Border.all(color: const Color(0x662A211C)),
  ),
);

Widget _artPeng(BuildContext context) => SizedBox(
  width: 50,
  height: 50,
  child: CustomPaint(painter: _RingPainter(context.c.accent, context.c.ink2)),
);

class _RingPainter extends CustomPainter {
  final Color accent;
  final Color ink;
  _RingPainter(this.accent, this.ink);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width * .38;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      0,
      math.pi * 1.65,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = ink.withAlpha(170)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      math.pi * 1.9,
      math.pi * .6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = accent
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(center.dx + 2, center.dy - 3),
      size.width * .11,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _artBrake(BuildContext context) => SizedBox(
  width: 56,
  height: 46,
  child: CustomPaint(
    painter: _SpeedoPainter(context.c.accent, context.c.ink2, context.c.line2),
  ),
);

class _SpeedoPainter extends CustomPainter {
  final Color accent;
  final Color ink;
  final Color line;
  _SpeedoPainter(this.accent, this.ink, this.line);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height * .86),
      radius: size.width * .40,
    );
    canvas.drawArc(
      rect,
      math.pi,
      math.pi * .86,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = accent
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      math.pi * 1.88,
      math.pi * .12,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFB04A36),
    );
    final c = Offset(size.width / 2, size.height * .86);
    final end = Offset(
      c.dx + math.cos(-math.pi * .32) * size.width * .26,
      c.dy + math.sin(-math.pi * .32) * size.width * .26,
    );
    canvas.drawLine(
      c,
      end,
      Paint()
        ..color = ink
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, 2, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _artIdiom(BuildContext context) => SizedBox(
  width: 76,
  height: 42,
  child: Stack(
    alignment: Alignment.center,
    children: [
      Positioned(left: 4, child: _paperTile(context, '成', -8)),
      Positioned(left: 26, child: _paperTile(context, '语', 4)),
      Positioned(left: 48, child: _paperTile(context, '接', -3)),
    ],
  ),
);

Widget _paperTile(BuildContext context, String char, double angle) =>
    Transform.rotate(
      angle: angle * math.pi / 180,
      child: Container(
        width: 24,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9E8),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0x66B04A36)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F2A211C),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          char,
          style: TextStyle(
            fontFamily: AppFonts.zcool,
            fontSize: 12,
            color: const Color(0xFF7A2D12),
          ),
        ),
      ),
    );

Widget _artFeihua(BuildContext context) => SizedBox(
  width: 76,
  height: 46,
  child: Stack(
    children: [
      Positioned(left: 12, top: 14, child: _petal(context, -18)),
      Positioned(left: 28, top: 4, child: _petal(context, 28)),
      Positioned(left: 46, top: 16, child: _petal(context, 74)),
    ],
  ),
);

Widget _petal(BuildContext context, double angle) => Transform.rotate(
  angle: angle * math.pi / 180,
  child: Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
        topRight: Radius.circular(12),
        bottomLeft: Radius.zero,
      ),
      gradient: const LinearGradient(
        colors: [Color(0xFFE4F2F0), Color(0xFFB7DAD7)],
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x382E6B73),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
  ),
);

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
