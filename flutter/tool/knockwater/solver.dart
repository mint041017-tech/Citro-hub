// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:citro/games/knockwater/engine.dart';
import 'package:citro/games/knockwater/levels.dart';

const Map<String, List<int>> kDirs = <String, List<int>>{
  'NW': <int>[-1, -1],
  'N': <int>[0, -1],
  'NE': <int>[1, -1],
  'W': <int>[-1, 0],
  'E': <int>[1, 0],
  'SW': <int>[-1, 1],
  'S': <int>[0, 1],
  'SE': <int>[1, 1],
};

class SolveResult {
  final bool solved;
  final List<String> moves;
  final Engine engine;
  const SolveResult(this.solved, this.moves, this.engine);
}

Engine cloneEngine(Engine s) {
  final n = Engine.fromLevel(s.level, levelIndex: s.levelIndex);
  n.charges = s.charges;
  n.maxCharges = s.maxCharges;
  n.cellX = s.cellX;
  n.cellY = s.cellY;
  n.bx = s.bx;
  n.by = s.by;
  n.fromX = s.bx;
  n.fromY = s.by;
  n.toX = s.bx;
  n.toY = s.by;
  n.moving = false;
  n.moveT = 0;
  n.time = s.time;
  n.steps = s.steps;
  n.status = s.status;
  n.loseReason = s.loseReason;
  n.winTimer = s.winTimer;
  n.loseTimer = s.loseTimer;
  n.idleTimer = s.idleTimer;
  n.endDelay = s.endDelay;
  n.wonAt = s.wonAt;
  for (var i = 0; i < s.petals.length; i++) {
    final a = s.petals[i];
    final b = n.petals[i];
    b.x = a.x;
    b.y = a.y;
    b.vx = a.vx;
    b.vy = a.vy;
    b.spin = a.spin;
    b.stranded = a.stranded;
    b.settled = a.settled;
    b.bayTime = a.bayTime;
    b.inBay = a.inBay;
  }
  // A step's wave usually outlives the 0.62s beat. Dropping waves here makes
  // the beam search explore states that a real replay can never reach.
  n.waves.clear();
  for (final w in s.waves) {
    final rays = <Ray>[];
    for (final r in w.rays) {
      final nr = Ray(r.x, r.y, r.dx, r.dy)
        ..path = r.path
        ..ampMul = r.ampMul
        ..bounces = r.bounces
        ..alive = r.alive;
      rays.add(nr);
    }
    final nw = Wave(rays, w.amp, w.maxR, w.speed, w.heavy)
      ..age = w.age
      ..dead = w.dead;
    nw.hit.addAll(w.hit);
    n.waves.add(nw);
  }
  n.pending.clear();
  for (final p in s.pending) {
    n.pending.add(
      PendingWave(
        p.t,
        p.x,
        p.y,
        p.amp,
        p.maxR,
        p.speed,
        sourceEcho: p.sourceEcho,
      ),
    );
  }
  return n;
}

int gridDist(Engine e, int tx, int ty) {
  const n = kCols * kRows;
  final dist = List<int>.filled(n, -1);
  final queue = List<int>.filled(n, 0);
  var head = 0;
  var tail = 0;
  final start = e.cellY * kCols + e.cellX;
  dist[start] = 0;
  queue[tail++] = start;
  const steps = <List<int>>[
    <int>[1, 0],
    <int>[-1, 0],
    <int>[0, 1],
    <int>[0, -1],
    <int>[1, 1],
    <int>[1, -1],
    <int>[-1, 1],
    <int>[-1, -1],
  ];
  while (head < tail) {
    final cur = queue[head++];
    final cx = cur % kCols;
    final cy = cur ~/ kCols;
    if (cx == tx && cy == ty) return dist[cur];
    for (final d in steps) {
      final nx = cx + d[0];
      final ny = cy + d[1];
      if (nx < 0 || nx >= kCols || ny < 0 || ny >= kRows) continue;
      final idx = ny * kCols + nx;
      if (dist[idx] != -1) continue;
      if (!e.canWalkCell(nx, ny)) continue;
      dist[idx] = dist[cur] + 1;
      queue[tail++] = idx;
    }
  }
  return 99;
}

