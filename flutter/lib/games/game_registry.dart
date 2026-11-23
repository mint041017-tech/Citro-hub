import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'game_identity.dart';

/// 游戏中心卡片数据。
///
/// 封面沿用原来的风格：两档粉彩渐变底 + 右侧（或居中）的圆角几何小画。
/// 但**颜色不再读主题**——每个游戏的封面色来自 [GameIdentity]，
/// 亮 / 暗主题、任何模块皮肤下都是同一套颜色，玩家靠颜色就能认出游戏。
class GameCardData {
  final String key;
  final String title;

  const GameCardData({required this.key, required this.title});

  GameIdentity get identity => identityOf(key);

  /// 封面渐变：身份色的浅端 → 向主色靠 45%。
  List<Color> get gradient => [
    identity.soft,
    Color.lerp(identity.soft, identity.primary, .45)!,
  ];

  /// 封面小画。
  Widget art(BuildContext context) => _artFor(identity);
}

const kGameCards = <GameCardData>[
  GameCardData(key: 'g2048', title: '2048'),
  GameCardData(key: 'gmem', title: '记忆卡牌'),
  GameCardData(key: 'gsudoku', title: '数独'),
  GameCardData(key: 'gnono', title: '数织'),
  GameCardData(key: 'gslide', title: '数字华容道'),
  GameCardData(key: 'gsnake', title: '贪吃蛇'),
  GameCardData(key: 'gsheep', title: '羊了个羊'),
  GameCardData(key: 'gjump', title: '跳一跳'),
  GameCardData(key: 'gpeng', title: '淘气小球'),
  GameCardData(key: 'gbrake', title: '极限刹车'),
  GameCardData(key: 'gidiom', title: '成语接龙'),
  GameCardData(key: 'gfeihua', title: '飞花令'),
  GameCardData(key: 'gliquid', title: '咕噜果冻'),
  GameCardData(key: 'gknockwater', title: '铃渡'),
];

Widget _artFor(GameIdentity id) {
  return switch (id.key) {
    'g2048' => _art2048(id),
    'gmem' => _artMem(id),
    'gsudoku' => _artGrid(id, _sudokuMask, const ['5', '3', '', '', '7', '', '', '', '']),
    'gnono' => _artGrid(id, _nonoMask, null),
    'gslide' => _artGrid(id, _slideMask, const ['1', '2', '3', '4', '5', '6', '7', '8', '']),
    'gsnake' => _artSnake(id),
    'gsheep' => _artSheep(id),
    'gjump' => _artJump(id),
    'gpeng' => _artPeng(id),
    'gbrake' => _artBrake(id),
    'gidiom' => _artIdiom(id),
    'gfeihua' => _artFeihua(id),
    'gliquid' => _artLiquid(id),
    'gknockwater' => _artKnockwater(id),
    _ => _art2048(id),
  };
}

/// 通用圆角小块（卡片艺术的基本形）。颜色全部来自身份色。
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

/// 主色浅端：身份色向白靠 55%，用作「浅一格」的砖。
Color _lite(GameIdentity id) => Color.lerp(id.soft, id.primary, .45)!;

Widget _art2048(GameIdentity id) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _tile('2', id.soft, id.ink, w: 20, h: 24, fontSize: 9),
      const SizedBox(width: 2),
      _tile('4', _lite(id), id.deep, w: 20, h: 24, fontSize: 9),
      const SizedBox(width: 2),
      _tile('8', id.primary, id.onPrimary, w: 20, h: 24, fontSize: 9),
      const SizedBox(width: 2),
      _tile('2048', id.deep, id.soft, w: 26, h: 24, fontSize: 9),
    ],
  );
}

Widget _artMem(GameIdentity id) {
  return SizedBox(
    width: 62,
    height: 46,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 8,
          child: _tile('橘', id.primary, id.onPrimary, w: 26, h: 34, radius: 8, fontSize: 13),
        ),
        Positioned(
          right: 8,
          child: _tile('福', id.soft, id.deep, w: 26, h: 34, radius: 8, fontSize: 13),
        ),
      ],
    ),
  );
}

/// 三格棋盘家族：数独 / 数织 / 数字华容道共用一个 3×3 栅格。
const List<double> _sudokuMask = [1, .35, 0, .35, 1, .35, 0, .35, 1];
const List<double> _nonoMask = [1, 0, 1, 0, 1, 0, 1, 0, 1];
const List<double> _slideMask = [.55, .55, .55, .55, 1, .55, .55, .55, -1];

Widget _artGrid(GameIdentity id, List<double> mask, List<String>? values) {
  return Container(
    width: 40,
    height: 40,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: id.soft,
      borderRadius: BorderRadius.circular(12),
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
              color: mask[i] < 0
                  ? Color.lerp(id.soft, id.primary, .2)
                  : Color.lerp(id.soft, id.primary, mask[i]),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: values == null || values[i].isEmpty
                ? null
                : Text(
                    values[i],
                    style: TextStyle(
                      fontFamily: AppFonts.rounded,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: mask[i] >= 1 ? id.onPrimary : id.deep,
                      height: 1,
                    ),
                  ),
          ),
      ],
    ),
  );
}

Widget _artSnake(GameIdentity id) {
  return SizedBox(
    width: 38,
    height: 38,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tile('', _lite(id), id.onPrimary, w: 16, h: 16, radius: 5),
            const SizedBox(width: 3),
            _tile('', _lite(id), id.onPrimary, w: 16, h: 16, radius: 5),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tile('', _lite(id), id.onPrimary, w: 16, h: 16, radius: 5),
            const SizedBox(width: 3),
            _tile('', id.primary, id.onPrimary, w: 16, h: 16, radius: 5),
          ],
        ),
      ],
    ),
  );
}

