import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../games/game_identity.dart';

/// 游戏卡上的图形徽标。
///
/// 每个游戏一个固定的矢量图形，颜色取自 [GameIdentity]，不读主题 accent。
/// 卡片在 3 列手机栅格、7 列桌面栅格和首页会玩卡之间尺寸差异很大，
/// 矢量图形在任何尺寸下都保持清晰，也不必维护一整套位图资源。
class GameEmblem extends StatelessWidget {
  const GameEmblem({
    super.key,
    required this.identity,
    this.size = 64,
    this.paper = const Color(0xFFFFFDF8),
    this.detail = true,
  });

  final GameIdentity identity;
  final double size;

  /// 图形里需要「纸白」的部分（卡牌背面、果冻瓶身）用这个颜色。
  final Color paper;

  /// false = 简化档：省略眼睛、刻度、铃舌这类 1~2px 的细节。
  /// 顶栏徽标只有 26pt，细节只会糊成一团。
  final bool detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _EmblemPainter(identity, paper, detail),
        ),
      ),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  _EmblemPainter(this.identity, this.paper, this.detail);

  final GameIdentity identity;
  final Color paper;
  final bool detail;

  static const int _ink = 0xFF2A211C;

  @override
  void paint(Canvas canvas, Size size) {
    // 所有图形都在 64×64 的设计栅格里画，再整体缩放到卡片尺寸。
    final u = size.width / 64;
    canvas.save();
    canvas.scale(u, u);
    switch (identity.key) {
      case 'g2048':
        _tiles2048(canvas);
      case 'gmem':
        _memoryCards(canvas);
      case 'gsudoku':
        _grid(canvas, _sudokuMask);
      case 'gnono':
        _grid(canvas, _nonoMask);
      case 'gslide':
        _grid(canvas, _slideMask);
      case 'gsnake':
        _snake(canvas);
      case 'gsheep':
        _sheep(canvas);
      case 'gjump':
        _jump(canvas);
      case 'gpeng':
        _orbit(canvas);
      case 'gbrake':
        _speedo(canvas);
      case 'gidiom':
        _idiomTiles(canvas);
      case 'gfeihua':
        _petals(canvas);
      case 'gliquid':
        _jar(canvas);
      case 'gknockwater':
        _bell(canvas);
      default:
        _tiles2048(canvas);
    }
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // 基础笔
  // ---------------------------------------------------------------------------

  Paint _fill(Color color) => Paint()..color = color..isAntiAlias = true;

  Paint _line(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  RRect _rr(double x, double y, double w, double h, double r) =>
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(r),
      );

  Offset _polar(Offset center, double radius, double angle) =>
      center +
      Offset(math.cos(angle) * radius, math.sin(angle) * radius);

  // ---------------------------------------------------------------------------
  // 2048：四块数字砖，颜色从浅到深排成一条升级链
  // ---------------------------------------------------------------------------

  void _tiles2048(Canvas canvas) {
    final colors = [
      identity.soft,
      Color.lerp(identity.primary, identity.soft, 0.45)!,
      identity.primary,
      identity.deep,
    ];
    final positions = [
      (11.0, 11.0),
      (33.0, 11.0),
      (11.0, 33.0),
      (33.0, 33.0),
    ];
    for (var i = 0; i < positions.length; i++) {
      final (x, y) = positions[i];
      final tile = _rr(x, y, 20, 20, 6);
      canvas.drawRRect(tile, _fill(colors[i]));
      canvas.drawRRect(tile, _line(identity.deep.withValues(alpha: .32), 1.4));
    }
    // 右上角那块翘起一点，打破 2x2 的呆板。
    canvas.save();
    canvas.translate(43, 21);
    canvas.rotate(-.12);
    canvas.drawCircle(const Offset(0, 0), 3.2, _fill(identity.deep));
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // 记忆卡牌：一张背面、一张正面，错开叠放
  // ---------------------------------------------------------------------------

  void _memoryCards(Canvas canvas) {
    // 背面：斜纹被裁进卡面，不会甩到卡片外面。
    canvas.save();
    canvas.translate(33.5, 26.5);
    canvas.rotate(-.14);
    final back = _rr(-10.5, -14.5, 21, 29, 6);
    canvas.drawRRect(back, _fill(identity.soft));
    canvas.save();
    canvas.clipRRect(back);
    for (var i = -3; i <= 3; i++) {
      canvas.drawLine(
        Offset(i * 6.0 - 11, 17),
        Offset(i * 6.0 + 11, -17),
        _line(identity.primary.withValues(alpha: .45), 1.8),
      );
    }
    canvas.restore();
    canvas.drawRRect(
      back,
      _line(identity.deep.withValues(alpha: .45), 1.5),
    );
    canvas.restore();

    // 正面：压在上面，微微反向倾斜。
    canvas.save();
    canvas.translate(27.5, 34.5);
    canvas.rotate(.1);
    final front = _rr(-10.5, -14.5, 21, 29, 6);
    canvas.drawRRect(front, _fill(paper));
    canvas.drawRRect(front, _line(identity.deep, 1.6));
    canvas.drawCircle(const Offset(0, 0), 5.4, _fill(identity.primary));
    canvas.drawCircle(
      const Offset(0, 0),
      5.4,
      _line(identity.deep.withValues(alpha: .5), 1.2),
    );
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // 三格棋盘家族：数独 / 数织 / 数字华容道共用一个 3×3 栅格
  // ---------------------------------------------------------------------------

  static const List<(int, int)> _cellOrigin = [
    (12, 12), (26, 12), (40, 12),
    (12, 26), (26, 26), (40, 26),
    (12, 40), (26, 40), (40, 40),
  ];

  /// 每格 10×10，格间距 4；[mask] 给出这一格的填充强度 0..1，-1 表示空格。
  void _grid(Canvas canvas, List<double> mask) {
    for (var i = 0; i < _cellOrigin.length; i++) {
      final (x, y) = _cellOrigin[i];
      final cell = _rr(x.toDouble(), y.toDouble(), 10, 10, 3);
      final v = mask[i];
      if (v < 0) {
        canvas.drawRRect(cell, _fill(identity.deep.withValues(alpha: .14)));
        canvas.drawRRect(
          cell,
          _line(identity.deep.withValues(alpha: .32), 1.1),
        );
        continue;
      }
      final color = v >= 1
          ? identity.primary
          : Color.lerp(identity.soft, identity.primary, v)!;
      canvas.drawRRect(cell, _fill(color));
      canvas.drawRRect(
        cell,
        _line(identity.deep.withValues(alpha: .28), 1.0),
      );
    }
  }

  static const List<double> _sudokuMask = [
    1, .35, 0,
    .35, 1, .35,
    0, .35, 1,
  ];

  static const List<double> _nonoMask = [
    1, 0, 1,
    0, 1, 0,
    1, 0, 1,
  ];

  static const List<double> _slideMask = [
    .55, .55, .55,
    .55, 1, .55,
    .55, .55, -1,
  ];

  // ---------------------------------------------------------------------------
  // 贪吃蛇：一条圆头折线，头部点一只眼睛
  // ---------------------------------------------------------------------------

  void _snake(Canvas canvas) {
    final body = Path()
      ..moveTo(12, 44)
      ..lineTo(12, 28)
      ..lineTo(28, 28)
      ..lineTo(28, 12)
      ..lineTo(44, 12);
    canvas.drawPath(body, _line(identity.primary, 9));
    canvas.drawPath(
      body,
      _line(identity.deep.withValues(alpha: .3), 9),
    );
    // 身体分节：在折角的直线段上画短横线，不出身体轮廓。
    if (detail) {
      for (final (p, horizontal) in const [
        (Offset(12, 36), false),
        (Offset(20, 28), true),
        (Offset(28, 20), false),
        (Offset(36, 12), true),
      ]) {
        final d = horizontal ? const Offset(3.6, 0) : const Offset(0, 3.6);
        canvas.drawLine(
          p - d,
          p + d,
          _line(identity.deep.withValues(alpha: .5), 1.6),
        );
      }
    }
    canvas.drawCircle(const Offset(46, 12), 6.4, _fill(identity.primary));
    canvas.drawCircle(const Offset(46, 12), 6.4, _line(identity.deep, 1.4));
    if (detail) {
      canvas.drawCircle(const Offset(48, 10), 1.7, _fill(const Color(_ink)));
    }
  }

  // ---------------------------------------------------------------------------
  // 羊了个羊：一团羊毛 + 一张小脸
  // ---------------------------------------------------------------------------

  void _sheep(Canvas canvas) {
    for (final (dx, dy, r) in const [
      (22.0, 26.0, 8.0), (32.0, 21.0, 9.0), (42.0, 26.0, 8.0),
      (19.0, 35.0, 7.0), (45.0, 35.0, 7.0), (27.0, 40.0, 8.0),
      (38.0, 40.0, 8.0),
    ]) {
      canvas.drawCircle(Offset(dx, dy), r, _fill(identity.soft));
    }
    for (final (dx, dy, r) in const [
      (22.0, 26.0, 8.0), (32.0, 21.0, 9.0), (42.0, 26.0, 8.0),
      (19.0, 35.0, 7.0), (45.0, 35.0, 7.0), (27.0, 40.0, 8.0),
      (38.0, 40.0, 8.0),
    ]) {
      canvas.drawCircle(
        Offset(dx, dy),
        r,
        _line(identity.deep.withValues(alpha: .3), 1.2),
      );
    }
    // 脸。
    canvas.drawCircle(const Offset(32, 33), 8.5, _fill(paper));
    canvas.drawCircle(const Offset(32, 33), 8.5, _line(identity.deep, 1.5));
    canvas.drawCircle(const Offset(29, 31.5), 1.5, _fill(const Color(_ink)));
    canvas.drawCircle(const Offset(35, 31.5), 1.5, _fill(const Color(_ink)));
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(32, 35), radius: 3),
      .15 * math.pi,
      .7 * math.pi,
      false,
      _line(const Color(_ink), 1.3),
    );
  }

  // ---------------------------------------------------------------------------
  // 跳一跳：两个落点 + 一颗抛起来的球
  // ---------------------------------------------------------------------------

  void _jump(Canvas canvas) {
    // 抛物线虚线。
    final arc = Path()
      ..moveTo(18, 38)
      ..quadraticBezierTo(32, 8, 46, 22);
    for (var t = 0.0; t <= 1.0; t += .12) {
      final p = _quadratic(Offset(18, 38), Offset(32, 8), Offset(46, 22), t);
      canvas.drawCircle(p, 1.4, _fill(identity.deep.withValues(alpha: .45)));
    }
    canvas.drawPath(arc, _line(identity.deep.withValues(alpha: .0), .01));
    canvas.drawRRect(_rr(9, 38, 18, 13, 4), _fill(identity.soft));
    canvas.drawRRect(
      _rr(9, 38, 18, 13, 4),
      _line(identity.deep.withValues(alpha: .4), 1.4),
    );
    canvas.drawRRect(_rr(37, 22, 18, 13, 4), _fill(identity.primary));
    canvas.drawRRect(
      _rr(37, 22, 18, 13, 4),
      _line(identity.deep, 1.4),
    );
    canvas.drawCircle(const Offset(32, 14), 6, _fill(identity.deep));
    canvas.drawCircle(const Offset(32, 14), 6, _line(identity.deep, 1.2));
    canvas.drawCircle(const Offset(30, 12), 1.6, _fill(paper));
  }

  Offset _quadratic(Offset a, Offset b, Offset c, double t) {
    final ab = Offset.lerp(a, b, t)!;
    final bc = Offset.lerp(b, c, t)!;
    return Offset.lerp(ab, bc, t)!;
  }

  // ---------------------------------------------------------------------------
  // 淘气小球：一圈轨道 + 一颗星球
  // ---------------------------------------------------------------------------

  void _orbit(Canvas canvas) {
    final center = const Offset(32, 32);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 16),
      0,
      math.pi * 1.72,
      false,
      _line(identity.deep.withValues(alpha: .55), 4.6),
    );
    canvas.drawCircle(center, 4.2, _fill(identity.soft));
    canvas.drawCircle(
      center,
      4.2,
      _line(identity.deep.withValues(alpha: .5), 1.2),
    );
    final dot = _polar(center, 16, math.pi * 1.72);
    canvas.drawCircle(dot, 6.4, _fill(identity.primary));
    canvas.drawCircle(dot, 6.4, _line(identity.deep, 1.5));
    canvas.drawCircle(dot - const Offset(1.6, -1.6), 1.7, _fill(paper));
  }

  // ---------------------------------------------------------------------------
  // 极限刹车：速度表 + 指针
  // ---------------------------------------------------------------------------

  void _speedo(Canvas canvas) {
    final center = Offset(32, 38);
    final rect = Rect.fromCircle(center: center, radius: 19);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi * .78,
      false,
      _line(identity.primary, 5),
    );
    canvas.drawArc(
      rect,
      math.pi * 1.82,
      math.pi * .18,
      false,
      _line(const Color(0xFFB04A36), 5),
    );
    final needle = _polar(center, 12.5, -math.pi * .34);
    canvas.drawLine(center, needle, _line(const Color(_ink), 2.6));
    canvas.drawCircle(center, 2.6, _fill(const Color(_ink)));
    if (detail) {
      for (var i = 0; i < 5; i++) {
        final a = math.pi + i * math.pi / 4;
        canvas.drawCircle(_polar(center, 23, a), 1.5, _fill(identity.ink));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 成语接龙：四块竖排字牌
  // ---------------------------------------------------------------------------

  void _idiomTiles(Canvas canvas) {
    final colors = [
      identity.soft,
      identity.primary,
      identity.soft,
      identity.deep,
    ];
    for (var i = 0; i < 4; i++) {
      final x = 8.0 + i * 13;
      final tile = _rr(x, 14, 10.5, 30, 3);
      canvas.drawRRect(tile, _fill(colors[i]));
      canvas.drawRRect(
        tile,
        _line(identity.deep.withValues(alpha: .45), 1.3),
      );
      // 牌面上的「字」：一横一竖两个笔画，四张牌各不相同。
      final cx = x + 5.25;
      canvas.drawLine(
        Offset(cx - 2.6, 24),
        Offset(cx + 2.6, 24),
        _line(identity.ink, 1.5),
      );
      canvas.drawLine(
        Offset(cx, 29),
        Offset(cx, 37),
        _line(identity.ink, 1.5),
      );
      if (i == 1 || i == 3) {
        canvas.drawLine(
          Offset(cx - 2.4, 32),
          Offset(cx + 2.4, 32),
          _line(identity.ink, 1.3),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 飞花令：三片花瓣
  // ---------------------------------------------------------------------------

  void _petals(Canvas canvas) {
    final center = const Offset(32, 32);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-math.pi / 2 + i * math.pi * 2 / 3);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(9, -8, 0, -19)
        ..quadraticBezierTo(-9, -8, 0, 0)
        ..close();
      canvas.drawPath(path, _fill(identity.soft));
      canvas.drawPath(
        path,
        _line(identity.deep.withValues(alpha: .45), 1.4),
      );
      canvas.restore();
    }
    canvas.drawCircle(center, 4.6, _fill(identity.primary));
    canvas.drawCircle(
      center,
      4.6,
      _line(identity.deep.withValues(alpha: .5), 1.2),
    );
  }

  // ---------------------------------------------------------------------------
  // 咕噜果冻：一罐果冻 + 一颗糖
  // ---------------------------------------------------------------------------

  void _jar(Canvas canvas) {
    final body = _rr(18, 14, 28, 34, 9);
    canvas.drawRRect(body, _fill(paper));
    canvas.save();
    canvas.clipRRect(body);
    final wave = Path()
      ..moveTo(14, 32)
      ..quadraticBezierTo(24, 26, 32, 32)
      ..quadraticBezierTo(40, 38, 50, 32)
      ..lineTo(50, 52)
      ..lineTo(14, 52)
      ..close();
    canvas.drawPath(wave, _fill(identity.primary));
    canvas.restore();
    canvas.drawRRect(body, _line(identity.ink, 1.8));
    canvas.drawLine(
      const Offset(14, 14),
      const Offset(26, 8),
      _line(identity.ink, 1.8),
    );
    canvas.drawLine(
      const Offset(50, 14),
      const Offset(38, 8),
      _line(identity.ink, 1.8),
    );
    final candy = identity.secondary ?? identity.deep;
    canvas.drawCircle(const Offset(41, 33), 7.5, _fill(candy));
    canvas.drawCircle(
      const Offset(41, 33),
      7.5,
      _line(identity.ink.withValues(alpha: .5), 1.2),
    );
    canvas.drawCircle(const Offset(38.5, 30.5), 1.8, _fill(paper));
  }

  // ---------------------------------------------------------------------------
  // 铃渡：一枚水铃 + 两圈涟漪
  // ---------------------------------------------------------------------------

  void _bell(Canvas canvas) {
    final center = const Offset(32, 30);
    for (var i = 1; i <= 2; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 15.0 + i * 7),
        math.pi * .15,
        math.pi * .7,
        false,
        _line(identity.primary.withValues(alpha: .9 - i * .3), 1.5),
      );
    }
    final dome = Path()
      ..moveTo(20, 38)
      ..quadraticBezierTo(20, 18, 32, 18)
      ..quadraticBezierTo(44, 18, 44, 38)
      ..close();
    canvas.drawPath(dome, _fill(identity.soft));
    canvas.drawPath(dome, _line(identity.deep, 1.6));
    canvas.drawLine(
      const Offset(18, 38),
      const Offset(46, 38),
      _line(identity.deep, 2),
    );
    final clapper = identity.secondary ?? identity.primary;
    if (detail) {
      canvas.drawCircle(const Offset(32, 43), 3.4, _fill(clapper));
      canvas.drawCircle(
        const Offset(32, 43),
        3.4,
        _line(identity.deep.withValues(alpha: .5), 1.1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter old) =>
      old.identity != identity || old.paper != paper || old.detail != detail;
}
