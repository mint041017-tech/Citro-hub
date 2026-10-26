import 'dart:math' as math;

const double _tau = math.pi * 2;

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);

double _hypot(double x, double y) => math.sqrt(x * x + y * y);

class Vec2 {
  const Vec2(this.x, this.y);
  final double x;
  final double y;
}

class WorldBounds {
  const WorldBounds({
    required this.left,
    required this.right,
    required this.top,
    required this.floor,
  });

  final double left;
  final double right;
  final double top;
  final double floor;

  double get width => right - left;
  double get height => floor - top;
}

class SoftPoint {
  SoftPoint(double x, double y, this.vx, this.vy)
    : x = x,
      y = y,
      px = x,
      py = y;

  double x;
  double y;
  double px;
  double py;
  double vx;
  double vy;
  int hit = 0;
}

/// sobosuba 式软体：外轮廓由一圈互相重叠的圆形节点（suba）组成。
/// 节点是真碰撞体，形状由皮肤拉伸、面积保持和中心配重共同维持，
/// 因此不需要固定轮廓，也不会在挤压时靠瞬移自愈。
class SoftBlob {
  SoftBlob({
    required this.level,
    required this.radius,
    required double x,
    required double y,
    double vx = 0,
    double vy = 0,
    required math.Random random,
  }) : _rnd = random {
    final desired = (radius * 0.28).round();
    n = desired < 10 ? 10 : (desired > 24 ? 24 : desired);
    // 相邻节点重叠 1/3，节距 = 4/3 r；外半径 = 环半径 + r。
    subaRadius = radius / (1 + (2 * n) / (3 * math.pi));
    ringR = math.max(radius * 0.15, radius - subaRadius);
    restSpacing = subaRadius * 4 / 3;
    targetArea = math.pi * ringR * ringR;
    // sobosuba 的小球配重很轻（外面积/350 再减去节点数），中心惯性小、
    // 抖动更活；按节点数取 0.3 倍，小球才有那种一碰就晃的果冻感。
    extraMass = math.max(2.0, 0.3 * n);
    totalMass = n + extraMass;
    invMass = 1 / totalMass;
    boundR = radius * 1.25;
    _fx = List<double>.filled(n, 0);
    _fy = List<double>.filled(n, 0);

    _phase = -math.pi / 2 + (random.nextDouble() - 0.5) * 0.06;
    points = List<SoftPoint>.generate(n, (i) {
      final a = _phase + (i / n) * _tau;
      return SoftPoint(
        x + math.cos(a) * ringR,
        y + math.sin(a) * ringR,
        vx,
        vy,
      );
    });
    normals = List<Vec2>.generate(n, (i) {
      final a = _phase + (i / n) * _tau;
      return Vec2(math.cos(a), math.sin(a));
    });

    extraX = x;
    extraY = y;
    extraVx = vx;
    extraVy = vy;

    wobblePhase = random.nextDouble() * _tau;
    faceSeed = random.nextDouble() * 1000;
    blinkIn = 1.8 + random.nextDouble() * 5.2;
    measure();
  }

  final math.Random _rnd;
  final int level;
  final double radius;

  late final int n;
  late final double subaRadius;
  late final double ringR;
  late final double restSpacing;
  late final double targetArea;
  late final double extraMass;
  late final double totalMass;
  late final double invMass;
  late final List<SoftPoint> points;
  late final List<Vec2> normals;
  late final List<double> _fx;
  late final List<double> _fy;
  late final double _phase;

  double extraX = 0;
  double extraY = 0;
  double extraVx = 0;
  double extraVy = 0;

  double cx = 0;
  double cy = 0;
  double area = 0;
  double perimeter = 0;
  double signedArea = 0;
  double boundR = 0;
  double kinetic = 0;
  double age = 0;
  double visualPop = 0;
  double mergeLock = 0;
  double crushedTime = 0;

  late final double wobblePhase;
  late final double faceSeed;
  late double blinkIn;
  double blinkFor = 0;
  bool contact = false;

  bool get isSmall => radius < 50;

  void measure() {
    var twiceArea = 0.0;
    var perimeterSum = 0.0;
    var sx = 0.0;
    var sy = 0.0;

    for (var i = 0; i < n; i++) {
      final a = points[i];
      final b = points[(i + 1) % n];
      twiceArea += a.x * b.y - b.x * a.y;
      perimeterSum += _hypot(b.x - a.x, b.y - a.y);
      sx += a.x;
      sy += a.y;
    }

    signedArea = twiceArea * 0.5;
    area = signedArea.abs();
    perimeter = perimeterSum;
    if (sx.isFinite && sy.isFinite) {
      cx = sx / n;
      cy = sy / n;
    }
  }

