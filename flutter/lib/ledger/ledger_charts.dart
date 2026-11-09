import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'ledger_theme.dart';

/// 记账看板的两个轻量图表，全部自绘：不引第三方图表库，
/// 也避免动画每帧重排整页。绘制范围只包在 RepaintBoundary 里。
class LedgerBarChart extends StatelessWidget {
  final List<({DateTime day, int expense, int income})> data;
  final double height;

  /// 只显示最近 N 天；null 表示整个月。
  final int? limit;

  const LedgerBarChart({
    super.key,
    required this.data,
    this.height = 132,
    this.limit,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = (limit == null || limit! >= data.length)
        ? data
        : data.sublist(data.length - limit!);
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarPainter(
            data: rows,
            line: c.line2,
            grid: c.grid,
            expense: c.accent2,
            todayColor: c.dark ? const Color(0xFFE7AEB7) : ledgerCoral,
            income: c.mintInk,
            inkSoft: c.inkSoft,
            today: DateTime.now(),
            dark: c.dark,
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<({DateTime day, int expense, int income})> data;
  final Color line;
  final Color grid;
  final Color expense;
  final Color income;
  final Color todayColor;
  final Color inkSoft;
  final DateTime today;
  final bool dark;

  _BarPainter({
    required this.data,
    required this.line,
    required this.grid,
    required this.expense,
    required this.income,
    required this.todayColor,
    required this.inkSoft,
    required this.today,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0) return;
    const labelH = 18.0;
    final plotH = size.height - labelH;
    final maxCents = data.fold<int>(
      0,
      (m, e) => math.max(m, math.max(e.expense, e.income)),
    );
    final safeMax = maxCents <= 0 ? 1 : maxCents;
    final gap = data.length > 20 ? 2.0 : (data.length > 10 ? 3.0 : 5.0);
    final slot = size.width / data.length;
    final barW = math.max(2.0, slot - gap);

    // 三条很淡的水平参考线，保留手帐纸的格线感。
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = plotH - plotH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final base = Paint()
      ..color = line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, plotH), Offset(size.width, plotH), base);

    final barPaint = Paint()..style = PaintingStyle.fill;
    final incomePaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < data.length; i++) {
      final row = data[i];
      final x = slot * i + (slot - barW) / 2;
      final isToday =
          row.day.year == today.year &&
          row.day.month == today.month &&
          row.day.day == today.day;
      final expH = row.expense <= 0
          ? 0.0
          : math.max(2.0, plotH * row.expense / safeMax);
      barPaint.color = isToday ? todayColor : expense.withAlpha(190);
      if (expH > 0) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, plotH - expH, barW, expH),
          const Radius.circular(3),
        );
        canvas.drawRRect(rect, barPaint);
      }
      // 收入用顶部一条细绿线表示，和支出柱不抢位置。
      final incH = row.income <= 0
          ? 0.0
          : math.max(2.0, plotH * row.income / safeMax);
      if (incH > 0) {
        incomePaint.color = income.withAlpha(isToday ? 255 : 170);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, plotH - incH, barW, math.min(3.0, incH)),
            const Radius.circular(2),
          ),
          incomePaint,
        );
      }
      if (data.length <= 12 ||
          i == 0 ||
          i == data.length - 1 ||
          isToday ||
          (i + 1) % 5 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${row.day.day}',
            style: TextStyle(
              color: isToday ? expense : inkSoft,
              fontSize: 9,
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + (barW - tp.width) / 2, plotH + 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.data != data ||
      old.line != line ||
      old.expense != expense ||
      old.income != income ||
      old.todayColor != todayColor ||
      old.dark != dark;
}

/// 分类占比环图。段数控制在 5 段以内，其余合并成「其他」。
class LedgerDonutChart extends StatelessWidget {
  final List<({String label, int value, Color color})> segments;
  final double size;
  final String centerLabel;
  final String centerValue;

  const LedgerDonutChart({
    super.key,
    required this.segments,
    this.size = 132,
    this.centerLabel = '支出',
    this.centerValue = '',
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DonutPainter(
            segments: segments,
            track: c.line,
            label: c.inkSoft,
            ink: c.ink,
            centerLabel: centerLabel,
            centerValue: centerValue,
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<({String label, int value, Color color})> segments;
  final Color track;
  final Color label;
  final Color ink;
  final String centerLabel;
  final String centerValue;

  _DonutPainter({
    required this.segments,
    required this.track,
    required this.label,
    required this.ink,
    required this.centerLabel,
    required this.centerValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 9;
    final stroke = math.max(10.0, size.shortestSide * .12);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(center, radius, base);

    final total = segments.fold<int>(0, (sum, e) => sum + e.value);
    if (total > 0) {
      var start = -math.pi / 2;
      const gap = .045;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      for (final segment in segments) {
        final sweep = math.max(.04, 2 * math.pi * segment.value / total - gap);
        paint.color = segment.color;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          start + gap / 2,
          sweep,
          false,
          paint,
        );
        start += 2 * math.pi * segment.value / total;
      }
    }

    final valueText = TextPainter(
      text: TextSpan(
        text: centerValue,
        style: TextStyle(
          color: ink,
          fontSize: size.shortestSide * .15,
          fontWeight: FontWeight.w700,
          fontFamily: AppFonts.kalam,
          fontFamilyFallback: AppFonts.fallback,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: radius * 1.5);
    final labelText = TextPainter(
      text: TextSpan(
        text: centerLabel,
        style: TextStyle(
          color: label,
          fontSize: 10,
          fontFamily: AppFonts.noto,
          fontFamilyFallback: AppFonts.bodyFallback,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    valueText.paint(
      canvas,
      Offset(center.dx - valueText.width / 2, center.dy - valueText.height + 3),
    );
    labelText.paint(
      canvas,
      Offset(center.dx - labelText.width / 2, center.dy + 4),
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.segments != segments ||
      old.track != track ||
      old.centerValue != centerValue ||
      old.centerLabel != centerLabel;
}
