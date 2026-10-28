import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

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
  GameCardData(
    key: 'gliquid',
    title: '咕噜果冻',
    gradient: _gMint,
    art: _artLiquid,
  ),
  GameCardData(
    key: 'gknockwater',
    title: '铃渡',
    gradient: _gJade,
    art: _artKnockwater,
  ),
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
List<Color> _gMint(CitroColors c) => const [
  Color(0x30A9E5C8),
  Color(0x18FFC3D6),
];
List<Color> _gJade(CitroColors c) => const [
  Color(0x2A2E6B62),
  Color(0x16143F3D),
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

Widget _artLiquid(BuildContext context) => SizedBox(
  width: 58,
  height: 48,
  child: CustomPaint(painter: _LiquidJarPainter(context.c)),
);

Widget _artKnockwater(BuildContext context) => SizedBox(
  width: 62,
  height: 48,
  child: CustomPaint(painter: _KnockwaterArtPainter(context.c)),
);

/// 青玉水墨小卡：一汪深潭、三片花瓣、湾心与一枚水铃。
class _KnockwaterArtPainter extends CustomPainter {
  _KnockwaterArtPainter(this.c);

  final CitroColors c;

  void _petal(Canvas canvas, Offset at, double angle, double scale) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, -4.6 * scale)
      ..cubicTo(3.2 * scale, -2.6 * scale, 3.4 * scale, 1.6 * scale, 0, 4.2 * scale)
      ..cubicTo(-3.4 * scale, 1.6 * scale, -3.2 * scale, -2.6 * scale, 0, -4.6 * scale)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFB69A));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = const Color(0x99C96B4E),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pond = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.52),
      width: size.width - 5,
      height: size.height - 7,
    );
    canvas.drawOval(
      pond,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF245B55), Color(0xFF123F3D), Color(0xFF071F1E)],
          stops: <double>[0, 0.55, 1],
        ).createShader(pond),
    );
    canvas.drawOval(
      pond,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(0x73A9F5E6),
    );

    for (var i = 1; i <= 3; i++) {
      final ripple = Rect.fromCenter(
        center: Offset(size.width * 0.36, size.height * 0.56),
        width: 9.0 * i,
        height: 4.4 * i,
      );
      canvas.drawOval(
        ripple,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = const Color(0x40A9F5E6),
      );
    }

    final bay = Offset(size.width * 0.73, size.height * 0.58);
    canvas.drawCircle(bay, 5.6, Paint()..color = const Color(0x33E3B878));
    canvas.drawCircle(
      bay,
      5.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xA6E3B878),
    );

    _petal(canvas, Offset(size.width * 0.46, size.height * 0.40), -0.55, 1);
    _petal(canvas, Offset(size.width * 0.55, size.height * 0.70), 0.7, 0.9);
    _petal(canvas, Offset(size.width * 0.60, size.height * 0.44), 1.9, 0.8);

    final bell = Offset(size.width * 0.30, size.height * 0.64);
    canvas.drawCircle(bell, 4.6, Paint()..color = const Color(0x33E3B878));
    canvas.drawCircle(bell, 2.5, Paint()..color = const Color(0xFFF2E9D8));
    canvas.drawCircle(
      bell,
      2.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = c.accentInk,
    );
    canvas.drawCircle(
      Offset(bell.dx, bell.dy + 3.4),
      0.9,
      Paint()..color = c.accentInk,
    );
  }

  @override
  bool shouldRepaint(covariant _KnockwaterArtPainter oldDelegate) =>
      oldDelegate.c != c;
}

class _LiquidJarPainter extends CustomPainter {
  _LiquidJarPainter(this.c);

  final CitroColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = c.ink;
    final rect = Rect.fromLTWH(10, 6, 38, 38);
    final jar = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(jar, Paint()..color = const Color(0xFFFFFAF0));

    canvas.save();
    canvas.clipRRect(jar);
    final wave = Path()
      ..moveTo(rect.left, rect.bottom - 15)
      ..quadraticBezierTo(
        rect.left + 9,
        rect.bottom - 21,
        rect.center.dx,
        rect.bottom - 16,
      )
      ..quadraticBezierTo(
        rect.right - 9,
        rect.bottom - 11,
        rect.right,
        rect.bottom - 17,
      )
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    canvas.drawPath(wave, Paint()..color = const Color(0xFFA9ECCB));

    const pink = Color(0xFFFFC3D6);
    const pinkEdge = Color(0xFFAB4F72);
    canvas.drawCircle(
      Offset(rect.right - 13, rect.bottom - 16),
      10.5,
      Paint()..color = pink,
    );
    canvas.drawCircle(
      Offset(rect.right - 13, rect.bottom - 16),
      10.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = pinkEdge,
    );
    canvas.drawCircle(
      Offset(rect.right - 16.5, rect.bottom - 19),
      1.6,
      Paint()..color = ink,
    );
    canvas.drawCircle(
      Offset(rect.right - 9.5, rect.bottom - 19),
      1.6,
      Paint()..color = ink,
    );

    final yellow = Offset(rect.left + 15, rect.bottom - 22);
    canvas.drawCircle(yellow, 7, Paint()..color = const Color(0xFFFFDD7F));
    canvas.drawCircle(
      yellow,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF98701A),
    );

    final star = Path()
      ..moveTo(rect.left + 9, rect.top + 12)
      ..lineTo(rect.left + 11, rect.top + 16)
      ..lineTo(rect.left + 15, rect.top + 18)
      ..lineTo(rect.left + 11, rect.top + 20)
      ..lineTo(rect.left + 9, rect.top + 24)
      ..lineTo(rect.left + 7, rect.top + 20)
      ..lineTo(rect.left + 3, rect.top + 18)
      ..lineTo(rect.left + 7, rect.top + 16)
      ..close();
    canvas.drawPath(star, Paint()..color = const Color(0xB3FFFAF0));
    canvas.restore();

    canvas.drawRRect(
      jar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = ink,
    );
    canvas.drawLine(
      Offset(rect.left - 3, rect.top + 1),
      Offset(rect.left + 8, rect.top - 3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = ink,
    );
    canvas.drawLine(
      Offset(rect.right + 3, rect.top + 1),
      Offset(rect.right - 8, rect.top - 3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = ink,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidJarPainter oldDelegate) => false;
}

