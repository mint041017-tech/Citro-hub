import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// 极限刹车 · 3D 赛道场景（v1.5.9 重写）
//
// 对齐 web 原版 index.html 21060-22360 的自绘 Canvas 2D 透视投影渲染器：
//   · 黄昏天空 / 云带 / 地平线暖光与太阳盘 / 两圈山裙
//   · 分段雾化的路面 / 路肩 / 路缘石 / 标线 / 车道虚线 / 轮迹磨痕
//   · 路灯（45m 间距、暖光头 + 路面光池）/ 指路牌（绿黄蓝 7 块）
//   · 连续护栏 + 立柱 / 2600m 处水马路障 + 「道路封闭」红板
//   · 低多边形黑色 SUV 车模（20 个面片 + 车轮 + ⊓ 形尾灯 + 绿牌 + 投影 +
//     夕阳轮廓光），撞击慢动作翻滚 / 刹车烟尘 / 火花 / 速度线 / 暗角 / 白闪
// 物理常量与 web GB_* 一致（launchAccel 7.4 / vmax 260km/h / 踏板 1612N …）。
// ---------------------------------------------------------------------------

const double gbAcc = 7.4; // 起步加速度 m/s²
const double gbAccExp = 1.55; // 加速度衰减指数
const double gbVmax = 72.222; // 最高车速 260 km/h
const double gbVref = 72; // 视觉参考速度
const double gbMinKmh = 100; // 允许踩刹车的最低车速
const double gbBreak = 1612; // 踏板断裂力度 N
const double gbFmax = 1715; // 力度条满量程 N
const double gbRampBase = 200; // 按住时力度上升基础速率 N/s
const double gbRampGrow = 400; // 爬升系数
const double gbFall = 900; // 松开回落 N/s
const double gbK = 10.8 / 1612; // 制动力→减速度
const double gbRollRes = 0.15; // 滚动阻力
const double gbDrag = 22e-5; // 风阻系数
const double gbStopV = 0.08; // 判定停住的速度阈值
const double gbTrack = 2600; // 起点到路障距离
const double gbNose = 2.7; // 车头前悬
const double gbSlowmo = 0.28; // 撞击慢动作倍率
const double gbSlowmoS = 1.6;

/// 原版太阳方向（three.js setFromSphericalCoords(1, 87.5°, 215°)）：
/// 近乎贴地平线、位于前进方向左前方。场景空间 z 与 three.js 相反。
const double gbSunX = -0.5736, gbSunY = 0.0436, gbSunZ = 0.8192;

class V3 {
  V3(this.x, this.y, this.z);
  double x, y, z;

  V3 clone() => V3(x, y, z);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get len => math.sqrt(x * x + y * y + z * z);
  V3 get norm => len <= 1e-9 ? V3(0, 0, 0) : this * (1 / len);
  void set(double a, double b, double c) {
    x = a;
    y = b;
    z = c;
  }

  void lerp(V3 t, double k) {
    x += (t.x - x) * k;
    y += (t.y - y) * k;
    z += (t.z - z) * k;
  }
}

/// web GB_HAZE #B07766（FogExp2 密度 0.00038）
const Color _haze = Color(0xFFB07766);

enum BrakePhase {
  idle, // 菜单（showcase 环绕相机）
  count, // 3-2-1-GO
  accel, // 自动加速
  brake, // 已踩刹车（动力切断）
  stop, // 刹停成功（环绕展示）
  crash, // 撞击慢动作
  over, // 结算面板
}

class _Smoke {
  _Smoke(this.x, this.y, this.z, this.r, this.a, this.vz, this.ad);
  double x, y, z, r, a;
  final double vz;
  final double ad;
}

class _Spark {
  _Spark(this.x, this.y, this.z, this.vx, this.vy, this.vz, this.ml);
  double x, y, z, vx, vy, vz, t = 0;
  final double ml;
}

/// 3D 世界：玩法状态 + 固定步长物理 + 渲染插值与相机。
/// 通过回调把「事件」抛给页面（toast / 声音 / 结算）。
class BrakeWorld {
  // ---- 事件回调（页面挂）----
  void Function(String text, {bool alert, double dur}) onToast = (
    _, {
    bool alert = false,
    double dur = 1.4,
  }) {};
  void Function()? onCountTone; // 倒计时哔
  void Function()? onGoTone;
  void Function()? onPressedTone; // 踩下刹车
  void Function(String kind)? onCrashStart; // break | wall
  void Function()? onSucceedTone;
  void Function()? onFinish; // crash/stop → over（弹出结算）

  // ---- 状态 ----
  BrakePhase phase = BrakePhase.idle;
  double t = 0, time = 0;
  double z = 0, v = 0, force = 0;
  bool pressed = false, powerCut = false;
  double holdT = 0;
  double bv = 0, bvKmh = 0, bt = 0, bz = 0, maxForce = 0;
  int score = 0;
  final List<List<double>> samples = <List<double>>[];
  double sampleAcc = 0;
  double shake = 0, roll = 0, rollV = 0, yaw = 0, yawV = 0, vy = 0, carY = 0;
  double carX = 0;

  // v1.6.3：相机按原版 shache.org 的 anchor + offset + lookAt 实现
  // （camera.position = anchor + offset，lookAt(anchor + lookOffset)）。
  final V3 offset = V3(6, 1.6, 6);
  final V3 lookOffset = V3(0, 0.85, 0);
  final V3 anchor = V3(0, 0, 0);
  final V3 camPos = V3(6, 1.6, 6);
  final V3 camTarget = V3(0, 0.85, 0);
  bool anchorReady = false;
  double camFov = 58;
  double orbA = 3.75;
  double crashT = 0, flash = 0, warnCd = 0;
  String crashKind = '';
  double overTimer = 0;
  int countStep = 3;
  double countTimer = 1;

  /// 倒计时大字（3 / 2 / 1 / GO / ''）。
  String countText = '';
  final List<_Smoke> smoke = <_Smoke>[];
  final List<_Spark> sparks = <_Spark>[];
  final math.Random rnd = math.Random();

  // 渲染插值 / 相机（供 painter 读取）
  double acc = 0;
  double prevZ = 0, prevV = 0;
  double rz = 0, rv = 0;
  double renderDt = 1 / 60;

  /// 相机在「场景 z」（正向）上的位置，供雾化与剔除使用。
  double camZ = -6;

  double get speedKmh => v * 3.6;
  double get distToBarrier => math.max(0, gbTrack - gbNose - z);

  void reset() {
    phase = BrakePhase.idle;
    t = 0;
    z = 0;
    v = 0;
    force = 0;
    pressed = false;
    powerCut = false;
    holdT = 0;
    bv = 0;
    bvKmh = 0;
    bt = 0;
    bz = 0;
    maxForce = 0;
    score = 0;
    samples.clear();
    sampleAcc = 0;
    shake = 0;
    roll = 0;
    rollV = 0;
    yaw = 0;
    yawV = 0;
    vy = 0;
    carY = 0;
    carX = 0;
    offset.set(6, 1.6, 6);
    lookOffset.set(0, 0.85, 0);
    anchor.set(0, 0, 0);
    camPos.set(6, 1.6, 6);
    camTarget.set(0, 0.85, 0);
    anchorReady = false;
    camFov = 58;
    camZ = -6;
    orbA = 3.75;
    smoke.clear();
    sparks.clear();
    crashT = 0;
    flash = 0;
    warnCd = 0;
    crashKind = '';
    overTimer = 0;
    countStep = 3;
    countTimer = 1;
    countText = '';
    acc = 0;
    rz = 0;
    rv = 0;
    prevZ = 0;
    prevV = 0;
  }

  void start() {
    reset();
    phase = BrakePhase.count;
    countStep = 3;
    countTimer = 1;
    countText = '3';
    onToast('3');
    onCountTone?.call();
  }

  bool get canPress => phase == BrakePhase.accel || phase == BrakePhase.brake;

  void press() {
    if (!canPress) return;
    if (!powerCut && v * 3.6 < gbMinKmh) {
      if (warnCd <= 0) {
        warnCd = 1.2;
        onToast('车速达到 ${gbMinKmh.round()} km/h 后才能刹车', alert: false);
      }
      return;
    }
    if (!powerCut) {
      powerCut = true;
      bv = v;
      bvKmh = v * 3.6;
      bz = z;
      bt = 0;
      samples
        ..clear()
        ..add([0, v * 3.6, 0]);
      phase = BrakePhase.brake;
      onToast('动力切断 · 初速度 ${bvKmh.toStringAsFixed(1)} km/h');
    }
    if (!pressed) {
      pressed = true;
      onPressedTone?.call();
    }
  }

  void release() {
    pressed = false;
  }

  void _fail(String kind) {
    if (phase == BrakePhase.crash) return;
    crashKind = kind;
    phase = BrakePhase.crash;
    crashT = 0;
    if (kind == 'break') {
      shake = 0.6;
      flash = 0.85;
      onToast('刹车踏板断裂！', alert: true, dur: 2.2);
      rollV = 3.6;
      yawV = 1.15;
      vy = 3.2;
    } else {
      shake = 0.8;
      flash = 0.5;
      onToast('撞上路障！', alert: true, dur: 2.2);
      rollV = 1.1;
      yawV = 0.5;
      vy = 1.6;
      z = gbTrack - gbNose;
    }
    for (var i = 0; i < 34; i++) {
      sparks.add(
        _Spark(
          (rnd.nextDouble() - 0.5) * 2.2,
          0.3 + rnd.nextDouble() * 1.4,
          z + (rnd.nextDouble() - 0.5) * 4,
          (rnd.nextDouble() - 0.5) * 9,
          1.5 + rnd.nextDouble() * 4.5,
          (rnd.nextDouble() - 0.7) * 6,
          0.5 + rnd.nextDouble() * 0.8,
        ),
      );
    }
    overTimer = 5.5;
    onCrashStart?.call(kind);
  }

