(function () {
  "use strict";

  const TAU = Math.PI * 2;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

  function particleCountFor(radius) {
    if (radius < 18) return 12;
    if (radius < 26) return 14;
    if (radius < 36) return 16;
    if (radius < 50) return 18;
    if (radius < 68) return 20;
    if (radius < 90) return 22;
    return 24;
  }

  function closestPointOnPolygon(points, x, y) {
    const n = points.length;
    let inside = false;
    let bestD2 = Infinity;
    let bestEdge = 0;
    let bestT = 0;
    let bestX = x;
    let bestY = y;

    for (let i = 0; i < n; i++) {
      const a = points[i];
      const b = points[(i + 1) % n];

      if (a.y > y !== b.y > y) {
        const xint = ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x;
        if (x < xint) inside = !inside;
      }

      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const len2 = dx * dx + dy * dy;
      let t = len2 > 0 ? ((x - a.x) * dx + (y - a.y) * dy) / len2 : 0;
      t = clamp(t, 0, 1);
      const px = a.x + dx * t;
      const py = a.y + dy * t;
      const ddx = x - px;
      const ddy = y - py;
      const d2 = ddx * ddx + ddy * ddy;
      if (d2 < bestD2) {
        bestD2 = d2;
        bestEdge = i;
        bestT = t;
        bestX = px;
        bestY = py;
      }
    }

    return {
      inside,
      dist: Math.sqrt(bestD2),
      edge: bestEdge,
      t: bestT,
      x: bestX,
      y: bestY,
    };
  }

  function outwardNormal(points, edge, sign) {
    const a = points[edge];
    const b = points[(edge + 1) % points.length];
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = Math.hypot(dx, dy) || 1;
    return { x: (dy / len) * sign, y: (-dx / len) * sign };
  }

  function segmentsCross(ax, ay, bx, by, cx, cy, dx, dy) {
    const rx = bx - ax;
    const ry = by - ay;
    const sx = dx - cx;
    const sy = dy - cy;
    const denom = rx * sy - ry * sx;
    if (Math.abs(denom) < 0.00001) return false;
    const qpx = cx - ax;
    const qpy = cy - ay;
    const t = (qpx * sy - qpy * sx) / denom;
    const u = (qpx * ry - qpy * rx) / denom;
    return t > 0.015 && t < 0.985 && u > 0.015 && u < 0.985;
  }

  class SoftBlob {
    constructor(level, x, y, radius, vx, vy) {
      this.level = level;
      this.R = radius;
      this.n = particleCountFor(radius);

      // The visible skin is the ring inflated by the collision radius of every
      // boundary node. Solve for a collision radius that keeps neighbouring
      // node discs overlapping, so blobs cannot slip between each other.
      let collisionR = radius * 0.2;
      for (let i = 0; i < 4; i++) {
        const ring = radius - collisionR;
        collisionR = 2 * ring * Math.sin(Math.PI / this.n) * 0.56;
      }
      this.cr = collisionR;
      this.ringR = radius - collisionR;

      this.targetArea =
        0.5 * this.n * this.ringR * this.ringR * Math.sin(TAU / this.n);
      this.edgeRest = 2 * this.ringR * Math.sin(Math.PI / this.n);
      this.spokeRest = 2 * this.ringR;
      this.invMass = 1 / Math.pow(Math.max(0.35, radius / 14), 2);

      this.p = [];
      this.phase = -Math.PI / 2 + (Math.random() - 0.5) * 0.08;
      for (let i = 0; i < this.n; i++) {
        const a = this.phase + (i / this.n) * TAU;
        const px = x + Math.cos(a) * this.ringR;
        const py = y + Math.sin(a) * this.ringR;
        this.p.push({
          x: px,
          y: py,
          px: px,
          py: py,
          vx: vx || 0,
          vy: vy || 0,
          hit: 0,
        });
      }

      this.cx = x;
      this.cy = y;
      this.stepCx = x;
      this.stepCy = y;
      this.area = this.targetArea;
      this.boundR = radius * 1.35;
      this.visR = radius;
      this.age = 0;
      this.thinTime = 0;
      this.aboveMouthTime = 0;

      // 浓稠液体：形变只驱动渲染，不参与碰撞
      this.jiggle = 0;
      this.jigglePhase = Math.random() * TAU;
      this.jiggleDir = -Math.PI / 2;
      this.floatT = 0;
      this.flowVx = 0;
      this.flowVy = 0;
      this.wasContact = false;

      this.blinkIn = 1.8 + Math.random() * 5.2;
      this.blinkFor = 0;

      this.fill = "#ffffff";
      this.edge = "#333333";
      this.contact = false;
      this.visualPop = 0;

      this.measure();
    }

    // Small drops act as near-rigid droplets: surface tension dominates, so
    // they never collapse into slivers when squeezed by bigger blobs.
    get isSmall() {
      return this.R < 50;
    }

    get rigidity() {
      return clamp(52 / this.R, 1.0, 2.2);
    }

    measure() {
      const p = this.p;
      const n = this.n;
      let twiceArea = 0;
      let cxSum = 0;
      let cySum = 0;
      let perimeter = 0;
      let minX = Infinity;
      let maxX = -Infinity;
      let minY = Infinity;
      let maxY = -Infinity;

      for (let i = 0; i < n; i++) {
        const a = p[i];
        const b = p[(i + 1) % n];
        const cross = a.x * b.y - b.x * a.y;
        twiceArea += cross;
        cxSum += (a.x + b.x) * cross;
        cySum += (a.y + b.y) * cross;
        perimeter += Math.hypot(b.x - a.x, b.y - a.y);
        if (a.x < minX) minX = a.x;
        if (a.x > maxX) maxX = a.x;
        if (a.y < minY) minY = a.y;
        if (a.y > maxY) maxY = a.y;
      }

      const areaAbs = Math.abs(twiceArea) * 0.5;
      if (Math.abs(twiceArea) > 1e-4 && areaAbs > this.targetArea * 0.02) {
        // The polygon-centroid formula explodes for a nearly collapsed ring;
        // keep it inside the node bounding box.
        cxSum /= 3 * twiceArea;
        cySum /= 3 * twiceArea;
        this.cx = clamp(cxSum, minX, maxX);
        this.cy = clamp(cySum, minY, maxY);
      } else {
        let sx = 0;
        let sy = 0;
        for (let i = 0; i < n; i++) {
          sx += p[i].x;
          sy += p[i].y;
        }
        this.cx = sx / n;
        this.cy = sy / n;
      }

      this.area = areaAbs;
      this.perimeter = perimeter;
      this.signedArea = twiceArea * 0.5;
      this.compactness =
        this.area > 0 && this.perimeter > 0
          ? (4 * Math.PI * this.area) / (this.perimeter * this.perimeter)
          : 1;
      return this;
    }

    refreshBounds() {
      let maxD = 0;
      for (let i = 0; i < this.n; i++) {
        const dx = this.p[i].x - this.cx;
        const dy = this.p[i].y - this.cy;
        const d = dx * dx + dy * dy;
        if (d > maxD) maxD = d;
      }
      this.boundR = Math.sqrt(maxD) + this.cr + 3;
      this.visR = Math.sqrt(maxD) + this.cr - 0.4;
    }

    boundaryPoints() {
      const p = this.p;
      const n = this.n;
      const sign = this.signedArea >= 0 ? 1 : -1;
      const offset = this.cr - 0.4;
      const points = new Array(n);

      for (let i = 0; i < n; i++) {
        const prev = p[(i - 1 + n) % n];
        const next = p[(i + 1) % n];
        const tx = next.x - prev.x;
        const ty = next.y - prev.y;
        const len = Math.hypot(tx, ty) || 1;
        const nx = (ty / len) * sign;
        const ny = (-tx / len) * sign;
        points[i] = {
          x: p[i].x + nx * offset,
          y: p[i].y + ny * offset,
        };
      }
      return points;
    }

    predict(h, gravity) {
      const p = this.p;
      this.stepCx = this.cx;
      this.stepCy = this.cy;
      this.contact = false;
      const g = gravity;
      if (this.floatT > 0) this.floatT = Math.max(0, this.floatT - h);
      for (let i = 0; i < this.n; i++) {
        const pt = p[i];
        pt.px = pt.x;
        pt.py = pt.y;
        pt.vy += g * h;
        pt.vx *= 0.9994;
        pt.vy *= 0.9994;
        pt.x += pt.vx * h;
        pt.y += pt.vy * h;
      }
    }

    solveEdges() {
      const p = this.p;
      const n = this.n;
      const rest = this.edgeRest;
      const kBase = 0.24 * this.rigidity;
      for (let i = 0; i < n; i++) {
        const a = p[i];
        const b = p[(i + 1) % n];
        let dx = b.x - a.x;
        let dy = b.y - a.y;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d < 1e-6) continue;
        const k = ((d - rest) / d) * kBase;
        dx *= k;
        dy *= k;
        a.x += dx;
        a.y += dy;
        b.x -= dx;
        b.y -= dy;
      }
    }

    solveSpokes() {
      const p = this.p;
      const half = this.n / 2;
      const rest = this.spokeRest;
      const kBase = 0.008 * this.rigidity;
      for (let i = 0; i < half; i++) {
        const a = p[i];
        const b = p[i + half];
        let dx = b.x - a.x;
        let dy = b.y - a.y;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d < 1e-6) continue;
        const k = ((d - rest) / d) * kBase;
        dx *= k;
        dy *= k;
        a.x += dx;
        a.y += dy;
        b.x -= dx;
        b.y -= dy;
      }
    }

    solveSurfaceTension() {
      const p = this.p;
      const n = this.n;
      const smooth = 0.045 * this.rigidity;
      for (let i = 0; i < n; i++) {
        const prev = p[(i - 1 + n) % n];
        const next = p[(i + 1) % n];
        const tx = (prev.x + next.x) * 0.5;
        const ty = (prev.y + next.y) * 0.5;
        const pt = p[i];
        pt.x += (tx - pt.x) * smooth;
        pt.y += (ty - pt.y) * smooth;
      }
    }

    solvePressure() {
      this.measure();
      const p = this.p;
      const n = this.n;
      const perimeter = Math.max(this.perimeter, 1);
      const cap = Math.max(0.35, this.ringR * 0.042 * this.rigidity);
      const ratio = this.area / this.targetArea;
      const boost = ratio < 0.62 ? 1 + (0.62 - ratio) * 3.2 : 1;
      const push = clamp(
        ((this.targetArea - this.area) / perimeter) * 0.46 * this.rigidity * boost,
        -cap * boost,
        cap * boost
      );

      for (let i = 0; i < n; i++) {
        const pt = p[i];
        const dx = pt.x - this.cx;
        const dy = pt.y - this.cy;
        const d = Math.sqrt(dx * dx + dy * dy) || 1;
        pt.x += (dx / d) * push;
        pt.y += (dy / d) * push;
      }
    }

    // Soft bodies can keep their area while flattening into a pancake. Pull
    // the ring back toward its rest radius so impact squash recovers round.
    solveShapeMemory() {
      this.measure();
      const p = this.p;
      const n = this.n;
      const thinBoost =
        this.compactness < 0.45
          ? 1 + (0.45 - this.compactness) * 12
          : 1;
      const k = 0.115 * this.rigidity * thinBoost;
      const target = this.ringR;
      for (let i = 0; i < n; i++) {
        const pt = p[i];
        const dx = pt.x - this.cx;
        const dy = pt.y - this.cy;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d < 1e-6) continue;
        const pull = (target - d) * k;
        pt.x += (dx / d) * pull;
        pt.y += (dy / d) * pull;
      }
    }

    solveShape() {
      this.solveEdges();
      this.solveSpokes();
      this.solveSurfaceTension();
      this.solveShapeMemory();
      this.solvePressure();
    }

    solveWalls(bounds, tolerance) {
      const p = this.p;
      const cr = this.cr;
      const tol = tolerance || 0;
      const left = bounds.left + cr - tol;
      const right = bounds.right - cr + tol;
      const top = bounds.top + cr - tol;
      const floor = bounds.floor - cr + tol;

      for (let i = 0; i < this.n; i++) {
        const pt = p[i];
        if (pt.x < left) {
          pt.x = left;
          pt.hit |= 1;
        } else if (pt.x > right) {
          pt.x = right;
          pt.hit |= 2;
        }
        if (pt.y < top) {
          pt.y = top;
          pt.hit |= 4;
        } else if (pt.y > floor) {
          pt.y = floor;
          pt.hit |= 8;
        }
      }
    }

    finish(h, bounds, speedLimit) {
      const p = this.p;
      const n = this.n;
      let kineticSum = 0;
      let sumVx = 0;
      let sumVy = 0;
      const smallBlob = this.isSmall;
      const nearFloor = this.cy + this.R >= bounds.floor - 6;
      const nearWall =
        this.cx - this.R <= bounds.left + 6 ||
        this.cx + this.R >= bounds.right - 6;
      const approxVx = this.averageVx();
      const approxVy = this.averageVy();
      const approxSpeed = Math.hypot(approxVx, approxVy);
      // 上升阶段（刚回弹）不算“贴地”，否则接触阻尼会把弹起吃掉
      const rising = approxVy < -40;
      const slowNear =
        (nearFloor || nearWall) && approxSpeed < 150 && !rising;
      const effectiveContact = this.contact || slowNear;
      const contactDamping = effectiveContact ? (smallBlob ? 0.9986 : 0.999) : 1;
      const cap = speedLimit || 2600;
      const maxSpeed = effectiveContact && smallBlob ? cap * 0.72 : cap;
      let wallImpact = 0;
      let wallDir = -Math.PI / 2;
      let floorHits = 0;
      let wallHits = 0;

      for (let i = 0; i < n; i++) {
        const pt = p[i];
        let vx = (pt.x - pt.px) / h;
        let vy = (pt.y - pt.py) / h;

        const incomingVx = pt.vx;
        const incomingVy = pt.vy;
        const floorY = bounds.floor - this.cr;
        const atFloor = (pt.hit & 8) !== 0 && pt.y >= floorY - 1.2;
        const atCeil = (pt.hit & 4) !== 0 && pt.y <= bounds.top + this.cr + 1.2;
        const atWall =
          (pt.hit & 3) !== 0 &&
          (pt.x <= bounds.left + this.cr + 1.2 ||
            pt.x >= bounds.right - this.cr - 1.2);
        const rebound = smallBlob ? 0.4 : 0.22;
        if (atFloor) {
          floorHits++;
          if (incomingVy > 200 && incomingVy > wallImpact) {
            wallImpact = incomingVy;
            wallDir = -Math.PI / 2;
          }
          vy = incomingVy > 60 ? -incomingVy * rebound : 0;
          vx *= 0.994;
        } else if (atWall) {
          wallHits++;
          const ax = Math.abs(incomingVx);
          if (ax > 200 && ax > wallImpact) {
            wallImpact = ax;
            wallDir =
              pt.x <= bounds.left + this.cr + 1.2 ? 0 : Math.PI;
          }
          vx = Math.abs(incomingVx) > 50 ? -incomingVx * rebound * 0.8 : 0;
          vy *= 0.9995;
        } else if (atCeil) {
          if (incomingVy < -200 && -incomingVy > wallImpact) {
            wallImpact = -incomingVy;
            wallDir = Math.PI / 2;
          }
          vy = incomingVy < -50 ? -incomingVy * rebound * 0.8 : 0;
        }
        const floorContact = atFloor || (nearFloor && Math.hypot(vx, vy) < 160);

        vx *= 0.9997 * contactDamping;
        vy *= 0.9997 * contactDamping;

        const speed2 = vx * vx + vy * vy;
        if (speed2 > maxSpeed * maxSpeed) {
          const s = maxSpeed / Math.sqrt(speed2);
          vx *= s;
          vy *= s;
        } else if (
          speed2 < (floorContact ? (smallBlob ? 4 : 2.5) : 0.02)
        ) {
          vx = 0;
          vy = 0;
        }
        if (vy < -1400) vy = -1400;

        pt.vx = vx;
        pt.vy = vy;
        pt.hit = 0;
        sumVx += vx;
        sumVy += vy;
        kineticSum += Math.abs(vx) + Math.abs(vy);
      }

      // 落地/贴墙时只该改变法向速度，切向动量要保留；否则形变求解会在
      // 罐底给整颗果冻“蹬”出一段横向漂移，像自己在走。
      if (floorHits > 0) {
        const avgVx = sumVx / n;
        const keepVx = Math.abs(approxVx) > 30 ? approxVx * 0.999 : 0;
        const adjX = (keepVx - avgVx) * 0.9;
        if (Math.abs(adjX) > 0.001) {
          for (let i = 0; i < n; i++) p[i].vx += adjX;
        }
      }
      if (wallHits > 0) {
        const avgVy = sumVy / n;
        const keepVy = Math.abs(approxVy) > 30 ? approxVy * 0.999 : 0;
        const adjY = (keepVy - avgVy) * 0.9;
        if (Math.abs(adjY) > 0.001) {
          for (let i = 0; i < n; i++) p[i].vy += adjY;
        }
      }
      if (floorHits > 0 || wallHits > 0) {
        sumVx = 0;
        sumVy = 0;
        kineticSum = 0;
        for (let i = 0; i < n; i++) {
          const pt = p[i];
          sumVx += pt.vx;
          sumVy += pt.vy;
          kineticSum += Math.abs(pt.vx) + Math.abs(pt.vy);
        }
      }

      // Resting on another blob is not free fall: cancel most of the
      // whole-body velocity while leaving the internal wobble untouched.
      // Without this the position solver keeps pushing a body back out of the
      // pile while its stored downward speed stays near the cap forever.
      if (this.contact || effectiveContact) {
        const avgVx = sumVx / n;
        const avgVy = sumVy / n;
        // A body wedged in the pile barely moves its centre from step to
        // step, yet the clip/floor correction leaves a large derived speed.
        // Kill that fake drift hard, but leave a genuinely moving contact
        // (and therefore the impact squash) almost untouched.
        const keepStable = 0.2;
        const keepMoving = 1;
        const keepX =
          Math.abs(this.cx - this.stepCx) < 0.15 ? keepStable : keepMoving;
        const keepY =
          Math.abs(this.cy - this.stepCy) < 0.15 ? keepStable : keepMoving;
        const dropVx = avgVx * (1 - keepX);
        const dropVy = avgVy * (1 - keepY);
        kineticSum = 0;
        for (let i = 0; i < n; i++) {
          const pt = p[i];
          pt.vx -= dropVx;
          pt.vy -= dropVy;
          kineticSum += Math.abs(pt.vx) + Math.abs(pt.vy);
        }
      }

      if (effectiveContact) {
        const avgVx = sumVx / n;
        const avgVy = sumVy / n;
        const blend = smallBlob ? 0.006 : 0.008;
        kineticSum = 0;
        for (let i = 0; i < n; i++) {
          const pt = p[i];
          pt.vx += (avgVx - pt.vx) * blend;
          pt.vy += (avgVy - pt.vy) * blend;
          kineticSum += Math.abs(pt.vx) + Math.abs(pt.vy);
        }
      }

      this.kinetic = kineticSum / n;
      // 黏稠：形状跟随速度但有明显滞后，停下后缓慢回缩
      const flowK = 1 - Math.exp(-1.7 * h);
      this.flowVx += (sumVx / n - this.flowVx) * flowK;
      this.flowVy += (sumVy / n - this.flowVy) * flowK;
      if (wallImpact > 0) {
        this.jiggle = Math.max(this.jiggle, Math.min(1, wallImpact / 900));
        this.jiggleDir = wallDir;
        // 落地时先卸掉下落的拉长，再慢慢摊开（splat）
        this.flowVx *= 0.4;
        this.flowVy *= 0.4;
      }
      const touching = this.contact || effectiveContact;
      if (touching && !this.wasContact) {
        const impact = Math.min(1, approxSpeed / 650);
        if (impact > 0.25 && impact > this.jiggle) {
          this.jiggle = impact;
          this.jiggleDir = -Math.PI / 2;
        }
      }
      if (!this.contact && approxVy < -400) {
        this.floatT = Math.max(this.floatT, 0.28);
      } else if (touching) {
        this.floatT = 0;
      }
      this.wasContact = touching;
      this.jiggle *= Math.exp(-(this.isSmall ? 2.8 : 2.2) * h);
      this.jigglePhase += h * (this.isSmall ? 8.5 : 7.0);
      this.age += h;
      if (this.compactness < 0.42 || this.area < this.targetArea * 0.3) {
        this.thinTime += h;
      } else {
        this.thinTime = Math.max(0, this.thinTime - h * 2);
      }

      this.blinkIn -= h;
      if (this.blinkFor > 0) {
        this.blinkFor -= h;
      } else if (this.blinkIn <= 0) {
        this.blinkFor = 0.12;
        this.blinkIn = 2.4 + Math.random() * 5.5;
      }
    }

    addVelocity(vx, vy) {
      for (let i = 0; i < this.n; i++) {
        this.p[i].vx += vx;
        this.p[i].vy += vy;
      }
    }

    averageVx() {
      let sum = 0;
      for (let i = 0; i < this.n; i++) sum += this.p[i].vx;
      return sum / this.n;
    }

    averageVy() {
      let sum = 0;
      for (let i = 0; i < this.n; i++) sum += this.p[i].vy;
      return sum / this.n;
    }

    translate(dx, dy) {
      for (let i = 0; i < this.n; i++) {
        const pt = this.p[i];
        pt.x += dx;
        pt.y += dy;
        pt.px += dx;
        pt.py += dy;
      }
    }

    // Position-only collision correction: move the previous position too so
    // the solver cannot turn repeated overlap fixes into artificial velocity.
    shove(i, dx, dy) {
      const pt = this.p[i];
      pt.x += dx;
      pt.y += dy;
      pt.px += dx;
      pt.py += dy;
    }

    meanX() {
      let sum = 0;
      for (let i = 0; i < this.n; i++) sum += this.p[i].x;
      return sum / this.n;
    }

    meanY() {
      let sum = 0;
      for (let i = 0; i < this.n; i++) sum += this.p[i].y;
      return sum / this.n;
    }

    // Shape solving may only reshape a small drop, never drag the whole drop
    // sideways while it is pinned against a wall.
    recenterShape(previousMeanX, previousMeanY) {
      const dx = this.meanX() - previousMeanX;
      const dy = this.meanY() - previousMeanY;
      if (Math.abs(dx) + Math.abs(dy) < 1e-6) return;
      for (let i = 0; i < this.n; i++) {
        const pt = this.p[i];
        pt.x -= dx;
        pt.y -= dy;
        pt.px -= dx;
        pt.py -= dy;
      }
    }

    rescale(f, nx, ny) {
      if (!(f > 0) || !Number.isFinite(f)) return;
      const oldCx = this.cx;
      const oldCy = this.cy;
      this.R *= f;
      this.cr *= f;
      this.ringR *= f;
      this.targetArea *= f * f;
      this.edgeRest *= f;
      this.spokeRest *= f;
      this.invMass = 1 / Math.pow(Math.max(0.35, this.R / 14), 2);
      for (let i = 0; i < this.n; i++) {
        const pt = this.p[i];
        pt.x = nx + (pt.x - oldCx) * f;
        pt.y = ny + (pt.y - oldCy) * f;
        pt.px = pt.x;
        pt.py = pt.y;
        pt.vx *= f;
        pt.vy *= f;
        pt.hit = 0;
      }
      this.cx = nx;
      this.cy = ny;
      this.stepCx = nx;
      this.stepCy = ny;
      this.measure();
      this.refreshBounds();
    }

    confineCircle(bounds) {
      const room = this.R * 0.70;
      const left = bounds.left + room;
      const right = bounds.right - room;
      const top = bounds.top + room;
      const floor = bounds.floor - room;
      let dx = 0;
      let dy = 0;
      if (this.cx < left) dx = left - this.cx;
      else if (this.cx > right) dx = right - this.cx;
      if (this.cy < top) dy = top - this.cy;
      else if (this.cy > floor) dy = floor - this.cy;
      if (dx === 0 && dy === 0) return;
      this.translate(dx, dy);
      this.cx += dx;
      this.cy += dy;
    }

    // A ring crushed into a sliver cannot recover through pressure alone.
    // Rebuild a smaller circle first so the area spring can inflate it back
    // inside whatever gap is actually available.
    fixShape(scale) {
      const s = clamp(scale === undefined ? 0.55 : scale, 0.2, 1);
      for (let i = 0; i < this.n; i++) {
        const angle = this.phase + (i / this.n) * TAU;
        const pt = this.p[i];
        pt.x = this.cx + Math.cos(angle) * this.ringR * s;
        pt.y = this.cy + Math.sin(angle) * this.ringR * s;
        pt.px = pt.x;
        pt.py = pt.y;
        pt.vx = 0;
        pt.vy = 0;
        pt.hit = 0;
      }
      this.measure();
      this.refreshBounds();
    }

    top() {
      let top = Infinity;
      for (let i = 0; i < this.n; i++) {
        if (this.p[i].y < top) top = this.p[i].y;
      }
      return top - this.cr;
    }

    pointInside(x, y) {
      const p = this.boundaryPoints();
      let inside = false;
      for (let i = 0, j = p.length - 1; i < p.length; j = i++) {
        const xi = p[i].x;
        const yi = p[i].y;
        const xj = p[j].x;
        const yj = p[j].y;
        const cross =
          yi > y !== yj > y &&
          x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;
        if (cross) inside = !inside;
      }
      return inside;
    }
  }

  class SoftWorld {
    constructor(bounds) {
      this.blobs = [];
      this.bounds = bounds;
      this.gravity = 2100;
      this.accumulator = 0;
      this.fixedStep = 1 / 150;
      this.maxSteps = 6;
      this.mergeGrace = 0;
      this.maxSpeed = 2600;
      this.mouthY = null;
    }

    add(blob) {
      this.blobs.push(blob);
      return blob;
    }

    step(dt) {
      const step = this.fixedStep;
      this.accumulator += Math.min(dt, 0.05);
      let count = 0;

      while (this.accumulator >= step && count < this.maxSteps) {
        this.substep(step);
        this.accumulator -= step;
        count++;
      }

      if (count === this.maxSteps) this.accumulator = 0;
    }

    substep(h) {
      const blobs = this.blobs;
      if (this.mergeGrace > 0) this.mergeGrace = Math.max(0, this.mergeGrace - h);

      for (let i = 0; i < blobs.length; i++) {
        blobs[i].predict(h, this.gravity);
      }

      for (let iteration = 0; iteration < 3; iteration++) {
        for (let i = 0; i < blobs.length; i++) {
          const blob = blobs[i];
          const small = blob.isSmall;
          const mx = blob.meanX();
          const my = blob.meanY();
          blob.solveShape();
          // 形变只改变形状，不应把整颗果冻挪走；大小球都做中心回正，
          // 否则大球落地时会被不对称的形变推着横向漂移。
          blob.recenterShape(mx, my);
          if (small) blob.confineCircle(this.bounds);
          blob.solveWalls(this.bounds);
        }
        this.resolveCollisions(0.5);
      }

      for (let i = 0; i < blobs.length; i++) blobs[i].refreshBounds();

      for (let pass = 0; pass < 2; pass++) {
        this.resolveCollisions(0.92);
        for (let i = 0; i < blobs.length; i++) {
          const blob = blobs[i];
          if (blob.isSmall) blob.confineCircle(this.bounds);
          blob.solveWalls(this.bounds);
          blob.measure();
          blob.refreshBounds();
        }
      }

      // Walls are the last constraint and can squeeze two bodies back into
      // each other. Finish with separation and allow a hair of wall overlap
      // (hidden inside the glass) so the visible outlines stay clean.
      this.resolveCollisions(0.75);
      for (let i = 0; i < blobs.length; i++) {
        const blob = blobs[i];
        if (blob.isSmall) blob.confineCircle(this.bounds);
        blob.solveWalls(this.bounds, 1.2);
        blob.measure();
        blob.refreshBounds();
      }

      for (let i = 0; i < blobs.length; i++) {
        const blob = blobs[i];
        blob.finish(h, this.bounds, this.maxSpeed);
        blob.refreshBounds();
      }

      let repaired = false;
      for (let i = 0; i < blobs.length; i++) {
        const blob = blobs[i];
        if (blob.thinTime > 0.35) {
          blob.fixShape(blob.isSmall ? 0.6 : 0.55);
          blob.thinTime = 0;
          repaired = true;
        }
      }
      if (repaired) {
        for (let pass = 0; pass < 2; pass++) {
          this.resolveCollisions(0.9);
          for (let i = 0; i < blobs.length; i++) {
            const blob = blobs[i];
            if (blob.isSmall) blob.confineCircle(this.bounds);
            blob.solveWalls(this.bounds);
            blob.measure();
            blob.refreshBounds();
          }
        }
        this.resolveCollisions(0.75);
        for (let i = 0; i < blobs.length; i++) {
          const blob = blobs[i];
          if (blob.isSmall) blob.confineCircle(this.bounds);
          blob.solveWalls(this.bounds, 1.2);
          blob.measure();
          blob.refreshBounds();
        }
      }

      // Explicit collision impulses must run after finish(), because finish
      // derives velocity from positions and would otherwise overwrite them.
      this.applyBlobImpulses();

      // A body that stays above the mouth is either an incoming shot or a
      // body wedged in the invisible corner over the rim. Nudge the latter
      // back toward the centre and down instead of letting it hang there.
      if (this.mouthY !== null) {
        const centerX = (this.bounds.left + this.bounds.right) * 0.5;
        for (let i = 0; i < blobs.length; i++) {
          const blob = blobs[i];
          if (blob.cy < this.mouthY - 2) {
            blob.aboveMouthTime += h;
            if (blob.aboveMouthTime > 0.3) {
              blob.aboveMouthTime = 0;
              const pushX = clamp((centerX - blob.cx) * 0.8, -260, 260);
              blob.addVelocity(pushX, 220);
            }
          } else {
            blob.aboveMouthTime = 0;
          }
        }
      }
    }

    resolveCollisions(stiffness, forceVisible) {
      const blobs = this.blobs;
      const count = blobs.length;
      const k = stiffness === undefined ? 0.5 : stiffness;

      for (let i = 0; i < count; i++) {
        const a = blobs[i];
        for (let j = i + 1; j < count; j++) {
          const b = blobs[j];
          const cdx = b.cx - a.cx;
          const cdy = b.cy - a.cy;
          const reach = a.boundR + b.boundR;

          if (cdx * cdx + cdy * cdy > reach * reach) continue;
          if (a.isSmall || b.isSmall) {
            this.resolveCirclePair(a, b, k);
            if (!a.isSmall) this.resolveSmallPolygon(b, a, k);
            else if (!b.isSmall) this.resolveSmallPolygon(a, b, k);
            else if (
              k > 0.7 &&
              (forceVisible ||
                this.mergeGrace > 0 ||
                a.visualPop > 0 ||
                b.visualPop > 0 ||
                a.jiggle > 0.12 ||
                b.jiggle > 0.12 ||
                a.compactness < 0.97 ||
                b.compactness < 0.97)
            ) {
              this.resolvePolygonPair(a, b, k * 0.8);
            }
          } else {
            this.resolvePolygonPair(a, b, k);
          }
        }
      }
    }

    resolveCirclePair(a, b, stiffness) {
      const dx = b.cx - a.cx;
      const dy = b.cy - a.cy;
      const d = Math.sqrt(dx * dx + dy * dy);
      // 用稳定半径做圆碰撞：果冻晃动时外凸的节点不能把整颗球永久顶开，
      // 否则两颗球会越挤越散，留下很大的空档。
      const minD = Math.max(
        a.R + b.R + 1.2,
        Math.min(a.visR || a.R, a.R + 0.5) +
          Math.min(b.visR || b.R, b.R + 0.5) -
          0.4
      );
      if (d >= minD) return;

      const nx = d > 0.001 ? dx / d : 0;
      const ny = d > 0.001 ? dy / d : -1;
      const invA = a.invMass;
      const invB = b.invMass;
      const total = invA + invB;
      if (!(total > 0)) return;
      const wa = invA / total;
      const wb = invB / total;
      const push = (minD - d) * stiffness;

      // Translate small drops as a whole and carry previous positions with
      // them, so separation never turns into launch velocity.
      const ax = -nx * push * wa;
      const ay = -ny * push * wa;
      const bx = nx * push * wb;
      const by = ny * push * wb;
      a.translate(ax, ay);
      b.translate(bx, by);
      a.cx += ax;
      a.cy += ay;
      b.cx += bx;
      b.cy += by;
      a.contact = true;
      b.contact = true;
    }

    // Circle separation alone lets a small drop sink into a big blob that has
    // been dented by it. Push the whole drop back out of the big blob's real
    // skin, carrying previous positions so the fix adds no launch velocity.
    resolveSmallPolygon(small, big, stiffness) {
      const ps = small.boundaryPoints();
      const pb = big.boundaryPoints();
      const signB = big.signedArea >= 0 ? 1 : -1;
      let deepest = null;

      for (let i = 0; i < ps.length; i++) {
        const q = ps[i];
        const info = closestPointOnPolygon(pb, q.x, q.y);
        if (!info.inside) continue;
        if (!deepest || info.dist > deepest.depth) {
          deepest = { depth: info.dist, edge: info.edge, t: info.t };
        }
      }

      if (!deepest) return;

      const margin = 0.5 + Math.min(0.8, (small.R + big.R) * 0.005);
      const maxPush = 4 + Math.min(small.R, big.R) * 0.06;
      const push =
        Math.min(deepest.depth + margin, maxPush) * stiffness;
      const n = outwardNormal(pb, deepest.edge, signB);

      const invA = small.invMass;
      const invB = big.invMass;
      const total = invA + invB;
      if (!(total > 0)) return;
      const wa = invA / total;
      const wb = invB / total;

      const dx = n.x * push * wa;
      const dy = n.y * push * wa;
      small.translate(dx, dy);
      small.cx += dx;
      small.cy += dy;

      const e1 = deepest.edge;
      const e2 = (deepest.edge + 1) % big.n;
      const w1 = 1 - deepest.t;
      const w2 = deepest.t;
      big.shove(e1, -n.x * push * wb * w1, -n.y * push * wb * w1);
      big.shove(e2, -n.x * push * wb * w2, -n.y * push * wb * w2);

      small.contact = true;
      big.contact = true;
    }

    resolvePolygonPair(a, b, stiffness) {
      const pa = a.boundaryPoints();
      const pb = b.boundaryPoints();
      if (!pa.length || !pb.length) return;

      const signA = a.signedArea >= 0 ? 1 : -1;
      const signB = b.signedArea >= 0 ? 1 : -1;
      const invA = a.invMass;
      const invB = b.invMass;
      const total = invA + invB;
      if (!(total > 0)) return;
      const wa = invA / total;
      const wb = invB / total;
      const margin = 0.5 + Math.min(0.8, (a.R + b.R) * 0.005);
      const maxPush = 4 + Math.min(a.R, b.R) * 0.06;
      let touched = false;

      const bBoundR2 = b.boundR * b.boundR;
      for (let i = 0; i < pa.length; i++) {
        const q = pa[i];
        const cdx = q.x - b.cx;
        const cdy = q.y - b.cy;
        if (cdx * cdx + cdy * cdy > bBoundR2) continue;
        const info = closestPointOnPolygon(pb, q.x, q.y);
        if (!info.inside && info.dist >= margin) continue;

        const depth = info.inside
          ? info.dist + margin
          : margin - info.dist;
        if (depth <= 0.01) continue;

        const n = outwardNormal(pb, info.edge, signB);
        const push = Math.min(depth, maxPush) * stiffness;
        a.shove(i, n.x * push * wa, n.y * push * wa);

        const e1 = info.edge;
        const e2 = (info.edge + 1) % b.n;
        const w1 = 1 - info.t;
        const w2 = info.t;
        b.shove(e1, -n.x * push * wb * w1, -n.y * push * wb * w1);
        b.shove(e2, -n.x * push * wb * w2, -n.y * push * wb * w2);
        touched = true;
      }

      const aBoundR2 = a.boundR * a.boundR;
      for (let j = 0; j < pb.length; j++) {
        const q = pb[j];
        const cdx = q.x - a.cx;
        const cdy = q.y - a.cy;
        if (cdx * cdx + cdy * cdy > aBoundR2) continue;
        const info = closestPointOnPolygon(pa, q.x, q.y);
        if (!info.inside && info.dist >= margin) continue;

        const depth = info.inside
          ? info.dist + margin
          : margin - info.dist;
        if (depth <= 0.01) continue;

        const n = outwardNormal(pa, info.edge, signA);
        const push = Math.min(depth, maxPush) * stiffness;
        b.shove(j, n.x * push * wb, n.y * push * wb);

        const e1 = info.edge;
        const e2 = (info.edge + 1) % a.n;
        const w1 = 1 - info.t;
        const w2 = info.t;
        a.shove(e1, -n.x * push * wa * w1, -n.y * push * wa * w1);
        a.shove(e2, -n.x * push * wa * w2, -n.y * push * wa * w2);
        touched = true;
      }

      if (!touched) {
        for (let i = 0; i < pa.length; i++) {
          const a1 = pa[i];
          const a2 = pa[(i + 1) % pa.length];
          for (let j = 0; j < pb.length; j++) {
            const b1 = pb[j];
            const b2 = pb[(j + 1) % pb.length];
            if (
              !segmentsCross(
                a1.x,
                a1.y,
                a2.x,
                a2.y,
                b1.x,
                b1.y,
                b2.x,
                b2.y
              )
            ) {
              continue;
            }

            const nA = outwardNormal(pa, i, signA);
            const nB = outwardNormal(pb, j, signB);
            const push = (margin + 1.1) * stiffness * 0.45;

            a.shove(i, nB.x * push * wa, nB.y * push * wa);
            a.shove((i + 1) % a.n, nB.x * push * wa, nB.y * push * wa);
            b.shove(j, nA.x * push * wb, nA.y * push * wb);
            b.shove((j + 1) % b.n, nA.x * push * wb, nA.y * push * wb);
            touched = true;
          }
        }
      }

      if (touched) {
        a.contact = true;
        b.contact = true;
      }
    }

    applyBlobImpulses() {
      const blobs = this.blobs;
      for (let i = 0; i < blobs.length; i++) {
        const a = blobs[i];
        for (let j = i + 1; j < blobs.length; j++) {
          const b = blobs[j];
          const dx = b.cx - a.cx;
          const dy = b.cy - a.cy;
          const d = Math.sqrt(dx * dx + dy * dy);
          if (d < 0.001) continue;
          const reach = Math.max((a.R + b.R) * 1.02, a.visR + b.visR + 2);
          if (d > reach) continue;

          let avx = 0;
          let avy = 0;
          let bvx = 0;
          let bvy = 0;
          for (let k = 0; k < a.n; k++) {
            avx += a.p[k].vx;
            avy += a.p[k].vy;
          }
          for (let k = 0; k < b.n; k++) {
            bvx += b.p[k].vx;
            bvy += b.p[k].vy;
          }
          avx /= a.n;
          avy /= a.n;
          bvx /= b.n;
          bvy /= b.n;

          const nx = dx / d;
          const ny = dy / d;
          const closing = (bvx - avx) * nx + (bvy - avy) * ny;
          if (closing >= 0) continue;

          const massA = a.n / a.invMass;
          const massB = b.n / b.invMass;
          // Small drops visibly bounce off each other; big blobs stay mostly
          // inelastic so a full jar does not turn into a pinball machine.
          // 果冻球之间只留一点点弹性，主要靠挤压形变表现 Q 弹；
          // 弹得太狠会把整堆球从中间顶散，越玩缝越大。
          const bounce = a.isSmall || b.isSmall ? 0.75 : 0.45;
          const impulse = (-closing / (1 / massA + 1 / massB)) * bounce;
          const dax = (nx * impulse) / massA;
          const day = (ny * impulse) / massA;
          const dbx = (nx * impulse) / massB;
          const dby = (ny * impulse) / massB;

          for (let k = 0; k < a.n; k++) {
            a.p[k].vx -= dax;
            a.p[k].vy -= day;
          }
          for (let k = 0; k < b.n; k++) {
            b.p[k].vx += dbx;
            b.p[k].vy += dby;
          }
          a.contact = true;
          b.contact = true;
        }
      }
    }

    applyRadialImpulse(originX, originY, radius, strength) {
      const blobs = this.blobs;
      for (let i = 0; i < blobs.length; i++) {
        const blob = blobs[i];
        const dx = blob.cx - originX;
        const dy = blob.cy - originY;
        const d = Math.sqrt(dx * dx + dy * dy) || 1;
        if (d > radius) continue;
        const falloff = 1 - d / radius;
        blob.addVelocity(
          (dx / d) * strength * falloff,
          (dy / d) * strength * falloff
        );
      }
    }

    makeRoom(x, y, radius, ignore) {
      const bounds = this.bounds;
      const moved = [];
      const blobs = this.blobs;

      for (let i = 0; i < blobs.length; i++) {
        const blob = blobs[i];
        if (ignore && ignore.indexOf(blob) >= 0) continue;

        const dx = blob.cx - x;
        const dy = blob.cy - y;
        const d = Math.sqrt(dx * dx + dy * dy);
        const minSep = radius + blob.R + 3;
        if (d >= minSep) continue;

        const baseAngle =
          d > 0.001 ? Math.atan2(dy, dx) : -Math.PI / 2;
        const offsets = [
          0,
          -0.35,
          0.35,
          -0.7,
          0.7,
          -1.05,
          1.05,
          -1.4,
          1.4,
          Math.PI,
        ];
        const targetDistance = minSep + 4;
        let target = null;

        for (let k = 0; k < offsets.length; k++) {
          const angle = baseAngle + offsets[k];
          const tx = x + Math.cos(angle) * targetDistance;
          const ty = y + Math.sin(angle) * targetDistance;
          if (tx < bounds.left + blob.R * 0.7) continue;
          if (tx > bounds.right - blob.R * 0.7) continue;
          if (ty < bounds.top + blob.R * 0.7) continue;
          if (ty > bounds.floor - blob.R * 0.7) continue;

          let blocked = false;
          for (let m = 0; m < blobs.length; m++) {
            const other = blobs[m];
            if (other === blob) continue;
            if (other.R > blob.R * 1.05 && other.pointInside(tx, ty)) {
              blocked = true;
              break;
            }
            const ox = tx - other.cx;
            const oy = ty - other.cy;
            const min = other.R * 0.7 + blob.R * 0.5;
            if (ox * ox + oy * oy < min * min) {
              blocked = true;
              break;
            }
          }
          if (blocked) continue;

          target = { x: tx, y: ty };
          break;
        }

        if (!target) {
          const nx = d > 0.001 ? dx / d : 0;
          target = {
            x: clamp(
              x + nx * targetDistance,
              bounds.left + blob.R * 0.7,
              bounds.right - blob.R * 0.7
            ),
            y: clamp(
              y - targetDistance,
              bounds.top + blob.R * 0.7,
              bounds.floor - blob.R * 0.7
            ),
          };
        }

        const mx = target.x - blob.cx;
        const my = target.y - blob.cy;
        if (Math.abs(mx) + Math.abs(my) < 0.5) continue;

        for (let k = 0; k < blob.n; k++) {
          const pt = blob.p[k];
          pt.x += mx;
          pt.y += my;
          pt.px += mx;
          pt.py += my;
          pt.vx = pt.vx * 0.5 + mx * 0.12;
          pt.vy = pt.vy * 0.5 + my * 0.12;
        }

        if (blob.isSmall) blob.confineCircle(bounds);
        blob.solveWalls(bounds);
        for (let k = 0; k < blob.n; k++) blob.p[k].hit = 0;
        blob.measure();
        blob.refreshBounds();
        moved.push(blob);
      }

      return moved;
    }

    rescale(oldLayout, newLayout) {
      if (!oldLayout || !newLayout) return;
      const f = newLayout.scale / oldLayout.scale;
      if (!(f > 0) || !Number.isFinite(f)) return;
      const oldCx = (oldLayout.jarX0 + oldLayout.jarX1) * 0.5;
      const newCx = (newLayout.jarX0 + newLayout.jarX1) * 0.5;
      const floorShift = newLayout.floorY - oldLayout.floorY;
      if (
        Math.abs(f - 1) < 1e-4 &&
        Math.abs(newCx - oldCx) < 0.5 &&
        Math.abs(floorShift) < 0.5
      ) {
        return;
      }
      for (let i = 0; i < this.blobs.length; i++) {
        const blob = this.blobs[i];
        const nx = newCx + (blob.cx - oldCx) * f;
        const ny = newLayout.floorY - (oldLayout.floorY - blob.cy) * f;
        blob.rescale(f, nx, ny);
      }
    }

    containAll() {
      for (let i = 0; i < this.blobs.length; i++) {
        const blob = this.blobs[i];
        if (blob.isSmall) blob.confineCircle(this.bounds);
        blob.solveWalls(this.bounds);
        for (let k = 0; k < blob.n; k++) blob.p[k].hit = 0;
        blob.measure();
        blob.refreshBounds();
      }
    }

    // A merge can drop a much larger blob into a gap that only fit the two
    // smaller ones. Settle the visible outlines right away instead of letting
    // the next physics frames show the new blob sinking into its neighbours.
    separateAll(passes) {
      const rounds = passes === undefined ? 4 : passes;
      this.mergeGrace = 0.8;
      for (let round = 0; round < rounds; round++) {
        this.resolveCollisions(0.95, true);
        for (let i = 0; i < this.blobs.length; i++) {
          const blob = this.blobs[i];
          if (blob.isSmall) blob.confineCircle(this.bounds);
          blob.solveWalls(this.bounds);
          for (let k = 0; k < blob.n; k++) blob.p[k].hit = 0;
          blob.measure();
          blob.refreshBounds();
        }
      }
    }
  }

  window.GuluPhysics = {
    SoftBlob,
    SoftWorld,
  };
})();
