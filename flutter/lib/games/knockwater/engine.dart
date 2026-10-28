import 'dart:math' as math;

import 'levels.dart';

const double kTau = math.pi * 2;
const double kPondCx = 6.0;
const double kPondCy = 10.0;
const double kPondRx = 5.15;
const double kPondRy = 8.72;
const int kCols = 12;
const int kRows = 20;

enum GameStatus { playing, won, lost }

enum LoseReason { none, stranded, empty }

enum SparkKind { rock, petal, water, reed, echo }

class PondMetric {
  final double len;
  final double limit;
  const PondMetric(this.len, this.limit);
}

/// The shared ellipse, plus a small non-negative lobe for each map variant.
/// Variants only expand outward, so every object inside the standard pond
/// remains inside every variant.
double pondLimitAtAngle(double a, int variant) {
  final base =
      1 + 0.035 * math.sin(3 * a + 1.7) + 0.022 * math.sin(5 * a - 0.6);
  final v = variant % 6;
  var lobe = 0.0;
  switch (v) {
    case 1:
      lobe = 0.04 + 0.03 * (0.5 + 0.5 * math.sin(4 * a + 0.4));
    case 2:
      lobe = 0.05 + 0.04 * (0.5 + 0.5 * math.sin(3 * a + 2.1));
    case 3:
      lobe = 0.03 + 0.06 * (0.5 + 0.5 * math.sin(5 * a - 1.2));
    case 4:
      lobe = 0.08 + 0.04 * (0.5 + 0.5 * math.sin(6 * a + 0.8));
    case 5:
      lobe = 0.04 + 0.08 * (0.5 + 0.5 * math.sin(7 * a - 0.3));
  }
  return base + lobe;
}

PondMetric pondMetric(double x, double y, [int variant = 0]) {
  final qx = (x - kPondCx) / kPondRx;
  final qy = (y - kPondCy) / kPondRy;
  final a = math.atan2(qy, qx);
  return PondMetric(
    math.sqrt(qx * qx + qy * qy),
    pondLimitAtAngle(a, variant),
  );
}

bool inWater(double x, double y, [double margin = 0, int variant = 0]) {
  final m = pondMetric(x, y, variant);
  return m.len < m.limit - margin;
}

class Bay {
  final double x, y, r;
  Bay(this.x, this.y, this.r);
}

class Rock {
  final double x, y, r;
  Rock(this.x, this.y, this.r);
}

class Reed {
  final double x, y, r;
  Reed(this.x, this.y, this.r);
}

class EchoStone {
  final double x, y, r;
  EchoStone(this.x, this.y, this.r);
}

class Current {
  final double x, y, r, dx, dy;
  Current(this.x, this.y, this.r, this.dx, this.dy);
}

class Vortex {
  final double x, y, r, strength;
  final bool clockwise;
  Vortex(this.x, this.y, this.r, this.strength, this.clockwise);
}

class Petal {
  final int id;
  final double w;
  final double r;
  final double seed;
  double x, y, vx = 0, vy = 0;
  double spin = 0;
  double glow = 0;
  double bayTime = 0;
  bool inBay = false;
  bool stranded = false;
  bool settled = false;

  Petal({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.seed,
  }) : r = 0.34 + 0.06 * math.min(w, 2.0);

  double get speed => math.sqrt(vx * vx + vy * vy);
}

class Ray {
  double x, y, dx, dy;
  double path = 0;
  double ampMul = 1;
  int bounces = 0;
  bool alive = true;

  Ray(this.x, this.y, this.dx, this.dy);
}

class Wave {
  final List<Ray> rays;
  final double amp;
  final double maxR;
  final double speed;
  final bool heavy;
  final Set<int> hit = <int>{};
  double age = 0;
  bool dead = false;

  Wave(this.rays, this.amp, this.maxR, this.speed, this.heavy);
}

class PendingWave {
  double t;
  final double x, y, amp, maxR, speed;

  /// The echo stone that produced this wave, if any. The child wave must not
  /// immediately re-trigger its own source, otherwise every echo rings forever.
  final int sourceEcho;
  PendingWave(
    this.t,
    this.x,
    this.y,
    this.amp,
    this.maxR,
    this.speed, {
    this.sourceEcho = -1,
  });
}

class Spark {
  double x, y, vx, vy;
  final SparkKind kind;
  double life;
  final double maxLife;
  Spark(this.x, this.y, this.vx, this.vy, this.kind, this.life)
    : maxLife = life;
}