  void recenter() {
    var sx = 0.0;
    var sy = 0.0;
    for (var i = 0; i < n; i++) {
      sx += points[i].x;
      sy += points[i].y;
    }
    cx = sx / n;
    cy = sy / n;
  }

  void updateNormals() {
    final sign = signedArea >= 0 ? 1.0 : -1.0;
    for (var i = 0; i < n; i++) {
      final prev = points[(i - 1 + n) % n];
      final cur = points[i];
      final next = points[(i + 1) % n];

      final e0x = cur.x - prev.x;
      final e0y = cur.y - prev.y;
      final e1x = next.x - cur.x;
      final e1y = next.y - cur.y;
      final l0 = _hypot(e0x, e0y);
      final l1 = _hypot(e1x, e1y);

      var nx = 0.0;
      var ny = 0.0;
      if (l0 > 1e-6) {
        nx += (e0y * sign) / l0;
        ny += (-e0x * sign) / l0;
      }
      if (l1 > 1e-6) {
        nx += (e1y * sign) / l1;
        ny += (-e1x * sign) / l1;
      }
      var len = _hypot(nx, ny);
      if (len < 1e-6) {
        nx = cur.x - cx;
        ny = cur.y - cy;
        len = _hypot(nx, ny);
      }
      if (len < 1e-6) {
        nx = math.cos(_phase + i / n * _tau);
        ny = math.sin(_phase + i / n * _tau);
        len = 1;
      }
      normals[i] = Vec2(nx / len, ny / len);
    }
  }

  void applyShapeForces(double h, {double shapeStiffness = 110}) {
    _applySkin(h);
    _applyArea(h);
    _applyShapeSpring(h, shapeStiffness);
    _applyCentralMass(h);
  }

  /// sobosuba 靠零重力保持圆润；罐子里球会被压成宽椭圆（面积没丢、
  /// 形状丢了）。这里给每个节点一根很软的“回自己圆上位置”的弹簧，
  /// 有形状记忆但不会变硬 —— 压扁后会慢慢鼓回圆。
  double get orientation {
    var dot = 0.0;
    var cross = 0.0;
    for (var i = 0; i < n; i++) {
      final bx = math.cos(_phase + i / n * _tau);
      final by = math.sin(_phase + i / n * _tau);
      final rx = points[i].x - cx;
      final ry = points[i].y - cy;
      dot += rx * bx + ry * by;
      cross += rx * by - ry * bx;
    }
    return -math.atan2(cross, dot);
  }

  void _applyShapeSpring(double h, double k) {
    final theta = orientation;
    for (var i = 0; i < n; i++) {
      final a0 = _phase + i / n * _tau + theta;
      final tx = cx + math.cos(a0) * ringR;
      final ty = cy + math.sin(a0) * ringR;
      final p = points[i];
      p.vx += (tx - p.x) * k * h;
      p.vy += (ty - p.y) * k * h;
    }
  }

  void _applySkin(double h) {
    for (var i = 0; i < n; i++) {
      final a = points[i];
      final b = points[(i + 1) % n];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final d = _hypot(dx, dy);
      if (d < 1e-6) continue;

      final inv = 1 / d;
      final ux = dx * inv;
      final uy = dy * inv;
      final rel = (b.vx - a.vx) * ux + (b.vy - a.vy) * uy;
      var f = 0.0;
      if (d > restSpacing) {
        f = 2300 * (d - restSpacing) + 9 * rel;
      } else {
        // sobosuba 只做“拉伸回弹”，因为它是零重力；罐子里被压的
        // 一侧也需要回弹，否则球会被压成扁饼。压缩刚度取 1/3。
        f = 900 * (d - restSpacing) + 4.5 * rel;
      }
      if (f > 6000) {
        f = 6000;
      } else if (f < -4000) {
        f = -4000;
      }
      final ax = ux * f * h;
      final ay = uy * f * h;
      a.vx += ax;
      a.vy += ay;
      b.vx -= ax;
      b.vy -= ay;
    }
  }

