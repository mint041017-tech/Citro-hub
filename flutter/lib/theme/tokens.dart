import 'package:flutter/material.dart';

/// 设计令牌 —— nosh 风格重设计（2026-11）。
///
/// 方向：干净、圆润、留白充足。圆角无衬线字体 + 大圆角卡片 + 粉彩分区底 +
/// 近黑胶囊主按钮。手账风（网格纸 / 胶带 / 便签 / 印章 / 手写体）全部退役。
///
/// 三色搭配：奶米底 #F9EDD7 + 青瓷强调 #A9C9C4 + 棕墨文字 #614A44。
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

  /// 青瓷：主行动、选中、图标、链接。
  final Color accent;

  /// 按压/更深的青瓷。
  final Color accent2;

  /// 浅青瓷：标签底、软强调。
  final Color accentLt;

  /// 浅底上的青瓷字（过 AA）。
  final Color accentInk;

  /// 青瓷底上的文字/图标。
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

  /// 两套配色逐项插值：主题色随背景图换时整体平滑过渡，而不是半程硬切。
  /// [dark] 不能插值，过半后取 [b] 的。
  static CitroColors lerp(CitroColors a, CitroColors b, double t) {
    if (identical(a, b) || t <= 0) return a;
    if (t >= 1) return b;
    Color l(Color x, Color y) => Color.lerp(x, y, t)!;
    return CitroColors(
      bg: l(a.bg, b.bg),
      bg2: l(a.bg2, b.bg2),
      surface: l(a.surface, b.surface),
      surface2: l(a.surface2, b.surface2),
      ink: l(a.ink, b.ink),
      ink2: l(a.ink2, b.ink2),
      inkSoft: l(a.inkSoft, b.inkSoft),
      line: l(a.line, b.line),
      line2: l(a.line2, b.line2),
      accent: l(a.accent, b.accent),
      accent2: l(a.accent2, b.accent2),
      accentLt: l(a.accentLt, b.accentLt),
      accentInk: l(a.accentInk, b.accentInk),
      onAccent: l(a.onAccent, b.onAccent),
      mint: l(a.mint, b.mint),
      mintInk: l(a.mintInk, b.mintInk),
      mintSoft: l(a.mintSoft, b.mintSoft),
      mintLine: l(a.mintLine, b.mintLine),
      stamp: l(a.stamp, b.stamp),
      danger: l(a.danger, b.danger),
      dangerSoft: l(a.dangerSoft, b.dangerSoft),
      hl: l(a.hl, b.hl),
      hlInk: l(a.hlInk, b.hlInk),
      tintYellow: l(a.tintYellow, b.tintYellow),
      tintPink: l(a.tintPink, b.tintPink),
      tintBlue: l(a.tintBlue, b.tintBlue),
      tintGreen: l(a.tintGreen, b.tintGreen),
      tintNeutral: l(a.tintNeutral, b.tintNeutral),
      dark: t < 0.5 ? a.dark : b.dark,
    );
  }

  /// 按场景取粉彩分区底。
  Color tint(CitroTint kind) => switch (kind) {
    CitroTint.neutral => tintNeutral,
    CitroTint.yellow => tintYellow,
    CitroTint.pink => tintPink,
    CitroTint.blue => tintBlue,
    CitroTint.green => tintGreen,
  };

  /// 浅色（默认）—— 沉浸式 iOS 方向（2026-11 重设计）。
  ///
  /// 背景图铺满所有页面，界面是浮在上面的一层磨砂材质：
  /// - 页面底 [bg] 只作兜底与罩面色（图片之上铺一层半透明 bg）；
  /// - 卡片 [surface] 是 55% 白的半透明材质，背景色透进来；
  /// - 内嵌块 [surface2] 是 iOS 的 tertiary fill（12% 灰），叠在任何底上都成立；
  /// - 文字改为中性近黑（iOS label / secondaryLabel），在彩色背景上更稳；
  /// - 强调色一族由 [AmbientPalette] 按首页背景图取色派生，这里是取不到色时
  ///   的默认值（青绿）。
  ///
  /// 弹层 / 底部面板这类盖在内容上的表面要不透明，用 [CitroSurfaceX.sheet]。
  static const light = CitroColors(
    bg: Color(0xFFF2F1F6),
    bg2: Color(0xFFE8E7EE),
    surface: Color(0x8CFFFFFF),
    surface2: Color(0x1F767680),
    ink: Color(0xFF1C1B1F),
    ink2: Color(0xFF3E3B44),
    // 元信息：玻璃是半透明的、底下是彩色背景，灰字要比纯白底上深一档，
    // 在 55% 白玻璃 + 自适应罩面上 ≥ 4.5:1。
    inkSoft: Color(0xFF615D69),
    line: Color(0x2E3C3C43),
    line2: Color(0x4A3C3C43),
    accent: Color(0xFF2FA597),
    accent2: Color(0xFF238A7E),
    accentLt: Color(0xFFD3EEEA),
    accentInk: Color(0xFF13665C),
    onAccent: Color(0xFFFFFFFF),
    // 成功 / 收藏：iOS 绿收一点饱和度。
    mint: Color(0xFF3DBE7A),
    mintInk: Color(0xFF1B7446),
    mintSoft: Color(0x2934C759),
    mintLine: Color(0x5934C759),
    // 提醒 / 逾期 / 「宜」：暖橙。
    stamp: Color(0xFFE0783C),
    danger: Color(0xFFE5484D),
    dangerSoft: Color(0x1FE5484D),
    hl: Color(0x402FA597),
    hlInk: Color(0xCC2FA597),
    tintYellow: Color(0x29FFB800),
    tintPink: Color(0x24FF5A79),
    tintBlue: Color(0x240A84FF),
    tintGreen: Color(0x2434C759),
    tintNeutral: Color(0x14767680),
    dark: false,
  );

  /// 深色：近黑底 + 10% 白色磨砂覆层，描边用白透明。
  static const darkColors = CitroColors(
    bg: Color(0xFF17161D),
    bg2: Color(0xFF111016),
    surface: Color(0x24FFFFFF),
    surface2: Color(0x3D767680),
    ink: Color(0xFFF5F4F8),
    ink2: Color(0xFFD8D5DE),
    inkSoft: Color(0xFFB2AEBA),
    line: Color(0x26FFFFFF),
    line2: Color(0x3DFFFFFF),
    accent: Color(0xFF4CC2B4),
    accent2: Color(0xFF3AAEA0),
    accentLt: Color(0xFF173B37),
    accentInk: Color(0xFF9FE3DA),
    onAccent: Color(0xFF06201D),
    mint: Color(0xFF3DD68C),
    mintInk: Color(0xFF8BE8B6),
    mintSoft: Color(0x2930D158),
    mintLine: Color(0x5230D158),
    stamp: Color(0xFFFF9F5A),
    danger: Color(0xFFFF6B6B),
    dangerSoft: Color(0x29FF6B6B),
    hl: Color(0x404CC2B4),
    hlInk: Color(0x664CC2B4),
    tintYellow: Color(0x24FFD60A),
    tintPink: Color(0x24FF6482),
    tintBlue: Color(0x240A84FF),
    tintGreen: Color(0x2430D158),
    tintNeutral: Color(0x1F767680),
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
  double get card => 22;

  /// 卡内内嵌块。
  double get inner => 14;

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
  static const double x6 = 48;

  /// iOS 最小可点击高度。
  static const double touch = 44;

  /// 全屏页面顶部留白：桌面 48，手机等窄屏取一半。
  static double pageTop(double width) => width >= 700 ? x6 : x3;

  // —— Tab 页（计划 / 游戏 / 社区）统一的「宽松」页边距 ——

  /// 左右留白：手机至少 20、宽屏至少 32；内容有最大宽度时居中，
  /// 两侧取居中后的余量和最小值里较大的那个。
  static double pageSide(double width, double maxWidth) {
    final min = width >= 700 ? 32.0 : 20.0;
    final centered = (width - maxWidth) / 2;
    return centered > min ? centered : min;
  }

  /// 顶部留白：手机 24、宽屏 56。
  static double pageTopRoomy(double width) => width >= 700 ? 56 : 24;

  /// 底部留白：有底部悬浮导航时留够它的高度 + 呼吸空间。
  static double pageBottom({required bool floatingNav}) =>
      floatingNav ? 128 : 56;

  /// 页面里两个模块之间的间距。
  static const double block = 28;

  /// 卡片网格 / 瀑布流的格间距。
  static const double grid = 16;
}