class _PetalSnap {
  final double x, y, vx, vy, spin;
  final bool stranded;
  final bool settled;
  final double bayTime;
  _PetalSnap(
    this.x,
    this.y,
    this.vx,
    this.vy,
    this.spin,
    this.stranded,
    this.settled,
    this.bayTime,
  );
}

class _Snapshot {
  final int charges;
  final int cellX, cellY;
  final int steps;
  final double bx, by;
  final double winTimer;
  final List<_PetalSnap> petals;
  _Snapshot({
    required this.charges,
    required this.cellX,
    required this.cellY,
    required this.steps,
    required this.bx,
    required this.by,
    required this.winTimer,
    required this.petals,
  });
}

class Engine {
  late LevelSpec level;
  late int levelIndex;

  late int charges;
  late int maxCharges;

  int cellX = 0;
  int cellY = 0;
  double bx = 0;
  double by = 0;

  bool moving = false;
  double moveT = 0;
  double fromX = 0, fromY = 0, toX = 0, toY = 0;

  late Bay bay;
  late List<Petal> petals;
  late List<Rock> rocks;
  late List<Reed> reeds;
  late List<EchoStone> echoes;
  late List<Current> currents;
  late List<Vortex> vortices;

  final List<Wave> waves = <Wave>[];
  final List<PendingWave> pending = <PendingWave>[];
  final List<Spark> sparks = <Spark>[];
  final List<_Snapshot> _history = <_Snapshot>[];

  GameStatus status = GameStatus.playing;
  LoseReason loseReason = LoseReason.none;

  double time = 0;
  double winTimer = 0;
  double loseTimer = 0;
  double idleTimer = 0;
  double endDelay = 0;
  double wonAt = -1;
  double shake = 0;
  double bayFlash = 0;

  void Function()? onSettle;
  void Function()? onStrand;
  void Function()? onWin;
  void Function()? onLose;

  bool charging = false;
  double chargeT = 0;
  int steps = 0;

  double _acc = 0;
  int _petalSeq = 0;
  final math.Random _rnd = math.Random(20261027);

  Engine(int index) {
    levelIndex = index.clamp(0, kLevels.length - 1).toInt();
    level = kLevels[levelIndex];
    _load();
  }

  Engine.fromLevel(this.level, {this.levelIndex = 0}) {
    _load();
  }

  void _load() {
    charges = level.charges;
    maxCharges = level.charges;
    cellX = level.bellX;
    cellY = level.bellY;
    bx = cellX + 0.5;
    by = cellY + 0.5;
    moving = false;
    moveT = 0;
    fromX = bx;
    fromY = by;
    toX = bx;
    toY = by;

    bay = Bay(level.bay.x, level.bay.y, level.bay.r);
    rocks = <Rock>[for (final r in level.rocks) Rock(r.x, r.y, r.r)];
    reeds = <Reed>[for (final r in level.reeds) Reed(r.x, r.y, r.r)];
    echoes = <EchoStone>[
      for (final e in level.echoes) EchoStone(e.x, e.y, e.r),
    ];
    currents = <Current>[
      for (final c in level.currents) Current(c.x, c.y, c.r, c.dx, c.dy),
    ];
    vortices = <Vortex>[
      for (final v in level.vortices)
        Vortex(v.x, v.y, v.r, v.strength, v.clockwise),
    ];

    _petalSeq = 0;
    petals = <Petal>[
      for (final p in level.petals)
        Petal(id: _petalSeq++, x: p.x, y: p.y, w: p.w, seed: _petalSeq * 2.399),
    ];

    waves.clear();
    pending.clear();
    sparks.clear();
    _history.clear();
    status = GameStatus.playing;
    loseReason = LoseReason.none;
    winTimer = 0;
    loseTimer = 0;
    idleTimer = 0;
    endDelay = 0;
    wonAt = -1;
    charging = false;
    chargeT = 0;
    steps = 0;
    shake = 0;
    bayFlash = 0;
    _acc = 0;
  }

  bool get canUndo => _history.isNotEmpty && !charging;

  int get petalsInBay => petals.where((p) => p.inBay && !p.stranded).length;

  bool get hasWon => status == GameStatus.won;

  double get chargeRatio => (chargeT / 0.8).clamp(0.0, 1.0).toDouble();

  double get previewRadius => 7 + 4 * chargeRatio;

