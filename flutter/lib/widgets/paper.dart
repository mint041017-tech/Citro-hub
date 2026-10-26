import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 24px 网格纸 + 纸纹。对应 .main-root 的背景。
class PaperBackground extends StatelessWidget {
  final Widget child;
  final Color? color;
  final bool grid;
  final bool wallpaper;

  const PaperBackground({
    super.key,
    required this.child,
    this.color,
    this.grid = true,
    this.wallpaper = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CustomPaint(
      // 背景网格是静态的：允许引擎把它缓存成位图，滚动/切页时不再重画网格线。
      isComplex: true,
      willChange: false,
      painter: _PaperPainter(
        color: color ?? c.surface,
        gridColor: c.grid,
        grid: grid,
        highlight: c.dark ? const Color(0x0CFFCE8E) : const Color(0x80FFF6E0),
        wallpaper: wallpaper,
      ),
      child: child,
    );
  }
}

class _PaperPainter extends CustomPainter {
  final Color color;
  final Color gridColor;
  final bool grid;
  final Color highlight;
  final bool wallpaper;

  _PaperPainter({
    required this.color,
    required this.gridColor,
    required this.grid,
    required this.highlight,
    required this.wallpaper,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (wallpaper) {
      final gradient = _gradient(rect);
      canvas.drawRect(rect, Paint()..shader = gradient);
    } else {
      canvas.drawRect(rect, Paint()..color = color);
      final g = Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.82, -0.95),
          radius: 0.75,
          colors: [highlight, highlight.withAlpha(0)],
        ).createShader(rect);
      canvas.drawRect(rect, g);
    }
    if (!grid) return;
    final line = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y + .5), Offset(size.width, y + .5), line);
    }
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x + .5, 0), Offset(x + .5, size.height), line);
    }
  }

  Shader _gradient(Rect rect) {
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFEBE4D5), Color(0xFFE4DCC9)],
      stops: [0, 1],
    ).createShader(rect);
  }

  @override
  bool shouldRepaint(covariant _PaperPainter old) =>
      old.color != color || old.gridColor != gridColor || old.grid != grid;
}

/// 纸胶带。默认 92x24，顶端居中，带撕边。
class Tape extends StatelessWidget {
  final Color color;
  final double width;
  final double height;
  final double angle;
  final Color? shadowColor;
  final double top;
  final double? left;
  final bool torn;

  const Tape({
    super.key,
    required this.color,
    this.width = 92,
    this.height = 24,
    this.angle = -2.5,
    this.shadowColor,
    this.top = 0,
    this.left,
    this.torn = true,
  });