double scoreOf(Engine e) {
  if (e.status == GameStatus.won) return 1e7 - e.steps;
  if (e.status == GameStatus.lost) return -1e7;
  var s = 0.0;
  Petal? target;
  var worst = -1.0;
  for (final p in e.petals) {
    if (p.stranded) return -1e7;
    final dx = p.x - e.bay.x;
    final dy = p.y - e.bay.y;
    final d = math.sqrt(dx * dx + dy * dy);
    s -= d * 12;
    if (p.inBay) {
      s += 45;
    } else if (d > worst) {
      worst = d;
      target = p;
    }
  }
  if (target != null) {
    final dx = target.x - e.bay.x;
    final dy = target.y - e.bay.y;
    final d = math.max(0.001, math.sqrt(dx * dx + dy * dy));
    final ix = target.x + dx / d * 1.5;
    final iy = target.y + dy / d * 1.5;
    var tx = (ix - 0.5).round().clamp(0, kCols - 1).toInt();
    var ty = (iy - 0.5).round().clamp(0, kRows - 1).toInt();
    if (!e.canWalkCell(tx, ty)) {
      var bestD = 1e9;
      for (var y = 0; y < kRows; y++) {
        for (var x = 0; x < kCols; x++) {
          if (!e.canWalkCell(x, y)) continue;
          final ddx = x + 0.5 - ix;
          final ddy = y + 0.5 - iy;
          final dd = ddx * ddx + ddy * ddy;
          if (dd < bestD) {
            bestD = dd;
            tx = x;
            ty = y;
          }
        }
      }
    }
    s -= gridDist(e, tx, ty) * 2.6;
  }
  return s;
}

class _Node {
  final Engine e;
  final List<String> moves;
  _Node(this.e, this.moves);
}

SolveResult solveLevel(int level, {int width = 14, int maxDepth = 34}) {
  final index = level.clamp(0, kLevels.length - 1).toInt();
  return solveSpec(kLevels[index], width: width, maxDepth: maxDepth);
}

SolveResult solveSpec(LevelSpec spec, {int width = 14, int maxDepth = 34}) {
  final root = Engine.fromLevel(spec);
  var beam = <_Node>[_Node(root, <String>[])];
  Engine? best;

  bool verified(List<String> moves) =>
      replaySolution(spec, moves, 0.62) != null &&
      replaySolution(spec, moves, 0.9) != null;

  bool tryWin(Engine e, List<String> moves) {
    var won = e.status == GameStatus.won;
    if (e.status != GameStatus.playing) {
      if (!won) return false;
    } else if (e.petals.isNotEmpty &&
        e.petals.every((p) => p.inBay && !p.stranded)) {
      e.advance(1.8);
      won = e.status == GameStatus.won;
    }
    if (!won) return false;
    return verified(moves);
  }

  for (var depth = 0; depth < maxDepth; depth++) {
    final next = <_Node>[];
    for (final node in beam) {
      final waitEngine = cloneEngine(node.e);
      waitEngine.advance(1.0);
      final waitMoves = <String>[...node.moves, '·'];
      if (tryWin(waitEngine, waitMoves)) {
        return SolveResult(true, waitMoves, waitEngine);
      }
      if (waitEngine.status == GameStatus.playing) {
        next.add(_Node(waitEngine, waitMoves));
      }

      for (final entry in kDirs.entries) {
        if (node.e.charges < 1) continue;
        final c = cloneEngine(node.e);
        if (!c.step(entry.value[0], entry.value[1])) continue;
        c.advance(0.62);
        final moves = <String>[...node.moves, entry.key];
        if (tryWin(c, moves)) return SolveResult(true, moves, c);
        if (c.status == GameStatus.playing) next.add(_Node(c, moves));
      }

      if (node.e.charges >= 3) {
        final k = cloneEngine(node.e);
        if (k.startCharge()) {
          k.chargeT = 1.2;
          k.releaseCharge();
          k.advance(1.5);
          final moves = <String>[...node.moves, 'K'];
          if (tryWin(k, moves)) return SolveResult(true, moves, k);
          if (k.status == GameStatus.playing) next.add(_Node(k, moves));
        }
      }
    }
    if (next.isEmpty) break;
    next.sort((a, b) => scoreOf(b.e).compareTo(scoreOf(a.e)));
    beam = next.take(width).toList();
    best = beam.first.e;
  }
  return SolveResult(false, const <String>[], best ?? root);
}

int? replaySolution(LevelSpec spec, List<String> moves, double beat) {
  final e = Engine.fromLevel(spec);
  for (final m in moves) {
    if (m == 'K') {
      if (!e.startCharge()) return null;
      e.chargeT = 1.2;
      e.releaseCharge();
      e.advance(1.5);
    } else if (m == '·') {
      e.advance(1.0);
    } else {
      final d = kDirs[m];
      if (d == null) return null;
      if (!e.step(d[0], d[1])) return null;
      e.advance(beat);
    }
    if (e.status != GameStatus.playing) break;
  }
  e.advance(3.4);
  return e.status == GameStatus.won ? e.charges : null;
}

