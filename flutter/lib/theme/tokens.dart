import 'package:flutter/material.dart';

/// Design tokens — 1:1 port of styles/citro-core.css (:root / dark).
class CitroColors {
  final Color bg;
  final Color bg2;
  final Color surface;
  final Color surface2;
  final Color paperLine;
  final Color ink;
  final Color ink2;
  final Color inkSoft;
  final Color line;
  final Color line2;
  final Color grid;
  final Color accent;
  final Color accent2;
  final Color accentLt;
  final Color accentInk;
  final Color mint;
  final Color mintInk;
  final Color mintSoft;
  final Color mintLine;
  final Color tape;
  final Color tape2;
  final Color tape3;
  final Color tapeLine;
  final Color hl;
  final Color hlInk;
  final Color noteY;
  final Color noteP;
  final Color noteB;
  final Color noteG;
  final Color stamp;
  final Color mask;
  final bool dark;

  const CitroColors({
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.paperLine,
    required this.ink,
    required this.ink2,
    required this.inkSoft,
    required this.line,
    required this.line2,
    required this.grid,
    required this.accent,
    required this.accent2,
    required this.accentLt,
    required this.accentInk,
    required this.mint,
    required this.mintInk,
    required this.mintSoft,
    required this.mintLine,
    required this.tape,
    required this.tape2,
    required this.tape3,
    required this.tapeLine,
    required this.hl,
    required this.hlInk,
    required this.noteY,
    required this.noteP,
    required this.noteB,
    required this.noteG,
    required this.stamp,
    required this.mask,
    required this.dark,
  });

  static const light = CitroColors(
    bg: Color(0xFFE7E0D0),
    bg2: Color(0xFFDFD7C4),
    surface: Color(0xFFFBF7EC),
    surface2: Color(0xFFFFFDF8),
    paperLine: Color(0xFFEDE4D2),
    ink: Color(0xFF23211C),
    ink2: Color(0xFF4E4A40),
    inkSoft: Color(0xFF6E6858),
    line: Color(0xFFE4DCC9),
    line2: Color(0xFFD2C8B0),
    grid: Color(0x1660523A),
    accent: Color(0xFFF2A43C),
    accent2: Color(0xFFDE8A1F),
    accentLt: Color(0xFFFFC873),
    accentInk: Color(0xFF8F4E05),
    mint: Color(0xFF8FC7A0),
    mintInk: Color(0xFF2C6B50),
    mintSoft: Color(0xFFEAF2E3),
    mintLine: Color(0xFFCFE2C9),
    tape: Color(0x9EF0B0B8),
    tape2: Color(0x9496C4E2),
    tape3: Color(0x99F4D678),
    tapeLine: Color(0x1A786040),
    hl: Color(0x9EFFE15C),
    hlInk: Color(0xEBFFE15C),
    noteY: Color(0xFFFBF1C4),
    noteP: Color(0xFFF8E4E4),
    noteB: Color(0xFFE2EDF6),
    noteG: Color(0xFFE7F1DF),
    stamp: Color(0xFFB3402A),
    mask: Color(0x4723211C),
    dark: false,
  );

  static const darkColors = CitroColors(
    bg: Color(0xFF0E0E11),
    bg2: Color(0xFF141418),
    surface: Color(0xFF191920),
    surface2: Color(0xFF202028),
    paperLine: Color(0x14FFF6E4),
    ink: Color(0xFFF1EEE5),
    ink2: Color(0xFFCFC9BC),
    inkSoft: Color(0xFFA49E90),
    line: Color(0x1AFFF6E4),
    line2: Color(0x2BFFF6E4),
    grid: Color(0x0DFFF0D6),
    accent: Color(0xFFFFAE52),
    accent2: Color(0xFFE08A24),
    accentLt: Color(0xFFFFD2A0),
    accentInk: Color(0xFFFFC078),
    mint: Color(0xFFC9D3B2),
    mintInk: Color(0xFFD8DFC4),
    mintSoft: Color(0x1AC9D3B2),
    mintLine: Color(0x38C9D3B2),
    tape: Color(0x33E2A0AA),
    tape2: Color(0x2E96BEDC),
    tape3: Color(0x2EE2C878),
    tapeLine: Color(0x1AFFF6E4),
    hl: Color(0x38FFD65A),
    hlInk: Color(0x57FFD65A),
    noteY: Color(0xFF332E1E),
    noteP: Color(0xFF332528),
    noteB: Color(0xFF222C34),
    noteG: Color(0xFF242E1E),
    stamp: Color(0xFFE0796A),
    mask: Color(0x9E000000),
    dark: true,
  );

  static const radii = AppRadii();
  static const shadows = AppShadows();
}

class AppRadii {
  const AppRadii();
  double get page => 16;
  double get card => 14;
  double get inner => 10;
  double get chip => 999;
}

class AppShadows {
  const AppShadows();
  List<BoxShadow> paper(CitroColors c) => c.dark
      ? const [
          BoxShadow(
            color: Color(0x6B000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0xFF000000),
            blurRadius: 24,
            spreadRadius: -14,
            offset: Offset(0, 10),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0E5A4A2C),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x4D5A4A2C),
            blurRadius: 20,
            spreadRadius: -12,
            offset: Offset(0, 8),
          ),
        ];

  List<BoxShadow> lg(CitroColors c) => c.dark
      ? const [
          BoxShadow(
            color: Color(0x75000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
          BoxShadow(
            color: Color(0xFF000000),
            blurRadius: 56,
            spreadRadius: -26,
            offset: Offset(0, 26),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0F5A4A2C),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
          BoxShadow(
            color: Color(0x6B5A4A2C),
            blurRadius: 48,
            spreadRadius: -24,
            offset: Offset(0, 22),
          ),
        ];

  List<BoxShadow> note(CitroColors c) => c.dark
      ? const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0xFF000000),
            blurRadius: 22,
            spreadRadius: -14,
            offset: Offset(0, 10),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0F5A4A2C),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x575A4A2C),
            blurRadius: 22,
            spreadRadius: -12,
            offset: Offset(0, 10),
          ),
        ];
}

class AppFonts {
  static const kalam = 'Kalam';
  static const zcool = 'ZCOOL';
  static const caveat = 'Caveat';
  static const noto = 'NotoSC';
  static const fallback = <String>[
    'ZCOOL',
    'NotoSC',
    'Noto Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
  ];
  static const bodyFallback = <String>[
    'NotoSC',
    'Noto Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
    'Segoe UI',
  ];
}

/// Convenience accessors used across the app.
extension CitroColorX on CitroColors {
  Color get tapeLike => tape;
}