  int get stars {
    final f = maxCharges == 0 ? 0.0 : charges / maxCharges;
    if (f >= 0.5) return 3;
    if (f >= 0.25) return 2;
    return 1;
  }

  bool canWalkCell(int x, int y) {
    final wx = x + 0.5;
    final wy = y + 0.5;
    if (wx < 0.4 || wx > kCols - 0.4 || wy < 0.4 || wy > kRows - 0.4) {
      return false;
    }
    if (!inWater(wx, wy, -0.055, level.pondVariant)) return false;
    for (final r in rocks) {
      if (_dist2(wx, wy, r.x, r.y) < (r.r + 0.34) * (r.r + 0.34)) return false;
    }
    for (final rd in reeds) {
      if (_dist2(wx, wy, rd.x, rd.y) < (rd.r + 0.3) * (rd.r + 0.3)) {
        return false;
      }
    }
    for (final p in petals) {
      if (_dist2(wx, wy, p.x, p.y) < (p.r + 0.38) * (p.r + 0.38)) {
        return false;
      }
    }
    return true;
  }

  bool step(int dx, int dy) {
    if (status != GameStatus.playing || charging || moving) return false;
    if (charges <= 0) return false;
    if (dx == 0 && dy == 0) return false;
    if (dx.abs() > 1 || dy.abs() > 1) return false;
    final nx = cellX + dx;
    final ny = cellY + dy;
    if (!canWalkCell(nx, ny)) return false;

    _pushHistory();
    charges--;
    fromX = bx;
    fromY = by;
    toX = nx + 0.5;
    toY = ny + 0.5;
    cellX = nx;
    cellY = ny;
    moving = true;
    moveT = 0;
    steps++;
    return true;
  }

  bool startCharge() {
    if (status != GameStatus.playing) return false;
    if (!level.allowHeavy) return false;
    if (charging || moving) return false;
    if (charges < 3) return false;
    charging = true;
    chargeT = 0;
    return true;
  }

  double? releaseCharge() {
    if (!charging) return null;
    charging = false;
    if (chargeT < 0.2 || charges < 3) {
      chargeT = 0;
      return null;
    }
    final p = chargeRatio;
    _pushHistory();
    charges -= 3;
    _emitWave(
      bx,
      by,
      amp: 1.1 + 0.9 * p,
      maxR: 7 + 4 * p,
      speed: 4.2,
      heavy: true,
    );
    shake = 1;
    chargeT = 0;
    return p;
  }

  void cancelCharge() {
    charging = false;
    chargeT = 0;
  }

  bool undo() {
    if (_history.isEmpty || charging) return false;
    final s = _history.removeLast();
    charges = s.charges;
    cellX = s.cellX;
    cellY = s.cellY;
    steps = s.steps;
    bx = s.bx;
    by = s.by;
    fromX = bx;
    fromY = by;
    toX = bx;
    toY = by;
    moving = false;
    moveT = 0;
    winTimer = s.winTimer;
    loseTimer = 0;
    idleTimer = 0;
    endDelay = 0;
    wonAt = -1;
    status = GameStatus.playing;
    loseReason = LoseReason.none;
    charging = false;
    chargeT = 0;
    waves.clear();
    pending.clear();
    sparks.clear();
    for (var i = 0; i < petals.length && i < s.petals.length; i++) {
      final a = s.petals[i];
      final p = petals[i];
      p.x = a.x;
      p.y = a.y;
      p.vx = a.vx;
      p.vy = a.vy;
      p.spin = a.spin;
      p.stranded = a.stranded;
      p.settled = a.settled;
      p.bayTime = a.bayTime;
      p.inBay = !a.stranded && _inBay(a.x, a.y);
      p.glow = 0;
    }
    return true;
  }

  void _pushHistory() {
    if (_history.length > 64) _history.removeAt(0);
    _history.add(
      _Snapshot(
        charges: charges,
        cellX: cellX,
        cellY: cellY,
        steps: steps,
        bx: bx,
        by: by,
        winTimer: winTimer,
        petals: <_PetalSnap>[
          for (final p in petals)
            _PetalSnap(
              p.x,
              p.y,
              p.vx,
              p.vy,
              p.spin,
              p.stranded,
              p.settled,
              p.bayTime,
            ),
        ],
      ),
    );
  }

  void update(double dt) {
    if (dt <= 0) return;
    _acc += math.min(dt, 0.08);
    var guard = 0;
    while (_acc >= 1 / 60 && guard++ < 6) {
      _tick(1 / 60);
      _acc -= 1 / 60;
    }
    if (guard >= 6) _acc = 0;
  }