/// 阴影：两层叠加（贴地的接触影 + 大范围的环境影），更接近真实纸张的厚度感。
///
/// 浅色下投影色带一点当前强调色（accentInk）的色相：主题色随首页背景图
/// 变化时，阴影也跟着偏向同一色调，卡片像是被背景的光照着，而不是贴了
/// 一块灰。深色下仍用纯黑（暗面上偏色会发脏），只把层次拉开。
class AppShadows {
  const AppShadows();

  /// 投影基色：浅色 = 黑与 accentInk 混合，深色 = 纯黑。自绘阴影也从这里取。
  static Color tone(CitroColors c) => c.dark
      ? const Color(0xFF000000)
      : Color.lerp(const Color(0xFF000000), c.accentInk, 0.45)!;

  static List<BoxShadow> _layers(
    CitroColors c, {
    required int contactAlpha,
    required double contactBlur,
    required double contactY,
    required int ambientAlpha,
    required double ambientBlur,
    required double ambientY,
  }) {
    final tone = AppShadows.tone(c);
    return [
      BoxShadow(
        color: tone.withAlpha(contactAlpha),
        blurRadius: contactBlur,
        offset: Offset(0, contactY),
      ),
      BoxShadow(
        color: tone.withAlpha(ambientAlpha),
        blurRadius: ambientBlur,
        offset: Offset(0, ambientY),
        spreadRadius: -ambientBlur * 0.15,
      ),
    ];
  }

