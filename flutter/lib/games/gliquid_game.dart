import 'dart:math' as math;

import 'gliquid_physics.dart';

const double _tau = math.pi * 2;

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);

class LiquidLevels {
  const LiquidLevels._();

  static const List<String> _baseNames = [
    '薄荷',
    '海盐',
    '紫苏',
    '蜜桃',
    '橘子',
    '焦糖',
    '青柠',
    '苏打',
    '莓果',
    '葡萄',
    '抹茶',
    '金箔',
  ];

  static const List<String> _extraNames = [
    '星云',
    '极光',
    '熔岩',
    '冰川',
    '蜜露',
    '幻海',
    '月岩',
    '云霞',
    '萤火',
    '星尘',
    '潮汐',
    '虹光',
  ];

  static const List<double> _baseRadii = [
    0,
    16,
    20,
    24,
    29,
    35,
    42,
    49,
    55,
    61,
    68,
    75,
    82,
    88,
  ];

  static final List<int> _values = _buildValues(256);

  static List<int> _buildValues(int count) {
    final values = List<int>.filled(count, 1);
    for (var i = 1; i < count; i++) {
      values[i] = values[i - 1] * 2;
    }
    return values;
  }

  /// 等级 1 = 1，等级 2 = 2 …… 等级 13 = 8192，没有终点。
  static int valueForLevel(int level) {
    final safeLevel = math.max(1, level);
    if (safeLevel <= _values.length) return _values[safeLevel - 1];
    var value = _values.last;
    for (var i = _values.length; i < safeLevel; i++) {
      value *= 2;
    }
    return value;
  }

  static String nameForLevel(int level) {
    final safeLevel = math.max(1, level);
    if (safeLevel <= _baseNames.length) return _baseNames[safeLevel - 1];
    return _extraNames[(safeLevel - _baseNames.length - 1) %
        _extraNames.length];
  }

  /// 半径先快速拉开，13 级后逼近渐近线，保证无限等级仍然塞得进罐子。
  static double baseRadiusForLevel(int level) {
    final safeLevel = math.max(1, level);
    if (safeLevel < _baseRadii.length) return _baseRadii[safeLevel];
    return 98 - 10 * math.exp(-(safeLevel - 13) / 8);
  }

  /// 2048 之后每 6 级再来一次虹彩，作为无限旅程里的里程碑。
  static bool shimmerForLevel(int level) =>
      level >= 12 && (level - 12) % 6 == 0;
}

class LiquidLayout {
  const LiquidLayout({
    required this.width,
    required this.height,
    required this.topInset,
    required this.cx,
    required this.jarW,
    required this.jarH,
    required this.jarX0,
    required this.jarX1,
    required this.jarTop,
    required this.floorY,
    required this.scale,
    required this.launcherX,
    required this.launcherY,
    required this.muzzle,
    required this.bounds,
    required this.dangerY,
  });

  final double width;
  final double height;
  final double topInset;
  final double cx;
  final double jarW;
  final double jarH;
  final double jarX0;
  final double jarX1;
  final double jarTop;
  final double floorY;
  final double scale;
  final double launcherX;
  final double launcherY;
  final double muzzle;
  final WorldBounds bounds;
  final double dangerY;

  factory LiquidLayout.compute(
    double width,
    double height, {
    double topInset = 96,
  }) {
    final compact = width < 760;
    final jarW = math.min(width - (compact ? 26 : 76), 380.0);
    final bottomPad = math.max(22.0, height * 0.045);
    final floorY = height - bottomPad;
    var jarH = math.min(height * 0.72, math.min(800.0, jarW * 1.46));
    var jarTop = floorY - jarH;
    final minTop = math.max(
      height < 540
          ? 150.0
          : height < 700
          ? 176.0
          : 190.0,
      topInset + 118,
    );

    if (jarTop < minTop) {
      jarTop = minTop;
      jarH = floorY - jarTop;
    }
    if (jarH < 160) jarH = 160;

    final cx = width / 2;
    final scale = _clamp(math.min(jarW / 430, jarH / 290), 0.92, 1.35);
    final jarX0 = cx - jarW / 2;
    final jarX1 = cx + jarW / 2;
    final pivotY = math.max(jarTop - 76, topInset + 18);

    return LiquidLayout(
      width: width,
      height: height,
      topInset: topInset,
      cx: cx,
      jarW: jarW,
      jarH: jarH,
      jarX0: jarX0,
      jarX1: jarX1,
      jarTop: jarTop,
      floorY: floorY,
      scale: scale,
      launcherX: cx,
      launcherY: pivotY,
      muzzle: 43 + scale * 8,
      bounds: WorldBounds(
        left: jarX0 + 5,
        right: jarX1 - 5,
        top: math.max(topInset + 6, jarTop - 70),
        floor: floorY - 5,
      ),
      dangerY: jarTop + 10,
    );
  }