  void advance(double seconds) {
    final n = (seconds * 60).round();
    for (var i = 0; i < n; i++) {
      _tick(1 / 60);
    }
  }

  void _tick(double dt) {
    time += dt;
    if (shake > 0) shake = math.max(0.0, shake - dt * 3.2);
    if (bayFlash > 0) bayFlash = math.max(0.0, bayFlash - dt * 1.35);
    if (charging) chargeT = math.min(0.8, chargeT + dt);
    if (status != GameStatus.playing && endDelay > 0) {
      endDelay = math.max(0.0, endDelay - dt);
    }
    _updateBell(dt);
    _updateWaves(dt);
    _updatePending(dt);
    _updatePetals(dt);
    _updateSparks(dt);
    _updateEnd(dt);
  }

  void _updateBell(double dt) {
    if (!moving) return;
    moveT += dt / 0.13;
    if (moveT >= 1) {
      moveT = 1;
      moving = false;
      bx = toX;
      by = toY;
      _emitWave(bx, by, amp: 0.45, maxR: 7.0, speed: 4.6);
      _spark(bx, by, SparkKind.water, 4);
    } else {
      final e = 1 - math.pow(1 - moveT, 3).toDouble();
      bx = fromX + (toX - fromX) * e;
      by = fromY + (toY - fromY) * e;
    }
  }

  void _emitWave(
    double x,
    double y, {
    required double amp,
    required double maxR,
    required double speed,
    bool heavy = false,
    int sourceEcho = -1,
  }) {
    const n = 72;
    final rays = <Ray>[];
    for (var i = 0; i < n; i++) {
      final a = i / n * kTau;
      rays.add(Ray(x, y, math.cos(a), math.sin(a)));
    }
    final wave = Wave(rays, amp, maxR, speed, heavy);
    if (sourceEcho >= 0) {
      // Seed the hit set so the child wave cannot hit its own echo stone on
      // the first step (the ray starts inside the stone). Other echo stones
      // may still be triggered normally.
      wave.hit.add(1000 + sourceEcho);
    }
    waves.add(wave);
    _spark(x, y, SparkKind.water, heavy ? 8 : 4);
  }

  void _updateWaves(double dt) {
    for (final w in waves) {
      w.age += dt;
      var anyAlive = false;
      for (final ray in w.rays) {
        if (!ray.alive) continue;
        var remain = w.speed * dt;
        var guard = 0;
        while (remain > 0.00001 && ray.alive && guard++ < 10) {
          final stepLen = math.min(remain, 0.15);
          remain -= stepLen;
          final nx = ray.x + ray.dx * stepLen;
          final ny = ray.y + ray.dy * stepLen;

          Rock? hitRock;
          var bestT = 2.0;
          for (final r in rocks) {
            final t = _segCircle(ray.x, ray.y, nx, ny, r.x, r.y, r.r);
            if (t != null && t < bestT) {
              bestT = t;
              hitRock = r;
            }
          }
          if (hitRock != null) {
            final px = ray.x + (nx - ray.x) * bestT;
            final py = ray.y + (ny - ray.y) * bestT;
            ray.path += stepLen * bestT;
            final nxn = (px - hitRock.x) / hitRock.r;
            final nyn = (py - hitRock.y) / hitRock.r;
            final dot = ray.dx * nxn + ray.dy * nyn;
            ray.dx -= 2 * dot * nxn;
            ray.dy -= 2 * dot * nyn;
            final len = math.sqrt(ray.dx * ray.dx + ray.dy * ray.dy);
            if (len > 0.0001) {
              ray.dx /= len;
              ray.dy /= len;
            }
            ray.x = px + nxn * 0.02;
            ray.y = py + nyn * 0.02;
            ray.bounces++;
            ray.ampMul *= 0.72;
            if (ray.bounces > 2) ray.alive = false;
            _spark(px, py, SparkKind.rock, 2);
            if (!ray.alive) break;
            continue;
          }

          var hitReed = false;
          for (final rd in reeds) {
            if (_segCircle(ray.x, ray.y, nx, ny, rd.x, rd.y, rd.r) != null) {
              hitReed = true;
              break;
            }
          }
          if (hitReed) {
            ray.alive = false;
            _spark(ray.x, ray.y, SparkKind.reed, 3);
            break;
          }

          if (!inWater(nx, ny, 0.008, level.pondVariant)) {
            ray.x = (ray.x + nx) * 0.5;
            ray.y = (ray.y + ny) * 0.5;
            ray.alive = false;
            _spark(ray.x, ray.y, SparkKind.water, 1);
            break;
          }

          final ox = ray.x;
          final oy = ray.y;
          ray.x = nx;
          ray.y = ny;
          ray.path += stepLen;

          for (final p in petals) {
            if (p.settled) continue;
            if (w.hit.contains(p.id)) continue;
            if (_segCircle(ox, oy, nx, ny, p.x, p.y, p.r + 0.3) != null) {
              w.hit.add(p.id);
              final fall = math.max(0.0, 1 - ray.path / w.maxR);
              final strength = w.amp * fall * ray.ampMul;
              if (strength > 0.02) {
                final imp = 3.7 * strength / p.w;
                p.vx += ray.dx * imp;
                p.vy += ray.dy * imp;
                p.glow = 1;
                _spark(p.x, p.y, SparkKind.petal, 3);
              }
            }
          }

          for (var idx = 0; idx < echoes.length; idx++) {
            final e = echoes[idx];
            final key = 1000 + idx;
            if (w.hit.contains(key)) continue;
            if (_segCircle(ox, oy, nx, ny, e.x, e.y, e.r + 0.2) != null) {
              w.hit.add(key);
              final childAmp = w.amp * 0.42;
              // Stop weak echo chains; otherwise two nearby echo stones can
              // ping-pong forever after the parent wave is long gone.
              if (childAmp >= 0.03) {
                pending.add(
                  PendingWave(
                    0.22,
                    e.x,
                    e.y,
                    childAmp,
                    w.maxR * 0.65,
                    w.speed * 0.92,
                    sourceEcho: idx,
                  ),
                );
                _spark(e.x, e.y, SparkKind.echo, 5);
              }
            }
          }

          if (ray.path >= w.maxR) ray.alive = false;
        }
        if (ray.alive) anyAlive = true;
      }
      if (!anyAlive) w.dead = true;
    }
    waves.removeWhere((w) => w.dead);
  }