  void _applyArea(double h) {
    final areaDiff = targetArea - area;
    final ratio = targetArea > 0 ? area / targetArea : 1.0;
    // sobosuba 的软体工作在零重力场景；罐子里有重量，压扁时需要
    // 更强的面积张力，否则小球会被上层压成薄片。
    var strength = 3.0 * areaDiff;
    if (ratio < 0.6) {
      strength *= 1 + (0.6 - ratio) * 3.0;
    }
    final thin = _clamp((0.6 - ratio) / 0.5, 0, 1);
    var sumX = 0.0;
    var sumY = 0.0;

    for (var i = 0; i < n; i++) {
      var nx = normals[i].x;
      var ny = normals[i].y;
      if (thin > 0.01) {
        // 薄片状态下边法向会互相抵消，混入从质心向外的径向分量，
        // 让被压成一条线的球也能重新鼓起来。
        final rx = points[i].x - cx;
        final ry = points[i].y - cy;
        final rl = _hypot(rx, ry);
        if (rl > 1e-6) {
          nx = nx * (1 - thin * 0.6) + (rx / rl) * thin * 0.6;
          ny = ny * (1 - thin * 0.6) + (ry / rl) * thin * 0.6;
          final nl = _hypot(nx, ny);
          if (nl > 1e-6) {
            nx /= nl;
            ny /= nl;
          }
        }
      }
      var ax = strength * nx;
      var ay = strength * ny;
      final mag = _hypot(ax, ay);
      if (mag > 16000) {
        ax = ax / mag * 16000;
        ay = ay / mag * 16000;
      }
      _fx[i] = ax;
      _fy[i] = ay;
      sumX += ax;
      sumY += ay;
    }

    sumX /= n;
    sumY /= n;
    // 健康形状只保留中心不漂移；快被压扁时放松这条约束，
    // 宁可轻微位移，也要把面积撑回来。
    final keepCenter = 1 - thin * 0.85;
    for (var i = 0; i < n; i++) {
      points[i].vx += (_fx[i] - sumX * keepCenter) * h;
      points[i].vy += (_fy[i] - sumY * keepCenter) * h;
    }
  }

  void _applyCentralMass(double h) {
    var dx = cx - extraX;
    var dy = cy - extraY;
    final dist = _hypot(dx, dy);
    if (dist > 140) {
      dx *= 140 / dist;
      dy *= 140 / dist;
    }

    var dvx = averageVx() - extraVx;
    var dvy = averageVy() - extraVy;
    final dv = _hypot(dvx, dvy);
    if (dv > 500) {
      dvx *= 500 / dv;
      dvy *= 500 / dv;
    }

    var ax = 200 * dx + 15 * dvx;
    var ay = 200 * dy + 15 * dvy;
    final mag = _hypot(ax, ay);
    if (mag > 6000) {
      ax = ax / mag * 6000;
      ay = ay / mag * 6000;
    }
    extraVx += ax * h;
    extraVy += ay * h;

    final rx = -ax * extraMass / n;
    final ry = -ay * extraMass / n;
    for (var i = 0; i < n; i++) {
      points[i].vx += rx * h;
      points[i].vy += ry * h;
    }
  }

  void integrate(double h, double gravity, double damping, double maxSpeed) {
    for (var i = 0; i < n; i++) {
      final p = points[i];
      p.px = p.x;
      p.py = p.y;
      p.vy += gravity * h;
      p.vx *= damping;
      p.vy *= damping;
      _capVelocity(p, maxSpeed);
      p.x += p.vx * h;
      p.y += p.vy * h;
    }

    extraVy += gravity * h;
    extraVx *= damping;
    extraVy *= damping;
    final speed = _hypot(extraVx, extraVy);
    if (speed > maxSpeed) {
      extraVx = extraVx / speed * maxSpeed;
      extraVy = extraVy / speed * maxSpeed;
    }
    extraX += extraVx * h;
    extraY += extraVy * h;
  }