/// The executed prefix up to and including the move that ends the level.
/// Tokens after a win/loss are ignored by replaySolution and must not be
/// counted as part of a solution (or as a distinct solution).
List<String> effectiveMoves(
  LevelSpec spec,
  List<String> moves,
  double beat,
) {
  final e = Engine.fromLevel(spec);
  final out = <String>[];
  for (final m in moves) {
    if (e.status != GameStatus.playing) break;
    if (m == 'K') {
      if (!e.startCharge()) return const <String>[];
      e.chargeT = 1.2;
      e.releaseCharge();
      e.advance(1.5);
    } else if (m == '·') {
      e.advance(1.0);
    } else {
      final d = kDirs[m];
      if (d == null) return const <String>[];
      if (!e.step(d[0], d[1])) return const <String>[];
      e.advance(beat);
    }
    out.add(m);
    if (e.status != GameStatus.playing) break;
  }
  e.advance(3.4);
  return e.status == GameStatus.won ? out : const <String>[];
}

class _CollectNode {
  final Engine engine;
  final List<String> moves;
  final double jitter;
  _CollectNode(this.engine, this.moves, this.jitter);
}

Map<String, List<String>> enumerateSolutions(
  LevelSpec spec, {
  int width = 24,
  int maxDepth = 16,
  int seeds = 2,
  int maxWins = 32,
  List<String> canonical = const <String>[],
}) {
  final verified = <String, List<String>>{};
  final seen = <String>{};

  bool isVerified(List<String> moves) {
    if (replaySolution(spec, moves, 0.62) == null) return false;
    if (replaySolution(spec, moves, 0.9) == null) return false;
    return true;
  }

  if (canonical.isNotEmpty && isVerified(canonical)) {
    verified[canonical.join(' ')] = List<String>.of(canonical);
  }

  bool terminal(Engine e, List<String> moves) {
    if (e.status == GameStatus.won) {
      if (verified.length < maxWins) {
        final key = moves.join(' ');
        if (seen.add(key) && isVerified(moves)) {
          verified[key] = List<String>.of(moves);
        }
      }
      return true;
    }
    if (e.status == GameStatus.lost) return true;
    if (e.petals.isNotEmpty && e.petals.every((p) => p.inBay && !p.stranded)) {
      e.advance(1.8);
      if (e.status == GameStatus.won) {
        if (verified.length < maxWins) {
          final key = moves.join(' ');
          if (seen.add(key) && isVerified(moves)) {
            verified[key] = List<String>.of(moves);
          }
        }
        return true;
      }
    }
    return false;
  }

  for (var seed = 1; seed <= seeds && verified.length < maxWins; seed++) {
    final rnd = math.Random(seed);
    var beam = <_CollectNode>[
      _CollectNode(Engine.fromLevel(spec), const <String>[], 0),
    ];
    for (var depth = 0; depth < maxDepth; depth++) {
      final next = <_CollectNode>[];
      for (final node in beam) {
        if (verified.length >= maxWins) break;
        for (final entry in kDirs.entries) {
          if (node.engine.charges < 1) continue;
          final c = cloneEngine(node.engine);
          if (!c.step(entry.value[0], entry.value[1])) continue;
          c.advance(0.62);
          final moves = <String>[...node.moves, entry.key];
          if (terminal(c, moves)) continue;
          if (c.status == GameStatus.playing) {
            next.add(_CollectNode(c, moves, rnd.nextDouble() * 14));
          }
        }
        if (node.engine.charges >= 3) {
          final c = cloneEngine(node.engine);
          if (c.startCharge()) {
            c.chargeT = 1.2;
            c.releaseCharge();
            c.advance(1.5);
            final moves = <String>[...node.moves, 'K'];
            if (terminal(c, moves)) continue;
            if (c.status == GameStatus.playing) {
              next.add(_CollectNode(c, moves, rnd.nextDouble() * 14));
            }
          }
        }
      }
      if (verified.length >= maxWins || next.isEmpty) break;
      next.sort(
        (a, b) => (scoreOf(b.engine) + b.jitter).compareTo(
          scoreOf(a.engine) + a.jitter,
        ),
      );
      beam = next.take(width).toList();
    }
  }
  return verified;
}

void main() {
  final watch = Stopwatch()..start();
  var solved = 0;
  for (var i = 0; i < kLevels.length; i++) {
    final r = solveLevel(i);
    final level = kLevels[i];
    if (r.solved) {
      solved++;
      print(
        'L${i + 1} ${level.name}: solved in ${r.moves.length} actions, '
        '${r.engine.charges}/${r.engine.maxCharges} charges left '
        '(${r.moves.join(' ')})',
      );
    } else {
      print('L${i + 1} ${level.name}: NOT SOLVED');
    }
  }
  watch.stop();
  print(
    'Solved $solved/${kLevels.length} levels in '
    '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
  );
}
