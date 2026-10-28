import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'sudoku_puzzle.dart';

/// 图六式三面立方体：顶面、左前面、右前面。
///
/// 内核通过 [SudokuPuzzle.cubeFaces] 给出每个面的局部 (r,c)→全局 cell 映射，
/// 共享边两侧返回同一索引；这里只负责等距投影、描线与点选。
class SudokuCubeView extends StatefulWidget {
  const SudokuCubeView({
    super.key,
    required this.puzzle,
    required this.board,
    required this.notes,
    required this.conflicts,
    required this.selected,
    required this.focusFace,
    required this.revision,
    this.onSelect,
    this.maxSide = 500,
  });

  final SudokuPuzzle puzzle;
  final List<int> board;
  final List<Set<int>> notes;
  final Set<int> conflicts;
  final int selected;
  final SudokuCubeFace focusFace;
  final int revision;
  final void Function(int index, SudokuCubeFace face)? onSelect;
  final double maxSide;

  static double heightForWidth(double width) => _CubeGeometry(width).height;

  @override
  State<SudokuCubeView> createState() => _SudokuCubeViewState();
}

class _SudokuCubeViewState extends State<SudokuCubeView> {
  double _yaw = 0;
  double _pitch = 0;

  bool get _rotated => _yaw.abs() > .001 || _pitch.abs() > .001;