  void finish(double h, double floorGrip, double maxSpeed) {
    var kineticSum = 0.0;
    for (var i = 0; i < n; i++) {
      final p = points[i];
      // sobosuba 的 suba 摩擦是 0：罐底只留很轻的阻尼，
      // 果冻才会像液体一样贴着罐壁滑开，而不是变成一颗静止的球。
      if ((p.hit & 8) != 0) {
        p.vx *= floorGrip;
      }
      _capVelocity(p, maxSpeed);
      p.hit = 0;
      p.px = p.x;
      p.py = p.y;
      kineticSum += _hypot(p.vx, p.vy);
    }
    kinetic = kineticSum / n;
    age += h;
    mergeLock = math.max(0, mergeLock - h);
    if (area < targetArea * 0.12) {
      crushedTime += h;
    } else {
      crushedTime = math.max(0, crushedTime - h * 3);
    }
    blinkIn -= h;
    if (blinkFor > 0) {
      blinkFor -= h;
    } else if (blinkIn <= 0) {
      blinkFor = 0.12;
      blinkIn = 2.4 + _rnd.nextDouble() * 5.5;
    }
  }

  void _capVelocity(SoftPoint p, double maxSpeed) {
    final speed = _hypot(p.vx, p.vy);
    if (speed > maxSpeed) {
      p.vx = p.vx / speed * maxSpeed;
      p.vy = p.vy / speed * maxSpeed;
    }
  }

  void addVelocity(double vx, double vy) {
    for (var i = 0; i < n; i++) {
      points[i].vx += vx;
      points[i].vy += vy;
    }
    extraVx += vx;
    extraVy += vy;
  }

  double top() {
    var top = double.infinity;
    for (var i = 0; i < n; i++) {
      if (points[i].y < top) top = points[i].y;
    }
    return top - subaRadius;
  }

  List<Vec2> boundaryPoints() {
    final offset = subaRadius * 0.96;
    return List<Vec2>.generate(n, (i) {
      final p = points[i];
      final nrm = normals[i];
      return Vec2(p.x + nrm.x * offset, p.y + nrm.y * offset);
    });
  }

  double averageVx() {
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += points[i].vx;
    }
    return sum / n;
  }

  double averageVy() {
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += points[i].vy;
    }
    return sum / n;
  }

  void translate(double dx, double dy) {
    for (var i = 0; i < n; i++) {
      final pt = points[i];
      pt.x += dx;
      pt.y += dy;
      pt.px += dx;
      pt.py += dy;
    }
  }

  void fixShape({double scale = 1.0}) {
    final avx = averageVx();
    final avy = averageVy();
    final r = ringR * scale;
    for (var i = 0; i < n; i++) {
      final a = _phase + (i / n) * _tau;
      final p = points[i];
      p.x = cx + math.cos(a) * r;
      p.y = cy + math.sin(a) * r;
      p.px = p.x;
      p.py = p.y;
      p.vx = avx;
      p.vy = avy;
      p.hit = 0;
    }
    extraX = cx;
    extraY = cy;
    extraVx = avx;
    extraVy = avy;
    measure();
    updateNormals();
  }

  /// 合并时，新球沿两个旧球留下的轮廓重新铺开节点：
  /// 从接触点两侧绕行，跳掉接触节点和它的邻居，再把路径等距重采样。
  void adoptMergePath(SoftBlob a, SoftBlob b, int indexA, int indexB) {
    final oldPositions = <Vec2>[];
    final oldVelocities = <Vec2>[];

    for (var k = 1; k <= a.n - 2; k++) {
      final i = (indexA + k) % a.n;
      oldPositions.add(Vec2(a.points[i].x, a.points[i].y));
      oldVelocities.add(Vec2(a.points[i].vx, a.points[i].vy));
    }
    for (var k = 1; k <= b.n - 2; k++) {
      final i = (indexB + k) % b.n;
      oldPositions.add(Vec2(b.points[i].x, b.points[i].y));
      oldVelocities.add(Vec2(b.points[i].vx, b.points[i].vy));
    }

    var pathLength = 0.0;
    for (var i = 1; i < oldPositions.length; i++) {
      pathLength += _hypot(
        oldPositions[i].x - oldPositions[i - 1].x,
        oldPositions[i].y - oldPositions[i - 1].y,
      );
    }

    final expectedPath = _tau * ringR;
    if (oldPositions.length >= 2 && pathLength > expectedPath * 0.45) {
      final distPerNode = pathLength / n;
      var dist = 0.0;
      var segment = 0;
      var walked = 0.0;

      for (var i = 0; i < n; i++) {
        while (segment < oldPositions.length - 2) {
          final p0 = oldPositions[segment];
          final p1 = oldPositions[segment + 1];
          final segLen = _hypot(p1.x - p0.x, p1.y - p0.y);
          if (walked + segLen >= dist) break;
          walked += segLen;
          segment++;
        }
        final p0 = oldPositions[segment];
        final p1 = oldPositions[segment + 1];
        final segLen = _hypot(p1.x - p0.x, p1.y - p0.y);
        final t = segLen > 1e-6
            ? _clamp((dist - walked) / segLen, 0, 1)
            : 0.0;
        final v0 = oldVelocities[segment];
        final v1 = oldVelocities[segment + 1];
        final p = points[i];
        p.x = p0.x + (p1.x - p0.x) * t;
        p.y = p0.y + (p1.y - p0.y) * t;
        p.px = p.x;
        p.py = p.y;
        p.vx = v0.x + (v1.x - v0.x) * t;
        p.vy = v0.y + (v1.y - v0.y) * t;
        dist += distPerNode;
      }
    } else {
      // 两个球几乎完全重叠时，轮廓路径会退化成一小段；此时改用
      // 两球中心的平均位置铺一个完整圆，避免合并出一个塌缩的球。
      final mx = (a.cx + b.cx) * 0.5;
      final my = (a.cy + b.cy) * 0.5;
      translate(mx - cx, my - cy);
      cx = mx;
      cy = my;
      final avx = (a.averageVx() + b.averageVx()) * 0.5;
      final avy = (a.averageVy() + b.averageVy()) * 0.5;
      for (var i = 0; i < n; i++) {
        points[i].vx = avx;
        points[i].vy = avy;
      }
    }

    extraX = (a.extraX + b.extraX) * 0.5;
    extraY = (a.extraY + b.extraY) * 0.5;
    extraVx = (a.extraVx + b.extraVx) * 0.5;
    extraVy = (a.extraVy + b.extraVy) * 0.5;
    // sobosuba 合并后的闪白期间不能再合体；闪白时长随外面积增长，
    // 大球连锁会明显变慢，这也是它难度的主要来源之一。
    final outerArea = math.pi * radius * radius;
    mergeLock = math.max(0.18, math.log(100) * outerArea / 60000);
    measure();
    updateNormals();
  }
}

