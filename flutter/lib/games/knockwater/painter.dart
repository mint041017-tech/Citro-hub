import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'engine.dart';

const Color kGold = Color(0xFFE3B878);
const Color kGlow = Color(0xFFA9F5E6);
const Color kCoral = Color(0xFFFF9E7A);

final Map<int, Path> _pondPathCache = <int, Path>{};

Path _pondPathFor(int variant) =>
    _pondPathCache.putIfAbsent(variant % 6, () => _buildPondPath(variant));

Path _buildPondPath(int variant) {
  final p = Path();
  const n = 180;
  for (var i = 0; i <= n; i++) {
    final a = i / n * kTau;
    final lim = pondLimitAtAngle(a, variant);
    final x = kPondCx + math.cos(a) * kPondRx * lim;
    final y = kPondCy + math.sin(a) * kPondRy * lim;
    if (i == 0) {
      p.moveTo(x, y);
    } else {
      p.lineTo(x, y);
    }
  }
  p.close();
  return p;
}

const List<List<Color>> _waterPalettes = <List<Color>>[
  <Color>[Color(0xFF1D5D56), Color(0xFF123F40), Color(0xFF082226)],
  <Color>[Color(0xFF1B5A5D), Color(0xFF123C46), Color(0xFF071F24)],
  <Color>[Color(0xFF205A4F), Color(0xFF143F38), Color(0xFF08211B)],
  <Color>[Color(0xFF1C5667), Color(0xFF123C4A), Color(0xFF071D26)],
  <Color>[Color(0xFF245B55), Color(0xFF143F3D), Color(0xFF08201F)],
  <Color>[Color(0xFF1D5260), Color(0xFF123B45), Color(0xFF071C22)],
];

class BackdropPainter extends CustomPainter {
  const BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sky = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, size.height * 0.18),
        size.width * 1.5,
        const <Color>[Color(0xFF0C2326), Color(0xFF071619), Color(0xFF030A0C)],
        const <double>[0, 0.48, 1],
      );
    canvas.drawRect(rect, sky);

    final glow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, size.height * 0.34),
        size.width * 0.9,
        <Color>[
          const Color(0xFF2E7A6E).withValues(alpha: 0.16),
          const Color(0x002E7A6E),
        ],
        const <double>[0, 1],
      );
    canvas.drawRect(rect, glow);

    final rnd = math.Random(19);
    for (var i = 0; i < 260; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.4 + rnd.nextDouble() * 1.1;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = Colors.white.withValues(
            alpha: 0.012 + rnd.nextDouble() * 0.02,
          ),
      );
    }

    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        size.longestSide * 0.72,
        const <Color>[Color(0x00000000), Color(0x99000000)],
        const <double>[0.48, 1],
      );
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant BackdropPainter oldDelegate) => false;
}

class PondPainter extends CustomPainter {
  final Engine engine;
  final Rect playRect;
  final bool showGame;

  /// 测试专用：水面实际 paint 次数（仅在 debug / 测试中累加）。
  static int debugPaintCount = 0;

