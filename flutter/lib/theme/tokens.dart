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

  CitroColors copyWith({
    Color? bg,
    Color? bg2,
    Color? surface,
    Color? surface2,
    Color? paperLine,
    Color? ink,
    Color? ink2,
    Color? inkSoft,
    Color? line,
    Color? line2,
    Color? grid,
    Color? accent,
    Color? accent2,
    Color? accentLt,
    Color? accentInk,
    Color? mint,
    Color? mintInk,
    Color? mintSoft,
    Color? mintLine,
    Color? tape,
    Color? tape2,
    Color? tape3,
    Color? tapeLine,
    Color? hl,
    Color? hlInk,
    Color? noteY,
    Color? noteP,
    Color? noteB,
    Color? noteG,
    Color? stamp,
    Color? mask,
    bool? dark,
  }) => CitroColors(
    bg: bg ?? this.bg,
    bg2: bg2 ?? this.bg2,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    paperLine: paperLine ?? this.paperLine,
    ink: ink ?? this.ink,
    ink2: ink2 ?? this.ink2,
    inkSoft: inkSoft ?? this.inkSoft,
    line: line ?? this.line,
    line2: line2 ?? this.line2,
    grid: grid ?? this.grid,
    accent: accent ?? this.accent,
    accent2: accent2 ?? this.accent2,
    accentLt: accentLt ?? this.accentLt,
    accentInk: accentInk ?? this.accentInk,
    mint: mint ?? this.mint,
    mintInk: mintInk ?? this.mintInk,
    mintSoft: mintSoft ?? this.mintSoft,
    mintLine: mintLine ?? this.mintLine,
    tape: tape ?? this.tape,
    tape2: tape2 ?? this.tape2,
    tape3: tape3 ?? this.tape3,
    tapeLine: tapeLine ?? this.tapeLine,
    hl: hl ?? this.hl,
    hlInk: hlInk ?? this.hlInk,
    noteY: noteY ?? this.noteY,
    noteP: noteP ?? this.noteP,
    noteB: noteB ?? this.noteB,
    noteG: noteG ?? this.noteG,
    stamp: stamp ?? this.stamp,
    mask: mask ?? this.mask,
    dark: dark ?? this.dark,
  );

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
    accent: Color(0xFFE9932F),
    accent2: Color(0xFFD07C1F),
    accentLt: Color(0xFFF7D8A9),
    accentInk: Color(0xFF7C4A12),
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
    accent: Color(0xFFF0AC55),
    accent2: Color(0xFFDE9636),
    accentLt: Color(0xFFF7DDB4),
    accentInk: Color(0xFFF6D9AE),
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

/// 圆角统一走 8pt / Apple 组件规范：
/// 按钮 12、卡片 16、弹层 20、小元素 8。
class AppRadii {
  const AppRadii();
  double get page => 24;
  double get card => 16;
  double get inner => 12;
  double get field => 12;
  double get button => 12;
  double get modal => 20;
  double get chip => 999;
}

/// 8pt 栅格标尺。所有新增间距从这里取，避免出现 10/14/18 这类半格值。
class AppSpacing {
  const AppSpacing._();
  static const double x1 = 8;
  static const double x2 = 16;
  static const double x3 = 24;
  static const double x4 = 32;
  static const double x5 = 40;
  static const double x6 = 48;

  /// iOS 最小可点击高度。
  static const double touch = 44;

  /// 全屏页面顶部留白：桌面 48，手机等窄屏取一半。
  static double pageTop(double width) => width >= 700 ? x6 : x3;

  /// 浮动 Tab 栏高度。
  static const double navBar = 64;
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

/// 字号刻度。界面只从这里取值，避免同一层级的文字在 2 到 3 个
/// 相邻字号之间摇摆。内容里的贴纸、邮票可以继续用小字，但要落在
/// [small] 与 [micro] 两档上。
class CitroType {
  const CitroType._();

  /// 邮票、胶带上的装饰小字。
  static const double micro = 8;

  /// 角标、计数、极紧凑的标签。
  static const double small = 10;

  /// 说明文字、次级标签。
  static const double caption = 11;

  /// 元信息、时间、来源。
  static const double meta = 12;

  /// 紧凑标签、按钮副标题。
  static const double label = 13;

  /// 正文、导航项。
  static const double body = 14;

  /// 稍大的正文、列表主行。
  static const double bodyLg = 15;

  /// 小节标题、卡片标题。
  static const double title = 16;

  /// 卡片主标题。
  static const double titleLg = 18;

  /// 页面副标题、弹层标题。
  static const double subtitle = 20;

  /// 页面标题。
  static const double heading = 24;

  /// 大标题、封面字。
  static const double display = 28;

  /// 首屏标题。
  static const double hero = 36;

  /// 海报字、艺术字。
  static const double poster = 48;

  /// 手账里两档字重足够：正文 400，强调与标题 700（字体文件实际只提供这两档）。
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight strong = FontWeight.w700;
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