  /// 轻浮起：列表项、小卡、输入条。
  List<BoxShadow> sm(CitroColors c) => _layers(
    c,
    contactAlpha: c.dark ? 0x40 : 0x0F,
    contactBlur: 2,
    contactY: 1,
    ambientAlpha: c.dark ? 0x40 : 0x12,
    ambientBlur: 12,
    ambientY: 4,
  );

  /// 常规卡片。
  /// 磨砂材质靠透明度和亮边分层，投影只留一层很淡的环境影。
  List<BoxShadow> card(CitroColors c) => _layers(
    c,
    contactAlpha: c.dark ? 0x33 : 0x08,
    contactBlur: 2,
    contactY: 1,
    ambientAlpha: c.dark ? 0x4D : 0x14,
    ambientBlur: 24,
    ambientY: 10,
  );

  /// 浮层 / 弹窗 / 大面板。
  List<BoxShadow> lg(CitroColors c) => _layers(
    c,
    contactAlpha: c.dark ? 0x66 : 0x14,
    contactBlur: 6,
    contactY: 2,
    ambientAlpha: c.dark ? 0xB3 : 0x29,
    ambientBlur: c.dark ? 48 : 40,
    ambientY: 18,
  );

  /// 悬浮控件（按钮、FAB、底部操作条）。
  List<BoxShadow> float(CitroColors c) => _layers(
    c,
    contactAlpha: c.dark ? 0x66 : 0x1A,
    contactBlur: 4,
    contactY: 2,
    ambientAlpha: c.dark ? 0x8C : 0x26,
    ambientBlur: 22,
    ambientY: 10,
  );