  PondPainter({
    required this.engine,
    required this.playRect,
    required this.showGame,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    assert(() {
      debugPaintCount++;
      return true;
    }());
    final scale = math.min(
      playRect.width / (kCols + 0.9),
      playRect.height / (kRows + 0.9),
    );
    final ox = playRect.center.dx - kCols * scale / 2;
    final oy = playRect.center.dy - kRows * scale / 2;

    canvas.save();
    final shake = engine.shake;
    if (shake > 0.001) {
      canvas.translate(
        math.sin(engine.time * 83) * shake * 0.055 * scale,
        math.cos(engine.time * 71) * shake * 0.045 * scale,
      );
    }
    if (engine.charging) {
      final pc = playRect.center;
      final zoom = 1 + 0.014 * engine.chargeRatio;
      canvas.translate(pc.dx, pc.dy);
      canvas.scale(zoom);
      canvas.translate(-pc.dx, -pc.dy);
    }
    canvas.translate(ox, oy);
    canvas.scale(scale);

    _drawPond(canvas);
    if (!showGame) {
      _drawTitleRipples(canvas);
      canvas.restore();
      return;
    }
    _drawCurrents(canvas);
    _drawVortices(canvas);
    _drawAmbientMotes(canvas);
    _drawBay(canvas);
    _drawRocks(canvas);
    // Chapter 7 seals the maze with boundary reeds whose centers can sit just
    // outside the visible water line; clip the static reed layer so the pond
    // edge stays clean without changing collision or wave rules.
    canvas.save();
    canvas.clipPath(_pondPathFor(engine.level.pondVariant));
    _drawReeds(canvas);
    canvas.restore();
    _drawWaves(canvas);
    _drawPetals(canvas);
    _drawSparks(canvas);
    _drawBell(canvas);
    if (engine.charging) _drawChargePreview(canvas);
    _drawWinBloom(canvas);
    _drawFinger(canvas);

    canvas.restore();
  }

  void _drawPond(Canvas c) {
    final pondPath = _pondPathFor(engine.level.pondVariant);
    final palette = _waterPalettes[engine.level.pondVariant % 6];
    c.save();
    c.translate(kPondCx, kPondCy);
    c.scale(1.058);
    c.translate(-kPondCx, -kPondCy);
    final shore = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(0, 20),
        const <Color>[Color(0xFF24332C), Color(0xFF0C1917), Color(0xFF17251F)],
        const <double>[0, 0.55, 1],
      );
    c.drawPath(pondPath, shore);
    c.restore();

    c.save();
    c.clipPath(pondPath);
    final water = Paint()
      ..shader = ui.Gradient.radial(
        const Offset(6, 9.2),
        9.8,
        palette,
        const <double>[0, 0.52, 1],
      );
    c.drawRect(const Rect.fromLTWH(-2, -2, 16, 24), water);

    final caustic = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.055
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFBDF7E9).withValues(alpha: 0.05);
    for (var k = 0; k < 7; k++) {
      final baseY = 1.6 + k * 2.6;
      final path = Path();
      for (var i = 0; i <= 24; i++) {
        final x = -1 + i * (14 / 24);
        final y =
            baseY +
            math.sin(x * 0.85 + engine.time * 0.2 + k * 1.7) * 0.4 +
            math.sin(x * 0.32 - engine.time * 0.12 + k) * 0.5;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      c.drawPath(path, caustic);
    }

    final deep = Paint()
      ..shader = ui.Gradient.radial(
        const Offset(6, 8.6),
        4.6,
        <Color>[
          const Color(0xFF54A995).withValues(alpha: 0.15),
          const Color(0x0054A995),
        ],
        const <double>[0, 1],
      );
    c.drawCircle(const Offset(6, 8.6), 4.6, deep);
    c.restore();

    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.24
      ..color = const Color(0xFF5FD6C0).withValues(alpha: 0.07);
    c.drawPath(pondPath, outer);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.035
      ..color = const Color(0xFF9AEBDC).withValues(alpha: 0.34);
    c.drawPath(pondPath, edge);
  }

  void _drawTitleRipples(Canvas c) {
    for (var i = 0; i < 3; i++) {
      final t = (engine.time * 0.11 + i / 3) % 1.0;
      final r = 1.2 + t * 4.6;
      final a = (1 - t) * 0.13;
      c.drawCircle(
        const Offset(6, 10.4),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.03
          ..color = const Color(0xFFBDF7E9).withValues(alpha: a),
      );
    }
  }