Widget _artSheep(GameIdentity id) {
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
              color: i == 0 ? id.primary : (i.isEven ? id.soft : _lite(id)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
      ],
    ),
  );
}

Widget _artJump(GameIdentity id) {
  return SizedBox(
    width: 70,
    height: 44,
    child: Stack(
      children: [
        Positioned(left: 6, top: 24, child: _block(id, 22, 20)),
        Positioned(left: 38, top: 8, child: _block(id, 26, 22, hot: true)),
        Positioned(left: 24, top: 8, child: _ball(id, 12)),
      ],
    ),
  );
}

Widget _block(GameIdentity id, double w, double h, {bool hot = false}) {
  return Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: hot ? id.primary : id.soft,
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [
        BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 2)),
      ],
    ),
  );
}

Widget _ball(GameIdentity id, double s) {
  return Container(width: s, height: s, decoration: BoxDecoration(color: id.deep, shape: BoxShape.circle));
}

Widget _artPeng(GameIdentity id) {
  return SizedBox(width: 50, height: 50, child: CustomPaint(painter: _RingPainter(id.primary, id.deep)));
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

Widget _artBrake(GameIdentity id) {
  return SizedBox(width: 56, height: 46, child: CustomPaint(painter: _SpeedoPainter(id)));
}

class _SpeedoPainter extends CustomPainter {
  final GameIdentity id;
  _SpeedoPainter(this.id);
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
        ..color = id.primary
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
        ..color = id.deep.withAlpha(120)
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
        ..color = id.ink
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, 2, Paint()..color = id.ink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _artIdiom(GameIdentity id) {
  return SizedBox(
    width: 76,
    height: 42,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _tile('成', _lite(id), id.deep, w: 22, h: 30, radius: 8, fontSize: 12),
        const SizedBox(width: 3),
        _tile('语', id.soft, id.deep, w: 22, h: 30, radius: 8, fontSize: 12),
        const SizedBox(width: 3),
        _tile('接', id.soft, id.deep, w: 22, h: 30, radius: 8, fontSize: 12),
      ],
    ),
  );
}

Widget _artFeihua(GameIdentity id) {
  return SizedBox(
    width: 76,
    height: 46,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _petal(id, id.soft),
        const SizedBox(width: 4),
        _petal(id, _lite(id)),
        const SizedBox(width: 4),
        _petal(id, id.primary),
      ],
    ),
  );
}

Widget _petal(GameIdentity id, Color color) {
  return Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
    ),
  );
}

/// 咕噜果冻小罐：透明罐 + 果冻波浪 + 小星星。
/// 罐身用身份纸白，果冻用主色，糖用第二色。
Widget _artLiquid(GameIdentity id) => SizedBox(
  width: 58,
  height: 48,
  child: CustomPaint(painter: _LiquidJarPainter(id)),
);

class _LiquidJarPainter extends CustomPainter {
  _LiquidJarPainter(this.id);

  final GameIdentity id;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = const Rect.fromLTWH(10, 6, 38, 38);
    final jar = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(jar, Paint()..color = GameIdentity.paper);

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
    canvas.drawPath(wave, Paint()..color = Color.lerp(id.soft, id.primary, .5)!);

    final jelly = id.primary;
    canvas.drawCircle(Offset(rect.right - 13, rect.bottom - 16), 10.5, Paint()..color = jelly);
    canvas.drawCircle(
      Offset(rect.right - 13, rect.bottom - 16),
      10.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = id.deep,
    );
    canvas.drawCircle(Offset(rect.right - 16.5, rect.bottom - 19), 1.6, Paint()..color = id.ink);
    canvas.drawCircle(Offset(rect.right - 9.5, rect.bottom - 19), 1.6, Paint()..color = id.ink);

    final candy = id.secondary ?? id.deep;
    final yellow = Offset(rect.left + 15, rect.bottom - 22);
    canvas.drawCircle(yellow, 7, Paint()..color = candy);
    canvas.drawCircle(
      yellow,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = id.deep,
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
    canvas.drawPath(star, Paint()..color = id.soft);
    canvas.restore();

    canvas.drawRRect(
      jar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = id.deep,
    );
    canvas.drawLine(
      Offset(rect.left - 3, rect.top + 1),
      Offset(rect.left + 8, rect.top - 3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = id.deep,
    );
    canvas.drawLine(
      Offset(rect.right + 3, rect.top + 1),
      Offset(rect.right - 8, rect.top - 3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = id.deep,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidJarPainter oldDelegate) => oldDelegate.id != id;
}

/// 青玉水墨小卡：铃渡的沉浸式深色水面是这款游戏的品牌资产，
/// 保持自绘深潭 + 金/珊瑚色，不并入全局 token。
Widget _artKnockwater(GameIdentity id) => SizedBox(
  width: 62,
  height: 48,
  child: CustomPaint(painter: _KnockwaterArtPainter(id)),
);

class _KnockwaterArtPainter extends CustomPainter {
  _KnockwaterArtPainter(this.id);

  final GameIdentity id;

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
        ..color = id.deep,
    );
    canvas.drawCircle(
      Offset(bell.dx, bell.dy + 3.4),
      0.9,
      Paint()..color = id.deep,
    );
  }

  @override
  bool shouldRepaint(covariant _KnockwaterArtPainter oldDelegate) => oldDelegate.id != id;
}
