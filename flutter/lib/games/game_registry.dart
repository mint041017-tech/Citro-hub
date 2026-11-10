import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'game_theme.dart';

/// 游戏中心卡片数据。
///
/// [gradient] 是卡片底的两档粉彩渐变（nosh 的留白 + 轻色底），
/// [art] 是卡片右侧的圆角几何小画；两者都只读 token，不再有旋转 / 胶带 / 便签。
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
  GameCardData(key: 'gmem', title: '记忆卡牌', gradient: _gOrange, art: _artMem),
  GameCardData(key: 'gsudoku', title: '数独', gradient: _gOrange, art: _artSudoku),
  GameCardData(key: 'gnono', title: '数织', gradient: _gGreen, art: _artNono),
  GameCardData(key: 'gslide', title: '数字华容道', gradient: _gOrange, art: _artSlide),
  GameCardData(key: 'gsnake', title: '贪吃蛇', gradient: _gGreen, art: _artSnake),
  GameCardData(key: 'gsheep', title: '羊了个羊', gradient: _gYellow, art: _artSheep),
  GameCardData(key: 'gjump', title: '跳一跳', gradient: _gBlue, art: _artJump),
  GameCardData(key: 'gpeng', title: '淘气小球', gradient: _gPink, art: _artPeng),
  GameCardData(key: 'gbrake', title: '极限刹车', gradient: _gOrange, art: _artBrake),
  GameCardData(key: 'gidiom', title: '成语接龙', gradient: _gPink, art: _artIdiom),
  GameCardData(key: 'gfeihua', title: '飞花令', gradient: _gBlue, art: _artFeihua),
  GameCardData(key: 'gliquid', title: '咕噜果冻', gradient: _gGreen, art: _artLiquid),
  GameCardData(key: 'gknockwater', title: '铃渡', gradient: _gNeutral, art: _artKnockwater),
];

List<Color> _gOrange(CitroColors c) => [c.tintYellow, c.tintPink];
List<Color> _gGreen(CitroColors c) => [c.tintGreen, c.tintNeutral];
List<Color> _gYellow(CitroColors c) => [c.tintYellow, c.tintGreen];
List<Color> _gBlue(CitroColors c) => [c.tintBlue, c.tintNeutral];
List<Color> _gPink(CitroColors c) => [c.tintPink, c.tintYellow];
List<Color> _gNeutral(CitroColors c) => [c.tintBlue, c.tintGreen];

/// 通用圆角小块（卡片艺术的基本形）。
Widget _tile(
  String text,
  Color bg,
  Color fg, {
  double w = 26,
  double h = 26,
  double radius = 8,
  double fontSize = 11,
}) {
  return Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 3)),
      ],
    ),
    alignment: Alignment.center,
    child: Text(
      text,
      style: TextStyle(
        fontFamily: AppFonts.rounded,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: fg,
        height: 1,
      ),
    ),
  );
}

Widget _art2048(BuildContext context) {
  final c = context.c;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _tile('2', c.surface2, c.ink2, w: 20, h: 24, fontSize: 9),
      const SizedBox(width: 2),
      _tile('4', c.accentLt, c.accentInk, w: 20, h: 24, fontSize: 9),
      const SizedBox(width: 2),
      _tile('8', c.accent, c.accentText, w: 20, h: 24, fontSize: 9),
      const SizedBox(width: 2),
      _tile('2048', c.ink, c.bg, w: 26, h: 24, fontSize: 9),
    ],
  );
}

Widget _artMem(BuildContext context) {
  final c = context.c;
  return SizedBox(
    width: 62,
    height: 46,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(left: 8, child: _tile('橘', c.accent, c.accentText, w: 26, h: 34, radius: CitroColors.radii.xs, fontSize: 13)),
        Positioned(right: 8, child: _tile('福', c.surface2, c.accentInk, w: 26, h: 34, radius: CitroColors.radii.xs, fontSize: 13)),
      ],
    ),
  );
}