  double _hash(int n) {
    final v = math.sin(n * 12.9898 + 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  void _drawAmbientMotes(Canvas c) {
    final t = engine.time;
    for (var i = 0; i < 30; i++) {
      final h1 = _hash(i * 3 + 1);
      final h2 = _hash(i * 7 + 5);
      final h3 = _hash(i * 11 + 9);
      final x = 0.8 + h1 * 10.4 + math.sin(t * 0.035 + i) * 0.32;
      final y = 1.6 + h2 * 16.8 + math.cos(t * 0.028 + i * 1.7) * 0.26;
      if (!inWater(x, y, 0.03, engine.level.pondVariant)) continue;
      final a = 0.03 + h3 * 0.065;
      c.drawCircle(
        Offset(x, y),
        0.016 + h3 * 0.026,
        Paint()..color = const Color(0xFFCFF7EE).withValues(alpha: a),
      );
    }
  }

  void _drawBay(Canvas c) {
    final b = engine.bay;
    final done =
        engine.petals.isNotEmpty && engine.petalsInBay == engine.petals.length;
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(b.x, b.y),
        b.r * 2.2,
        <Color>[
          const Color(0xFFFFD39A).withValues(alpha: done ? 0.3 : 0.14),
          const Color(0x00FFD39A),
        ],
        const <double>[0, 1],
      );
    c.drawCircle(Offset(b.x, b.y), b.r * 2.2, glow);
    c.drawCircle(
      Offset(b.x, b.y),
      b.r,
      Paint()
        ..color = const Color(0xFFF0C98C).withValues(alpha: done ? 0.1 : 0.045),
    );

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.045
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF2C98E).withValues(alpha: done ? 0.75 : 0.4);
    _dashCircle(c, Offset(b.x, b.y), b.r, 32, 0.55, engine.time * 0.05, ring);
    ring.color = const Color(0xFFF2C98E).withValues(alpha: 0.15);
    _dashCircle(
      c,
      Offset(b.x, b.y),
      b.r * 0.68,
      18,
      0.34,
      -engine.time * 0.09,
      ring,
    );

    for (var i = 0; i < 5; i++) {
      final a = engine.time * 0.22 + i * kTau / 5;
      final rr = b.r * (0.52 + 0.32 * math.sin(engine.time * 0.5 + i * 2));
      c.drawCircle(
        Offset(b.x + math.cos(a) * rr, b.y + math.sin(a) * rr),
        0.032,
        Paint()..color = const Color(0xFFFFE0B0).withValues(alpha: 0.38),
      );
    }

    final flash = engine.bayFlash;
    if (flash > 0.01) {
      final rr = b.r + (1 - flash) * 2.6;
      c.drawCircle(
        Offset(b.x, b.y),
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.055
          ..color = const Color(0xFFFFD9A0)
              .withValues(alpha: 0.5 * flash.clamp(0.0, 1.0)),
      );
      c.drawCircle(
        Offset(b.x, b.y),
        b.r * 1.5,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(b.x, b.y),
            b.r * 1.5,
            <Color>[
              const Color(0xFFFFD9A0).withValues(alpha: 0.22 * flash),
              const Color(0x00FFD9A0),
            ],
            const <double>[0, 1],
          ),
      );
    }
  }

  void _drawRocks(Canvas c) {
    for (var i = 0; i < engine.rocks.length; i++) {
      final r = engine.rocks[i];
      final rnd = math.Random(1009 + engine.levelIndex * 17 + i * 37);
      const n = 9;
      final path = Path();
      for (var k = 0; k < n; k++) {
        final a = k / n * kTau;
        final rr = r.r * (0.86 + rnd.nextDouble() * 0.24);
        final x = r.x + math.cos(a) * rr;
        final y = r.y + math.sin(a) * rr;
        if (k == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();

      c.drawOval(
        Rect.fromCenter(
          center: Offset(r.x + 0.1, r.y + 0.16),
          width: r.r * 2.3,
          height: r.r * 1.45,
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.28),
      );

      final fill = Paint()
        ..shader = ui.Gradient.linear(
          Offset(r.x - r.r, r.y - r.r),
          Offset(r.x + r.r, r.y + r.r),
          const <Color>[Color(0xFF2B403A), Color(0xFF0A1514)],
          const <double>[0, 1],
        );
      c.drawPath(path, fill);

      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.028
        ..color = const Color(0xFF5F7F73).withValues(alpha: 0.55);
      c.drawPath(path, rim);

      c.drawCircle(
        Offset(r.x - r.r * 0.28, r.y - r.r * 0.22),
        r.r * 0.2,
        Paint()..color = const Color(0xFF6C8760).withValues(alpha: 0.36),
      );
      c.drawCircle(
        Offset(r.x + r.r * 0.26, r.y + r.r * 0.1),
        r.r * 0.12,
        Paint()..color = const Color(0xFF6C8760).withValues(alpha: 0.26),
      );
    }
  }

  void _drawReeds(Canvas c) {
    for (var i = 0; i < engine.reeds.length; i++) {
      final rd = engine.reeds[i];
      final rnd = math.Random(411 + i * 29);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.038
        ..color = const Color(0xFF8C9E6C).withValues(alpha: 0.55);
      for (var k = 0; k < 8; k++) {
        final baseA = -math.pi / 2 + (k - 3.5) * 0.17 + rnd.nextDouble() * 0.08;
        final len = rd.r * (1.5 + rnd.nextDouble() * 0.9);
        final sway = math.sin(engine.time * 0.85 + k * 0.8 + i) * 0.13;
        final tipX = rd.x + math.cos(baseA + sway) * len * 0.62;
        final tipY = rd.y + math.sin(baseA) * len;
        final ctrlX = rd.x + math.cos(baseA) * len * 0.35 + sway * 0.6;
        final ctrlY = rd.y - len * 0.5;
        final p = Path()
          ..moveTo(rd.x + (k - 3.5) * 0.045, rd.y + 0.12)
          ..quadraticBezierTo(ctrlX, ctrlY, tipX, tipY);
        c.drawPath(p, paint);
      }
      c.drawCircle(
        Offset(rd.x, rd.y + 0.14),
        rd.r * 0.5,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(rd.x, rd.y + 0.14),
            rd.r * 0.5,
            <Color>[
              const Color(0xFF3D5B45).withValues(alpha: 0.4),
              const Color(0x003D5B45),
            ],
            const <double>[0, 1],
          ),
      );
    }
  }

  void _drawCurrents(Canvas c) {
    for (var ci = 0; ci < engine.currents.length; ci++) {
      final cur = engine.currents[ci];
      c.drawCircle(
        Offset(cur.x, cur.y),
        cur.r,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cur.x, cur.y),
            cur.r,
            <Color>[
              const Color(0xFF9BE3D3).withValues(alpha: 0.045),
              const Color(0x009BE3D3),
            ],
            const <double>[0, 1],
          ),
      );
      final rnd = math.Random(907 + ci * 61);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.04
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFB6E8DC).withValues(alpha: 0.26);
      for (var k = 0; k < 14; k++) {
        final yOff = (rnd.nextDouble() * 2 - 1) * cur.r * 0.82;
        final phase = rnd.nextDouble();
        final span = cur.r * 2.05;
        final xOff = ((engine.time * 0.32 + phase) % 1.0) * span - cur.r;
        final x = cur.x + xOff;
        final y = cur.y + yOff;
        final dx = x - cur.x;
        final dy = y - cur.y;
        if (dx * dx + dy * dy > cur.r * cur.r * 0.95) continue;
        c.drawLine(Offset(x - 0.3, y), Offset(x + 0.22, y), paint);
      }
      for (var k = 0; k < 5; k++) {
        final a = engine.time * 0.18 + k * 1.7 + ci;
        final rr = cur.r * (0.3 + 0.55 * ((k * 0.27 + ci * 0.4) % 1));
        final x = cur.x + math.cos(a) * rr;
        final y = cur.y + math.sin(a * 1.3) * rr * 0.7;
        c.drawCircle(
          Offset(x, y),
          0.026,
          Paint()..color = const Color(0xFFCFF7EE).withValues(alpha: 0.3),
        );
      }
    }
  }

  void _drawVortices(Canvas c) {
    for (var vi = 0; vi < engine.vortices.length; vi++) {
      final v = engine.vortices[vi];
      c.drawCircle(
        Offset(v.x, v.y),
        v.r,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(v.x, v.y),
            v.r,
            <Color>[
              const Color(0xFF9AD9F0).withValues(alpha: 0.06),
              const Color(0x009AD9F0),
            ],
            const <double>[0, 1],
          ),
      );
      c.save();
      c.translate(v.x, v.y);
      final dir = v.clockwise ? 1.0 : -1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.045
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFB9EAF2).withValues(alpha: 0.36);
      for (var k = 0; k < 3; k++) {
        final rr = v.r * (0.35 + 0.22 * k);
        final start = dir * engine.time * (0.45 + 0.1 * k) + k * 2.1 + vi;
        c.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: rr),
          start,
          1.55,
          false,
          paint,
        );
      }
      c.restore();
    }
  }

  void _drawWaves(Canvas c) {
    for (final w in engine.waves) {
      final denom = w.maxR / w.speed;
      final life = (1 - w.age / denom).clamp(0.0, 1.0).toDouble();
      final alpha = ((w.heavy ? 0.55 : 0.4) * (0.25 + 0.75 * life))
          .clamp(0.0, 1.0)
          .toDouble();
      if (alpha <= 0.005) continue;

      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = w.heavy ? 0.19 : 0.12
        ..color = const Color(0xFF9DF2E0).withValues(alpha: alpha * 0.13);
      final core = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = w.heavy ? 0.055 : 0.042
        ..color = const Color(0xFFD2FFF6).withValues(alpha: alpha);
      final warm = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.026
        ..color = const Color(0xFFFFE3B0).withValues(alpha: alpha * 0.24);

      Path? run;
      var prevAlive = false;
      void flush() {
        if (run != null) {
          c.drawPath(run!, glow);
          c.drawPath(run!, core);
          if (w.heavy) c.drawPath(run!, warm);
          run = null;
        }
      }

      for (final ray in w.rays) {
        if (ray.alive) {
          if (!prevAlive) {
            run = Path()..moveTo(ray.x, ray.y);
          } else {
            run!.lineTo(ray.x, ray.y);
          }
          prevAlive = true;
        } else {
          flush();
          prevAlive = false;
        }
      }
      flush();
    }
  }

  void _drawPetals(Canvas c) {
    for (final p in engine.petals) {
      final bob = math.sin(engine.time * 1.5 + p.seed) * 0.028;
      final base = p.stranded
          ? const Color(0xFF8C7C6B)
          : (p.w >= 1.6
                ? const Color(0xFFF2706D)
                : (p.w <= 0.9
                      ? const Color(0xFFFFC2A1)
                      : const Color(0xFFFF9E7A)));
      final light = p.stranded
          ? const Color(0xFFA39484)
          : (p.w >= 1.6 ? const Color(0xFFFFA09A) : const Color(0xFFFFD9BC));

      if (!p.stranded && p.speed > 0.8) {
        final fade = math.min(1.0, p.speed / 3.5);
        for (var i = 1; i <= 3; i++) {
          final tx = p.x - p.vx * 0.05 * i;
          final ty = p.y - p.vy * 0.05 * i;
          c.drawCircle(
            Offset(tx, ty + bob),
            p.r * (1 - 0.16 * i),
            Paint()..color = base.withValues(alpha: 0.1 * fade * (1 - i / 4)),
          );
        }
      }

      c.drawOval(
        Rect.fromCenter(
          center: Offset(p.x + 0.1, p.y + 0.14 + bob),
          width: p.r * 2.15,
          height: p.r * 1.3,
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.22),
      );

      if (!p.stranded && (p.glow > 0 || p.inBay)) {
        final a = math.max<double>(
          p.glow * 0.22,
          p.inBay ? (p.settled ? 0.2 : 0.12) : 0.0,
        );
        c.drawCircle(
          Offset(p.x, p.y + bob),
          p.r * 2.4,
          Paint()
            ..shader = ui.Gradient.radial(
              Offset(p.x, p.y + bob),
              p.r * 2.4,
              <Color>[
                const Color(0xFFFFC98E).withValues(alpha: a),
                const Color(0x00FFC98E),
              ],
              const <double>[0, 1],
            ),
        );
      }

      c.save();
      c.translate(p.x, p.y + bob);
      c.rotate(p.spin);
      final shader = ui.Gradient.radial(
        Offset.zero,
        p.r * 1.1,
        <Color>[light, base],
        const <double>[0, 1],
      );
      final fill = Paint()..shader = shader;
      final vein = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.018
        ..color = Colors.white.withValues(alpha: p.stranded ? 0.12 : 0.32);
      for (var i = 0; i < 5; i++) {
        c.save();
        c.rotate(i * kTau / 5);
        final path = Path()
          ..moveTo(0, 0)
          ..cubicTo(
            p.r * 0.55,
            -p.r * 0.5,
            p.r * 1.0,
            -p.r * 0.24,
            p.r * 1.02,
            0,
          )
          ..cubicTo(p.r * 1.0, p.r * 0.24, p.r * 0.55, p.r * 0.5, 0, 0);
        c.drawPath(path, fill);
        c.drawLine(Offset(p.r * 0.16, 0), Offset(p.r * 0.86, 0), vein);
        c.restore();
      }
      c.drawCircle(
        Offset.zero,
        p.r * 0.17,
        Paint()
          ..color = p.stranded
              ? const Color(0xFF6E6357)
              : const Color(0xFFFFE5B8),
      );
      if (p.settled) {
        c.drawCircle(
          Offset.zero,
          p.r * 1.42,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.03
            ..color = const Color(0xFFFFD79A).withValues(alpha: 0.6),
        );
      }
      c.restore();
    }
  }

  void _drawSparks(Canvas c) {
    for (final s in engine.sparks) {
      final a = (s.life / s.maxLife).clamp(0.0, 1.0).toDouble();
      final color = switch (s.kind) {
        SparkKind.rock => const Color(0xFF9FE0D2),
        SparkKind.petal => const Color(0xFFFFB58C),
        SparkKind.water => const Color(0xFFBFF7EA),
        SparkKind.reed => const Color(0xFFA9C27E),
        SparkKind.echo => const Color(0xFF9ED8FF),
      };
      c.drawCircle(
        Offset(s.x, s.y),
        0.025 + a * 0.03,
        Paint()..color = color.withValues(alpha: a * 0.7),
      );
    }
  }

  void _drawBell(Canvas c) {
    final e = engine;
    final t = e.time;
    final charging = e.charging;
    final charge = e.chargeRatio;

    if (charging) {
      final pulse = 0.5 + 0.5 * math.sin(t * 9);
      c.drawCircle(
        Offset(e.bx, e.by),
        1.15 + pulse * 0.12,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(e.bx, e.by),
            1.3,
            <Color>[
              const Color(0xFFFFD08A).withValues(alpha: 0.12 + charge * 0.14),
              const Color(0x00FFD08A),
            ],
            const <double>[0, 1],
          ),
      );
    }

    c.drawCircle(
      Offset(e.bx, e.by + 0.02),
      0.95,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(e.bx, e.by + 0.02),
          0.95,
          <Color>[
            const Color(0xFFE8C58A).withValues(alpha: 0.1),
            const Color(0x00E8C58A),
          ],
          const <double>[0, 1],
        ),
    );
    c.drawOval(
      Rect.fromCenter(
        center: Offset(e.bx + 0.08, e.by + 0.24),
        width: 0.78,
        height: 0.3,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );

    final idle = (t * 0.3) % 1.0;
    c.drawCircle(
      Offset(e.bx, e.by),
      0.34 + idle * 0.52,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.018
        ..color = const Color(0xFFBFF7EA).withValues(alpha: 0.1 * (1 - idle)),
    );
    if (e.moving) {
      final dx = e.toX - e.fromX;
      final dy = e.toY - e.fromY;
      final len = math.max(0.001, math.sqrt(dx * dx + dy * dy));
      for (var i = 1; i <= 2; i++) {
        c.drawCircle(
          Offset(e.bx - dx / len * 0.22 * i, e.by - dy / len * 0.22 * i),
          0.13 + 0.04 * i,
          Paint()
            ..color = const Color(0xFFBFF7EA)
                .withValues(alpha: 0.07 * (1 - i / 3)),
        );
      }
    }

    final squash = e.moving ? 1 - 0.09 * math.sin(math.pi * e.moveT) : 1.0;
    final bob = e.moving ? 0.0 : math.sin(t * 2.1) * 0.018;

    c.save();
    c.translate(e.bx, e.by + bob);
    c.scale(1 / math.sqrt(squash), squash);

    final body = Path()
      ..moveTo(-0.2, -0.12)
      ..cubicTo(-0.25, -0.37, -0.13, -0.45, 0, -0.45)
      ..cubicTo(0.13, -0.45, 0.25, -0.37, 0.2, -0.12)
      ..lineTo(0.27, 0.13)
      ..cubicTo(0.13, 0.23, -0.13, 0.23, -0.27, 0.13)
      ..close();

    final gold = ui.Gradient.linear(
      const Offset(-0.28, -0.45),
      const Offset(0.3, 0.25),
      <Color>[
        const Color(0xFFFFE4B4),
        const Color(0xFFD9A24A),
        const Color(0xFF8A5E28),
        const Color(0xFFC99550),
      ],
      const <double>[0, 0.38, 0.78, 1],
    );
    c.drawPath(body, Paint()..shader = gold);

    c.drawArc(
      Rect.fromCenter(center: Offset.zero, width: 0.57, height: 0.32),
      0.28,
      math.pi - 0.56,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.038
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFF0CC).withValues(alpha: 0.55),
    );

    c.drawOval(
      Rect.fromCenter(center: const Offset(0, 0.13), width: 0.55, height: 0.18),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.03
        ..color = const Color(0xFF6E4A1D).withValues(alpha: 0.7),
    );

    c.drawArc(
      Rect.fromCenter(
        center: const Offset(0, -0.53),
        width: 0.16,
        height: 0.18,
      ),
      0,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.035
        ..color = const Color(0xFFD9A24A).withValues(alpha: 0.9),
    );

    c.drawCircle(
      const Offset(0, 0.31),
      0.055,
      Paint()..color = const Color(0xFF7A5424),
    );
    c.restore();

    if (charging) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.04
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFD79A)
            .withValues(alpha: 0.35 + charge * 0.4);
      _dashCircle(
        c,
        Offset(e.bx, e.by),
        0.62 + charge * 0.22,
        18,
        0.5,
        -t * 0.6,
        ring,
      );
    }
  }

  void _drawChargePreview(Canvas c) {
    final e = engine;
    final p = e.chargeRatio;
    final r = e.previewRadius;
    c.save();
    c.clipPath(_pondPathFor(engine.level.pondVariant));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.045
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD79A).withValues(alpha: 0.14 + p * 0.2);
    _dashCircle(c, Offset(e.bx, e.by), r, 44, 0.42, e.time * 0.15, ring);

    if (p >= 0.18) {
      for (final petal in e.petals) {
        if (petal.stranded) continue;
        final dx = petal.x - e.bx;
        final dy = petal.y - e.by;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d > r || d < 0.001) continue;
        final nx = dx / d;
        final ny = dy / d;
        final x0 = petal.x + nx * (petal.r + 0.2);
        final y0 = petal.y + ny * (petal.r + 0.2);
        const len = 0.55;
        final x1 = petal.x + nx * (petal.r + 0.2 + len);
        final y1 = petal.y + ny * (petal.r + 0.2 + len);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.045
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFFD79A).withValues(alpha: 0.42 + p * 0.3);
        c.drawLine(Offset(x0, y0), Offset(x1, y1), paint);
        c.drawLine(
          Offset(x0, y0),
          Offset(x0 + (0.17 * -ny + 0.11 * nx), y0 + (0.17 * nx + 0.11 * ny)),
          paint,
        );
        c.drawLine(
          Offset(x0, y0),
          Offset(x0 + (0.17 * ny + 0.11 * nx), y0 + (-0.17 * nx + 0.11 * ny)),
          paint,
        );
      }
    }
    c.restore();
  }

  void _drawWinBloom(Canvas c) {
    final e = engine;
    if (e.status != GameStatus.won || e.wonAt < 0) return;
    final t = (e.time - e.wonAt).clamp(0.0, 3.5).toDouble();
    for (var i = 0; i < 3; i++) {
      final r = e.bay.r + t * 1.25 + i * 0.38;
      final a = (1 - t / 3.5) * (0.34 - i * 0.07);
      c.drawCircle(
        Offset(e.bay.x, e.bay.y),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.045
          ..color = const Color(0xFFFFD9A0)
              .withValues(alpha: a.clamp(0.0, 1.0).toDouble()),
      );
    }
    c.drawCircle(
      Offset(e.bay.x, e.bay.y),
      e.bay.r * 1.5,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(e.bay.x, e.bay.y),
          e.bay.r * 1.5,
          <Color>[
            const Color(0xFFFFE0AC).withValues(alpha: 0.16 * (1 - t / 4)),
            const Color(0x00FFE0AC),
          ],
          const <double>[0, 1],
        ),
    );
  }

  void _drawFinger(Canvas c) {
    final e = engine;
    if (e.levelIndex != 0 ||
        e.steps != 0 ||
        e.charging ||
        e.status != GameStatus.playing) {
      return;
    }
    final t = e.time;
    final pulse = 0.5 + 0.5 * math.sin(t * 2.2);
    c.drawCircle(
      Offset(e.bx, e.by),
      0.58 + pulse * 0.12,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.028
        ..color = const Color(0xFFFFD79A).withValues(alpha: 0.26),
    );
    c.drawCircle(
      Offset(e.bx, e.by),
      0.9 + pulse * 0.18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.016
        ..color = const Color(0xFFFFD79A).withValues(alpha: 0.1),
    );

    final a = Offset(e.bx + 0.7, e.by - 0.55);
    final b = Offset(e.bx + 1.85, e.by - 1.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.035
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD79A).withValues(alpha: 0.3);
    for (var i = 0; i < 6; i++) {
      final t0 = i / 6;
      final t1 = t0 + 0.06;
      c.drawLine(Offset.lerp(a, b, t0)!, Offset.lerp(a, b, t1)!, paint);
    }
    final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
    c.drawLine(
      b,
      b - Offset(math.cos(ang - 0.5), math.sin(ang - 0.5)) * 0.3,
      paint,
    );
    c.drawLine(
      b,
      b - Offset(math.cos(ang + 0.5), math.sin(ang + 0.5)) * 0.3,
      paint,
    );
    final p = (t * 0.55) % 1.0;
    c.drawCircle(
      Offset.lerp(a, b, p)!,
      0.06,
      Paint()..color = const Color(0xFFFFD79A).withValues(alpha: 0.5),
    );
  }

  void _dashCircle(
    Canvas c,
    Offset center,
    double r,
    int n,
    double duty,
    double rotation,
    Paint paint,
  ) {
    final rect = Rect.fromCircle(center: center, radius: r);
    final seg = kTau / n;
    for (var i = 0; i < n; i++) {
      c.drawArc(rect, rotation + i * seg, seg * duty, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PondPainter oldDelegate) {
    return oldDelegate.engine != engine ||
        oldDelegate.playRect != playRect ||
        oldDelegate.showGame != showGame;
  }
}