  void _updatePending(double dt) {
    for (final p in pending) {
      p.t -= dt;
    }
    final ready = pending.where((p) => p.t <= 0).toList();
    for (final p in ready) {
      pending.remove(p);
      _emitWave(
        p.x,
        p.y,
        amp: p.amp,
        maxR: p.maxR,
        speed: p.speed,
        sourceEcho: p.sourceEcho,
      );
    }
  }

  bool _inBay(double x, double y) {
    final dx = x - bay.x;
    final dy = y - bay.y;
    return dx * dx + dy * dy < (bay.r - 0.05) * (bay.r - 0.05);
  }

  void _updatePetals(double dt) {
    for (final p in petals) {
      if (p.stranded) continue;
      if (p.settled) {
        p.inBay = _inBay(p.x, p.y);
        continue;
      }

      for (final c in currents) {
        final dx = p.x - c.x;
        final dy = p.y - c.y;
        if (dx * dx + dy * dy < c.r * c.r) {
          p.vx += c.dx * 1.7 * dt;
          p.vy += c.dy * 1.7 * dt;
        }
      }

      for (final v in vortices) {
        final dx = p.x - v.x;
        final dy = p.y - v.y;
        final d2 = dx * dx + dy * dy;
        if (d2 < v.r * v.r && d2 > 0.0001) {
          final d = math.sqrt(d2);
          final s = v.clockwise ? 1.0 : -1.0;
          p.vx += (-dy / d) * v.strength * s * dt;
          p.vy += (dx / d) * v.strength * s * dt;
        }
      }

      p.x += p.vx * dt;
      p.y += p.vy * dt;

      for (final r in rocks) {
        final dx = p.x - r.x;
        final dy = p.y - r.y;
        final d = math.sqrt(dx * dx + dy * dy);
        final minD = r.r + p.r * 0.72;
        if (d < minD && d > 0.0001) {
          final nx = dx / d;
          final ny = dy / d;
          p.x = r.x + nx * minD;
          p.y = r.y + ny * minD;
          final vn = p.vx * nx + p.vy * ny;
          if (vn < 0) {
            p.vx -= vn * nx * 1.25;
            p.vy -= vn * ny * 1.25;
          }
        }
      }

      p.inBay = _inBay(p.x, p.y);

      final m = pondMetric(p.x, p.y, level.pondVariant);
      final edge = m.limit - 0.035;
      if (m.len > edge) {
        final qx = (p.x - kPondCx) / kPondRx;
        final qy = (p.y - kPondCy) / kPondRy;
        final k = edge / m.len;
        p.x = kPondCx + qx * kPondRx * k;
        p.y = kPondCy + qy * kPondRy * k;
        p.vx = 0;
        p.vy = 0;
        p.stranded = true;
        p.inBay = false;
        onStrand?.call();
        _spark(p.x, p.y, SparkKind.water, 8);
        continue;
      }

      final drag = p.inBay ? 13.0 : 4.2;
      if (p.inBay) {
        p.vx += (bay.x - p.x) * 3.0 * dt;
        p.vy += (bay.y - p.y) * 3.0 * dt;
        if (p.speed < 0.5) {
          p.bayTime += dt;
          if (p.bayTime > 0.7) {
            p.settled = true;
            p.vx = 0;
            p.vy = 0;
            bayFlash = 1;
            onSettle?.call();
            _spark(p.x, p.y, SparkKind.petal, 5);
          }
        } else {
          p.bayTime = 0;
        }
      } else {
        p.bayTime = 0;
      }
      final damp = math.exp(-drag * dt);
      p.vx *= damp;
      p.vy *= damp;
      if (p.vx.abs() < 0.001) p.vx = 0;
      if (p.vy.abs() < 0.001) p.vy = 0;
      p.spin += (0.12 + p.speed * 0.45) * dt;
      if (p.glow > 0) p.glow = math.max(0.0, p.glow - dt * 2.6);
    }
  }