class MergeContact {
  const MergeContact({
    required this.a,
    required this.b,
    required this.indexA,
    required this.indexB,
    required this.x,
    required this.y,
  });

  final SoftBlob a;
  final SoftBlob b;
  final int indexA;
  final int indexB;
  final double x;
  final double y;
}

class SoftWorld {
  SoftWorld(this.bounds);

  final List<SoftBlob> blobs = [];
  WorldBounds bounds;
  double gravity = 2350;

  /// 每子步速度保留率。
  double linearDamping = 0.9992;

  /// 圆形记忆强度。
  double shapeStiffness = 110;

  /// 速度上限。
  double maxSpeed = 2000;

  /// 罐底摩擦（每子步切向保留率）。
  double floorGrip = 0.999;

  double accumulator = 0;
  double fixedStep = 1 / 180;
  int maxSteps = 6;

  void add(SoftBlob blob) => blobs.add(blob);

  void remove(SoftBlob blob) {
    blobs.remove(blob);
  }

  void step(double dt) {
    accumulator += math.min(dt, 0.05);
    var count = 0;
    while (accumulator >= fixedStep && count < maxSteps) {
      substep(fixedStep);
      accumulator -= fixedStep;
      count++;
    }
    if (count == maxSteps) accumulator = 0;
  }

  void substep(double h) {
    for (final blob in blobs) {
      blob.measure();
      blob.updateNormals();
      blob.applyShapeForces(h, shapeStiffness: shapeStiffness);
    }

    for (final blob in blobs) {
      blob.integrate(h, gravity, linearDamping, maxSpeed);
    }

    for (final blob in blobs) {
      blob.measure();
      blob.updateNormals();
    }

    _solveSelfCollisions();
    _solveBlobCollisions();
    _solveBodySeparation();
    _solveWalls();

    for (var iteration = 1; iteration < 6; iteration++) {
      _solveBlobCollisions();
      _solveBodySeparation();
      _solveSelfCollisions();
      _solveWalls();
    }
    // 最后按“可见轮廓”再兜两层：节点求解和罐壁挤压都可能让两个球的
    // 轮廓交叉，必须用它自己的多边形把最深的那块推开。
    for (var pass = 0; pass < 3; pass++) {
      _solvePolygonSeparation();
      _solveWalls();
    }

    // 压扁自愈会重建整圈节点，可能又碰到邻居；所以放在最后，
    // 并紧跟着再跑一次分离 + 罐壁，保证一帧结束时没有重叠。
    for (final blob in blobs) {
      if (blob.crushedTime > 0.5) {
        // 被压成一条线时面积法向会互相抵消，无法自行鼓回来；
        // 像 sobosuba 的 fix_shape 一样先缩成小圆，再让面积张力吹开。
        blob.crushedTime = 0;
        blob.fixShape(scale: 0.4);
        containBlob(blob);
      }
    }
    for (var pass = 0; pass < 3; pass++) {
      _solvePolygonSeparation();
      _solveWalls();
      _solveBodySeparation();
    }

    for (final blob in blobs) {
      blob.measure();
      blob.updateNormals();
    }

    for (final blob in blobs) {
      blob.finish(h, floorGrip, maxSpeed);
    }
  }