  double get gravityFactor => _clamp(scale, 0.68, 1.08);

  double levelRadius(int level) =>
      LiquidLevels.baseRadiusForLevel(level) * scale * 1.15;

  /// 经典模式沿用我们调过的投掷速度。
  double launchSpeed(double power) =>
      (750 + 1050 * _clamp(power, 0, 1)) * math.sqrt(gravityFactor);
}

enum LiquidPhase { intro, playing, ending, over }

enum LiquidEventType {
  start,
  shoot,
  merge,
  tierUp,
  unlock,
  warn,
  overflow,
  over,
}

class LiquidEvent {
  const LiquidEvent({
    required this.type,
    this.level = 0,
    this.value = 0,
    this.combo = 0,
    this.x = 0,
    this.y = 0,
    this.power = 0,
    this.message,
  });

  final LiquidEventType type;
  final int level;
  final int value;
  final int combo;
  final double x;
  final double y;
  final double power;
  final String? message;
}

class LiquidFX {
  LiquidFX.ring({
    required this.x,
    required this.y,
    required this.radius,
    required this.growth,
    required this.life,
    required this.level,
    required this.width,
    this.cream = false,
  }) : maxLife = life,
       size = 0,
       vx = 0,
       vy = 0,
       gravity = 0,
       kind = 0;

  LiquidFX.dot({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.life,
    required this.level,
    required this.gravity,
    this.cream = false,
  }) : maxLife = life,
       radius = 0,
       growth = 0,
       width = 0,
       kind = 1;

  final int kind;
  double x;
  double y;
  double vx;
  double vy;
  double radius;
  double growth;
  double size;
  final double gravity;
  double life;
  final double maxLife;
  final int level;
  final double width;
  final bool cream;

  bool get dead => life <= 0;
}

class LiquidFloat {
  LiquidFloat({
    required this.x,
    required this.y,
    required this.text,
    required this.life,
    required this.rise,
    required this.size,
    required this.color,
  }) : maxLife = life;

  final double x;
  double y;
  final String text;
  double life;
  final double maxLife;
  final double rise;
  final double size;
  final int color;

  bool get dead => life <= 0;
}

class LiquidGhost {
  LiquidGhost({
    required this.pointsA,
    required this.pointsB,
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    required this.radiusA,
    required this.radiusB,
    required this.level,
  }) : life = 0.3;

  final List<Vec2> pointsA;
  final List<Vec2> pointsB;
  final double ax;
  final double ay;
  final double bx;
  final double by;
  final double radiusA;
  final double radiusB;
  final int level;
  double life;

  double get progress => 1 - life / 0.3;
  bool get dead => life <= 0;
}

class LiquidGame {
  LiquidGame({
    required this.layout,
    math.Random? random,
  }) : rnd = random ?? math.Random() {
    _createWorld();
    reset();
  }

  final math.Random rnd;
  LiquidLayout layout;
  late SoftWorld world;

  LiquidPhase phase = LiquidPhase.intro;
  final List<int> queue = [];
  final List<LiquidEvent> events = [];
  final List<LiquidFX> effects = [];
  final List<LiquidFloat> floats = [];
  final List<LiquidGhost> ghosts = [];

  int score = 0;
  int shots = 0;
  int maxLevel = 1;
  double aim = 0;
  double power = 0;
  double chargeTime = 0;
  double cooldown = 0;
  double comboTimer = 0;
  int combo = 0;
  double overflowTime = 0;
  bool overflowWarned = false;
  double shake = 0;
  double time = 0;
  double endTimer = 0;
  double recoil = 0;
  double previewPop = 0;
  double hintTimer = 0;
  bool charging = false;
  bool hintVisible = false;
  double previewSeed = 0;

  final Set<int> _announced = {};

  /// sobosuba 的出货池：按“合成出某等级的个数”逐级解锁，池内等概率随机。
  static const List<int> spawnLadder = [2, 3, 4, 5, 6, 7, 8];
  static const List<int> spawnUnlockMerges = [0, 1, 3, 6, 10, 15, 21];
  final List<int> _spawnUnlocked = [2];
  final Map<int, int> _spawnMergeCounts = {};
  int _lastSpawnLevel = 0;