  void _updateSparks(double dt) {
    for (final s in sparks) {
      s.life -= dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vx *= 0.94;
      s.vy *= 0.94;
    }
    sparks.removeWhere((s) => s.life <= 0);
  }

  void _spark(double x, double y, SparkKind kind, int count) {
    if (sparks.length > 220) return;
    final n = math.min(count, 6);
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * kTau;
      final sp =
          (0.2 + _rnd.nextDouble() * 1.1) *
          (kind == SparkKind.petal ? 0.7 : 1.0);
      sparks.add(
        Spark(
          x,
          y,
          math.cos(a) * sp,
          math.sin(a) * sp,
          kind,
          0.35 + _rnd.nextDouble() * 0.45,
        ),
      );
    }
  }

  void _updateEnd(double dt) {
    if (status != GameStatus.playing) return;

    var allIn = petals.isNotEmpty;
    for (final p in petals) {
      if (p.stranded || !p.inBay || p.speed > 0.45) {
        allIn = false;
        break;
      }
    }
    if (allIn) {
      winTimer += dt;
      if (winTimer >= 0.8) {
        status = GameStatus.won;
        wonAt = time;
        bayFlash = 1.4;
        endDelay = 1.4;
        onWin?.call();
        return;
      }
    } else {
      winTimer = 0;
    }

    if (petals.any((p) => p.stranded)) {
      loseTimer += dt;
      if (loseTimer >= 0.9) {
        status = GameStatus.lost;
        loseReason = LoseReason.stranded;
        endDelay = 0.7;
        onLose?.call();
      }
      return;
    }
    loseTimer = 0;

    final settled =
        charges <= 0 &&
        !moving &&
        !charging &&
        waves.isEmpty &&
        pending.isEmpty;
    if (settled) {
      idleTimer += dt;
      if (idleTimer >= 1.2) {
        status = GameStatus.lost;
        loseReason = LoseReason.empty;
        endDelay = 0.35;
        onLose?.call();
      }
    } else {
      idleTimer = 0;
    }
  }

  static double _dist2(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return dx * dx + dy * dy;
  }

  static double? _segCircle(
    double x1,
    double y1,
    double x2,
    double y2,
    double cx,
    double cy,
    double r,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final fx = x1 - cx;
    final fy = y1 - cy;
    final a = dx * dx + dy * dy;
    if (a < 1e-9) {
      if (fx * fx + fy * fy <= r * r) return 0;
      return null;
    }
    final b = 2 * (fx * dx + fy * dy);
    final c = fx * fx + fy * fy - r * r;
    if (c <= 0) return 0;
    final disc = b * b - 4 * a * c;
    if (disc < 0) return null;
    final t = (-b - math.sqrt(disc)) / (2 * a);
    if (t < 0 || t > 1) return null;
    return t;
  }
}