  /// 玻璃浮起：贴地的接触影 + 更大、更往下的环境影（负扩散，影子收在
  /// 卡片正下方，不会在四周糊一圈灰）。没有白边时，悬浮感主要靠它。
  List<BoxShadow> lift(CitroColors c) => _layers(
    c,
    contactAlpha: c.dark ? 0x4D : 0x10,
    contactBlur: 3,
    contactY: 1,
    ambientAlpha: c.dark ? 0x80 : 0x29,
    ambientBlur: 30,
    ambientY: 14,
  );

  /// 选中 / 聚焦态的强调光晕：贴着元素一圈极淡的 accent 色。
  List<BoxShadow> glow(CitroColors c) => [
    BoxShadow(
      color: c.accent.withAlpha(c.dark ? 0x40 : 0x55),
      blurRadius: 16,
      offset: const Offset(0, 4),
      spreadRadius: -2,
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
/// 色场组件的色调（2026-11「色场」重设计）。
///
/// 首页 / 计划等页面的模块不再是同一种白磨砂，而是从背景图主色派生出的
/// 一组实心色块：同一色相家族、明暗差拉开，模块之间靠颜色区分，
/// 最重要的模块（待办）用最饱和的 [primary]。换背景图，整组一起换。
enum FieldTone {
  /// 主色：背景取色派生的强调色实心块，白字。
  primary,

  /// 浅色：同色相偏暖的浅底，深色字。
  light,

  /// 暖色：色相再偏一点的中明度块。
  warm,

  /// 深色：近黑的同色相底，白字。
  deep,

  /// 玻璃：高不透明度的白（深色模式为深灰）磨砂块，普通墨色字。
  glass,
}

/// 一块色场的颜色：底、前景（文字 / 图标）、块内强调色及其上的文字色。
class FieldSwatch {
  final Color bg;
  final Color fg;
  final Color accent;
  final Color onAccent;

  const FieldSwatch({
    required this.bg,
    required this.fg,
    required this.accent,
    required this.onAccent,
  });

  /// 色块本身是不是深色（决定块内控件走深色还是浅色变体）。
  bool get isDark => bg.computeLuminance() < .36;
}

extension CitroFieldX on CitroColors {
  static double _cl(double v, double lo, double hi) => v.clamp(lo, hi);

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance() + .05;
    final lb = b.computeLuminance() + .05;
    return la > lb ? la / lb : lb / la;
  }

  /// 按色块亮度选前景：浅块用同色相的深墨，深块用白。
  static Color _ink(Color bg, double hue, double sat) =>
      bg.computeLuminance() > .36
      ? HSLColor.fromAHSL(1, hue, _cl(sat * .6, 0, .7), .17).toColor()
      : const Color(0xFFFFFFFF);

  /// 一种色调的色块颜色。全部由当前强调色（= 背景图主色）推出来：
  /// 同色相家族 + 小幅色相偏移（类比色），换任何背景都和谐。
  FieldSwatch field(FieldTone tone) {
    final h = HSLColor.fromColor(accent2);
    final hue = h.hue;
    // 色块要「有颜色」：饱和度下限 0.45，否则低饱和背景会出一片土灰。
    final sat = _cl(h.saturation, .45, .85);
    // 类比色往哪边偏：琥珀 / 黄 / 黄绿（20°–120°）往红橙方向偏，
    // 否则会一路偏进橄榄、芥末绿；其余色相往暖的一侧（+）偏。
    final dir = (hue >= 20 && hue <= 120) ? -1.0 : 1.0;
    Color hsl(double dh, double s, double l, [double a = 1]) =>
        HSLColor.fromAHSL(
          a,
          (hue + dh * dir + 360) % 360,
          _cl(s, 0, 1),
          _cl(l, 0, 1),
        ).toColor();

    // 明暗跟随主题：浅色模式下所有色块都是浅色（深色字），深色模式下
    // 所有色块都是深色（浅色字）。色块之间只靠色相 / 饱和度 / 一点明度差
    // 区分，整页亮度统一，不会出现一块刺眼的深色或亮色。
    late Color bg;
    late Color accentIn;
    switch (tone) {
      case FieldTone.primary:
        // 最饱和的一块：视觉重心。
        bg = dark
            ? hsl(0, sat * .80, .30)
            : hsl(0, _cl(sat * 1.05, 0, .92), .80);
        accentIn = dark ? hsl(0, sat, .72) : hsl(0, sat, .36);
      case FieldTone.warm:
        bg = dark
            ? hsl(22, sat * .65, .25)
            : hsl(24, _cl(sat * .95, 0, .9), .85);
        accentIn = dark ? hsl(22, sat, .70) : hsl(22, sat, .36);
      case FieldTone.light:
        bg = dark ? hsl(12, sat * .45, .20) : hsl(12, sat * .75, .92);
        accentIn = dark ? hsl(0, sat, .70) : hsl(0, sat, .40);
      case FieldTone.deep:
        // 「沉」的一块：浅色模式是低饱和的灰调浅色，深色模式是近黑。
        bg = dark ? hsl(-8, sat * .30, .13) : hsl(-8, sat * .28, .88);
        accentIn = dark ? hsl(24, sat * .9, .70) : hsl(-8, sat * .8, .38);
      case FieldTone.glass:
        final glass = dark ? const Color(0xE62A2830) : const Color(0xE6FFFFFF);
        return FieldSwatch(
          bg: glass,
          fg: ink,
          accent: accent2,
          onAccent: onAccent,
        );
    }
    return FieldSwatch(
      bg: bg,
      fg: _ink(bg, hue, sat),
      accent: accentIn,
      onAccent: _ink(accentIn, hue, sat),
    );
  }

  /// 色块内部使用的整套配色：把墨色 / 描边 / 内嵌底 / 强调色都换成
  /// 以色块为底的版本。块里沿用 `context.c` 的旧代码不用改，自动变色。
  CitroColors onField(FieldTone tone) {
    final s = field(tone);
    if (tone == FieldTone.glass) return copyWith(surface: s.bg);
    final f = s.fg;
    Color a(double o) => f.withValues(alpha: o);
    final dk = s.isDark;
    return copyWith(
      bg: s.bg,
      surface: s.bg,
      surface2: a(dk ? .16 : .10),
      ink: f,
      ink2: a(.92),
      inkSoft: a(.80),
      line: a(.18),
      line2: a(.28),
      accent: s.accent,
      accent2: s.accent,
      accentLt: a(.16),
      accentInk: f,
      onAccent: s.onAccent,
      mint: a(.9),
      mintInk: f,
      mintSoft: a(.14),
      mintLine: a(.30),
      stamp: f,
      hl: a(.25),
      hlInk: a(.50),
      tintYellow: a(.10),
      tintPink: a(.10),
      tintBlue: a(.10),
      tintGreen: a(.10),
      tintNeutral: a(.08),
      dark: dk,
    );
  }
}

extension CitroSurfaceX on CitroColors {
  /// 不透明的表面：弹层、底部面板、菜单、对话框——盖在内容之上的东西
  /// 不能透出底下的字。等于把半透明 [surface] 叠在 [bg] 上的结果。
  Color get sheet => Color.alphaBlend(surface, bg);

  /// 磨砂材质的边缘线：深色使用同色玻璃描边，浅色保留亮边。
  Color get rim =>
      dark ? surface.withValues(alpha: .28) : const Color(0x8CFFFFFF);

  /// 更薄的一档材质：首页小组件、问候区底。
  Color get glassThin =>
      dark ? const Color(0x17FFFFFF) : const Color(0x66FFFFFF);

  /// 页面罩面：铺在背景图之上、内容之下，保证任何图上的字都读得清。
  Color get wash => bg.withValues(alpha: dark ? .58 : .55);
}

extension CitroColorX on CitroColors {
  /// 半透蒙层（图片上的文字底、模态背后）。
  Color get scrim => dark ? const Color(0x99000000) : const Color(0x66000000);
}
