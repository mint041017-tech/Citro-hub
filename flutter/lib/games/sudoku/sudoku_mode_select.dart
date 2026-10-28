import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/paper.dart';
import '../game_ui.dart';
import 'sudoku_modes.dart';

/// 统一数独入口的模式选择：经典 / 异形 / 高级阶数。
class SudokuModeSelect extends StatelessWidget {
  const SudokuModeSelect({super.key, required this.onStart});

  final void Function(SudokuModeSpec mode, SudokuDifficulty difficulty) onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final classic = kSudokuModes.first;
    final jigsaw = kSudokuModes.firstWhere((m) => m.key == 'jigsaw');
    final windmill = kSudokuModes.firstWhere((m) => m.key == 'windmill');
    final overlaps = kSudokuModes
        .where((m) => m.isOverlap && m.key != 'windmill')
        .toList();
    final advanced = sudokuModesInGroup(SudokuGroup.advanced);

    final hero = _Hero(
      glyph: _VariantGlyph(variant: SudokuVariant.classic, size: 86),
    );
    final classicSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupHeader(
          index: '01',
          title: '数独',
          subtitle: '经典九宫 · 四档难度',
        ),
        const SizedBox(height: 9),
        _ModeCard(
          mode: classic,
          onStart: onStart,
          glyph: _VariantGlyph(variant: SudokuVariant.classic, size: 72),
        ),
      ],
    );
    final jigsawSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const _GroupHeader(
          index: '02',
          title: '异形数独',
          subtitle: '宫形每局变化 · 风车 · 多盘重叠',
        ),
        const SizedBox(height: 9),
        LayoutBuilder(
          builder: (context, box) {
            final two = box.maxWidth >= 560;
            final w = two ? (box.maxWidth - 12) / 2 : box.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: w,
                  child: _ModeCard(
                    mode: jigsaw,
                    onStart: onStart,
                    glyph: _VariantGlyph(
                      variant: SudokuVariant.jigsaw,
                      size: 60,
                    ),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _ModeCard(
                    mode: windmill,
                    onStart: onStart,
                    glyph: _VariantGlyph(
                      variant: SudokuVariant.overlap,
                      overlapCount: 5,
                      windmill: true,
                      size: 60,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
    final overlapSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const _SubTitle(title: '重叠数独', hint: '共享宫格同数 · 盘数越多越难'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 620 ? 3 : 2;
            final w = (box.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in overlaps)
                  SizedBox(
                    width: w,
                    child: _CompactModeCard(
                      mode: m,
                      onStart: onStart,
                      glyph: _VariantGlyph(
                        variant: SudokuVariant.overlap,
                        overlapCount: m.overlapCount,
                        size: 44,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
    final advancedSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupHeader(
          index: '03',
          title: '高级阶数',
          subtitle: '规则变体 · 3D 立方',
        ),
        const SizedBox(height: 9),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 620 ? 3 : 2;
            final w = (box.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in advanced)
                  SizedBox(
                    width: w,
                    child: _CompactModeCard(
                      mode: m,
                      onStart: onStart,
                      glyph: _VariantGlyph(variant: m.variant, size: 44),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
    final footer = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          gameIcon(GameIcons.sparkle, size: 15, color: c.accentInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '每一局都复核唯一解；难度按逻辑技巧与搜索分支评级，'
              '标为“专家”的题目不能只靠最基础的裸单技巧推完。',
              style: context.body(
                size: 11.5,
                color: c.inkSoft,
                height: 1.65,
              ),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final media = MediaQuery.sizeOf(context);
        final wide = media.width > media.height && box.maxWidth >= 760;
        if (wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hero,
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        classicSection,
                        jigsawSection,
                        overlapSection,
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        advancedSection,
                        const SizedBox(height: 18),
                        footer,
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero,
            const SizedBox(height: 18),
            classicSection,
            jigsawSection,
            overlapSection,
            const SizedBox(height: 18),
            advancedSection,
            const SizedBox(height: 18),
            footer,
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

}

class _Hero extends StatelessWidget {
  const _Hero({required this.glyph});

  final Widget glyph;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line),
            boxShadow: CitroColors.shadows.paper(c),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUDOKU · 数独',
                      style: context
                          .hand(size: 12, color: c.accentInk)
                          .copyWith(letterSpacing: 1.6),
                    ),
                    const SizedBox(height: 4),
                    Text('选一种数独', style: context.heading(size: 27)),
                    const SizedBox(height: 5),
                    Text(
                      '经典九宫、异形宫形与高阶变体，全部唯一解。',
                      style: context.body(
                        size: 12,
                        color: c.inkSoft,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              glyph,
            ],
          ),
        ),
        Positioned(
          top: -8,
          left: 24,
          child: IgnorePointer(
            child: GameTape(
              width: 64,
              height: 18,
              color: c.accentLt.withValues(alpha: c.dark ? .35 : .75),
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.index,
    required this.title,
    required this.subtitle,
  });

  final String index;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 25,
              height: 25,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                index,
                style: const TextStyle(
                  fontFamily: AppFonts.kalam,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E2C22),
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(title, style: context.heading(size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: c.line)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 33, top: 3),
          child: Text(
            subtitle,
            style: context.body(size: 11, color: c.inkSoft),
          ),
        ),
      ],
    );
  }
}

class _SubTitle extends StatelessWidget {
  const _SubTitle({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Text(
          title,
          style: context.body(size: 13, weight: FontWeight.w700, color: c.ink2),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.body(size: 10.5, color: c.inkSoft),
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.onStart,
    required this.glyph,
  });

  final SudokuModeSpec mode;
  final void Function(SudokuModeSpec, SudokuDifficulty) onStart;
  final Widget glyph;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line2),
        boxShadow: CitroColors.shadows.paper(c),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          glyph,
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        mode.title,
                        style: context.body(
                          size: 15,
                          weight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (mode.variant == SudokuVariant.jigsaw) ...[
                      const SizedBox(width: 6),
                      _Tag(text: '每局不同'),
                    ],
                    if (mode.key == 'windmill') ...[
                      const SizedBox(width: 6),
                      _Tag(text: '5 盘'),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  mode.blurb,
                  style: context.body(
                    size: 10.5,
                    color: c.inkSoft,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    for (final d in mode.difficulties)
                      _StartChip(
                        label: mode.difficulties.length == 1
                            ? '开始 · ${d.label}'
                            : d.label,
                        onTap: () => onStart(mode, d),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactModeCard extends StatelessWidget {
  const _CompactModeCard({
    required this.mode,
    required this.onStart,
    required this.glyph,
  });

  final SudokuModeSpec mode;
  final void Function(SudokuModeSpec, SudokuDifficulty) onStart;
  final Widget glyph;

  bool get _largeBoard =>
      mode.variant == SudokuVariant.overlap ||
      mode.variant == SudokuVariant.cube3d;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line2),
        boxShadow: CitroColors.shadows.paper(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              glyph,
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.title,
                      style: context.body(
                        size: 13,
                        weight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode.blurb,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: 9.5,
                        color: c.inkSoft,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              for (final d in mode.difficulties)
                _StartChip(
                  label: mode.difficulties.length == 1 ? d.label : d.label,
                  compact: true,
                  onTap: () => onStart(mode, d),
                ),
              if (_largeBoard && MediaQuery.sizeOf(context).shortestSide < 600)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.bg2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.line),
                  ),
                  child: Text(
                    '手机建议 iPad/桌面/网页',
                    style: context.body(
                      size: 8.5,
                      color: c.inkSoft,
                      height: 1.2,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.accentLt.withValues(alpha: c.dark ? .24 : .55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: context.body(
          size: 8.5,
          weight: FontWeight.w700,
          color: c.accentInk,
          height: 1.2,
        ),
      ),
    );
  }
}

class _StartChip extends StatelessWidget {
  const _StartChip({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      scale: .96,
      child: Container(
        height: compact ? 25 : 28,
        padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 11),
        decoration: BoxDecoration(
          color: c.hl,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.accent.withValues(alpha: .55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.body(
                size: compact ? 10 : 11,
                weight: FontWeight.w700,
                color: c.accentInk,
                height: 1,
              ),
            ),
            const SizedBox(width: 3),
            gameIcon(
              GameIcons.arrowRightSolid,
              size: compact ? 8 : 9,
              color: c.accentInk,
            ),
          ],
        ),
      ),
    );
  }
}

/// 模式小图标：用极简线稿区分经典 / 异形 / 雪花 / 重叠 / 高阶变体。
class _VariantGlyph extends StatelessWidget {
  const _VariantGlyph({
    required this.variant,
    required this.size,
    this.overlapCount = 0,
    this.windmill = false,
  });

  final SudokuVariant variant;
  final double size;
  final int overlapCount;
  final bool windmill;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(size * .22),
        border: Border.all(color: c.line),
      ),
      child: CustomPaint(
        painter: _GlyphPainter(
          variant: variant,
          overlapCount: overlapCount,
          windmill: windmill,
          ink: c.ink2,
          accent: c.accent,
          soft: c.line2,
          paper: c.surface2,
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({
    required this.variant,
    required this.overlapCount,
    required this.windmill,
    required this.ink,
    required this.accent,
    required this.soft,
    required this.paper,
  });

  final SudokuVariant variant;
  final int overlapCount;
  final bool windmill;
  final Color ink;
  final Color accent;
  final Color soft;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final pad = s * .16;
    final rect = Rect.fromLTWH(pad, pad, s - pad * 2, s - pad * 2);
    final line = Paint()
      ..color = ink.withValues(alpha: .72)
      ..strokeWidth = math.max(1.0, s * .018)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    switch (variant) {
      case SudokuVariant.classic:
        _grid(canvas, rect, line, 3);
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, rect.width / 3, rect.height / 3),
          Paint()..color = accent.withValues(alpha: .28),
        );
        break;
      case SudokuVariant.jigsaw:
        _jigsaw(canvas, rect, line, accent);
        break;
      case SudokuVariant.snowflake:
        _snowflake(canvas, rect, line, accent);
        break;
      case SudokuVariant.overlap:
        _overlap(canvas, rect, line, accent);
        break;
      case SudokuVariant.evenOdd:
        _grid(canvas, rect, line, 3);
        for (var r = 0; r < 3; r++) {
          for (var c = 0; c < 3; c++) {
            if ((r + c).isEven) {
              canvas.drawRect(
                Rect.fromLTWH(
                  rect.left + c * rect.width / 3,
                  rect.top + r * rect.height / 3,
                  rect.width / 3,
                  rect.height / 3,
                ),
                Paint()..color = accent.withValues(alpha: .22),
              );
            }
          }
        }
        break;
      case SudokuVariant.diagonal:
        _grid(canvas, rect, line, 3);
        final d = Paint()
          ..color = accent.withValues(alpha: .75)
          ..strokeWidth = math.max(1.0, s * .02)
          ..style = PaintingStyle.stroke;
        canvas.drawLine(rect.topLeft, rect.bottomRight, d);
        canvas.drawLine(rect.topRight, rect.bottomLeft, d);
        break;
      case SudokuVariant.inequality:
        _grid(canvas, rect, line, 3);
        _chevron(canvas, rect, accent);
        break;
      case SudokuVariant.killer:
        _killer(canvas, rect, line, accent, soft);
        break;
      case SudokuVariant.cube3d:
        _cube(canvas, rect, line, accent, soft);
        break;
    }
  }

  void _grid(Canvas canvas, Rect r, Paint p, int n) {
    for (var i = 1; i < n; i++) {
      final x = r.left + r.width * i / n;
      final y = r.top + r.height * i / n;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), p);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), p);
    }
    canvas.drawRect(r, p);
  }

  void _jigsaw(Canvas canvas, Rect r, Paint p, Color accent) {
    final cell = r.width / 5;
    final path = Path()..addRect(r);
    // 不规则粗线：5×5 网格里挑几条错位边，形成异形宫的感觉。
    for (var i = 1; i < 5; i++) {
      final x = r.left + cell * i;
      final y = r.top + cell * i;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.top + cell * 2), p);
      canvas.drawLine(Offset(x, r.bottom - cell * 2), Offset(x, r.bottom), p);
      canvas.drawLine(Offset(r.left, y), Offset(r.left + cell * 2, y), p);
      canvas.drawLine(Offset(r.right - cell * 2, y), Offset(r.right, y), p);
    }
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.top, cell * 2, cell * 2),
      Paint()..color = accent.withValues(alpha: .22),
    );
    canvas.drawPath(path, p);
  }

  void _snowflake(Canvas canvas, Rect r, Paint p, Color accent) {
    final center = r.center;
    final radius = r.width * .46;
    final a = Paint()
      ..color = accent.withValues(alpha: .55)
      ..strokeWidth = math.max(1.2, r.width * .025)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final tip = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawLine(center, tip, p);
      final branch =
          tip - Offset(math.cos(angle), math.sin(angle)) * radius * .32;
      for (final sign in [-1, 1]) {
        final ba = angle + sign * math.pi / 4;
        canvas.drawLine(
          branch,
          branch + Offset(math.cos(ba), math.sin(ba)) * radius * .26,
          a,
        );
      }
    }
    canvas.drawCircle(center, radius * .11, Paint()..color = accent);
  }

  void _overlap(Canvas canvas, Rect r, Paint p, Color accent) {
    final count = overlapCount <= 0 ? 2 : overlapCount;
    // 虚拟坐标：一个 9×9 子盘边长 9，偏移取 3 的倍数。
    final origins = <Offset>[];
    if (count == 2) {
      origins.addAll([Offset.zero, const Offset(6, 0)]);
    } else if (count == 3) {
      origins.addAll([Offset.zero, const Offset(6, 0), const Offset(0, 6)]);
    } else if (count == 4) {
      // 与内核一致：四盘绕中心空洞的风车。
      origins.addAll([
        const Offset(6, 0),
        const Offset(0, 6),
        const Offset(12, 6),
        const Offset(6, 12),
      ]);
    } else if (count == 5 && windmill) {
      origins.addAll([
        const Offset(3, 0),
        const Offset(12, 3),
        const Offset(9, 12),
        const Offset(0, 9),
        const Offset(6, 6),
      ]);
    } else if (count == 5) {
      origins.addAll([
        Offset.zero,
        const Offset(12, 0),
        const Offset(0, 12),
        const Offset(12, 12),
        const Offset(6, 6),
      ]);
    } else if (count == 8) {
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 3; col++) {
          if (row == 1 && col == 1) continue;
          origins.add(Offset(col * 6, row * 6));
        }
      }
    } else {
      for (var row = -2; row <= 2; row++) {
        for (var col = -2; col <= 2; col++) {
          if (row.abs() + col.abs() <= 2) {
            origins.add(Offset(12 + col * 6, 12 + row * 6));
          }
        }
      }
    }
    final boxes = [for (final o in origins) Rect.fromLTWH(o.dx, o.dy, 9, 9)];
    var union = boxes.first;
    for (final b in boxes.skip(1)) {
      union = union.expandToInclude(b);
    }
    final scale = math.min(r.width / union.width, r.height / union.height);
    final dx = r.left + (r.width - union.width * scale) / 2;
    final dy = r.top + (r.height - union.height * scale) / 2;
    Rect map(Rect b) => Rect.fromLTWH(
      dx + (b.left - union.left) * scale,
      dy + (b.top - union.top) * scale,
      b.width * scale,
      b.height * scale,
    );
    final fill = Paint()..color = accent.withValues(alpha: .14);
    final stroke = Paint()
      ..color = p.color
      ..strokeWidth = math.max(.7, p.strokeWidth * .7)
      ..style = PaintingStyle.stroke;
    for (final box in boxes) {
      final mapped = map(box);
      canvas.drawRect(mapped, fill);
      canvas.drawRect(mapped, stroke);
    }
  }

  void _chevron(Canvas canvas, Rect r, Color accent) {
    final p = Paint()
      ..color = accent
      ..strokeWidth = math.max(1.2, r.width * .025)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final mid = r.center;
    final d = r.width * .08;
    canvas.drawLine(mid + Offset(-d, -d), mid + Offset(d, 0), p);
    canvas.drawLine(mid + Offset(d, 0), mid + Offset(-d, d), p);
  }

  void _killer(Canvas canvas, Rect r, Paint p, Color accent, Color soft) {
    _grid(canvas, r, p, 3);
    final dash = Paint()
      ..color = accent.withValues(alpha: .8)
      ..strokeWidth = math.max(1.1, r.width * .022)
      ..style = PaintingStyle.stroke;
    final box = Rect.fromLTWH(
      r.left + r.width / 3,
      r.top + r.height / 3,
      r.width * .5,
      r.height * .5,
    );
    const dashW = 3.0;
    for (var x = box.left; x < box.right; x += dashW * 2) {
      canvas.drawLine(
        Offset(x, box.top),
        Offset(math.min(x + dashW, box.right), box.top),
        dash,
      );
      canvas.drawLine(
        Offset(x, box.bottom),
        Offset(math.min(x + dashW, box.right), box.bottom),
        dash,
      );
    }
    for (var y = box.top; y < box.bottom; y += dashW * 2) {
      canvas.drawLine(
        Offset(box.left, y),
        Offset(box.left, math.min(y + dashW, box.bottom)),
        dash,
      );
      canvas.drawLine(
        Offset(box.right, y),
        Offset(box.right, math.min(y + dashW, box.bottom)),
        dash,
      );
    }
    canvas.drawCircle(
      Offset(box.left + 3, box.top + 3),
      2.2,
      Paint()..color = accent,
    );
  }

  void _cube(Canvas canvas, Rect r, Paint p, Color accent, Color soft) {
    final w = r.width * .68;
    final h = r.height * .52;
    final dx = r.width * .16;
    final dy = r.height * .16;
    final front = Rect.fromLTWH(
      r.left + dx * .4,
      r.top + r.height - h - 2,
      w,
      h,
    );
    final fill = Paint()..color = accent.withValues(alpha: .14);
    for (var i = 2; i >= 0; i--) {
      final layer = front.translate(dx * i * .55, -dy * i * .55);
      canvas.drawRect(layer, fill);
      canvas.drawRect(layer, p);
    }
    canvas.drawLine(front.topLeft, front.topLeft + Offset(dx, -dy), p);
    canvas.drawLine(front.topRight, front.topRight + Offset(dx, -dy), p);
    canvas.drawLine(front.bottomRight, front.bottomRight + Offset(dx, -dy), p);
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.variant != variant ||
      old.overlapCount != overlapCount ||
      old.ink != ink ||
      old.accent != accent ||
      old.soft != soft ||
      old.paper != paper;
}