  @override
  Widget build(BuildContext context) {
    final tape = ClipPath(
      clipper: torn ? _TapeClipper() : null,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          boxShadow: [
            BoxShadow(
              color: shadowColor ?? const Color(0x1A786040),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
    return Positioned(
      top: top,
      left: left,
      right: left == null ? null : null,
      child: left == null
          ? Align(
              alignment: Alignment.topCenter,
              child: Transform.rotate(
                angle: angle * math.pi / 180,
                child: tape,
              ),
            )
          : Transform.rotate(angle: angle * math.pi / 180, child: tape),
    );
  }
}

class _TapeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * .02, size.height * .06)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * .97, size.height * .94)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

enum PaperShadow { paper, large, note, none }

/// 手账卡纸。支持整卡微旋、顶部纸胶带、便签配色与右下折角。
class PaperCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final PaperShadow shadow;
  final double rotate;
  final Color? tapeColor;
  final double? tapeWidth;
  final double? tapeHeight;
  final double tapeAngle;
  final double tapeTop;
  final bool fold;
  final bool clip;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final BoxConstraints? constraints;

  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.margin,
    this.color,
    this.borderColor,
    this.radius = 14,
    this.shadow = PaperShadow.paper,
    this.rotate = 0,
    this.tapeColor,
    this.tapeWidth,
    this.tapeHeight,
    this.tapeAngle = -2.5,
    this.tapeTop = -9,
    this.fold = false,
    this.clip = false,
    this.borderRadius,
    this.onTap,
    this.constraints,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final br = borderRadius ?? BorderRadius.circular(radius);
    Widget box = Container(
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface2,
        borderRadius: br,
        border: Border.all(color: borderColor ?? c.line, width: 1),
        boxShadow: switch (shadow) {
          PaperShadow.paper => CitroColors.shadows.paper(c),
          PaperShadow.large => CitroColors.shadows.lg(c),
          PaperShadow.note => CitroColors.shadows.note(c),
          PaperShadow.none => const [],
        },
      ),
      child: clip ? ClipRRect(borderRadius: br, child: child) : child,
    );
    if (fold) {
      box = Stack(
        clipBehavior: Clip.none,
        children: [
          box,
          Positioned(
            right: 0,
            bottom: 0,
            child: ClipPath(
              clipper: _FoldClipper(corner: 18, radius: br.bottomRight.x),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c.surface2, c.line.withAlpha(200)],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (rotate != 0) {
      box = Transform.rotate(angle: rotate * math.pi / 180, child: box);
    }
    if (tapeColor != null) {
      box = Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        children: [
          box,
          Positioned(
            top: tapeTop,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.rotate(
                angle: tapeAngle * math.pi / 180,
                child: Opacity(
                  opacity: 1,
                  child: ClipPath(
                    clipper: _TapeClipper(),
                    child: Container(
                      width: tapeWidth ?? 92,
                      height: tapeHeight ?? 24,
                      decoration: BoxDecoration(
                        color: tapeColor,
                        boxShadow: [
                          BoxShadow(
                            color: c.tapeLine,
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (onTap != null) {
      box = Pressable(onTap: onTap, scale: .985, borderRadius: br, child: box);
    }
    if (margin != null) {
      return Padding(padding: margin!, child: box);
    }
    return box;
  }
}

class _FoldClipper extends CustomClipper<Path> {
  final double corner;
  final double radius;
  _FoldClipper({required this.corner, required this.radius});

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - 3)
      ..lineTo(size.width - 3, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _FoldClipper old) => false;
}

/// 虚线分隔线。
class DashedLine extends StatelessWidget {
  final Color? color;
  final double height;
  final double dash;
  final double gap;
  final double thickness;

  const DashedLine({
    super.key,
    this.color,
    this.height = 1,
    this.dash = 4,
    this.gap = 4,
    this.thickness = 1,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _DashPainter(
          color: color ?? context.c.line2,
          dash: dash,
          gap: gap,
          thickness: thickness,
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  final double dash;
  final double gap;
  final double thickness;
  _DashPainter({
    required this.color,
    required this.dash,
    required this.gap,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + dash, size.width), size.height / 2),
        p,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) =>
      old.color != color || old.dash != dash || old.gap != gap;
}

/// 标题（橙色短横 + 荧光笔底纹）。对应 .tile-title。
class SectionTitle extends StatelessWidget {
  final String text;
  final double size;
  final EdgeInsetsGeometry padding;

  const SectionTitle(
    this.text, {
    super.key,
    this.size = 23,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Transform.rotate(
            angle: -3 * math.pi / 180,
            child: Container(
              width: 16,
              height: 5,
              margin: const EdgeInsets.only(right: 9, top: 4),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          HighlightedText(
            text,
            style: context.heading(
              size: size,
              color: c.ink,
              letterSpacing: .02 * size,
            ),
            highlight: c.hl,
          ),
        ],
      ),
    );
  }
}

/// 下半段黄色荧光笔底纹的文本。
class HighlightedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color highlight;
  final bool rotate;

  const HighlightedText(
    this.text, {
    super.key,
    required this.style,
    required this.highlight,
    this.rotate = true,
  });

  @override
  Widget build(BuildContext context) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final h = tp.height;
    final bar = Positioned(
      left: 0,
      right: 0,
      top: h * .58,
      height: h * .36,
      child: Transform.rotate(
        angle: rotate ? -.7 * math.pi / 180 : 0,
        child: Container(color: highlight),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        bar,
        Text(text, style: style, maxLines: 1, softWrap: false),
      ],
    );
  }
}

/// 手写小标签胶囊。
class HandChip extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? bg;
  final EdgeInsets padding;
  final double size;
  final Border? border;

  const HandChip(
    this.text, {
    super.key,
    this.color,
    this.bg,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    this.size = 12,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg ?? Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: border ?? Border.all(color: c.line2),
      ),
      child: Text(
        text,
        style: context.display(
          size: size,
          color: color ?? c.accentInk,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

/// 通用图标：内联 SVG（1:1 复刻站点图标）。
class AppIcon extends StatelessWidget {
  final String svg;
  final double size;
  final Color? color;

  const AppIcon(this.svg, {super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color ?? context.c.ink2, BlendMode.srcIn),
    );
  }
}

String strokeSvg(String body, {double width = 2, String color = '#000000'}) =>
    '<svg viewBox="0 0 24 24" fill="none" stroke="$color" stroke-width="$width" '
    'stroke-linecap="round" stroke-linejoin="round">$body</svg>';

/// 常用路径（来源 index.html）。
class AppIcons {
  static const home =
      '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 10v10h14V10"/>';
  static const games =
      '<path d="M6 12h4M8 10v4"/><circle cx="15.5" cy="10.5" r="1"/><circle cx="17.5" cy="13.5" r="1"/><rect x="2" y="6" width="20" height="12" rx="4"/>';
  static const users =
      '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>';
  static const user =
      '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>';
  static const arrowLeft = '<path d="M19 12H5"/><path d="M12 19l-7-7 7-7"/>';
  static const arrowRight = '<path d="M5 12h14"/><path d="m13 6 6 6-6 6"/>';
  static const arrowUpRight = '<path d="M7 17 17 7"/><path d="M8 7h9v9"/>';
  static const clock = '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>';
  static const calendar =
      '<path d="M8 3v3M16 3v3M3.5 9.5h17"/><rect x="3.5" y="5" width="17" height="16" rx="3.4"/><path d="M8.6 14.2l2.4 2.4 4.6-4.8"/>';
  static const search =
      '<circle cx="11" cy="11" r="8"/><path d="M21 21l-4.3-4.3"/>';
  static const plus = '<path d="M12 5v14M5 12h14"/>';
  static const minus = '<path d="M5 12h14"/>';
  static const close = '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>';
  static const maximize = '<rect x="5" y="5" width="14" height="14" rx="2.4"/>';
  static const restore =
      '<rect x="8" y="3.5" width="12.5" height="12.5" rx="2.2"/><path d="M3.5 8.5v9a2 2 0 0 0 2 2h9"/>';
  static const library =
      '<rect x="3" y="3" width="7.2" height="7.2" rx="1.8"/><rect x="13.8" y="3" width="7.2" height="7.2" rx="1.8"/><rect x="3" y="13.8" width="7.2" height="7.2" rx="1.8"/><rect x="13.8" y="13.8" width="7.2" height="7.2" rx="1.8"/>';
  static const download =
      '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>';
  static const edit =
      '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>';
  static const note =
      '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="9" y1="13" x2="15" y2="13"/><line x1="9" y1="17" x2="13" y2="17"/>';
  static const logout =
      '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>';
  static const monitor =
      '<rect x="2" y="4" width="20" height="14" rx="2"/><path d="M8 21h8"/><path d="M12 18v3"/>';
  static const sun =
      '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>';
  static const moon =
      '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>';
  static const star =
      '<circle cx="12" cy="12" r="9"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1"/><circle cx="12" cy="12" r="2.2"/>';
  static const trophy =
      '<path d="M8 21h8"/><path d="M12 17v4"/><path d="M6 3h12v6a6 6 0 0 1-12 0z"/><path d="M18 5h2a2 2 0 0 1 0 6h-2"/><path d="M6 5H4a2 2 0 0 0 0 6h2"/>';
  static const refresh =
      '<path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 3v6h-6"/>';
  static const location =
      '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z"/><circle cx="12" cy="10" r="3"/>';
  static const bell =
      '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>';
  static const sparkle =
      '<path d="M12 3l1.9 5.8a2 2 0 0 0 1.3 1.3L21 12l-5.8 1.9a2 2 0 0 0-1.3 1.3L12 21l-1.9-5.8a2 2 0 0 0-1.3-1.3L3 12l5.8-1.9a2 2 0 0 0 1.3-1.3L12 3z"/>';
  static const play = '<polygon points="5 3 19 12 5 21 5 3"/>';
  static const trash =
      '<polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>';
  static const image =
      '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9.5" r="1.5"/><path d="M21 16l-5-5-7 7"/>';
  static const camera =
      '<path d="M4 7h3l2-2h6l2 2h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1z"/><circle cx="12" cy="13" r="4"/>';
  static const mic =
      '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><line x1="12" y1="18" x2="12" y2="21"/><line x1="9" y1="21" x2="15" y2="21"/>';
  static const heart =
      '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8l1.1 1.1L12 21l7.8-7.5 1.1-1.1a5.5 5.5 0 0 0-.1-7.8z"/>';
  static const hug =
      '<path d="M17 21v-2a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v2"/><circle cx="10" cy="7" r="4"/><path d="M21 11l-2 2-2-2"/>';
  static const comment =
      '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>';
  static const book =
      '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/><path d="M9 7h7"/><path d="M9 11h5"/>';
  static const globe =
      '<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 0 1 0 18a15 15 0 0 1 0-18z"/>';
  static const cart =
      '<circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/>';
  static const fork =
      '<path d="M3 2v7c0 1.1.9 2 2 2h0a2 2 0 0 0 2-2V2"/><path d="M5 2v20"/><path d="M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3zm0 0v7"/>';
  static const menu =
      '<path d="M4 5h16"/><path d="M4 12h16"/><path d="M4 19h9"/>';
  static const inbox =
      '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>';
  static const send =
      '<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4z"/>';
  static const eye =
      '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>';
  static const lock =
      '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>';
  static const chevronDown = '<path d="m6 9 6 6 6-6"/>';
  static const chevronLeft = '<path d="m15 18-6-6 6-6"/>';
  static const chevronRight = '<path d="m9 18 6-6-6-6"/>';
  static const copy =
      '<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>';
}

/// 点击缩放包装。
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? hoverOverlayColor;
  final double hoverLift;
  final bool? hoverShadow;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = .97,
    this.borderRadius,
    this.hoverColor,
    this.hoverOverlayColor,
    this.hoverLift = 2.5,
    this.hoverShadow,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;
  bool _focused = false;

  void _activate() => widget.onTap?.call();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final c = context.c;
    final hoverShadow = widget.hoverShadow ?? !kIsWeb;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        if (enabled && !_hover) setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(
              0,
              _hover && !_down ? -widget.hoverLift : 0,
              0,
            ),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: hoverShadow && widget.borderRadius != null
                  ? [
                      BoxShadow(
                        color: _hover && !_down
                            ? (c.dark
                                  ? const Color(0x66000000)
                                  : const Color(0x385A4A2C))
                            : Colors.transparent,
                        blurRadius: _hover && !_down ? 22 : 0,
                        spreadRadius: _hover && !_down ? -12 : 0,
                        offset: const Offset(0, 9),
                      ),
                    ]
                  : const [],
            ),
            child: AnimatedScale(
              scale: _down
                  ? widget.scale
                  : (_hover ? 1.016 : (_focused ? 1.016 : 1)),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              child:
                  widget.hoverColor == null && widget.hoverOverlayColor == null
                  ? widget.child
                  : Stack(
                      fit: StackFit.passthrough,
                      children: [
                        if (widget.hoverColor != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: _hover ? 1 : 0,
                                duration: const Duration(milliseconds: 140),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: widget.hoverColor,
                                    borderRadius:
                                        widget.borderRadius ??
                                        BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        widget.child,
                        if (widget.hoverOverlayColor != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: _hover ? 1 : 0,
                                duration: const Duration(milliseconds: 140),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: widget.hoverOverlayColor,
                                    borderRadius:
                                        widget.borderRadius ??
                                        BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppToast {
  static OverlayEntry? _entry;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1800),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry?.remove();
    _entry = OverlayEntry(
      builder: (ctx) {
        final c = ctx.c;
        // v1.6.2：全局轻提示统一显示在屏幕上方（用户反馈：文字游戏上下
        // 各有一条 toast，且键盘弹出时底部提示被遮）。
        return Positioned(
          left: 24,
          right: 24,
          top: MediaQuery.paddingOf(ctx).top + 88,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: c.ink.withAlpha(240),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: CitroColors.shadows.paper(c),
                ),
                child: Text(
                  message,
                  style: ctx.body(size: 13, color: c.surface2),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
    Future.delayed(duration, () {
      _entry?.remove();
      _entry = null;
    });
  }
}

Future<void> copyText(
  String text, {
  BuildContext? context,
  String tip = '已复制',
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context != null && context.mounted) AppToast.show(context, tip);
}
