import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ZodiacRing extends StatelessWidget {
  final int score;

  /// 外圈直径，随首页卡片尺寸缩放。
  final double size;

  const ZodiacRing({super.key, required this.score, this.size = 70});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          score.clamp(0, 100) / 100,
          c.accent,
          c.line,
        ),
        child: Center(
          child: Container(
            width: size * .83,
            height: size * .83,
            decoration: BoxDecoration(
              color: c.surface2,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$score',
                      style: context.hand(
                        size: math.max(14, size * .33),
                        color: c.ink,
                        height: 1,
                      ),
                    ),
                    TextSpan(
                      text: '分',
                      style: context.body(
                        size: math.max(7, size * .115),
                        color: c.inkSoft,
                      ),
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