  void _resetView() {
    if (!_rotated) return;
    setState(() {
      _yaw = 0;
      _pitch = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : widget.maxSide;
        final width = math.min(available, widget.maxSide);
        final geometry = _CubeGeometry(width, yaw: _yaw, pitch: _pitch);
        return Center(
          child: SizedBox(
            width: width,
            height: geometry.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) {
                          setState(() {
                            // 三面模型只有正面有数，旋转保持在三个面都朝外的范围内。
                            _yaw = (_yaw + details.delta.dx * .006).clamp(
                              -.48,
                              .48,
                            );
                            _pitch = (_pitch + details.delta.dy * .008).clamp(
                              -.34,
                              .34,
                            );
                          });
                        },
                        onTapUp: widget.onSelect == null
                            ? null
                            : (details) {
                                final hit = geometry.hit(
                                  details.localPosition,
                                  widget.puzzle.cubeFaces,
                                );
                                if (hit == null) return;
                                final map = geometry.mapOf(
                                  widget.puzzle.cubeFaces,
                                  hit.$1,
                                );
                                if (map == null) return;
                                final index = map.cellAt(hit.$2, hit.$3);
                                if (!widget.puzzle.isActive(index)) return;
                                widget.onSelect!(index, hit.$1);
                              },
                        child: CustomPaint(
                          painter: _SudokuCubePainter(
                            puzzle: widget.puzzle,
                            board: widget.board,
                            notes: widget.notes,
                            conflicts: widget.conflicts,
                            selected: widget.selected,
                            focusFace: widget.focusFace,
                            revision: widget.revision,
                            colors: c,
                            geometry: geometry,
                          ),
                          size: Size(width, geometry.height),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_rotated)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: _CubeResetButton(onTap: _resetView),
                  )
                else
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 4,
                    child: IgnorePointer(
                      child: Center(
                        child: Text(
                          '拖动旋转查看',
                          style: TextStyle(
                            fontFamily: AppFonts.noto,
                            fontFamilyFallback: AppFonts.fallback,
                            fontSize: 11,
                            letterSpacing: .5,
                            color: c.inkSoft.withValues(alpha: .82),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CubeResetButton extends StatelessWidget {
  const _CubeResetButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: '复位视角',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface.withValues(alpha: .9),
              border: Border.all(color: c.ink.withValues(alpha: .22)),
            ),
            child: Icon(Icons.restart_alt_rounded, size: 17, color: c.ink2),
          ),
        ),
      ),
    );
  }
}

class _CubeGeometry {
  _CubeGeometry(double width, {this.yaw = 0, this.pitch = 0}) {
    // 旋转范围内最大轮廓：横向 17.8u、纵向 18.73u，预留边距免得转出画布。
    u = math.max(1, (width - 6) / _maxWidth);
    origin = Offset(width / 2, .5 * u + 4);
    vx = Offset(u * _isoX, u * .5);
    vy = Offset(-u * _isoX, u * .5);
    vz = Offset(0, u);
    height = _maxHeight * u + 8;
  }

  static const double _isoX = .8660254037844386;
  static const double _maxWidth = 17.8;
  static const double _maxHeight = 19.4;
  final double yaw;
  final double pitch;
  late final double u;
  late final Offset origin;
  late final Offset vx;
  late final Offset vy;
  late final Offset vz;
  late final double height;

  SudokuCubeFaceMap? mapOf(
    List<SudokuCubeFaceMap> maps,
    SudokuCubeFace face,
  ) {
    for (final m in maps) {
      if (m.face == face) return m;
    }
    return null;
  }

  _V3 _face3(SudokuCubeFace face, double r, double c) {
    switch (face) {
      case SudokuCubeFace.top:
        return _V3(c, r, 0);
      case SudokuCubeFace.frontLeft:
        return _V3(c, 9, r);
      case SudokuCubeFace.frontRight:
        return _V3(9, c, r);
    }
  }

  _V3 _rotateVec(_V3 p) {
    final cyaw = math.cos(yaw);
    final syaw = math.sin(yaw);
    final x1 = p.x * cyaw - p.y * syaw;
    final y1 = p.x * syaw + p.y * cyaw;
    final cp = math.cos(pitch);
    final sp = math.sin(pitch);
    final y2 = y1 * cp - p.z * sp;
    final z2 = y1 * sp + p.z * cp;
    return _V3(x1, y2, z2);
  }

  _V3 _rotate(_V3 p) {
    const c = 4.5;
    final q = _rotateVec(_V3(p.x - c, p.y - c, p.z - c));
    return _V3(q.x + c, q.y + c, q.z + c);
  }

  bool frontFacing(SudokuCubeFace face) {
    final normal = switch (face) {
      SudokuCubeFace.top => const _V3(0, 0, -1),
      SudokuCubeFace.frontLeft => const _V3(0, 1, 0),
      SudokuCubeFace.frontRight => const _V3(1, 0, 0),
    };
    final q = _rotateVec(normal);
    return q.x + q.y - q.z > .02;
  }

  /// 右面投影后局部基是左手系，文字需要再翻一次 x 才不会镜像。
  bool mirrored(SudokuCubeFace face) {
    final o = point(face, 0, 0);
    final bu = point(face, 0, 1) - o;
    final bv = point(face, 1, 0) - o;
    return bu.dx * bv.dy - bu.dy * bv.dx < 0;
  }

  Offset _project(_V3 p) =>
      origin + vx * p.x + vy * p.y + vz * p.z;

  Offset point(SudokuCubeFace face, num r, num c) =>
      _project(_rotate(_face3(face, r.toDouble(), c.toDouble())));

  double faceDepth(SudokuCubeFace face) {
    final q = _rotate(_face3(face, 4.5, 4.5));
    return q.x + q.y - q.z;
  }

  Path facePath(SudokuCubeFace face) {
    final p00 = point(face, 0, 0);
    final p01 = point(face, 0, 9);
    final p11 = point(face, 9, 9);
    final p10 = point(face, 9, 0);
    return Path()
      ..moveTo(p00.dx, p00.dy)
      ..lineTo(p01.dx, p01.dy)
      ..lineTo(p11.dx, p11.dy)
      ..lineTo(p10.dx, p10.dy)
      ..close();
  }

  /// 局部坐标 (列, 行) → 屏幕，让数字和格线跟随面一起透视。
  Float64List matrix(SudokuCubeFace face) {
    final o = point(face, 0, 0);
    final bu = point(face, 0, 1) - o;
    final bv = point(face, 1, 0) - o;
    return Float64List.fromList([
      bu.dx, bu.dy, 0, 0, //
      bv.dx, bv.dy, 0, 0, //
      0, 0, 1, 0, //
      o.dx, o.dy, 0, 1, //
    ]);
  }

  (SudokuCubeFace, int, int)? hit(
    Offset p,
    List<SudokuCubeFaceMap> maps,
  ) {
    (SudokuCubeFace, int, int)? best;
    var bestDepth = double.negativeInfinity;
    for (final face in const [
      SudokuCubeFace.top,
      SudokuCubeFace.frontLeft,
      SudokuCubeFace.frontRight,
    ]) {
      if (mapOf(maps, face) == null) continue;
      if (!frontFacing(face)) continue;
      final local = _local(face, p);
      if (local == null) continue;
      final depth = faceDepth(face);
      if (depth <= bestDepth) continue;
      final r = local.$1.floor();
      final c = local.$2.floor();
      if (r < 0 || r >= 9 || c < 0 || c >= 9) continue;
      bestDepth = depth;
      best = (face, r, c);
    }
    return best;
  }

  (double, double)? _local(SudokuCubeFace face, Offset p) {
    final o = point(face, 0, 0);
    final bu = point(face, 0, 1) - o;
    final bv = point(face, 1, 0) - o;
    final d = p - o;
    final det = bu.dx * bv.dy - bu.dy * bv.dx;
    if (det.abs() < 1e-6) return null;
    final c = (d.dx * bv.dy - d.dy * bv.dx) / det;
    final r = (bu.dx * d.dy - bu.dy * d.dx) / det;
    if (r < -0.02 || r > 9.02 || c < -0.02 || c > 9.02) return null;
    return (r.clamp(0, 8.999), c.clamp(0, 8.999));
  }
}

class _V3 {
  const _V3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

class _SudokuCubePainter extends CustomPainter {
  _SudokuCubePainter({
    required this.puzzle,
    required this.board,
    required this.notes,
    required this.conflicts,
    required this.selected,
    required this.focusFace,
    required this.revision,
    required this.colors,
    required this.geometry,
  });

  final SudokuPuzzle puzzle;
  final List<int> board;
  final List<Set<int>> notes;
  final Set<int> conflicts;
  final int selected;
  final SudokuCubeFace focusFace;
  final int revision;
  final CitroColors colors;
  final _CubeGeometry geometry;

  Set<int> _peers() {
    final result = <int>{};
    if (selected < 0) return result;
    for (final unit in puzzle.units) {
      if (!unit.contains(selected)) continue;
      result.addAll(unit);
    }
    result.remove(selected);
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final peers = _peers();
    final selectedValue = selected >= 0 && selected < board.length
        ? board[selected]
        : 0;
    final maps = puzzle.cubeFaces;
    final faces = [
      SudokuCubeFace.top,
      SudokuCubeFace.frontLeft,
      SudokuCubeFace.frontRight,
    ]..sort(
      (a, b) => geometry.faceDepth(a).compareTo(geometry.faceDepth(b)),
    );
    // 由远到近逐个面完整绘制，旋转后近面会自然盖住远面。
    for (final face in faces) {
      final map = geometry.mapOf(maps, face);
      if (map == null) continue;
      _paintFace(canvas, map, face, peers, selectedValue);
    }
    _paintFocus(canvas, maps);
  }

  Color _faceBase(SudokuCubeFace face) {
    final shade = switch (face) {
      SudokuCubeFace.top => .00,
      SudokuCubeFace.frontLeft => .05,
      SudokuCubeFace.frontRight => .09,
    };
    return Color.alphaBlend(
      colors.ink.withValues(alpha: colors.dark ? shade * .45 : shade),
      colors.surface2,
    );
  }

  void _paintFace(
    Canvas canvas,
    SudokuCubeFaceMap map,
    SudokuCubeFace face,
    Set<int> peers,
    int selectedValue,
  ) {
    final path = geometry.facePath(face);
    canvas.save();
    canvas.clipPath(path);
    canvas.transform(geometry.matrix(face));
    final base = _faceBase(face);
    final fill = Paint();
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        final index = map.cellAt(r, c);
        if (!puzzle.isActive(index)) continue;
        final value = index < board.length ? board[index] : 0;
        var color = base;
        if (face == focusFace) {
          color = Color.alphaBlend(
            colors.accent.withValues(alpha: .035),
            color,
          );
        }
        if (peers.contains(index)) {
          color = Color.alphaBlend(colors.mintSoft, color);
        }
        if (selectedValue != 0 && value == selectedValue) {
          color = Color.alphaBlend(colors.accent.withValues(alpha: .18), color);
        }
        if (index == selected) {
          color = Color.alphaBlend(colors.accent.withValues(alpha: .28), color);
        }
        if (conflicts.contains(index)) {
          color = Color.alphaBlend(
            colors.stamp.withValues(alpha: index == selected ? .26 : .14),
            color,
          );
        }
        fill.color = color;
        canvas.drawRect(
          Rect.fromLTWH(c.toDouble(), r.toDouble(), 1, 1),
          fill,
        );
      }
    }
    if (selected >= 0) {
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .06
        ..color = conflicts.contains(selected) ? colors.stamp : colors.accent;
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          if (map.cellAt(r, c) != selected) continue;
          canvas.drawRect(
            Rect.fromLTWH(c.toDouble(), r.toDouble(), 1, 1).deflate(.03),
            border,
          );
        }
      }
    }
    final thin = Paint()
      ..color = colors.inkSoft.withValues(alpha: .55)
      ..strokeWidth = .028
      ..style = PaintingStyle.stroke;
    final thick = Paint()
      ..color = colors.ink.withValues(alpha: .82)
      ..strokeWidth = .06
      ..style = PaintingStyle.stroke;
    for (var k = 0; k <= 9; k++) {
      final p = k % 3 == 0 ? thick : thin;
      canvas.drawLine(Offset(0, k.toDouble()), Offset(9, k.toDouble()), p);
      canvas.drawLine(Offset(k.toDouble(), 0), Offset(k.toDouble(), 9), p);
    }
    // 共享边的外轮廓加粗。
    final shared = Paint()
      ..color = colors.ink
      ..strokeWidth = .085
      ..style = PaintingStyle.stroke;
    for (final local in map.sharedEdgeCells) {
      final r = local ~/ 9;
      final c = local % 9;
      bool isShared(int rr, int cc) =>
          rr >= 0 &&
          rr < 9 &&
          cc >= 0 &&
          cc < 9 &&
          map.sharedEdgeCells.contains(rr * 9 + cc);
      if (!isShared(r - 1, c)) {
        canvas.drawLine(
          Offset(c.toDouble(), r.toDouble()),
          Offset(c + 1.0, r.toDouble()),
          shared,
        );
      }
      if (!isShared(r + 1, c)) {
        canvas.drawLine(
          Offset(c.toDouble(), r + 1.0),
          Offset(c + 1.0, r + 1.0),
          shared,
        );
      }
      if (!isShared(r, c - 1)) {
        canvas.drawLine(
          Offset(c.toDouble(), r.toDouble()),
          Offset(c.toDouble(), r + 1.0),
          shared,
        );
      }
      if (!isShared(r, c + 1)) {
        canvas.drawLine(
          Offset(c + 1.0, r.toDouble()),
          Offset(c + 1.0, r + 1.0),
          shared,
        );
      }
    }
    _paintValues(canvas, map, geometry.mirrored(face));
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, geometry.u * .04)
        ..color = colors.ink.withValues(alpha: .78),
    );
  }

  // 局部坐标下字号只有 0.62 格，直接排版会被取整而整体偏左上；
  // 统一按 100px 排版，再在画布上缩放到目标格号大小。
  static const double _glyphBase = 100;

  void _paintValues(Canvas canvas, SudokuCubeFaceMap map, bool mirrored) {
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        final index = map.cellAt(r, c);
        if (!puzzle.isActive(index)) continue;
        final value = index < board.length ? board[index] : 0;
        final cx = c + .5;
        final cy = r + .5;
        if (value != 0) {
          final given =
              index < puzzle.givens.length && puzzle.givens[index] != 0;
          final conflict = conflicts.contains(index);
          final tp = _layoutGlyph(
            '$value',
            TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.fallback,
              fontWeight: given ? FontWeight.w700 : FontWeight.w600,
              color: conflict
                  ? colors.stamp
                  : (given ? colors.ink : colors.accentInk),
              height: 1,
            ),
          );
          _paintGlyph(canvas, tp, Offset(cx, cy), mirrored, .62);
        } else if (index < notes.length && notes[index].isNotEmpty) {
          _paintNotes(canvas, Offset(cx, cy), notes[index], mirrored);
        }
      }
    }
  }

  void _paintNotes(
    Canvas canvas,
    Offset center,
    Set<int> values,
    bool mirrored,
  ) {
    for (var n = 1; n <= 9; n++) {
      if (!values.contains(n)) continue;
      final r = (n - 1) ~/ 3;
      final c = (n - 1) % 3;
      final tp = _layoutGlyph(
        '$n',
        TextStyle(
          fontFamily: AppFonts.noto,
          fontWeight: FontWeight.w600,
          color: colors.ink2,
          height: 1,
        ),
      );
      _paintGlyph(
        canvas,
        tp,
        Offset(center.dx + (c - 1) * .22, center.dy + (r - 1) * .22),
        mirrored,
        .2,
      );
    }
  }

  TextPainter _layoutGlyph(String text, TextStyle style) => TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(fontSize: _glyphBase),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  void _paintGlyph(
    Canvas canvas,
    TextPainter tp,
    Offset center,
    bool mirrored,
    double emCells,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (mirrored) canvas.scale(-1, 1);
    canvas.scale(emCells / _glyphBase);
    // 数字字形落在基线以上，视觉中心比行框中心高约 5.6%，补回来。
    tp.paint(
      canvas,
      Offset(-tp.width / 2, -tp.height / 2 + tp.height * .056),
    );
    canvas.restore();
  }

  void _paintFocus(Canvas canvas, List<SudokuCubeFaceMap> maps) {
    final map = geometry.mapOf(maps, focusFace);
    if (map == null || !geometry.frontFacing(focusFace)) return;
    final path = Path()
      ..moveTo(
        geometry.point(focusFace, 0, 0).dx,
        geometry.point(focusFace, 0, 0).dy,
      )
      ..lineTo(
        geometry.point(focusFace, 0, 9).dx,
        geometry.point(focusFace, 0, 9).dy,
      )
      ..lineTo(
        geometry.point(focusFace, 9, 9).dx,
        geometry.point(focusFace, 9, 9).dy,
      )
      ..lineTo(
        geometry.point(focusFace, 9, 0).dx,
        geometry.point(focusFace, 9, 0).dy,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.4, geometry.u * .085)
        ..color = colors.accent.withValues(alpha: .92),
    );
  }

  @override
  bool shouldRepaint(covariant _SudokuCubePainter old) =>
      old.revision != revision ||
      old.selected != selected ||
      old.focusFace != focusFace ||
      old.puzzle != puzzle ||
      old.colors != colors ||
      old.geometry.u != geometry.u ||
      old.geometry.yaw != geometry.yaw ||
      old.geometry.pitch != geometry.pitch;
}
