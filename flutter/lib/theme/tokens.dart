import 'package:flutter/material.dart';

/// 设计令牌 —— nosh 风格重设计（2026-11）。
///
/// 方向：干净、圆润、留白充足。圆角无衬线字体 + 大圆角卡片 + 粉彩分区底 +
/// 近黑胶囊主按钮。手账风（网格纸 / 胶带 / 便签 / 印章 / 手写体）全部退役。
///
/// 四色搭配：奶青底 #FDEBD3 + 蓝紫品牌 #6B7BB4 + 橄榄语义 #89A411 + 橙强调 #F58E3C。
///
/// 浅色与深色是两套完整值，不是「浅色 + 滤镜」：深色的表面抬升、描边、
/// 阴影都按暗色下的实际观感单独调过，新增颜色时两边都要给。
class CitroColors {
  /// 页面底。
  final Color bg;

  /// 比 [bg] 更深一档的底，用于大面积分区/桌底。
  final Color bg2;

  /// 卡片/浮层表面。
  final Color surface;

  /// 卡内内嵌区域（输入框底、次级块）。
  final Color surface2;

  /// 主文字。
  final Color ink;

  /// 次级文字。
  final Color ink2;

  /// 弱文字/占位/时间戳。
  final Color inkSoft;

  /// 描边。
  final Color line;

  /// 分割线/更强的描边。
  final Color line2;

  /// 品牌蓝紫：主行动、选中、图标、链接。
  final Color accent;

  /// 按压/更深的蓝紫。
  final Color accent2;

  /// 浅蓝紫：标签底、软强调。
  final Color accentLt;

  /// 浅底上的蓝紫字（过 AA）。
  final Color accentInk;

  /// 蓝紫底上的文字/图标。
  final Color onAccent;

  /// 橄榄绿：成功、收藏、次要语义。
  final Color mint;
  final Color mintInk;
  final Color mintSoft;
  final Color mintLine;

  /// 橙：日历「宜」、提醒、游戏强调。
  final Color stamp;

  /// 危险/删除。
  final Color danger;
  final Color dangerSoft;

  /// 橙：标记重点。
  final Color hl;
  final Color hlInk;

  /// 粉彩分区底（nosh 的按场景换色）。
  final Color tintYellow;
  final Color tintPink;
  final Color tintBlue;
  final Color tintGreen;
  final Color tintNeutral;

  final bool dark;

  const CitroColors({
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.inkSoft,
    required this.line,
    required this.line2,
    required this.accent,
    required this.accent2,
    required this.accentLt,
    required this.accentInk,
    required this.onAccent,
    required this.mint,
    required this.mintInk,
    required this.mintSoft,
    required this.mintLine,
    required this.stamp,
    required this.danger,
    required this.dangerSoft,
    required this.hl,
    required this.hlInk,
    required this.tintYellow,
    required this.tintPink,
    required this.tintBlue,
    required this.tintGreen,
    required this.tintNeutral,
    required this.dark,
  });

  CitroColors copyWith({
    Color? bg,
    Color? bg2,
    Color? surface,
    Color? surface2,
    Color? ink,
    Color? ink2,
    Color? inkSoft,
    Color? line,
    Color? line2,
    Color? accent,
    Color? accent2,
    Color? accentLt,
    Color? accentInk,
    Color? onAccent,
    Color? mint,
    Color? mintInk,
    Color? mintSoft,
    Color? mintLine,
    Color? stamp,
    Color? danger,
    Color? dangerSoft,
    Color? hl,
    Color? hlInk,
    Color? tintYellow,
    Color? tintPink,
    Color? tintBlue,
    Color? tintGreen,
    Color? tintNeutral,
    bool? dark,
  }) => CitroColors(
    bg: bg ?? this.bg,
    bg2: bg2 ?? this.bg2,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    ink: ink ?? this.ink,
    ink2: ink2 ?? this.ink2,
    inkSoft: inkSoft ?? this.inkSoft,
    line: line ?? this.line,
    line2: line2 ?? this.line2,
    accent: accent ?? this.accent,
    accent2: accent2 ?? this.accent2,
    accentLt: accentLt ?? this.accentLt,
    accentInk: accentInk ?? this.accentInk,
    onAccent: onAccent ?? this.onAccent,
    mint: mint ?? this.mint,
    mintInk: mintInk ?? this.mintInk,
    mintSoft: mintSoft ?? this.mintSoft,
    mintLine: mintLine ?? this.mintLine,
    stamp: stamp ?? this.stamp,
    danger: danger ?? this.danger,
    dangerSoft: dangerSoft ?? this.dangerSoft,
    hl: hl ?? this.hl,
    hlInk: hlInk ?? this.hlInk,
    tintYellow: tintYellow ?? this.tintYellow,
    tintPink: tintPink ?? this.tintPink,
    tintBlue: tintBlue ?? this.tintBlue,
    tintGreen: tintGreen ?? this.tintGreen,
    tintNeutral: tintNeutral ?? this.tintNeutral,
    dark: dark ?? this.dark,
  );