  static const double chargeDuration = 1.05;
  static const double overflowLimit = 1.4;

  List<SoftBlob> get blobs => world.blobs;

  void _createWorld() {
    world = SoftWorld(layout.bounds);
    _applyPhysics();
  }

  void _applyPhysics() {
    world.gravity = 900 * layout.gravityFactor;
    world.linearDamping = 0.9992;
    world.floorGrip = 0.999;
    world.shapeStiffness = 110;
    world.maxSpeed = 2000;
  }

  void resize(LiquidLayout next) {
    final scaleChanged = (next.scale - layout.scale).abs() > 0.001;
    layout = next;
    world.bounds = next.bounds;
    world.gravity = 900 * next.gravityFactor;
    _applyPhysics();
    if (scaleChanged) world.containAll();
  }

  void reset({bool demo = false}) {
    phase = LiquidPhase.intro;
    score = 0;
    shots = 0;
    maxLevel = 1;
    aim = 0;
    power = 0;
    chargeTime = 0;
    cooldown = 0;
    comboTimer = 0;
    combo = 0;
    overflowTime = 0;
    overflowWarned = false;
    shake = 0;
    endTimer = 0;
    recoil = 0;
    previewPop = 0;
    hintTimer = 0;
    hintVisible = false;
    charging = false;
    events.clear();
    effects.clear();
    floats.clear();
    ghosts.clear();
    _announced.clear();
    _spawnUnlocked
      ..clear()
      ..add(spawnLadder.first);
    _spawnMergeCounts.clear();
    _lastSpawnLevel = 0;

    _createWorld();
    queue
      ..clear()
      ..addAll([2, 3, 2, 4]);
    while (queue.length < 4) {
      queue.add(rollLevel(true));
    }
    previewSeed = rnd.nextDouble() * 1000;

    _seedJar(demo: demo);
    for (var i = 0; i < 42; i++) {
      world.step(1 / 60);
    }
    for (final blob in blobs) {
      maxLevel = math.max(maxLevel, blob.level);
    }
  }

