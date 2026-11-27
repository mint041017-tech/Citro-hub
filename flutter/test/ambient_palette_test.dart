import 'dart:math' as math;

import 'package:citro/theme/ambient_palette.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractAccentColor', () {
    test('按彩度加权取主色，忽略灰像素', () {
      // 左半纯红、右半中灰：灰的彩度为 0，不参与。
      final c = extractAccentColor(100, 100, (x, y) {
        if (x < 50) return (220, 40, 40);
        return (128, 128, 128);
      })!;
      expect(c.r * 255, greaterThan(200));
      expect(c.g * 255, lessThan(60));
    });

    test('整张图无彩色时返回 null', () {
      expect(
        extractAccentColor(10, 10, (_, _) => (90, 90, 90)),
        isNull,
      );
    });
  });

  group('AmbientPalette', () {
    tearDown(() => AmbientPalette.apply(null));

    test('无主色时就是默认令牌', () {
      expect(identical(AmbientPalette.light, CitroColors.light), isTrue);
      expect(identical(AmbientPalette.dark, CitroColors.darkColors), isTrue);
    });

    test('强调色一族换到主色色相，语义色与文字色不动', () {
      AmbientPalette.apply(const Color(0xFFD05050));
      final l = AmbientPalette.light;
      final d = AmbientPalette.dark;
      expect(HSLColor.fromColor(l.accent).hue, closeTo(0, 12));
      expect(HSLColor.fromColor(d.accent).hue, closeTo(0, 12));
      expect(HSLColor.fromColor(l.accentLt).hue, closeTo(0, 12));
      expect(HSLColor.fromColor(l.accentInk).hue, closeTo(0, 12));
      expect(HSLColor.fromColor(l.hl).hue, closeTo(0, 12));
      expect(l.hl.a, CitroColors.light.hl.a);
      expect(l.ink, CitroColors.light.ink);
      expect(l.danger, CitroColors.light.danger);
      expect(l.mint, CitroColors.light.mint);
      // 浅色强调要浅、强调墨要深，深色反过来。
      expect(HSLColor.fromColor(l.accent).lightness, greaterThan(0.6));
      expect(HSLColor.fromColor(l.accentInk).lightness, lessThan(0.4));
      expect(HSLColor.fromColor(d.accent).lightness, greaterThan(0.6));
      expect(HSLColor.fromColor(d.accentInk).lightness, greaterThan(0.6));
    });

    test('同一主色重复应用不重复通知', () {
      var hits = 0;
      AmbientPalette.revision.addListener(() => hits++);
      AmbientPalette.apply(const Color(0xFF4080C0));
      AmbientPalette.apply(const Color(0xFF4080C0));
      expect(hits, 1);
    });

    test('灰色图不派生，回到默认令牌但仍通知一次', () {
      final before = AmbientPalette.revision.value;
      AmbientPalette.apply(const Color(0xFF808080));
      expect(identical(AmbientPalette.light, CitroColors.light), isTrue);
      expect(AmbientPalette.revision.value, before + 1);
    });

    test('强调墨在浅底上仍过 AA 对比', () {
      for (final seed in const [
        Color(0xFFE0A030),
        Color(0xFF30A070),
        Color(0xFF6070C0),
        Color(0xFFD05050),
      ]) {
        AmbientPalette.apply(seed);
        final l = AmbientPalette.light;
        final d = AmbientPalette.dark;
        expect(_contrast(l.accentInk, l.accentLt), greaterThanOrEqualTo(4.5));
        expect(_contrast(l.onAccent, l.accent), greaterThanOrEqualTo(4.5));
        expect(_contrast(d.accentInk, d.accentLt), greaterThanOrEqualTo(4.5));
        expect(_contrast(d.onAccent, d.accent), greaterThanOrEqualTo(4.5));
      }
    });
  });
}

double _luminance(Color c) {
  double lin(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