Widget _artSudoku(BuildContext context) {
  final c = context.c;
  const values = ['5', '3', '', '', '7', '', '', '', ''];
  return Container(
    width: 40,
    height: 40,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: c.surface2,
      borderRadius: BorderRadius.circular(CitroColors.radii.small),
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
                  ? c.accentLt
                  : (i == 0 ? c.accent : c.surface),
              borderRadius: BorderRadius.circular(CitroColors.radii.xs),
            ),
            alignment: Alignment.center,
            child: Text(
              values[i],
              style: context.body(
                size: CitroType.micro,
                weight: CitroType.strong,
                color: i == 0 ? c.accentText : c.ink2,
              ),
            ),
          ),
      ],
    ),
  );
}

Widget _artNono(BuildContext context) {
  final c = context.c;
  const filled = [1, 0, 1, 0, 1, 0, 1, 0, 1];
  return Container(
    width: 40,
    height: 40,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: c.surface2,
      borderRadius: BorderRadius.circular(CitroColors.radii.small),
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
              color: filled[i] == 1 ? c.mint : c.surface,
              borderRadius: BorderRadius.circular(CitroColors.radii.xs),
            ),
          ),
      ],
    ),
  );
}

Widget _artSlide(BuildContext context) {
  final c = context.c;
  return Container(
    width: 40,
    height: 40,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: c.surface2,
      borderRadius: BorderRadius.circular(CitroColors.radii.small),
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
              color: i == 8 ? c.accent : c.surface,
              borderRadius: BorderRadius.circular(CitroColors.radii.xs),
            ),
            alignment: Alignment.center,
            child: Text(
              '$i',
              style: context.body(
                size: CitroType.micro,
                weight: CitroType.strong,
                color: i == 8 ? c.accentText : c.ink2,
              ),
            ),
          ),
        const SizedBox.shrink(),
      ],
    ),
  );
}

Widget _artSnake(BuildContext context) {
  final c = context.c;
  return SizedBox(
    width: 38,
    height: 38,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tile('', c.mint, c.accentText, w: 16, h: 16, radius: 5),
            const SizedBox(width: 3),
            _tile('', c.mint, c.accentText, w: 16, h: 16, radius: 5),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tile('', c.mint, c.accentText, w: 16, h: 16, radius: 5),
            const SizedBox(width: 3),
            _tile('', c.accent, c.accentText, w: 16, h: 16, radius: 5),
          ],
        ),
      ],
    ),
  );
}

Widget _artSheep(BuildContext context) {
  final c = context.c;
  return SizedBox(
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
                c.tintGreen,
                c.tintYellow,
                c.tintBlue,
              ][i % 3],
              borderRadius: BorderRadius.circular(CitroColors.radii.xs),
            ),
          ),
      ],
    ),
  );
}

Widget _artJump(BuildContext context) {
  return SizedBox(
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
}

Widget _block(BuildContext context, double w, double h) {
  final c = context.c;
  return Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: c.tintYellow,
      borderRadius: BorderRadius.circular(CitroColors.radii.xs),
      boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 2))],
    ),
  );
}

Widget _ball(BuildContext context, double s) {
  final c = context.c;
  return Container(
    width: s,
    height: s,
    decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
  );
}

Widget _artPeng(BuildContext context) {
  return SizedBox(
    width: 50,
    height: 50,
    child: CustomPaint(painter: _RingPainter(context.c.accent, context.c.ink2)),
  );
}

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

Widget _artBrake(BuildContext context) {
  return SizedBox(
    width: 56,
    height: 46,
    child: CustomPaint(
      painter: _SpeedoPainter(context.c.accent, context.c.ink2, context.c.line2),
    ),
  );
}

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
        ..color = line
        ..strokeCap = StrokeCap.round,
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