  /// 按场景取粉彩分区底。
  Color tint(CitroTint kind) => switch (kind) {
    CitroTint.neutral => tintNeutral,
    CitroTint.yellow => tintYellow,
    CitroTint.pink => tintPink,
    CitroTint.blue => tintBlue,
    CitroTint.green => tintGreen,
  };

  /// 浅色（默认）。
  ///
  /// 底是奶青（#FDEBD3），卡片浅奶青，文字近黑，
  /// 强调用蓝紫（#6B7BB4）+ 橄榄（#89A411）+ 橙（#F58E3C）三色搭配。
  static const light = CitroColors(
    bg: Color(0xFFFDEBD3),
    bg2: Color(0xFFF3E2C6),
    surface: Color(0xFFFFF9EE),
    surface2: Color(0xFFF7E7CE),
    ink: Color(0xFF2A2A33),
    ink2: Color(0xFF4A4A55),
    // 11-13px 的元信息用墨：对卡面 5:1，过 AA。
    inkSoft: Color(0xFF6B6760),
    line: Color(0xFFEBDCC3),
    line2: Color(0xFFDCC9A8),
    // 品牌色：蓝紫（#6B7BB4）。奶青底 + 蓝紫 + 橄榄 + 橙四色搭配。
    accent: Color(0xFF6B7BB4),
    accent2: Color(0xFF5868A0),
    accentLt: Color(0xFFDCE2F2),
    accentInk: Color(0xFF3E4A7A),
    // 蓝紫底上的文字用白（对比度约 4:1，标题/加粗足够）。
    onAccent: Color(0xFFFFFFFF),
    // 橄榄绿：成功、收藏、次要语义。
    mint: Color(0xFF89A411),
    mintInk: Color(0xFF3F4D0A),
    mintSoft: Color(0xFFEEF2DA),
    mintLine: Color(0xFFD5DDA8),
    // 橙：标记、提醒、游戏强调。
    stamp: Color(0xFFF58E3C),
    danger: Color(0xFFD94F4F),
    dangerSoft: Color(0xFFFDECEC),
    hl: Color(0x66F58E3C),
    hlInk: Color(0xCCF58E3C),
    tintYellow: Color(0xFFFDEBD3),
    tintPink: Color(0xFFFDECEF),
    tintBlue: Color(0xFFE4EAF7),
    tintGreen: Color(0xFFEFF4DA),
    tintNeutral: Color(0xFFF1EDE4),
    dark: false,
  );

  /// 深色（近黑表面 + 同强调色）。
  ///
  /// 三级表面：底 #1A1C26 → 卡 #232636 → 内嵌 #2B2E40；
  /// 描边用白透明而非灰，避免暗面上发脏；阴影一律纯黑。
  static const darkColors = CitroColors(
    bg: Color(0xFF1A1C26),
    bg2: Color(0xFF12141C),
    surface: Color(0xFF232636),
    surface2: Color(0xFF2B2E40),
    ink: Color(0xFFF2F1EC),
    ink2: Color(0xFFC7C5BD),
    inkSoft: Color(0xFF9E9C94),
    line: Color(0x1AFFFFFF),
    line2: Color(0x29FFFFFF),
    accent: Color(0xFF8B9BD4),
    accent2: Color(0xFF6B7BB4),
    accentLt: Color(0xFF2A3050),
    accentInk: Color(0xFFC4CEF0),
    onAccent: Color(0xFF1A1C26),
    mint: Color(0xFFA8C43A),
    mintInk: Color(0xFFD0E08A),
    mintSoft: Color(0xFF232A10),
    mintLine: Color(0xFF3A4618),
    stamp: Color(0xFFF58E3C),
    danger: Color(0xFFFF6E73),
    dangerSoft: Color(0xFF2A1718),
    hl: Color(0x40F58E3C),
    hlInk: Color(0x66F58E3C),
    tintYellow: Color(0xFF2A2410),
    tintPink: Color(0xFF2A1719),
    tintBlue: Color(0xFF1A2030),
    tintGreen: Color(0xFF1C2410),
    tintNeutral: Color(0xFF17181B),
    dark: true,
  );

