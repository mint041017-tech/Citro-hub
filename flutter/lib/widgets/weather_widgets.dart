import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WeatherGlyph extends StatelessWidget {
  final int code;
  final double size;
  final Color color;
  const WeatherGlyph({
    super.key,
    required this.code,
    this.size = 42,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _WeatherPainter(
          code,
          color,
          context.c.accentLt,
          context.c.inkSoft,
        ),
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  final int code;
  final Color color;
  final Color light;
  final Color inkSoft;
  _WeatherPainter(this.code, this.color, this.light, this.inkSoft);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * .22;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .065
      ..strokeCap = StrokeCap.round;
    if (code == 0 || code == 1) {
      p.color = color;
      canvas.drawCircle(c, r, Paint()..color = light);
      canvas.drawCircle(c, r, p);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final from = Offset(
          c.dx + math.cos(a) * r * 1.7,
          c.dy + math.sin(a) * r * 1.7,
        );
        final to = Offset(
          c.dx + math.cos(a) * r * 2.25,
          c.dy + math.sin(a) * r * 2.25,
        );
        canvas.drawLine(from, to, p);
      }
      return;
    }
    // cloud + rain/snow
    p.color = inkSoft.withAlpha(180);
    final cloudPaint = Paint()..color = light.withAlpha(230);
    final path = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(c.dx - size.width * .12, c.dy - size.width * .03),
          radius: r * 1.05,
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(c.dx + size.width * .12, c.dy - size.width * .02),
          radius: r * .9,
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(c.dx, c.dy + size.width * .06),
          radius: r * 1.15,
        ),
      );
    canvas.drawPath(path, cloudPaint);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .055
        ..color = color,
    );
    if (code >= 51) {
      p.color = color.withAlpha(210);
      for (var i = 0; i < 3; i++) {
        final x = size.width * (.28 + i * .22);
        final y = size.height * .74;
        canvas.drawLine(
          Offset(x, y),
          Offset(x - size.width * .04, y + size.height * .15),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter old) =>
      old.code != code || old.color != color;
}

class ZodiacRing extends StatelessWidget {
  final int score;
  const ZodiacRing({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: 70,
      height: 70,
      child: CustomPaint(
        painter: _RingPainter(
          score.clamp(0, 100) / 100,
          c.accent,
          c.dark ? const Color(0x2294530A) : const Color(0x2194530A),
        ),
        child: Center(
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: c.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
            child: Center(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$score',
                      style: context.display(size: 23, color: c.ink, height: 1),
                    ),
                    TextSpan(
                      text: '分',
                      style: context.body(size: 8, color: c.inkSoft),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final Color color;
  final Color track;
  _RingPainter(this.pct, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius
      ..color = track;
    canvas.drawArc(
      rect.deflate(radius / 2),
      -math.pi / 2,
      math.pi * 2,
      false,
      trackPaint,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius
      ..strokeCap = StrokeCap.butt
      ..color = color;
    canvas.drawArc(
      rect.deflate(radius / 2),
      -math.pi / 2,
      math.pi * 2 * pct,
      false,
      paint,
    );
    // inner disc
    canvas.drawCircle(
      center,
      radius - 5,
      Paint()..color = const Color(0x00000000),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.pct != pct || old.color != color;
}