  void _succeed() {
    phase = BrakePhase.stop;
    v = 0;
    final v0r = (bvKmh * 10).roundToDouble() / 10;
    final tr = math.max(0.001, (bt * 1000).roundToDouble() / 1000);
    score = (v0r * v0r / tr).round();
    orbA = 0.9;
    overTimer = 1.8;
    onSucceedTone?.call();
    onToast('完美刹停！', dur: 1.6);
  }

  void _finish() {
    if (phase == BrakePhase.over) return;
    phase = BrakePhase.over;
    onFinish?.call();
  }

  /// 固定 1/60 步长物理（web gbStep）。
  void step(double dt) {
    t += dt;
    time += dt;
    if (warnCd > 0) warnCd -= dt;
    if (flash > 0) flash = math.max(0, flash - dt * 2.2);
    if (phase == BrakePhase.idle) {
      orbA += dt * 0.16;
    } else if (phase == BrakePhase.stop) {
      orbA += dt * 0.25;
    }

    if (phase == BrakePhase.count) {
      countTimer -= dt;
      if (countTimer <= 0) {
        countStep--;
        if (countStep > 0) {
          countTimer = 1;
          countText = '$countStep';
          onToast('$countStep');
          onCountTone?.call();
        } else if (countStep == 0) {
          countTimer = 0.7;
          countText = 'GO';
          onToast('GO');
          onGoTone?.call();
        } else {
          phase = BrakePhase.accel;
          countText = '';
          onToast('');
        }
      }
      return;
    }

    if (phase == BrakePhase.accel || phase == BrakePhase.brake) {
      if (pressed) {
        holdT += dt;
        force = math.min(
          gbFmax,
          force + (gbRampBase + 2 * gbRampGrow * holdT) * dt,
        );
      } else {
        holdT = 0;
        force = math.max(0, force - gbFall * dt);
      }
      if (force > maxForce) maxForce = force;
      if (force >= gbBreak) {
        _fail('break');
        return;
      }
      double a;
      if (powerCut) {
        a = -(gbRollRes + gbDrag * v * v + gbK * force);
      } else {
        a = gbAcc * (1 - math.pow(math.min(1, v / gbVmax), gbAccExp));
      }
      v += a * dt;
      if (v > gbVmax) v = gbVmax;
      if (v < 0) v = 0;
      z += v * dt;

      if (phase == BrakePhase.brake) {
        bt += dt;
        sampleAcc += dt;
        if (sampleAcc >= 0.04) {
          sampleAcc = 0;
          if (samples.length < 400) {
            samples.add([bt, v * 3.6, math.min(gbBreak, force)]);
          }
        }
        if (v <= gbStopV) {
          _succeed();
          return;
        }
      }

      if (z >= gbTrack - gbNose) {
        _fail('wall');
        return;
      }

      // 刹车烟尘
      if (powerCut && v > 4 && force > gbBreak * 0.55) {
        final nn = math.min(1, (force / gbBreak - 0.55) / 0.45);
        if (rnd.nextDouble() < nn * 0.9) {
          final sxd = rnd.nextBool() ? -1.0 : 1.0;
          final ml = 1.2 + rnd.nextDouble();
          smoke.add(
            _Smoke(
              sxd * 0.86,
              0.15,
              z - 1.32,
              0.5 + nn * 0.6,
              0.25 + nn * 0.25,
              -v * 0.35,
              1 / ml,
            ),
          );
        }
      }
      for (var i = smoke.length - 1; i >= 0; i--) {
        final s = smoke[i];
        s.r += dt * 2.6;
        s.y += dt * 0.85;
        s.z += dt * s.vz;
        s.a -= dt * s.ad;
        if (s.a <= 0) smoke.removeAt(i);
      }
      if (smoke.length > 90) smoke.removeRange(0, smoke.length - 90);
    } else if (phase == BrakePhase.crash) {
      crashT += dt;
      final scl = crashT < gbSlowmoS
          ? gbSlowmo
          : math.min(1, gbSlowmo + (crashT - gbSlowmoS) * 0.8);
      final sdt = dt * scl;
      roll += rollV * sdt;
      yaw += yawV * sdt;
      rollV *= 0.995;
      carY = math.max(0, carY + vy * sdt);
      vy -= 13 * sdt;
      if (carY <= 0) {
        carY = 0;
        vy = 0;
        rollV *= 0.6;
        yawV *= 0.6;
      }
      v = math.max(0, v - 9 * sdt);
      z += v * sdt;
      if (z > gbTrack + 26) z = gbTrack + 26;
      shake = math.max(0, shake - dt * 1.6);
      overTimer -= dt;
      if (overTimer <= 0) {
        _finish();
        return;
      }
    } else if (phase == BrakePhase.stop) {
      overTimer -= dt;
      if (overTimer <= 0) {
        _finish();
        return;
      }
    }

    for (var i = sparks.length - 1; i >= 0; i--) {
      final s = sparks[i];
      s.t += dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.z += s.vz * dt;
      s.vy -= 9.8 * dt;
      if (s.y < 0.02) {
        s.y = 0.02;
        s.vy = s.vy.abs() * 0.35;
      }
      if (s.t > s.ml) sparks.removeAt(i);
    }
    if (shake > 0) shake = math.max(0, shake - dt * 2.2);
  }

  /// 每帧渲染前调用：插值 + 相机平滑（web gbRender 相机段）。
  /// 页面每帧开头先调 [snapshotFrame] 记录本帧起点，再跑固定步长 step 循环。
  void snapshotFrame() {
    prevZ = z;
    prevV = v;
  }

  void render(double dt, bool portrait) {
    renderDt = dt;
    final a = (acc * 60).clamp(0.0, 1.0);
    rz = prevZ + (z - prevZ) * a;
    rv = prevV + (v - prevV) * a;

    final sp = math.min(1, rv / gbVref);
    final mode = phase == BrakePhase.idle
        ? 'showcase'
        : (phase == BrakePhase.crash)
        ? 'crash'
        : (phase == BrakePhase.stop || phase == BrakePhase.over)
        ? 'finish'
        : (phase == BrakePhase.brake)
        ? 'brake'
        : 'chase';
    final baseFov = portrait ? 58.0 : 42.0;
    // v1.6.3：完全按原版 shache.org 的相机模型 —— 目标是「车锚点 + 偏移」，
    // 视线看「车锚点 + lookOffset」（追尾态朝前看 6m），不是简单的俯仰角。
    final tOff = V3(0, 0, 0);
    final tLook = V3(0, 0, 0);
    double tFov, rate;
    switch (mode) {
      case 'showcase':
        // 原版：R=portrait?9.5:7.8，y=portrait?2.4:1.5，看向车下方 1.6m
        final r = portrait ? 9.5 : 7.8;
        tOff.set(math.sin(orbA) * r, portrait ? 2.4 : 1.5, math.cos(orbA) * r);
        tLook.set(0, portrait ? -1.6 : 0.85, 0);
        tFov = baseFov;
        rate = 2;
      case 'chase':
        // 注意：场景空间 +z 为前进方向，原版 offset.z=+8.2（车后）在此取负。
        tOff.set(1.6 - sp * 1.2, 2.2 - sp * 0.5, -(8.2 - sp * 1.4));
        tLook.set(0, 1, 6);
        tFov = baseFov + sp * 22;
        rate = 2.5;
      case 'brake':
        tOff.set(2, 1.55, -(7.6 - sp));
        tLook.set(0.3, 0.9, 4);
        tFov = baseFov + sp * 14;
        rate = 1.8;
      case 'crash':
        tOff.set(9, 4.5, -13);
        tLook.set(0, 0, 0);
        tFov = baseFov + 6;
        rate = 2.2;
      default: // finish
        final r2 = portrait ? 8.5 : 6.8;
        tOff.set(math.sin(orbA) * r2, 1.4, math.cos(orbA) * r2);
        tLook.set(0, 0.8, 0);
        tFov = baseFov;
        rate = 1.6;
      // 环绕相机 z 分量本身就绕圈，无需取反。
    }

    final carPos = V3(carX, carY, rz);
    if (!anchorReady || mode != 'crash') {
      anchor.set(carPos.x, carPos.y, carPos.z);
      anchorReady = true;
    } else {
      anchor.lerp(carPos, 1 - math.exp(-renderDt * 5));
    }
    final s = 1 - math.exp(-renderDt * rate);
    offset.lerp(tOff, s);
    lookOffset.lerp(tLook, math.min(1, s * 1.5));
    camPos.set(anchor.x + offset.x, anchor.y + offset.y, anchor.z + offset.z);
    camTarget.set(
      anchor.x + lookOffset.x,
      anchor.y + lookOffset.y,
      anchor.z + lookOffset.z,
    );
    camFov += (tFov - camFov) * math.min(1, renderDt * 2);
    camZ = camPos.z;
  }

  void commitFrame() {
    // 兼容旧调用名（语义同 snapshotFrame：帧首记录起点，acc 保留跨帧余量）。
    snapshotFrame();
  }
}