  static const radii = AppRadii();
  static const shadows = AppShadows();
}

/// 粉彩分区底的种类。
enum CitroTint { neutral, yellow, pink, blue, green }

/// 圆角锁：卡片 24 / 浮层 28 / 内嵌 16 / 小件 12 / 胶囊与头像 999。
///
/// 比旧体系（16/14/10）整体放大一档，接近 nosh 的观感：
/// 所有可见容器都带明显圆角，没有任何直角。
class AppRadii {
  const AppRadii();

  /// 页面级大卡 / 浮层。
  double get page => 28;

  /// 常规卡片。
  double get card => 24;

  /// 卡内内嵌块。
  double get inner => 16;

  /// 输入框。
  double get field => 16;

  /// 按钮（胶囊，固定 999）。
  double get button => 999;

  /// 弹层。
  double get modal => 28;

  /// 胶囊/标签。
  double get chip => 999;

  /// 小元素（角标、小图标底）。
  double get small => 12;

  /// 极小元素。
  double get xs => 8;

  /// 头像/圆形按钮。
  double get avatar => 999;
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

/// 阴影：纯黑低透明 + 大模糊，浅色下也不偏色（不再用暖棕投影）。
class AppShadows {
  const AppShadows();

  List<BoxShadow> sm(CitroColors c) => [
    BoxShadow(
      color: const Color(0x12000000),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];

  List<BoxShadow> card(CitroColors c) => [
    BoxShadow(
      color: c.dark ? const Color(0x73000000) : const Color(0x14000000),
      blurRadius: c.dark ? 20 : 16,
      offset: const Offset(0, 6),
    ),
  ];

  List<BoxShadow> lg(CitroColors c) => [
    BoxShadow(
      color: c.dark ? const Color(0xCC000000) : const Color(0x1F000000),
      blurRadius: c.dark ? 40 : 32,
      offset: const Offset(0, 16),
    ),
  ];

  /// 悬浮控件（按钮、FAB、底部操作条）。
  List<BoxShadow> float(CitroColors c) => [
    BoxShadow(
      color: c.dark ? const Color(0x99000000) : const Color(0x26000000),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

/// 字号刻度。界面只从这里取值，避免同一层级的文字在 2 到 3 个
/// 相邻字号之间摇摆。
///
/// 圆体在小号下比旧的手写体更清楚，因此整体比旧刻度略大一号。
class CitroType {
  const CitroType._();

  /// 角标、极紧凑的标签。
  static const double micro = 9;

  /// 计数、辅助信息。
  static const double small = 11;

  /// 说明文字、次级标签。
  static const double caption = 12;

  /// 元信息、时间、来源。
  static const double meta = 13;

  /// 紧凑标签、按钮副标题。
  static const double label = 14;

  /// 正文、导航项。
  static const double body = 15;

  /// 稍大的正文、列表主行。
  static const double bodyLg = 16;

  /// 小节标题、卡片标题。
  static const double title = 18;

  /// 卡片主标题。
  static const double titleLg = 20;

  /// 页面副标题、弹层标题。
  static const double subtitle = 22;

  /// 页面标题。
  static const double heading = 26;

  /// 大标题、封面字。
  static const double display = 32;

  /// 首屏标题。
  static const double hero = 40;

  /// 海报字、艺术字。
  static const double poster = 56;

  /// 圆体三档字重足够：正文 400、标签 500、标题/强调 700。
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight strong = FontWeight.w700;
}

class AppFonts {
  /// UI / 标题：Resource Han Rounded CN（思源圆体，OFL）。
  static const rounded = 'RoundedCN';

  /// 数字 / 数据读出：Xiaolai Mono（OFL）。
  static const mono = 'XiaolaiMono';

  /// 兼容旧名：正文字体。
  static const noto = rounded;

  /// 兼容旧名：展示字体。
  static const kalam = rounded;

  /// 兼容旧名：标题字体。
  static const zcool = rounded;

  /// 兼容旧名：数字/注释字体。
  static const caveat = mono;

  static const fallback = <String>[
    rounded,
    'Noto Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
  ];
  static const bodyFallback = <String>[
    rounded,
    'Noto Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
    'Segoe UI',
  ];
}

/// Convenience accessors used across the app.
extension CitroColorX on CitroColors {
  /// 半透蒙层（图片上的文字底、模态背后）。
  Color get scrim => dark ? const Color(0x99000000) : const Color(0x66000000);
}