  void _seedJar({bool demo = false}) {
    final levels = demo ? [2, 2, 3, 4] : [2, 3, 2, 4];
    const offsets = [-0.34, -0.12, 0.12, 0.34];

    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      final radius = layout.levelRadius(level);
      final x =
          layout.cx + offsets[i] * layout.jarW + (rnd.nextDouble() - .5) * 8;
      final y =
          layout.bounds.floor - radius - 7 - (i.isEven ? 0 : radius * 0.36);
      final blob = SoftBlob(
        level: level,
        radius: radius,
        x: x,
        y: y,
        random: rnd,
      );
      world.add(blob);
    }
  }

  void start() {
    if (phase != LiquidPhase.intro) return;
    phase = LiquidPhase.playing;
    events.add(const LiquidEvent(type: LiquidEventType.start));
    hintVisible = true;
    hintTimer = 9;
  }

  bool get isPlaying => phase == LiquidPhase.playing;

  void step(double dt) {
    final clamped = _clamp(dt, 0, 0.05);
    time += clamped;

    if (phase != LiquidPhase.over) {
      world.step(clamped);
      for (final blob in blobs) {
        if (blob.visualPop > 0) {
          blob.visualPop = math.max(0, blob.visualPop - clamped);
        }
      }
      if (phase == LiquidPhase.playing || phase == LiquidPhase.intro) {
        _checkMerges();
      }
    }

    _updateFX(clamped);

    if (phase == LiquidPhase.playing) {
      _updateOverflow(clamped);
      if (phase != LiquidPhase.playing) return;

      cooldown = math.max(0, cooldown - clamped);
      if (comboTimer > 0) {
        comboTimer = math.max(0, comboTimer - clamped);
        if (comboTimer == 0) combo = 0;
      }
      if (charging) {
        chargeTime += clamped;
        power = math.min(1, 0.12 + (chargeTime / chargeDuration) * 0.88);
      }
      if (previewPop > 0) {
        previewPop = math.max(0, previewPop - clamped * 1.8);
      }
      if (recoil > 0) recoil = math.max(0, recoil - clamped * 7);
      shake = math.max(0, shake - clamped * 26);

      if (hintVisible) {
        hintTimer -= clamped;
        if (hintTimer <= 0 || shots >= 4) hintVisible = false;
      }
    } else if (phase == LiquidPhase.ending) {
      shake = math.max(0, shake - clamped * 14);
      if (recoil > 0) recoil = math.max(0, recoil - clamped * 7);
      endTimer -= clamped;
      if (endTimer <= 0) {
        phase = LiquidPhase.over;
        events.add(const LiquidEvent(type: LiquidEventType.over));
      }
    } else {
      shake = math.max(0, shake - clamped * 20);
      if (recoil > 0) recoil = math.max(0, recoil - clamped * 7);
    }
  }

  void setAimFromPoint(double x, double y) {
    final dx = x - layout.launcherX;
    final dy = math.max(10, y - layout.launcherY);
    aim = _clamp(math.atan2(dx, dy), -1, 1);
  }

  void nudgeAim(double delta) {
    aim = _clamp(aim + delta, -1, 1);
  }

  bool beginCharge() {
    if (phase != LiquidPhase.playing || cooldown > 0 || charging) return false;
    charging = true;
    chargeTime = 0;
    power = 0.12;
    return true;
  }

  bool releaseShot() {
    if (!charging || phase != LiquidPhase.playing) return false;
    charging = false;
    final launched = launchAt(aim, power);
    if (launched) {
      power = 0;
      chargeTime = 0;
    }
    return launched;
  }

  void cancelCharge() {
    charging = false;
    power = 0;
    chargeTime = 0;
  }

  bool launchAt(double aimValue, double powerValue) {
    if (phase != LiquidPhase.playing || cooldown > 0) return false;
    final level = queue.isEmpty ? 2 : queue.first;
    final radius = layout.levelRadius(level);
    aim = _clamp(aimValue, -1, 1);
    power = _clamp(powerValue, 0.12, 1);

    final dirX = math.sin(aim);
    final dirY = math.cos(aim);
    final muzzleDist = layout.muzzle + radius * 0.12;
    final x = layout.launcherX + dirX * muzzleDist;
    final y = layout.launcherY + dirY * muzzleDist;
    final speed = layout.launchSpeed(power);

    final blob = SoftBlob(
      level: level,
      radius: radius,
      x: x,
      y: y,
      vx: dirX * speed,
      vy: dirY * speed,
      random: rnd,
    );
    world.add(blob);

    effects.add(
      LiquidFX.ring(
        x: x,
        y: y,
        radius: radius * 0.35,
        growth: 70 + power * 80,
        life: 0.36,
        level: level,
        width: 2,
      ),
    );
    for (var i = 0; i < 5; i++) {
      final angle = math.atan2(dirY, dirX) + (rnd.nextDouble() - .5) * 1.4;
      final s = 35 + rnd.nextDouble() * 85;
      effects.add(
        LiquidFX.dot(
          x: x,
          y: y,
          vx: math.cos(angle) * s,
          vy: math.sin(angle) * s,
          size: 1.5 + rnd.nextDouble() * 1.9,
          life: 0.22 + rnd.nextDouble() * 0.18,
          level: level,
          gravity: 350,
        ),
      );
    }

    events.add(
      LiquidEvent(
        type: LiquidEventType.shoot,
        level: level,
        value: LiquidLevels.valueForLevel(level),
        x: x,
        y: y,
        power: power,
      ),
    );

    shake = math.min(8, shake + 1.2 + power * 1.8);
    recoil = 1;
    previewPop = 0.24;
    // 投掷节奏也是难度来源：0.18s 的回收时间让玩家能持续施压，
    // 不再出现罐口悬停、靠慢慢合并无限续命的情况。
    cooldown = 0.18;
    shots += 1;

    queue.removeAt(0);
    queue.add(rollLevel(false));
    previewSeed = rnd.nextDouble() * 1000;

    if (shots >= 4 && hintVisible) hintVisible = false;
    return true;
  }

  // sobosuba 的出货逻辑：初始只能出最小的一档，之后每合成出某等级
  // 若干次就解锁该等级的出货；池子里等概率随机，并避开刚投出的同级。
  // 门槛沿用 sobosuba 的 [0,1,3,6,10,15,21]。
  static const int maxSpawnLevel = 8;

  int _spawnIndexFor(int level) => spawnLadder.indexOf(level);

  bool _isSpawnUnlocked(int level) => _spawnUnlocked.contains(level);

  void _notifySpawnUnlocked(int level) {
    final labels = _spawnUnlocked
        .map((l) => _formatValue(LiquidLevels.valueForLevel(l)))
        .join(' / ');
    events.add(
      LiquidEvent(
        type: LiquidEventType.tierUp,
        level: level,
        value: LiquidLevels.valueForLevel(level),
        message: '出货升级：现在可以投出 $labels',
      ),
    );
  }

  void _onMergeProduced(int level) {
    final index = _spawnIndexFor(level);
    if (index <= 0 || index >= spawnUnlockMerges.length) return;
    if (_isSpawnUnlocked(level)) return;
    final count = (_spawnMergeCounts[level] ?? 0) + 1;
    _spawnMergeCounts[level] = count;
    if (count >= spawnUnlockMerges[index]) {
      _spawnUnlocked.add(level);
      _notifySpawnUnlocked(level);
    }
  }

  int rollLevel(bool intro) {
    if (intro) return rnd.nextDouble() < 0.6 ? 2 : 3;

    // sobosuba 会避开还停在发射口的同级果冻；这里等价为不连续出同一个等级。
    final pool = _spawnUnlocked.where((l) => l != _lastSpawnLevel).toList();
    final source = pool.isEmpty ? _spawnUnlocked : pool;
    final level = source[rnd.nextInt(source.length)];
    _lastSpawnLevel = level;
    return level;
  }

  void _checkMerges() {
    final contact = world.findMergeContact();
    if (contact == null) return;
    world.remove(contact.a);
    world.remove(contact.b);
    _resolveMerge(contact);
  }

  void _resolveMerge(MergeContact contact) {
    final a = contact.a;
    final b = contact.b;
    if (comboTimer > 0) {
      combo += 1;
    } else {
      combo = 1;
    }
    comboTimer = 1.35;

    final newLevel = a.level + 1;
    final newValue = LiquidLevels.valueForLevel(newLevel);
    final gained = newValue + (combo > 1 ? combo * 4 : 0);
    score += gained;
    shake = math.min(12, shake + 3 + newLevel * 0.7);

    ghosts.add(
      LiquidGhost(
        pointsA: a.boundaryPoints(),
        pointsB: b.boundaryPoints(),
        ax: a.cx,
        ay: a.cy,
        bx: b.cx,
        by: b.cy,
        radiusA: a.radius,
        radiusB: b.radius,
        level: newLevel,
      ),
    );

    final radius = layout.levelRadius(newLevel);
    final blob = SoftBlob(
      level: newLevel,
      radius: radius,
      x: contact.x,
      y: contact.y,
      random: rnd,
    )..visualPop = 0.34;
    blob.adoptMergePath(a, b, contact.indexA, contact.indexB);
    world.add(blob);
    // 合并点可能贴着罐底；先把新液滴收回罐内，避免出生帧漏到罐外。
    world.containBlob(blob);

    final x = blob.cx;
    final y = blob.cy;
    _spawnMergeFX(contact.x, contact.y, radius, newLevel);
    events.add(
      LiquidEvent(
        type: LiquidEventType.merge,
        level: newLevel,
        value: newValue,
        combo: combo,
        x: x,
        y: y,
      ),
    );

    floats.add(
      LiquidFloat(
        x: x,
        y: y - math.max(14, radius * 0.5),
        text: '+${_formatNumber(gained)}',
        life: 0.95,
        rise: 38,
        size: 20 + math.min(8, newLevel * 0.7),
        color: combo > 1 ? 0xFFD9584A : 0xFF26313F,
      ),
    );
    if (combo > 1) {
      floats.add(
        LiquidFloat(
          x: x,
          y: y - math.max(32, radius * 0.9),
          text: '连锁 ×$combo',
          life: 1.05,
          rise: 30,
          size: 13,
          color: 0xFFD9584A,
        ),
      );
    }

    if (newLevel >= 5 && _announced.add(newLevel)) {
      final name = LiquidLevels.nameForLevel(newLevel);
      String message;
      if (newLevel == 12) {
        message = '2048 成精了！还能继续往上合';
      } else if (newLevel == 13) {
        message = '4096 · 果冻没有上限';
      } else if (newLevel > 13) {
        message = '$name ${_formatValue(newValue)} · 无上限';
      } else {
        message = '新果冻解锁：$name ${_formatValue(newValue)}';
      }
      events.add(
        LiquidEvent(
          type: LiquidEventType.unlock,
          level: newLevel,
          value: newValue,
          message: message,
        ),
      );
    }

    maxLevel = math.max(maxLevel, newLevel);
    _onMergeProduced(newLevel);
  }

  void _spawnMergeFX(double x, double y, double radius, int level) {
    effects.add(
      LiquidFX.ring(
        x: x,
        y: y,
        radius: radius * 0.45,
        growth: 130 + level * 16,
        life: 0.5,
        level: level,
        width: 2.4,
      ),
    );
    effects.add(
      LiquidFX.ring(
        x: x,
        y: y,
        radius: radius * 0.2,
        growth: 90 + level * 9,
        life: 0.3,
        level: level,
        width: 3,
        cream: true,
      ),
    );

    final count = 12 + math.min(20, level * 2);
    for (var i = 0; i < count; i++) {
      final angle = rnd.nextDouble() * _tau;
      final speed = 80 + rnd.nextDouble() * (180 + level * 10);
      effects.add(
        LiquidFX.dot(
          x: x,
          y: y,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed - 40,
          size: 1.6 + rnd.nextDouble() * 2.8,
          life: 0.3 + rnd.nextDouble() * 0.4,
          level: level,
          gravity: 900,
          cream: i % 3 == 0,
        ),
      );
    }
  }

  void _updateFX(double dt) {
    var write = 0;
    for (var i = 0; i < effects.length; i++) {
      final fx = effects[i];
      fx.life -= dt;
      if (!fx.dead) {
        if (fx.kind == 0) {
          fx.radius += fx.growth * dt;
        } else {
          fx.vy += fx.gravity * dt;
          fx.x += fx.vx * dt;
          fx.y += fx.vy * dt;
        }
        effects[write++] = fx;
      }
    }
    effects.length = write;

    var floatWrite = 0;
    for (var i = 0; i < floats.length; i++) {
      final item = floats[i];
      item.life -= dt;
      if (!item.dead) {
        item.y -= item.rise * dt;
        floats[floatWrite++] = item;
      }
    }
    floats.length = floatWrite;

    var ghostWrite = 0;
    for (var i = 0; i < ghosts.length; i++) {
      final ghost = ghosts[i];
      ghost.life -= dt;
      if (!ghost.dead) ghosts[ghostWrite++] = ghost;
    }
    ghosts.length = ghostWrite;
  }

  void _updateOverflow(double dt) {
    final dangerY = layout.dangerY;
    var crowded = false;

    for (final blob in blobs) {
      if (blob.age < 1.0) continue;
      if (blob.top() < dangerY) {
        crowded = true;
        break;
      }
    }

    if (crowded) {
      overflowTime += dt;
      if (!overflowWarned && overflowTime > 0.35) {
        overflowWarned = true;
        events.add(const LiquidEvent(type: LiquidEventType.warn));
      }
      if (overflowTime >= overflowLimit) {
        _finishRound();
      }
    } else {
      // 罐口是液面：一次漫过再落回去不该完全清零，否则堆满时只要晃一晃
      // 计时器就会反复归零。缓慢衰减让「持续顶到罐口」真正成为失败线。
      overflowTime = math.max(0, overflowTime - dt * 0.2);
      if (overflowTime == 0) overflowWarned = false;
    }
  }

  void _finishRound() {
    if (phase != LiquidPhase.playing) return;
    phase = LiquidPhase.ending;
    charging = false;
    power = 0;
    endTimer = 0.9;
    shake = math.max(shake, 9);
    events.add(const LiquidEvent(type: LiquidEventType.overflow));
  }

  List<LiquidEvent> drainEvents() {
    if (events.isEmpty) return const [];
    final copy = List<LiquidEvent>.of(events);
    events.clear();
    return copy;
  }

  static String _formatNumber(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static const List<String> _units = [
    'K',
    'M',
    'B',
    'T',
    'Qa',
    'Qi',
    'Sx',
    'Sp',
    'Oc',
    'No',
    'Dc',
  ];

  static String _formatValue(int value) {
    if (value < 10000000) return value.toString();
    var scaled = value.toDouble();
    var unit = -1;
    while (scaled >= 1000 && unit < _units.length - 1) {
      scaled /= 1000;
      unit++;
    }
    if (unit < 0) return value.toString();
    final digits = scaled >= 100 ? 0 : 1;
    return '${scaled.toStringAsFixed(digits)}${_units[unit]}';
  }

  static String formatBlobValue(int value) {
    if (value < 10000000) return value.toString();
    return _formatValue(value);
  }

  static String formatScore(int value) => _formatNumber(value);
}