  void _solveSelfCollisions() {
    for (final blob in blobs) {
      final n = blob.n;
      final minD = blob.subaRadius * 2;
      for (var i = 0; i < n; i++) {
        final a = blob.points[i];
        for (var j = i + 1; j < n; j++) {
          if (j == i + 1 || (i == 0 && j == n - 1)) continue;
          final b = blob.points[j];
          final dx = b.x - a.x;
          final dy = b.y - a.y;
          final d2 = dx * dx + dy * dy;
          if (d2 >= minD * minD) continue;

          final d = math.sqrt(d2);
          final nx = d > 1e-6 ? dx / d : 0.0;
          final ny = d > 1e-6 ? dy / d : -1.0;
          final push = (minD - d) * 0.5 * 0.8;
          a.x -= nx * push;
          a.y -= ny * push;
          b.x += nx * push;
          b.y += ny * push;

          final vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
          if (vn < 0) {
            final impulse = -vn * 0.5;
            a.vx -= nx * impulse;
            a.vy -= ny * impulse;
            b.vx += nx * impulse;
            b.vy += ny * impulse;
          }
          blob.contact = true;
        }
      }
    }
  }

  void _solveBlobCollisions() {
    for (var i = 0; i < blobs.length; i++) {
      final a = blobs[i];
      for (var j = i + 1; j < blobs.length; j++) {
        final b = blobs[j];
        final cdx = b.cx - a.cx;
        final cdy = b.cy - a.cy;
        final reach = a.radius + b.radius + 3;
        if (cdx * cdx + cdy * cdy > reach * reach) continue;
        _resolveBlobPair(a, b);
      }
    }
  }

  void _resolveBlobPair(SoftBlob a, SoftBlob b) {
    final minD = a.subaRadius + b.subaRadius;
    final minD2 = minD * minD;

    for (var ia = 0; ia < a.n; ia++) {
      final pa = a.points[ia];
      for (var ib = 0; ib < b.n; ib++) {
        final pb = b.points[ib];
        final dx = pb.x - pa.x;
        final dy = pb.y - pa.y;
        final d2 = dx * dx + dy * dy;
        if (d2 >= minD2) continue;

        final d = math.sqrt(d2);
        final nx = d > 1e-6 ? dx / d : 0.0;
        final ny = d > 1e-6 ? dy / d : -1.0;
        final push = (minD - d) * 0.5 * 0.9;
        pa.x -= nx * push;
        pa.y -= ny * push;
        pb.x += nx * push;
        pb.y += ny * push;

        final vn = (pb.vx - pa.vx) * nx + (pb.vy - pa.vy) * ny;
        if (vn < 0) {
          final impulse = -vn * 0.5;
          pa.vx -= nx * impulse;
          pa.vy -= ny * impulse;
          pb.vx += nx * impulse;
          pb.vy += ny * impulse;
        }
        a.contact = true;
        b.contact = true;
      }
    }
  }

  void _translateWithinBounds(SoftBlob blob, double dx, double dy) {
    final r = blob.subaRadius;
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (var i = 0; i < blob.n; i++) {
      final p = blob.points[i];
      if (p.x - r < minX) minX = p.x - r;
      if (p.x + r > maxX) maxX = p.x + r;
      if (p.y - r < minY) minY = p.y - r;
      if (p.y + r > maxY) maxY = p.y + r;
    }
    if (minX + dx < bounds.left) dx = bounds.left - minX;
    if (maxX + dx > bounds.right) dx = bounds.right - maxX;
    if (minY + dy < bounds.top) dy = bounds.top - minY;
    if (maxY + dy > bounds.floor) dy = bounds.floor - maxY;
    if (dx.abs() < 1e-9 && dy.abs() < 1e-9) return;
    blob.translate(dx, dy);
    blob.cx += dx;
    blob.cy += dy;
  }