Widget _artIdiom(BuildContext context) {
  final c = context.c;
  return SizedBox(
    width: 76,
    height: 42,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _tile('成', c.accentLt, c.accentInk, w: 22, h: 30, radius: CitroColors.radii.xs, fontSize: 12),
        const SizedBox(width: 3),
        _tile('语', c.surface2, c.ink2, w: 22, h: 30, radius: CitroColors.radii.xs, fontSize: 12),
        const SizedBox(width: 3),
        _tile('接', c.surface2, c.ink2, w: 22, h: 30, radius: CitroColors.radii.xs, fontSize: 12),
      ],
    ),
  );
}

Widget _artFeihua(BuildContext context) {
  final c = context.c;
  return SizedBox(
    width: 76,
    height: 46,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _petal(context, c.tintPink),
        const SizedBox(width: 4),
        _petal(context, c.tintBlue),
        const SizedBox(width: 4),
        _petal(context, c.tintGreen),
      ],
    ),
  );
}

Widget _petal(BuildContext context, Color color) {
  return Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(CitroColors.radii.small),
        bottomRight: Radius.circular(CitroColors.radii.small),
        topRight: Radius.circular(CitroColors.radii.small),
      ),
    ),
  );
}

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

/// 青玉水墨小卡：铃渡的沉浸式深色水面是这款游戏的品牌资产，
/// 保持自绘深潭 + 金/珊瑚色，不并入全局 token（其余游戏卡片都走 token）。
class _KnockwaterArtPainter extends CustomPainter {
  _KnockwaterArtPainter(this.c);

  final CitroColors c;

  void _petal(Canvas canvas, Offset at, double angle, double scale) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, -4.6 * scale)
      ..cubicTo(
        3.2 * scale,
        -2.6 * scale,
        3.4 * scale,
        1.6 * scale,
        0,
        4.2 * scale,
      )
      ..cubicTo(
        -3.4 * scale,
        1.6 * scale,
        -3.2 * scale,
        -2.6 * scale,
        0,
        -4.6 * scale,
      )
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
          colors: <Color>[
            Color(0xFF245B55),
            Color(0xFF123F3D),
            Color(0xFF071F1E),
          ],
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

/// 咕噜果冻小罐：透明罐 + 果冻波浪 + 小星星，全部走 token。
class _LiquidJarPainter extends CustomPainter {
  _LiquidJarPainter(this.c);

  final CitroColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = const Rect.fromLTWH(10, 6, 38, 38);
    final jar = RRect.fromRectAndRadius(rect, Radius.circular(CitroColors.radii.small));
    canvas.drawRRect(jar, Paint()..color = c.surface);

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
    canvas.drawPath(wave, Paint()..color = c.mintSoft);

    final jelly = c.accentLt;
    canvas.drawCircle(Offset(rect.right - 13, rect.bottom - 16), 10.5, Paint()..color = jelly);
    canvas.drawCircle(
      Offset(rect.right - 13, rect.bottom - 16),
      10.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = c.accent,
    );
    canvas.drawCircle(Offset(rect.right - 16.5, rect.bottom - 19), 1.6, Paint()..color = c.ink);
    canvas.drawCircle(Offset(rect.right - 9.5, rect.bottom - 19), 1.6, Paint()..color = c.ink);

    final yellow = Offset(rect.left + 15, rect.bottom - 22);
    canvas.drawCircle(yellow, 7, Paint()..color = c.tintYellow);
    canvas.drawCircle(
      yellow,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = c.accentInk,
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
    canvas.drawPath(star, Paint()..color = c.surface2);
    canvas.restore();

    canvas.drawRRect(
      jar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = c.ink,
    );
    canvas.drawLine(
      Offset(rect.left - 3, rect.top + 1),
      Offset(rect.left + 8, rect.top - 3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = c.ink,
    );
    canvas.drawLine(
      Offset(rect.right + 3, rect.top + 1),
      Offset(rect.right - 8, rect.top - 3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = c.ink,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidJarPainter oldDelegate) => oldDelegate.c != c;
}