// ---------------------------------------------------------------------------
// 渲染器
// ---------------------------------------------------------------------------

Color _mix(Color a, Color b, double t) => Color.fromARGB(
  (a.a + (b.a - a.a) * t).round(),
  (a.r + (b.r - a.r) * t).round(),
  (a.g + (b.g - a.g) * t).round(),
  (a.b + (b.b - a.b) * t).round(),
);

/// 主光方向（原版 DirectionalLight 沿太阳方向 #FFB27A ×3.2）
final double _Lx = gbSunX;
final double _Ly = gbSunY;
final double _Lz = gbSunZ;

double _hash(double n) {
  final x = math.sin(n * 127.1) * 43758.5453;
  return x - x.floorToDouble();
}

class BrakeScenePainter extends CustomPainter {
  BrakeScenePainter(this.w, {Listenable? repaint}) : super(repaint: repaint);

  final BrakeWorld w;

  // 相机（paint 内由世界状态构建，场景 z 与 three.js 世界镜像）
  double _camZ = 0;
  double _focal = 600, _cx = 0, _cy = 0;
  final V3 _cp = V3(6, 1.6, 6), _ct = V3(0, 0.85, 0);
  final V3 _f = V3(0, 0, 1), _r = V3(1, 0, 0), _u = V3(0, 1, 0);

  final Float64List _p = Float64List(3);
  final Float64List _q = Float64List(3);

  /// 最近一次投影是否有顶点落在近平面内（多边形裁剪后已不再使用，
  /// 保留以便调试投影）。

  double _fogT(double z) {
    final d = z - _camZ;
    final t = 1 - math.exp(-(d * 0.00038) * (d * 0.00038));
    return t > 0.92 ? 0.92 : t;
  }

  /// 建相机基（forward / right / up），与 three.js 的 lookAt 一致。
  void _aim() {
    _cp.set(w.camPos.x, w.camPos.y, -w.camPos.z);
    _ct.set(w.camTarget.x, w.camTarget.y, -w.camTarget.z);
    final f = (_ct - _cp).norm;
    final r = f.cross(V3(0, 1, 0)).norm;
    final u = r.cross(f).norm;
    _f.set(f.x, f.y, f.z);
    _r.set(r.x, r.y, r.z);
    _u.set(u.x, u.y, u.z);
    _camZ = w.camZ;
  }

  /// 相机空间坐标（vx, vy, vz），vz 为前向深度。
  void _cam(double x, double y, double z, Float64List out) {
    // 场景 z（车向 +z 前进）→ 世界 z（原版车向 -z）
    final dz = -z - _cp.z;
    final dx = x - _cp.x;
    final dy = y - _cp.y;
    out[0] = dx * _r.x + dy * _r.y + dz * _r.z;
    out[1] = dx * _u.x + dy * _u.y + dz * _u.z;
    out[2] = dx * _f.x + dy * _f.y + dz * _f.z;
  }

  void _proj(double x, double y, double z, Float64List out) {
    _cam(x, y, z, out);
    var vz = out[2];
    if (vz < 1.2) vz = 1.2;
    out[0] = _cx + (out[0] / vz) * _focal;
    out[1] = _cy - (out[1] / vz) * _focal;
    out[2] = vz;
  }

  /// 四点面片（不做近平面裁剪，任一点在相机后方就整片跳过）。
  /// v1.6.5：`_quad` 的裁剪在远距离面片上会失效（薄面片被整片丢弃），
  /// 道路 / 护栏 / 路障这些主结构改用这个直投版本，保证一定画出。
  void _face(
    Canvas c,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    double x2,
    double y2,
    double z2,
    double x3,
    double y3,
    double z3,
    Color fill,
  ) {
    _proj(x0, y0, z0, _p);
    final ax = _p[0], ay = _p[1], az = _p[2];
    _proj(x1, y1, z1, _q);
    final bx = _q[0], by = _q[1], bz = _q[2];
    _proj(x2, y2, z2, _p);
    final cx2 = _p[0], cy2 = _p[1], cz2 = _p[2];
    _proj(x3, y3, z3, _q);
    final dx = _q[0], dy = _q[1], dz = _q[2];
    if (az <= 1.5 || bz <= 1.5 || cz2 <= 1.5 || dz <= 1.5) return;
    final path = Path()
      ..moveTo(ax, ay)
      ..lineTo(bx, by)
      ..lineTo(cx2, cy2)
      ..lineTo(dx, dy)
      ..close();
    c.drawPath(path, Paint()..color = fill);
  }