  /// 节点圆负责接触形状，这里再补一层“整体不可深穿”的硬约束：
  /// 只靠相切圆，两个大球的环会像齿轮一样互相咬住，小球也会被
  /// 吞进空心内部。球心最小距离只留小球半径 12% 的挤压余量，
  /// 视觉上就是贴着互相压扁，而不是互相穿过去。
  void _solveBodySeparation() {
    for (final blob in blobs) {
      blob.recenter();
    }
    for (var i = 0; i < blobs.length; i++) {
      final a = blobs[i];
      for (var j = i + 1; j < blobs.length; j++) {
        final b = blobs[j];
        final big = math.max(a.radius, b.radius);
        final small = math.min(a.radius, b.radius);
        final minD = big + small + 1.0;
        final dx = b.cx - a.cx;
        final dy = b.cy - a.cy;
        final d = _hypot(dx, dy);
        if (d >= minD || d < 1e-4) continue;

        final nx = dx / d;
        final ny = dy / d;
        final push = (minD - d) * 0.5 * 0.9;
        _translateWithinBounds(a, -nx * push, -ny * push);
        _translateWithinBounds(b, nx * push, ny * push);

        final vn =
            (b.averageVx() - a.averageVx()) * nx +
            (b.averageVy() - a.averageVy()) * ny;
        if (vn < 0) {
          final impulse = -vn * 0.5;
          a.addVelocity(-nx * impulse, -ny * impulse);
          b.addVelocity(nx * impulse, ny * impulse);
        }
        a.contact = true;
        b.contact = true;
      }
    }
  }

  /// 按“可见轮廓”做最后一道分离：找到两个球轮廓最深的一处交叉，
  /// 沿最短穿出方向把球推开。罐壁和邻居一起夹住的角落靠它解开。
  void _solvePolygonSeparation() {
    if (blobs.length < 2) return;
    for (final blob in blobs) {
      blob.recenter();
    }
    final polys = List<List<Vec2>>.generate(
      blobs.length,
      (i) => blobs[i].boundaryPoints(),
    );
    for (var i = 0; i < blobs.length; i++) {
      final a = blobs[i];
      for (var j = i + 1; j < blobs.length; j++) {
        final b = blobs[j];
        final cdx = b.cx - a.cx;
        final cdy = b.cy - a.cy;
        final reach = a.radius + b.radius + 10;
        if (cdx * cdx + cdy * cdy > reach * reach) continue;
        _ejectOutline(a, polys[i], polys[j]);
        _ejectOutline(b, polys[j], polys[i]);
      }
    }
  }

  void _ejectOutline(SoftBlob victim, List<Vec2> own, List<Vec2> other) {
    if (other.length < 3) return;
    var bestDepth = 0.0;
    var bestX = 0.0;
    var bestY = 0.0;
    for (final p in own) {
      final hit = _closestOnPolygon(other, p.x, p.y);
      if (!hit.inside) continue;
      if (hit.depth > bestDepth) {
        bestDepth = hit.depth;
        bestX = hit.x - p.x;
        bestY = hit.y - p.y;
      }
    }
    if (bestDepth < 0.35) return;
    final len = _hypot(bestX, bestY);
    if (len < 1e-4) return;
    final step = math.min(bestDepth, 7.0) * 0.55;
    victim.translate(bestX / len * step, bestY / len * step);
    victim.cx += bestX / len * step;
    victim.cy += bestY / len * step;
  }

  void _solveWalls() {
    for (final blob in blobs) {
      final r = blob.subaRadius;
      final left = bounds.left + r;
      final right = bounds.right - r;
      final top = bounds.top + r;
      final floor = bounds.floor - r;

      for (var i = 0; i < blob.n; i++) {
        final p = blob.points[i];
        if (p.x < left) {
          p.x = left;
          if (p.vx < 0) {
            p.vx = 0;
          }
          p.hit |= 1;
        } else if (p.x > right) {
          p.x = right;
          if (p.vx > 0) {
            p.vx = 0;
          }
          p.hit |= 2;
        }
        if (p.y < top) {
          p.y = top;
          if (p.vy < 0) {
            p.vy = 0;
          }
          p.hit |= 4;
        } else if (p.y > floor) {
          p.y = floor;
          if (p.vy > 0) {
            p.vy = 0;
          }
          p.hit |= 8;
        }
      }
    }
  }