  void _quad(
    Canvas c,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    double x2,
    double y2,
    double z2,
    double x3,
    double y3,
    double z3,
    Color fill,
  ) {
    // 近平面裁剪（Sutherland–Hodgman，单平面）：地面等超大四边形有角点落在
    // 相机后方，整面剔除会导致整个近景消失，必须按面裁剪。
    const near = 1.2;
    final src = <Float64List>[
      Float64List(3),
      Float64List(3),
      Float64List(3),
      Float64List(3),
    ];
    _cam(x0, y0, z0, src[0]);
    _cam(x1, y1, z1, src[1]);
    _cam(x2, y2, z2, src[2]);
    _cam(x3, y3, z3, src[3]);

    final clipped = <List<double>>[];
    for (var i = 0; i < 4; i++) {
      final cur = src[i];
      final nxt = src[(i + 1) % 4];
      final inCur = cur[2] >= near;
      final inNxt = nxt[2] >= near;
      if (inCur) {
        clipped.add([cur[0], cur[1], cur[2]]);
      }
      if (inCur != inNxt) {
        final t = (near - cur[2]) / (nxt[2] - cur[2]);
        clipped.add([
          cur[0] + (nxt[0] - cur[0]) * t,
          cur[1] + (nxt[1] - cur[1]) * t,
          near,
        ]);
      }
    }
    if (clipped.length < 3) return;
    final path = Path();
    for (var i = 0; i < clipped.length; i++) {
      final vz = clipped[i][2];
      final sx = _cx + (clipped[i][0] / vz) * _focal;
      final sy = _cy - (clipped[i][1] / vz) * _focal;
      if (i == 0) {
        path.moveTo(sx, sy);
      } else {
        path.lineTo(sx, sy);
      }
    }
    path.close();
    c.drawPath(path, Paint()..color = fill);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;
    _cx = W / 2;
    _cy = H / 2;
    _focal = (H / 2) / math.tan(w.camFov * math.pi / 360);
    _aim();

    canvas.save();
    if (w.shake > 0.01) {
      final st = w.t;
      final sx =
          w.shake *
          13 *
          (math.sin(st * 23.3) * 0.6 + math.sin(st * 41.7 + 1.3) * 0.4) *
          0.5;
      final sy =
          w.shake *
          13 *
          (math.sin(st * 29.1 + 0.7) * 0.6 + math.sin(st * 47.9 + 2.1) * 0.4) *
          0.5;
      canvas.translate(sx, sy);
    }

    _drawSky(canvas, W, H);
    _drawHills(canvas, W, H);
    _drawGround(canvas, W, H);
    _drawRoadside(canvas, W);
    _drawGuardrails(canvas, W);
    _drawBarrier(canvas);
    _drawSmoke(canvas);
    _drawCar(canvas, W, H);
    _drawSparks(canvas);
    _drawSpeedLines(canvas, W, H);
    canvas.restore();

    _drawVignette(canvas, W, H);
    if (w.flash > 0.004) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = Color.fromRGBO(255, 235, 218, math.min(0.9, w.flash)),
      );
    }
  }

  // ---------- 天空 / 云 / 暖光 ----------

  void _drawSky(Canvas canvas, double W, double H) {
    // v1.6.3：按原版 shache.org 天空 shader 的实际渲染结果取色（含色调映射）：
    // 天顶暗紫褐 → 中层紫红 → 地平线暖橙；地平线以下由地面覆盖。
    _proj(0, 0, _camZ + 12000, _p);
    final hy = _p[1].roundToDouble();
    final horizonY = hy.clamp(-H, H * 2.0);
    // 原版天空球 shader 覆盖整个视口：地平线以下输出 uGround（#2A1D22），
    // 实际地面网格再盖在上面 —— 这样地平线不会出现生硬的断层。
    final k = (horizonY / H).clamp(0.05, 0.95);
    final fullRect = Offset.zero & Size(W, H);
    canvas.drawRect(
      fullRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            // 取自用户提供的原版截图（492×869）：(97,49,51) → (132,71,71)
            // → (220,152,113) 的地平线暖色。
            Color(0xFF4A2828), // 天顶
            Color(0xFF6B3A3B),
            Color(0xFF9A5A4E),
            Color(0xFFC17F60),
            Color(0xFFDC9871), // 地平线
            Color(0xFF2A1D22), // uGround
            Color(0xFF2A1D22),
          ],
          stops: [
            0,
            0.30 * k,
            0.58 * k,
            0.80 * k,
            k,
            (k + 0.02).clamp(0.0, 1.0),
            1,
          ],
        ).createShader(fullRect),
    );
    // 云带：3 条暗云（原版 fbm 云 → 近似为柔边椭圆）
    final cloudShader = const RadialGradient(
      colors: [Color(0x4D2A1620), Color(0x262A1620), Color(0x002A1620)],
      stops: [0, 0.62, 1],
    ).createShader(const Rect.fromLTWH(-1, -1, 2, 2));
    for (var cl = 0; cl < 3; cl++) {
      final cW = W * (0.5 + _hash(cl * 7.1) * 0.5);
      final cH = math.max(6.0, horizonY * (0.05 + _hash(cl * 3.3) * 0.06));
      final span = W + cW * 2;
      final cx = -cW + ((w.time * (2.2 + cl * 0.9) + cl * span * 0.31) % span);
      final cy = horizonY * (0.22 + cl * 0.16);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(cW, cH);
      canvas.drawCircle(Offset.zero, 1, Paint()..shader = cloudShader);
      canvas.restore();
    }
    // v1.6.4：原版（用户截图）里没有大光团 —— 只有贴着地平线的一层薄暖光。
    // 太阳方向仅用于确定地平线暖光的水平偏置；不再画全屏径向渐变。
    _proj(
      w.camPos.x + gbSunX * 9000,
      w.camPos.y + gbSunY * 9000,
      w.camZ + gbSunZ * 9000,
      _p,
    );
    final sunX = _p[0].clamp(-W, W * 2);
    final bandTop = (horizonY - H * 0.30).clamp(0.0, H);
    final bandRect = Rect.fromLTRB(0, bandTop, W, horizonY);
    if (bandRect.height > 1) {
      canvas.drawRect(
        bandRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0x00FFC48E),
              Color(0x2EFFC48E),
              Color(0x8CFFC48E),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(bandRect),
      );
      // 地平线附近一层很淡的水平暖雾（原版是大气散射，不是光球）
      final hazeRect = Rect.fromLTRB(0, horizonY - H * 0.14, W, horizonY + 6);
      canvas.drawRect(
        hazeRect,
        Paint()
          ..shader = RadialGradient(
            center: Alignment((sunX / W) * 2 - 1, 1.1),
            radius: 1.6,
            colors: const [
              Color(0x3DFFC79A),
              Color(0x14FFB486),
              Color(0x00FFA070),
            ],
            stops: const [0, 0.5, 1],
          ).createShader(hazeRect),
      );
    }
  }

  // ---------- 远景山裙 ----------

  static const List<List<double>> _mtn = [
    [2600, 260, 2600, 0.30], // R / 峰高 / 种子 / u0 → 色 #3A3044
    [2200, 170, 2200, 0.62], // → 色 #4A3A46
  ];
  static const List<Color> _mtnCol = [Color(0xFF3A3044), Color(0xFF4A3A46)];

  double _mtnH(List<double> m, double u) {
    return m[1] *
        (0.35 +
            0.35 * (math.sin(u * math.pi * 7 + m[2])).abs() +
            0.2 * (math.sin(u * math.pi * 23)).abs() +
            0.15 * _hash(u * 511.7 + m[2]));
  }

  void _drawHills(Canvas canvas, double W, double H) {
    final cz = w.rz * 0.92;
    for (var mi = 0; mi < _mtn.length; mi++) {
      final m = _mtn[mi];
      const n = 84;
      final step = 1.8 / n;
      final path = Path();
      var first = true;
      for (var pi = 0; pi <= n; pi++) {
        final phi = -0.9 + pi * step;
        final u = m[3] + phi / (math.pi * 2);
        final zw = cz + m[0] * math.cos(phi);
        _proj(m[0] * math.sin(phi), _mtnH(m, u), zw, _p);
        if (first) {
          path.moveTo(_p[0], _p[1] + 1);
          first = false;
        } else {
          path.lineTo(_p[0], _p[1]);
        }
      }
      _proj(0, 0, _camZ + 4000, _p);
      path.lineTo(_p[0] + 2000, _p[1] + 3);
      path.lineTo(_p[0] - 2000, _p[1] + 3);
      path.close();
      canvas.drawPath(
        path,
        Paint()..color = _mix(_mtnCol[mi], _haze, _fogT(cz + m[0])),
      );
    }
  }

  // ---------- 地面 / 路面 / 标线 ----------

  void _drawGround(Canvas canvas, double W, double H) {
    // 地面：屏幕空间铺满（±420m 的超大四边形会让 Skia 在近平面附近丢面，
    // 而且原版地面本来也是一层纯色 + 纹理，无结构）。
    _proj(0, 0, _camZ + 12000, _p);
    final horizonY = _p[1].clamp(-H, H * 2.0);
    final groundRect = Rect.fromLTRB(0, horizonY, W, H);
    if (groundRect.height > 0.5) {
      canvas.drawRect(
        groundRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _mix(const Color(0xFF201B18), _haze, 0.34),
              const Color(0xFF201B18),
            ],
          ).createShader(groundRect),
      );
    }

    // 路面：整块多边形（左/右边缘按近密远疏采样），一次填充带纵向渐变，
    // 避免分段渲染出现色块与接缝。
    List<Offset> edge(double x) {
      const n = 26;
      final pts = <Offset>[];
      for (var i = 0; i <= n; i++) {
        final t = i / n;
        final z = _camZ + 1.5 + 1400 * t * t;
        _proj(x, 0.02, z, _p);
        pts.add(Offset(_p[0], _p[1]));
      }
      return pts;
    }

    final left = edge(-7.0);
    final right = edge(7.0);
    final roadPath = Path()..moveTo(right.first.dx, right.first.dy);
    for (final p in right.skip(1)) {
      roadPath.lineTo(p.dx, p.dy);
    }
    for (final p in left.reversed) {
      roadPath.lineTo(p.dx, p.dy);
    }
    roadPath.close();
    final roadRect = roadPath.getBounds();
    canvas.drawPath(
      roadPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _mix(const Color(0xFF8A6A55), _haze, 0.35),
            const Color(0xFF6B5546),
            const Color(0xFF4E3E34),
          ],
          stops: const [0, 0.35, 1],
        ).createShader(roadRect),
    );

    // 路缘石（左右各一条，随透视收窄）
    for (final sx in <double>[-1, 1]) {
      final a = edge(sx * 7.0);
      final b = edge(sx * 7.45);
      final p = Path()..moveTo(a.first.dx, a.first.dy);
      for (final q in a.skip(1)) {
        p.lineTo(q.dx, q.dy);
      }
      for (final q in b.reversed) {
        p.lineTo(q.dx, q.dy);
      }
      p.close();
      canvas.drawPath(
        p,
        Paint()..color = _mix(const Color(0xFFB09070), _haze, 0.25),
      );
    }
    // v1.6.4：删除「夕阳反光带」—— 那是旧版（Citro web 版）的元素，
    // 原始 three.js 场景没有，正是用户看到的「中间这么大的光团」。
    // 标线：用投影折线逐段描边（薄四边形在极端透视下会被 Skia 丢面）
    // 边线：与路面同一套「整条多边形」画法，保证可见
    void line(double x, Color c) {
      canvas.drawPath(_worldStrip(x, 0.04, 0.24), Paint()..color = c);
    }

    line(-5.4, _mix(const Color(0xFFFBF7EC), _haze, 0.12));
    line(5.4, _mix(const Color(0xFFFBF7EC), _haze, 0.12));
    line(-6.6, _mix(const Color(0xFFFFD75E), _haze, 0.12));
    line(6.6, _mix(const Color(0xFFFFD75E), _haze, 0.12));
    // 车道虚线（±1.8，6 划 6 空）
    final z0 = (((_camZ + 6.2) / 12).floor() * 12).toDouble();
    for (var zz = z0; zz < _camZ + 400; zz += 12) {
      if (zz < _camZ + 6.2) continue;
      for (var dx = -1; dx <= 1; dx += 2) {
        _laneSegment(
          canvas,
          dx * 1.8,
          0.5,
          zz,
          zz + 6.0,
          const Color(0xFFFBF7EC),
        );
      }
    }
  }

  /// 沿 z 轴的一条定宽长条（近密远疏采样），与路面同一套画法。
  Path _worldStrip(double x, double y, double halfW) {
    const n = 24;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final z = _camZ + 1.5 + 1400 * t * t;
      _proj(x - halfW, y, z, _p);
      left.add(Offset(_p[0], _p[1]));
      _proj(x + halfW, y, z, _q);
      right.add(Offset(_q[0], _q[1]));
    }
    final p = Path()..moveTo(right.first.dx, right.first.dy);
    for (final q in right.skip(1)) {
      p.lineTo(q.dx, q.dy);
    }
    for (final q in left.reversed) {
      p.lineTo(q.dx, q.dy);
    }
    return p..close();
  }

  void _laneSegment(
    Canvas canvas,
    double wx,
    double width,
    double z0,
    double z1,
    Color color,
  ) {
    _proj(wx, 0.03, z0, _p);
    _proj(wx, 0.03, z1, _q);
    if (_p[2] <= 1.0 || _q[2] <= 1.0) return;
    final d0 = _p[2], d1 = _q[2];
    if (d0 > 1600 && d1 > 1600) return;
    final f0 = _fogT(z0), f1 = _fogT(z1);
    final c0 = _mix(color, _haze, f0);
    final c1 = _mix(color, _haze, f1);
    // v1.6.4：用四边形画线；细线在透视下只剩亚像素宽会被丢弃，
    // 因此设世界宽度下限保证可见。
    final half = math.max(0.26, width / 2);
    _face(
      canvas,
      wx - half,
      0.035,
      z0,
      wx + half,
      0.035,
      z0,
      wx + half,
      0.035,
      z1,
      wx - half,
      0.035,
      z1,
      c1,
    );
    if (d0 < 220) {
      _face(
        canvas,
        wx - half,
        0.036,
        z0,
        wx + half,
        0.036,
        z0,
        wx + half,
        0.036,
        (z0 + z1) / 2,
        wx - half,
        0.036,
        (z0 + z1) / 2,
        c0,
      );
    }
  }

  // ---------- 路灯 / 指路牌 ----------

  void _drawRoadside(Canvas canvas, double W) {
    // v1.6.1：灯杆/灯头加大一档（间距保持 web 的 45m，30m 时近灯光晕会
    // 连成蝴蝶状光斑）。
    final base = (((_camZ - 45) / 45).floor() * 45).toDouble();
    for (var z = base; z < _camZ + 900; z += 45) {
      for (var side = -1; side <= 1; side += 2) {
        if (z < _camZ - 10) continue;
        final pz = z + (side > 0 ? 22.5 : 0.0);
        if (pz < _camZ - 10) continue;
        final x = side * 9.2;
        final pf = _fogT(pz);
        final cPole = _mix(const Color(0xFF3A3D42), _haze, pf);
        // web 原值：杆宽 0.22、灯头宽 0.9、y 8.79-8.91
        _quad(
          canvas,
          x - 0.11,
          0,
          pz,
          x + 0.11,
          0,
          pz,
          x + 0.11,
          8.95,
          pz,
          x - 0.11,
          8.95,
          pz,
          cPole,
        );
        _quad(
          canvas,
          x,
          8.85,
          pz - 0.05,
          x - side * 2.4,
          8.85,
          pz - 0.05,
          x - side * 2.4,
          8.95,
          pz + 0.05,
          x,
          8.95,
          pz + 0.05,
          cPole,
        );
        final lx = x - side * 2.1;
        _quad(
          canvas,
          lx - 0.45,
          8.79,
          pz,
          lx + 0.45,
          8.79,
          pz,
          lx + 0.45,
          8.91,
          pz,
          lx - 0.45,
          8.91,
          pz,
          _mix(const Color(0xFFFFC58A), _haze, pf * 0.6),
        );
        if (pz - _camZ < 420) {
          _proj(lx, 8.85, pz, _p);
          // v1.6.4：光晕半径封顶 22px、只画 180m 内 —— 原版远处路灯只有
          // 一颗小亮点；旧实现 92px 的光晕在消失点连成一片亮团
          //（用户截图里「中间这么大的光团」正是它）。
          final rr = math.max(2.0, _p[2] * 0.055);
          final gr = math.min(rr * 4, 22.0);
          final nearLamp = pz - _camZ < 180;
          if (nearLamp) {
            canvas.drawCircle(
              Offset(_p[0], _p[1]),
              gr,
              Paint()
                ..shader =
                    RadialGradient(
                      colors: const [
                        Color(0xD9FFECC8),
                        Color(0x59FFD096),
                        Color(0x00FFC58A),
                      ],
                      stops: const [0, 0.24, 1],
                    ).createShader(
                      Rect.fromCircle(center: Offset(_p[0], _p[1]), radius: gr),
                    ),
            );
          } else {
            canvas.drawCircle(
              Offset(_p[0], _p[1]),
              math.max(1.1, rr * 0.22),
              Paint()..color = const Color(0xCCFFE3B4),
            );
          }
          if (pz - _camZ < 160) {
            _proj(lx, 0.04, pz, _p);
            _proj(lx + 3.2, 0.04, pz, _q);
            final prx = (_q[0] - _p[0]).abs();
            if (prx > 1.5) {
              canvas.save();
              canvas.translate(_p[0], _p[1]);
              canvas.scale(prx, prx * 0.26);
              canvas.drawCircle(
                Offset.zero,
                1,
                Paint()
                  ..shader = const RadialGradient(
                    colors: [
                      Color(0x4DFFD896),
                      Color(0x1FFFCE8C),
                      Color(0x00FFC58A),
                    ],
                    stops: [0, 0.55, 1],
                  ).createShader(const Rect.fromLTWH(-1, -1, 2, 2)),
              );
              canvas.restore();
            }
          }
        }
      }
    }
    _drawSigns(canvas);
  }

  /// v1.6.1 新增：路肩两侧的树剪影（每 ~70m 一棵，椭圆冠 + 短杆），
  /// 位置用 hash 抖动，远景雾化 —— 补足「景观感」。
  static const List<List<dynamic>> _signs = [
    // z, side, bg, fg, l1, l2
    [1100, 1, Color(0xFF0F6B3A), Color(0xFFFFFFFF), '前方施工', '1500 m'],
    [1600, 1, Color(0xFF0F6B3A), Color(0xFFFFFFFF), '前方施工', '1000 m'],
    [2100, 1, Color(0xFF0F6B3A), Color(0xFFFFFFFF), '前方施工', '500 m'],
    [2300, 1, Color(0xFFF2B21B), Color(0xFF1A1A1A), '道路封闭', '300 m'],
    [2400, 1, Color(0xFFF2B21B), Color(0xFF1A1A1A), '道路封闭', '200 m'],
    [2500, 1, Color(0xFFF2B21B), Color(0xFF1A1A1A), '道路封闭', '100 m'],
    [80, -1, Color(0xFF14325C), Color(0xFFFFFFFF), '极限刹车挑战', '100 km/h 后可刹车'],
  ];

  void _drawSigns(Canvas canvas) {
    for (final sg in _signs) {
      final sz = (sg[0] as num).toDouble();
      final side = (sg[1] as num).toDouble();
      final d = sz - _camZ;
      if (d < 24 || d > 880) continue;
      final x = side * 10.2;
      const y0 = 3.2, y1 = 5.2, bw = 4.0;
      final st = _fogT(sz);
      final cPole = _mix(const Color(0xFF8A8278), _haze, st);
      _quad(
        canvas,
        x + 1.4,
        y0 - 3.2,
        sz,
        x + 1.7,
        y0 - 3.2,
        sz,
        x + 1.7,
        y0,
        sz,
        x + 1.4,
        y0,
        sz,
        cPole,
      );
      _quad(
        canvas,
        x + bw - 1.7,
        y0 - 3.2,
        sz,
        x + bw - 1.4,
        y0 - 3.2,
        sz,
        x + bw - 1.4,
        y0,
        sz,
        x + bw - 1.7,
        y0,
        sz,
        cPole,
      );
      _proj(x, y0, sz, _p);
      _proj(x + bw, y1, sz, _q);
      final sx = math.min(_p[0], _q[0]);
      final sy = math.min(_p[1], _q[1]);
      final sw = (_q[0] - _p[0]).abs();
      final sh = (_q[1] - _p[1]).abs();
      if (sw < 10) continue;
      canvas.drawRect(
        Rect.fromLTRB(sx, sy, sx + sw, sy + sh),
        Paint()..color = _mix(sg[2] as Color, _haze, st * 0.5),
      );
      canvas.drawRect(
        Rect.fromLTRB(
          sx + sw * 0.035,
          sy + sh * 0.07,
          sx + sw * 0.965,
          sy + sh * 0.93,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, sw * 0.02)
          ..color = _mix(sg[3] as Color, _haze, st * 0.5),
      );
      if (sw > 56) {
        _paintCentered(
          canvas,
          sg[4] as String,
          Offset(sx + sw / 2, sy + sh * 0.32),
          sh * 0.30,
          FontWeight.w700,
          _mix(sg[3] as Color, _haze, st * 0.35),
        );
        _paintCentered(
          canvas,
          sg[5] as String,
          Offset(sx + sw / 2, sy + sh * 0.70),
          sh * 0.26,
          FontWeight.w600,
          _mix(sg[3] as Color, _haze, st * 0.35),
        );
      }
    }
  }

  // ---------- 护栏 ----------

  void _drawGuardrails(Canvas canvas, double W) {
    // v1.6.5：护栏是道路轮廓的核心，改为两条整条多边形带（上沿带受光高光），
    // 从近处一直延伸到消失点，清晰可辨。
    for (final sd in <double>[-1, 1]) {
      // 贴着黄边线外沿（6.6 + 0.75），保证在追尾视角里也能看到两道护栏
      final x = sd * 7.35;
      List<Offset> band(double y) {
        const n = 22;
        final pts = <Offset>[];
        for (var i = 0; i <= n; i++) {
          final t = i / n;
          final z = _camZ + 1.2 + 700 * t * t;
          _proj(x, y, z, _p);
          pts.add(Offset(_p[0], _p[1]));
        }
        return pts;
      }

      final lo = band(0.55);
      final hi = band(1.15);
      final p = Path()..moveTo(hi.first.dx, hi.first.dy);
      for (final q in hi.skip(1)) {
        p.lineTo(q.dx, q.dy);
      }
      for (final q in lo.reversed) {
        p.lineTo(q.dx, q.dy);
      }
      p.close();
      canvas.drawPath(
        p,
        Paint()..color = _mix(const Color(0xFFD5DAE2), _haze, 0.28),
      );
      // 受光顶沿
      final t0 = band(0.885);
      final t1 = band(0.925);
      final hp = Path()..moveTo(t1.first.dx, t1.first.dy);
      for (final q in t1.skip(1)) {
        hp.lineTo(q.dx, q.dy);
      }
      for (final q in t0.reversed) {
        hp.lineTo(q.dx, q.dy);
      }
      hp.close();
      canvas.drawPath(
        hp,
        Paint()..color = _mix(const Color(0xFFF7E7C8), _haze, 0.20),
      );
    }
    _drawGuardrailPosts(canvas);
  }

  void _drawGuardrailPosts(Canvas canvas) {
    // 立柱（200m 内，每 4m）
    final pbase = (((_camZ - 4) / 4).floor() * 4).toDouble();
    for (var gz = pbase; gz < _camZ + 200; gz += 4) {
      if (gz < _camZ + 1) continue;
      final pf = _fogT(gz);
      final cP = _mix(const Color(0xFF8B9096), _haze, pf);
      final cPE = _mix(const Color(0xFFB9BEC6), _haze, pf);
      for (var sd = -1; sd <= 1; sd += 2) {
        _quad(
          canvas,
          sd * 8.26,
          0,
          gz,
          sd * 8.14,
          0,
          gz,
          sd * 8.14,
          0.62,
          gz,
          sd * 8.26,
          0.62,
          gz,
          cP,
        );
        _quad(
          canvas,
          sd * 8.14,
          0,
          gz,
          sd * 8.10,
          0,
          gz,
          sd * 8.10,
          0.62,
          gz,
          sd * 8.14,
          0.62,
          gz,
          cPE,
        );
      }
    }
  }

  // ---------- 路障 ----------

  void _drawBarrier(Canvas canvas) {
    const z = gbTrack;
    final st = _fogT(z);
    // v1.6.5：路障要「全程可见」——原版是真实几何 + 雾化，近处才看得清；
    // 这里近距离照常画水马 + 警示牌，远距离再叠一条高亮色带保证可见。
    if (z - _camZ < 1) return;
    final far = z - _camZ > 420;
    final cOr = _mix(const Color(0xFFE8501B), _haze, st);
    final cWh = _mix(const Color(0xFFFFFFFF), _haze, st);
    final cSide = _mix(const Color(0xFFB9B2A8), _haze, st);
    final cTop = _mix(const Color(0xFFC8C1B6), _haze, st);
    for (var bx = -6.0; bx <= 6; bx += 2) {
      _face(
        canvas,
        bx - 0.95,
        1,
        z,
        bx + 0.95,
        1,
        z,
        bx + 0.95,
        1,
        z + 0.7,
        bx - 0.95,
        1,
        z + 0.7,
        cTop,
      );
      if (bx == -6) {
        _face(
          canvas,
          bx - 0.95,
          0,
          z,
          bx - 0.95,
          0,
          z,
          bx - 0.95,
          1,
          z + 0.7,
          bx - 0.95,
          1,
          z + 0.7,
          cSide,
        );
      }
      if (bx == 6) {
        _face(
          canvas,
          bx + 0.95,
          0,
          z,
          bx + 0.95,
          0,
          z,
          bx + 0.95,
          1,
          z + 0.7,
          bx + 0.95,
          1,
          z + 0.7,
          cSide,
        );
      }
      _face(
        canvas,
        bx - 0.95,
        0,
        z,
        bx + 0.95,
        0,
        z,
        bx + 0.95,
        1,
        z,
        bx - 0.95,
        1,
        z,
        cOr,
      );
      for (var i = 0; i < 4; i++) {
        final p = bx - 0.95 + i * 0.475;
        _face(
          canvas,
          p,
          0,
          z,
          p + 0.2375,
          0,
          z,
          p + 0.475,
          1,
          z,
          p + 0.2375,
          1,
          z,
          cWh,
        );
      }
    }
    // 大警示板 + 立柱
    final cRed = _mix(const Color(0xFFD8351B), _haze, st);
    final cFg = _mix(const Color(0xFFFFFFFF), _haze, st * 0.5);
    final cPost = _mix(const Color(0xFF555A60), _haze, st);
    _face(
      canvas,
      -4.3,
      0,
      z + 3,
      -4.1,
      0,
      z + 3,
      -4.1,
      4.5,
      z + 3,
      -4.3,
      4.5,
      z + 3,
      cPost,
    );
    _face(
      canvas,
      4.1,
      0,
      z + 3,
      4.3,
      0,
      z + 3,
      4.3,
      4.5,
      z + 3,
      4.1,
      4.5,
      z + 3,
      cPost,
    );
    _face(
      canvas,
      -4.5,
      2.3,
      z + 3,
      4.5,
      2.3,
      z + 3,
      4.5,
      4.5,
      z + 3,
      -4.5,
      4.5,
      z + 3,
      cRed,
    );
    _proj(-4.5, 2.3, z + 3, _p);
    _proj(4.5, 4.5, z + 3, _q);
    final sx = math.min(_p[0], _q[0]);
    final sy = math.min(_p[1], _q[1]);
    final sw = (_q[0] - _p[0]).abs();
    final sh = (_q[1] - _p[1]).abs();
    if (sw > 14) {
      canvas.drawRect(
        Rect.fromLTRB(
          sx + sw * 0.03,
          sy + sh * 0.10,
          sx + sw * 0.97,
          sy + sh * 0.90,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, sw * 0.012)
          ..color = cFg,
      );
      if (sw > 120) {
        _paintCentered(
          canvas,
          '道路封闭 ROAD CLOSED',
          Offset(sx + sw / 2, sy + sh * 0.5),
          sh * 0.34,
          FontWeight.w700,
          cFg,
        );
      }
    }
    // v1.6.5：远距离高亮 —— 起步 2600 m 外也能看见橙红色路障带 + 呼吸灯
    if (far) {
      _proj(-6.5, 0.0, z, _p);
      _proj(6.5, 1.35, z, _q);
      final bwRaw = (_q[0] - _p[0]).abs();
      final bh = (_p[1] - _q[1]).abs();
      // 远处只有几像素宽也要能看见 → 保底 30px 宽
      final bw = math.max(30.0, bwRaw);
      final cx0 = (_p[0] + _q[0]) / 2;
      final bx0 = cx0 - bw / 2;
      final by0 = math.min(_p[1], _q[1]);
      if (bwRaw >= 0) {
        canvas.drawRect(
          Rect.fromLTWH(bx0, by0, bw, math.max(5.0, bh)),
          Paint()..color = const Color(0xF2E8501B),
        );
        canvas.drawRect(
          Rect.fromLTWH(bx0, by0, bw, math.max(2.0, bh * 0.30)),
          Paint()..color = const Color(0xD9F5EFE6),
        );
        final blink = 0.45 + 0.55 * math.sin(w.time * 6).abs();
        _proj(0, 1.7, z, _p);
        canvas.drawCircle(
          Offset(_p[0], _p[1]),
          math.max(2.0, bw * 0.05),
          Paint()..color = Color.fromRGBO(255, 92, 40, 0.60 * blink),
        );
      }
    }
  }

  // ---------- 烟尘 / 火花 / 速度线 ----------

  void _drawSmoke(Canvas canvas) {
    for (final s in w.smoke) {
      _proj(s.x, s.y, s.z, _p);
      final rr = math.max(1.0, s.r * _focal / _p[2]);
      canvas.drawCircle(
        Offset(_p[0], _p[1]),
        rr,
        Paint()..color = Color.fromRGBO(196, 186, 176, s.a.clamp(0.0, 1.0)),
      );
    }
  }

  void _drawSparks(Canvas canvas) {
    if (w.sparks.isEmpty) return;
    for (final s in w.sparks) {
      _proj(s.x, s.y, s.z, _p);
      if (_p[2] <= 0.1) continue;
      final lifek = 1 - s.t / s.ml;
      final sr = math.max(0.8, _focal / _p[2] * 0.02 * (0.5 + lifek * 0.5));
      canvas.drawCircle(
        Offset(_p[0], _p[1]),
        sr,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = Color.fromRGBO(
            255,
            (150 + 90 * lifek).round(),
            70,
            0.75 * lifek,
          ),
      );
    }
  }

  void _drawSpeedLines(Canvas canvas, double W, double H) {
    final sp = math.min(1, w.rv / gbVref);
    if (sp <= 0.35) return;
    final k = (sp - 0.35) / 0.65;
    _proj(0, 1.2, _camZ + 90, _p);
    final paint = Paint()
      ..color = Color.fromRGBO(244, 228, 200, k * k * 0.30)
      ..strokeWidth = 1.0;
    final frame = (w.time * 6).floorToDouble();
    for (var li = 0; li < 12; li++) {
      final ang = _hash(li * 7.3 + frame) * math.pi * 2;
      final rr3 = 0.26 + _hash(li * 3.9) * 0.5;
      final rr4 = rr3 + 0.05 + k * 0.09;
      canvas.drawLine(
        Offset(
          _p[0] + math.cos(ang) * rr3 * W,
          _p[1] + math.sin(ang) * rr3 * H * 0.7,
        ),
        Offset(
          _p[0] + math.cos(ang) * rr4 * W,
          _p[1] + math.sin(ang) * rr4 * H * 0.7,
        ),
        paint,
      );
    }
  }

  void _drawVignette(Canvas canvas, double W, double H) {
    // web：中心 (W/2, H*0.52)，r0 = min*0.30 → r1 = max*0.72，透明 → rgba(20,8,4,.34)
    final center = Offset(W / 2, H * 0.52);
    final r1 = math.max(W, H) * 0.72;
    final r0 = math.min(W, H) * 0.30;
    final t0 = (r0 / r1).clamp(0.0, 0.99);
    canvas.drawRect(
      Offset.zero & Size(W, H),
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0x00000000), Color(0x57140804)],
          stops: [t0, 1],
        ).createShader(Rect.fromCircle(center: center, radius: r1)),
    );
  }

  // ---------- 车辆 ----------

  // 面片表（web GB_CARQ）：12 坐标 + 颜色索引 + amb + dif
  static const List<Color> _carCols = [
    Color(0xFF191A20), // 黑漆
    Color(0xFFD8C6A0), // 金漆
    Color(0xFF171B21), // 玻璃
    Color(0xFFCFCCC4), // 镀铬
    Color(0xFF3A3A3C), // 饰条
  ];
  static const List<List<double>> _carQ = [
    // 车身下半
    [
      -0.98,
      0.30,
      -2.50,
      0.98,
      0.30,
      -2.50,
      0.98,
      1.06,
      -2.50,
      -0.98,
      1.06,
      -2.50,
      0,
      0.40,
      0.60,
    ],
    [
      -0.90,
      0.30,
      2.50,
      0.90,
      0.30,
      2.50,
      0.90,
      1.05,
      2.50,
      -0.90,
      1.05,
      2.50,
      0,
      0.40,
      0.60,
    ],
    [
      -0.98,
      1.06,
      -2.50,
      0.98,
      1.06,
      -2.50,
      0.90,
      1.05,
      2.50,
      -0.90,
      1.05,
      2.50,
      1,
      0.46,
      0.54,
    ],
    [
      -0.98,
      0.30,
      -2.50,
      -0.98,
      1.06,
      -2.50,
      -0.90,
      1.05,
      2.50,
      -0.90,
      0.30,
      2.50,
      0,
      0.34,
      0.66,
    ],
    [
      0.98,
      0.30,
      -2.50,
      0.98,
      1.06,
      -2.50,
      0.90,
      1.05,
      2.50,
      0.90,
      0.30,
      2.50,
      0,
      0.34,
      0.66,
    ],
    // 座舱
    [
      -0.86,
      1.06,
      -2.50,
      0.86,
      1.06,
      -2.50,
      0.80,
      1.80,
      -2.40,
      -0.80,
      1.80,
      -2.40,
      2,
      0.34,
      0.30,
    ],
    [
      -0.86,
      1.06,
      -2.50,
      -0.98,
      1.06,
      -2.50,
      -0.94,
      1.80,
      -2.40,
      -0.80,
      1.80,
      -2.40,
      1,
      0.40,
      0.60,
    ],
    [
      0.86,
      1.06,
      -2.50,
      0.98,
      1.06,
      -2.50,
      0.94,
      1.80,
      -2.40,
      0.80,
      1.80,
      -2.40,
      1,
      0.40,
      0.60,
    ],
    [
      -0.84,
      1.82,
      -2.42,
      0.84,
      1.82,
      -2.42,
      0.84,
      1.82,
      1.60,
      -0.84,
      1.82,
      1.60,
      1,
      0.48,
      0.52,
    ],
    [
      0.84,
      1.82,
      1.60,
      -0.84,
      1.82,
      1.60,
      -0.92,
      1.06,
      2.30,
      0.92,
      1.06,
      2.30,
      2,
      0.34,
      0.30,
    ],
    [
      -0.99,
      1.06,
      -2.48,
      -0.84,
      1.80,
      -2.40,
      -0.84,
      1.82,
      1.58,
      -0.99,
      1.06,
      2.28,
      2,
      0.34,
      0.30,
    ],
    [
      0.99,
      1.06,
      -2.48,
      0.84,
      1.80,
      -2.40,
      0.84,
      1.82,
      1.58,
      0.99,
      1.06,
      2.28,
      2,
      0.34,
      0.30,
    ],
    // 行李架导轨
    [
      -0.88,
      1.82,
      -2.36,
      -0.74,
      1.82,
      -2.36,
      -0.74,
      1.87,
      1.52,
      -0.88,
      1.87,
      1.52,
      3,
      0.46,
      0.52,
    ],
    [
      0.74,
      1.82,
      -2.36,
      0.88,
      1.82,
      -2.36,
      0.88,
      1.87,
      1.52,
      0.74,
      1.87,
      1.52,
      3,
      0.46,
      0.52,
    ],
    // 鲨鱼鳍天线
    [
      -0.08,
      1.82,
      -2.30,
      0.08,
      1.82,
      -2.30,
      0.08,
      2.00,
      -1.84,
      -0.08,
      2.00,
      -1.84,
      4,
      0.48,
      0.52,
    ],
    // 外后视镜
    [
      -1.22,
      1.10,
      0.92,
      -0.98,
      1.10,
      0.92,
      -0.98,
      1.28,
      1.24,
      -1.22,
      1.28,
      1.24,
      4,
      0.36,
      0.54,
    ],
    [
      0.98,
      1.10,
      0.92,
      1.22,
      1.10,
      0.92,
      1.22,
      1.28,
      1.24,
      0.98,
      1.28,
      1.24,
      4,
      0.36,
      0.54,
    ],
    // 后包围 + 镀铬饰条
    [
      -0.94,
      0.30,
      -2.53,
      0.94,
      0.30,
      -2.53,
      0.94,
      0.62,
      -2.53,
      -0.94,
      0.62,
      -2.53,
      4,
      0.36,
      0.48,
    ],
    [
      -0.92,
      0.30,
      -2.55,
      0.92,
      0.30,
      -2.55,
      0.92,
      0.40,
      -2.55,
      -0.92,
      0.40,
      -2.55,
      3,
      0.56,
      0.36,
    ],
  ];

  void _drawCar(Canvas canvas, double W, double H) {
    const cs = 1.082, cw = 1.01; // 原站车长 5.41 / 宽 1.99
    final cr = math.cos(w.roll), sr = math.sin(w.roll);
    final cyw = math.cos(w.yaw), syw = math.sin(w.yaw);
    final faces = <_CarFace>[];
    for (final q in _carQ) {
      final pts = <Offset>[];
      var d = 0.0;
      for (var j = 0; j < 4; j++) {
        final px = q[j * 3] * cw, py = q[j * 3 + 1], pz = q[j * 3 + 2] * cs;
        final X = px * cr - py * sr, Y = px * sr + py * cr;
        final X2 = X * cyw + pz * syw, Z2 = -X * syw + pz * cyw;
        _proj(X2 + w.carX, Y + w.carY, Z2 + w.rz, _p);
        pts.add(Offset(_p[0], _p[1]));
        d += _p[2];
      }
      // 顶点叉积法线（车身局部坐标），翻到朝外
      final ax = q[3] - q[0], ay = q[4] - q[1], az = q[5] - q[2];
      final bx = q[6] - q[0], by = q[7] - q[1], bz = q[8] - q[2];
      var nx = ay * bz - az * by;
      var ny = az * bx - ax * bz;
      var nz = ax * by - ay * bx;
      final ln = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (ln > 0) {
        nx /= ln;
        ny /= ln;
        nz /= ln;
      }
      final mx = (q[0] + q[3] + q[6] + q[9]) / 4;
      final my = (q[1] + q[4] + q[7] + q[10]) / 4 - 0.86;
      final mz = (q[2] + q[5] + q[8] + q[11]) / 4;
      if (nx * mx + ny * my + nz * mz < 0) {
        nx = -nx;
        ny = -ny;
        nz = -nz;
      }
      final rnx = nx * cr - ny * sr, rny = nx * sr + ny * cr;
      final fnx = rnx * cyw + nz * syw, fnz = -rnx * syw + nz * cyw;
      final dl = _Lx * fnx + _Ly * rny + _Lz * fnz;
      final k = q[13] + q[14] * (dl < 0 ? 0 : dl);
      faces.add(
        _CarFace(
          pts: pts,
          d: d / 4,
          colIdx: q[12].round(),
          k: k,
          glass: q[12] == 2,
        ),
      );
    }
    // 车轮
    const wheels = [
      [-0.89, -1.58],
      [0.89, -1.58],
      [-0.89, 1.62],
      [0.89, 1.62],
    ];
    for (final wl in wheels) {
      final wx = wl[0], wz = wl[1];
      final WX = wx * cr - 0.42 * sr, WY = wx * sr + 0.42 * cr;
      final WX2 = WX * cyw + wz * syw, WZ2 = -WX * syw + wz * cyw;
      _proj(WX2 + w.carX, WY + w.carY, WZ2 + w.rz, _p);
      final cx = _p[0], cyy = _p[1], dep = _p[2];
      _proj(WX2 + w.carX + 0.14, WY + w.carY, WZ2 + w.rz, _q);
      _proj(WX2 + w.carX, WY + 0.42 + w.carY, WZ2 + w.rz, _p);
      var rx = (_q[0] - cx).abs();
      var ry = (_p[1] - cyy).abs();
      if (rx < 0.8) rx = 0.8;
      if (ry < 0.8) ry = 0.8;
      faces.add(
        _CarFace(
          pts: const [],
          d: dep - 0.01,
          colIdx: 0,
          k: 0,
          glass: false,
          wx: cx,
          wy: cyy,
          wrx: rx,
          wry: ry,
        ),
      );
    }
    faces.sort((a, b) => b.d.compareTo(a.d));
    for (final f in faces) {
      if (f.wheel) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(f.wx!, f.wy!),
            width: f.wrx! * 2,
            height: f.wry! * 2,
          ),
          Paint()..color = const Color(0xFF14171C),
        );
        if (f.wrx! > 4) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(f.wx!, f.wy!),
              width: f.wrx!,
              height: f.wry! * 1.24,
            ),
            Paint()..color = const Color(0xFF3E444C),
          );
        }
        continue;
      }
      final path = Path()
        ..moveTo(f.pts[0].dx, f.pts[0].dy)
        ..lineTo(f.pts[1].dx, f.pts[1].dy)
        ..lineTo(f.pts[2].dx, f.pts[2].dy)
        ..lineTo(f.pts[3].dx, f.pts[3].dy)
        ..close();
      Paint paint;
      if (f.glass) {
        var gy0 = f.pts[0].dy, gy1 = f.pts[0].dy;
        for (final p in f.pts) {
          gy0 = math.min(gy0, p.dy);
          gy1 = math.max(gy1, p.dy);
        }
        if (gy1 - gy0 < 1.2) gy1 = gy0 + 1.2;
        paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xF5586C86),
              Color(0xF71E2734),
              Color(0xFC090C12),
            ],
            stops: const [0, 0.32, 1],
          ).createShader(Rect.fromLTRB(0, gy0, 0 + 1, gy1));
      } else {
        final cc = _carCols[f.colIdx];
        final k1 = math.min(1.5, f.k * 1.20);
        final k2 = f.k * 0.78;
        final top = Color.fromRGBO(
          (cc.r * k1).clamp(0, 255).round(),
          (cc.g * k1).clamp(0, 255).round(),
          (cc.b * k1).clamp(0, 255).round(),
          1,
        );
        final bot = Color.fromRGBO(
          (cc.r * k2).clamp(0, 255).round(),
          (cc.g * k2).clamp(0, 255).round(),
          (cc.b * k2).clamp(0, 255).round(),
          1,
        );
        var gy0 = f.pts[0].dy, gy1 = f.pts[0].dy;
        for (final p in f.pts) {
          gy0 = math.min(gy0, p.dy);
          gy1 = math.max(gy1, p.dy);
        }
        if (gy1 - gy0 < 1.2) gy1 = gy0 + 1.2;
        paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bot],
          ).createShader(Rect.fromLTRB(0, gy0, 0 + 1, gy1));
      }
      // 同色描边盖掉相邻面共边的 1px 亮缝
      canvas.drawPath(path, paint);
      if (paint.shader != null) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9
            ..shader = paint.shader,
        );
      }
    }
    // 尾灯：横带 + 两侧竖条（⊓）
    final brakeLit = w.pressed || w.force > 60;
    final lz = w.rz - 2.71;
    final litC = brakeLit ? const Color(0xFFFF6A42) : const Color(0xFFF9562F);
    void litRect(double x0, double x1, double y0, double y1) {
      _proj(x0, y0, lz, _p);
      _proj(x1, y0, lz, _q);
      _proj(x1, y1, lz, _p2);
      _proj(x0, y1, lz, _q2);
      final p = Path()
        ..moveTo(_p[0], _p[1])
        ..lineTo(_q[0], _q[1])
        ..lineTo(_p2[0], _p2[1])
        ..lineTo(_q2[0], _q2[1])
        ..close();
      canvas.drawPath(
        p,
        Paint()
          ..color = litC
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, brakeLit ? 9 : 5),
      );
      canvas.drawPath(p, Paint()..color = litC);
    }

    litRect(-0.90, 0.90, 1.00, 1.03);
    litRect(-0.93, -0.87, 0.64, 1.00);
    litRect(0.87, 0.93, 0.64, 1.00);
    // 新能源绿牌
    _proj(-0.24, 0.60, lz + 0.015, _p);
    _proj(0.24, 0.60, lz + 0.015, _q);
    final pw = (_q[0] - _p[0]).abs();
    if (pw > 2.5) {
      final ph = pw * 0.3125;
      final rect = Rect.fromLTWH(_p[0], _p[1] - ph / 2, pw, ph);
      canvas.drawRect(rect, Paint()..color = const Color(0xFF2E9E52));
      if (pw > 24) {
        _paintCentered(
          canvas,
          '沪A·D1612F',
          rect.center,
          ph * 0.60,
          FontWeight.w600,
          const Color(0xFFF4F8F4),
        );
      }
    }
    // 地面投影
    _proj(-1.15, 0.03, w.rz - 2.705, _p);
    _proj(1.15, 0.03, w.rz + 2.705, _q);
    final sw = (_q[0] - _p[0]).abs();
    final scx = (_p[0] + _q[0]) / 2;
    final scy = (_p[1] + _q[1]) / 2;
    if (sw > 2) {
      canvas.save();
      canvas.translate(scx, scy);
      canvas.scale(1, 0.34);
      canvas.drawCircle(
        Offset.zero,
        sw * 0.62,
        Paint()
          ..shader = RadialGradient(
            colors: const [
              Color(0x9E000000),
              Color(0x4D000000),
              Color(0x00000000),
            ],
            stops: const [0, 0.6, 1],
          ).createShader(const Rect.fromLTWH(-1, -1, 2, 2)),
      );
      canvas.restore();
    }
    // 刹车时尾灯在路面的反光
    if (brakeLit) {
      _proj(0, 0.035, w.rz - 2.95, _p);
      _proj(1.3, 0.035, w.rz - 2.95, _q);
      final srx = (_q[0] - _p[0]).abs();
      if (srx > 3) {
        canvas.save();
        canvas.translate(_p[0], _p[1]);
        canvas.scale(srx, srx * 0.30);
        canvas.drawCircle(
          Offset.zero,
          1,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = const RadialGradient(
              colors: [Color(0x57FF4228), Color(0x1FFF3C24), Color(0x00FF3C24)],
              stops: [0, 0.6, 1],
            ).createShader(const Rect.fromLTWH(-1, -1, 2, 2)),
        );
        canvas.restore();
      }
    }
    // 夕阳轮廓光（尾面棱线）
    const rimE = [
      [-0.86, 1.068, -2.508, 0.86, 1.068, -2.508, 0.42],
      [-0.84, 1.832, -2.42, 0.84, 1.832, -2.42, 0.95],
      [-0.982, 0.34, -2.52, -0.982, 1.05, -2.52, 0.30],
      [0.982, 0.34, -2.52, 0.982, 1.05, -2.52, 0.50],
      [-0.86, 1.80, -2.415, 0.86, 1.80, -2.415, 0.55],
    ];
    for (final e in rimE) {
      final exx = e[0] * cw, eyy = e[1], ezz = e[2] * cs;
      final X = exx * cr - eyy * sr, Y = exx * sr + eyy * cr;
      final X2 = X * cyw + ezz * syw, Z2 = -X * syw + ezz * cyw;
      _proj(X2 + w.carX, Y + w.carY, Z2 + w.rz, _p);
      final exx2 = e[3] * cw, eyy2 = e[4], ezz2 = e[5] * cs;
      final Xb = exx2 * cr - eyy2 * sr, Yb = exx2 * sr + eyy2 * cr;
      final X2b = Xb * cyw + ezz2 * syw, Z2b = -Xb * syw + ezz2 * cyw;
      _proj(X2b + w.carX, Yb + w.carY, Z2b + w.rz, _q);
      final ez = (_p[2] + _q[2]) / 2;
      final rlw = math.max(0.7, _focal / ez * 0.016);
      final ra = e[6];
      canvas.drawLine(
        Offset(_p[0], _p[1]),
        Offset(_q[0], _q[1]),
        Paint()
          ..blendMode = BlendMode.plus
          ..strokeWidth = rlw * 3.2
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(255, 206, 138, (ra * 0.30).clamp(0.0, 1.0)),
      );
      canvas.drawLine(
        Offset(_p[0], _p[1]),
        Offset(_q[0], _q[1]),
        Paint()
          ..blendMode = BlendMode.plus
          ..strokeWidth = rlw
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(255, 228, 178, ra.clamp(0.0, 1.0)),
      );
    }
  }

  // ---------- 文本 ----------

  void _paintCentered(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    FontWeight weight,
    Color color,
  ) {
    final para = gbParagraph(text, fontSize, weight, color);
    canvas.drawParagraph(
      para,
      Offset(
        center.dx - para.maxIntrinsicWidth / 2,
        center.dy - para.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant BrakeScenePainter oldDelegate) => true;
}

/// 画布文字段落缓存（painter 每帧重建，缓存放顶层避免反复排版）。
final Map<String, ui.Paragraph> _gbParaCache = <String, ui.Paragraph>{};

ui.Paragraph gbParagraph(
  String text,
  double fontSize,
  FontWeight weight,
  Color color,
) {
  final key = '$text|$fontSize|$weight|$color';
  final cached = _gbParaCache[key];
  if (cached != null) return cached;
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontSize: fontSize,
            fontWeight: weight,
            fontFamily: 'NotoSC',
            textAlign: TextAlign.center,
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
            fontFamily: 'NotoSC',
          ),
        )
        ..addText(text);
  final para = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 4000));
  if (_gbParaCache.length > 60) _gbParaCache.clear();
  _gbParaCache[key] = para;
  return para;
}

class _CarFace {
  const _CarFace({
    required this.pts,
    required this.d,
    required this.colIdx,
    required this.k,
    required this.glass,
    this.wx,
    this.wy,
    this.wrx,
    this.wry,
  });

  final List<Offset> pts;
  final double d;
  final int colIdx;
  final double k;
  final bool glass;
  final double? wx, wy, wrx, wry;

  bool get wheel => wx != null;
}

// painter 里额外临时寄存器
final Float64List _p2 = Float64List(3);
final Float64List _q2 = Float64List(3);