  MergeContact? findMergeContact() {
    MergeContact? best;
    for (var i = 0; i < blobs.length; i++) {
      final a = blobs[i];
      if (a.age < 0.16 || a.mergeLock > 0) continue;
      for (var j = i + 1; j < blobs.length; j++) {
        final b = blobs[j];
        if (a.level != b.level || b.age < 0.16 || b.mergeLock > 0) continue;
        final cdx = b.cx - a.cx;
        final cdy = b.cy - a.cy;
        final reach = a.radius + b.radius + 3;
        if (cdx * cdx + cdy * cdy > reach * reach) continue;

        final limit = a.subaRadius + b.subaRadius + 2.5;
        final limit2 = limit * limit;
        for (var ia = 0; ia < a.n; ia++) {
          final pa = a.points[ia];
          for (var ib = 0; ib < b.n; ib++) {
            final pb = b.points[ib];
            final dx = pb.x - pa.x;
            final dy = pb.y - pa.y;
            if (dx * dx + dy * dy > limit2) continue;
            final midY = (pa.y + pb.y) * 0.5;
            if (best == null || midY > best.y) {
              best = MergeContact(
                a: a,
                b: b,
                indexA: ia,
                indexB: ib,
                x: (pa.x + pb.x) * 0.5,
                y: midY,
              );
            }
          }
        }
      }
    }
    return best;
  }

  void containBlob(SoftBlob blob) {
    final r = blob.subaRadius;
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (var i = 0; i < blob.n; i++) {
      final p = blob.points[i];
      if (p.x - r < minX) minX = p.x - r;
      if (p.x + r > maxX) maxX = p.x + r;
      if (p.y - r < minY) minY = p.y - r;
      if (p.y + r > maxY) maxY = p.y + r;
    }

    var dx = 0.0;
    var dy = 0.0;
    if (minX < bounds.left) {
      dx = bounds.left - minX;
    } else if (maxX > bounds.right) {
      dx = bounds.right - maxX;
    }
    if (minY < bounds.top) {
      dy = bounds.top - minY;
    } else if (maxY > bounds.floor) {
      dy = bounds.floor - maxY;
    }
    if (dx.abs() > 1e-9 || dy.abs() > 1e-9) {
      blob.translate(dx, dy);
      blob.extraX += dx;
      blob.extraY += dy;
    }

    final left = bounds.left + r;
    final right = bounds.right - r;
    final top = bounds.top + r;
    final floor = bounds.floor - r;
    final midX = (bounds.left + bounds.right) * 0.5;
    final midY = (bounds.top + bounds.floor) * 0.5;
    for (var i = 0; i < blob.n; i++) {
      final p = blob.points[i];
      p.x = left <= right ? _clamp(p.x, left, right) : midX;
      p.y = top <= floor ? _clamp(p.y, top, floor) : midY;
    }
    blob.measure();
    blob.updateNormals();
  }

  void containAll() {
    for (final blob in blobs) {
      containBlob(blob);
    }
  }
}

({bool inside, double x, double y, double depth}) _closestOnPolygon(
  List<Vec2> poly,
  double x,
  double y,
) {
  var inside = false;
  var bestD2 = double.infinity;
  var bestX = x;
  var bestY = y;
  final n = poly.length;

  for (var i = 0; i < n; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % n];

    if ((a.y > y) != (b.y > y)) {
      final xint = ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x;
      if (x < xint) inside = !inside;
    }

    final ex = b.x - a.x;
    final ey = b.y - a.y;
    final len2 = ex * ex + ey * ey;
    var t = len2 > 0 ? ((x - a.x) * ex + (y - a.y) * ey) / len2 : 0.0;
    t = _clamp(t, 0, 1);
    final px = a.x + ex * t;
    final py = a.y + ey * t;
    final dx = x - px;
    final dy = y - py;
    final d2 = dx * dx + dy * dy;
    if (d2 < bestD2) {
      bestD2 = d2;
      bestX = px;
      bestY = py;
    }
  }

  return (
    inside: inside,
    x: bestX,
    y: bestY,
    depth: math.sqrt(bestD2),
  );
}
