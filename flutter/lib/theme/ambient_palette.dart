import 'package:flutter/material.dart';

import 'tokens.dart';

/// 全局主题色随首页背景图取色。
///
/// 背景图解码时提取一个主色（[seed]），由它派生整套 [CitroColors]：
/// 强调色一族（accent / accent2 / accentLt / accentInk / onAccent /
/// hl / hlInk / tintBlue）换到主色的色相，并抬成 iOS 式的饱和强调色；
/// 页面底与半透明材质向主色轻微偏色（保留透明度）；语义色与文字色不动。
///
/// 浅色 / 深色各派生一份；还没取到主色时退回默认青瓷令牌。
class AmbientPalette {
  AmbientPalette._();

  static CitroColors? _light;
  static CitroColors? _dark;

  /// 当前主色（ARGB 整数）；同一张图重复解码时据此跳过重算。
  static int? _seed;

  /// 每次主色变化 +1，供外层（main）决定是否重建主题。
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static CitroColors get light => _light ?? CitroColors.light;
  static CitroColors get dark => _dark ?? CitroColors.darkColors;

  /// 用背景图主色派生主题；[seed] 为 null 回到默认令牌。
  static void apply(Color? seed) {
    if (seed == null) {
      if (_seed == null) return;
      _seed = null;
      _light = null;
      _dark = null;
      revision.value++;
      return;
    }
    if (seed.toARGB32() == _seed) return;
    _seed = seed.toARGB32();
    final hsl = HSLColor.fromColor(seed);
    // 几乎无彩色的图（灰雾 / 黑夜 / 纯白）派生出来只会发脏，直接用默认。
    if (hsl.saturation < 0.08) {
      _light = null;
      _dark = null;
    } else {
      _light = _derive(CitroColors.light, hsl);
      _dark = _derive(CitroColors.darkColors, hsl);
    }
    revision.value++;
  }

  static double _c(num v, num lo, num hi) => v.clamp(lo, hi).toDouble();

  /// 只改颜色、保留原透明度：半透明材质偏色后仍然是半透明。
  static Color _tint(Color c, Color to, double t) =>
      Color.lerp(c.withValues(alpha: 1), to, t)!.withValues(alpha: c.a);

  /// WCAG 对比度。
  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance() + .05;
    final lb = b.computeLuminance() + .05;
    return la > lb ? la / lb : lb / la;
  }

  /// 文字放在 [bg] 上用白还是用深墨：按 WCAG 相对亮度二选一。
  static Color _onColor(Color bg, Color darkInk) =>
      bg.computeLuminance() > .36 ? darkInk : const Color(0xFFFFFFFF);

  static CitroColors _derive(CitroColors base, HSLColor seed) {
    final dark = base.dark;
    // 黄 / 黄绿（约 45°–110°）压暗后会变成橄榄 / 军绿，很脏。
    // 这段色相整体往琥珀方向挪 18°：米色、奶黄、暖灰的背景图会得到
    // 一组焦糖 / 琥珀色，而不是一片土黄。
    final yellowish0 = seed.hue >= 45 && seed.hue <= 110;
    final hue = yellowish0 ? (seed.hue - 18) % 360 : seed.hue;
    // iOS 式强调色要「亮而饱和」：饱和度抬到 0.45–0.80，
    // 明度固定在可放白字的区间，换任何背景都是同一档存在感。
    // 黄 / 黄绿（约 45°–100°）在高饱和下会发「荧光」，收到 0.62 以内。
    // 低饱和的图（米色、灰调插画）也要给出有存在感的色块：饱和度下限 0.50。
    final yellowish = yellowish0 || (hue >= 35 && hue <= 100);
    final sat = _c(seed.saturation * 1.4, 0.50, yellowish ? 0.70 : 0.82);

    Color hsl(double s, double l, [double a = 1]) =>
        HSLColor.fromAHSL(a, hue, _c(s, 0, 1), _c(l, 0, 1)).toColor();

    // 浅色：主按钮上放白字，强调色从 L=0.50 往下压，直到对白色的对比度
    // ≥ 3:1（WCAG 大字 / 图标标准）。黄色系因此落到芥末 / 橄榄，而不是
    // 一块看不清字的亮黄。深色：强调色放在近黑底上，保持亮色即可。
    var lightL = .50;
    while (!dark &&
        lightL > .28 &&
        _contrast(hsl(sat, lightL), const Color(0xFFFFFFFF)) < 3.0) {
      lightL -= .02;
    }
    final accent = dark ? hsl(sat * .85, .64) : hsl(sat, lightL);
    final accent2 = dark ? hsl(sat * .80, .56) : hsl(sat, lightL - .07);
    final accentLt = dark ? hsl(sat * .45, .19) : hsl(sat * .70, .92);
    final accentInk = dark ? hsl(sat * .60, .82) : hsl(sat * .90, .30);
    final onAccent = _onColor(accent, dark ? hsl(sat * .5, .09) : hsl(sat * .6, .14));

    // 页面底 / 材质向主色偏一点，只动色相不动透明度。
    final cast = dark ? hsl(sat * .45, .11) : hsl(sat * .55, .95);
    return base.copyWith(
      bg: _tint(base.bg, cast, dark ? .55 : .65),
      bg2: _tint(base.bg2, cast, dark ? .45 : .45),
      surface: _tint(base.surface, cast, dark ? .30 : .18),
      accent: accent,
      accent2: accent2,
      accentLt: accentLt,
      accentInk: accentInk,
      onAccent: onAccent,
      hl: accent.withAlpha(dark ? 0x40 : 0x40),
      hlInk: accent.withAlpha(dark ? 0x66 : 0xCC),
      tintBlue: accent.withAlpha(dark ? 0x29 : 0x24),
      tintNeutral: _tint(base.tintNeutral, accent, .25),
    );
  }
}

/// 从解码后的背景图里提取主色：按彩度加权求平均，跳过近黑 / 近白
/// 的像素，这样天空、灰墙、夜空都不会把强调色拉成灰的。
///
/// 网格采样（最长边约 96 步），大图也不逐像素扫。
Color? extractAccentColor(
  int width,
  int height,
  (int, int, int) Function(int x, int y) pixelAt,
) {
  if (width <= 0 || height <= 0) return null;
  final stepX = (width / 96).ceil().clamp(1, 64);
  final stepY = (height / 96).ceil().clamp(1, 64);
  var r = 0.0, g = 0.0, b = 0.0, n = 0.0;
  for (var y = 0; y < height; y += stepY) {
    for (var x = 0; x < width; x += stepX) {
      final (pr, pg, pb) = pixelAt(x, y);
      final max = pr > pg ? (pr > pb ? pr : pb) : (pg > pb ? pg : pb);
      final min = pr < pg ? (pr < pb ? pr : pb) : (pg < pb ? pg : pb);
      final chroma = max - min;
      // 彩度太低（灰）或明度极端（黑 / 白）的像素不参与。
      if (chroma < 14 || max < 36 || min > 232) continue;
      final w = chroma.toDouble();
      r += pr * w;
      g += pg * w;
      b += pb * w;
      n += w;
    }
  }
  if (n == 0) return null;
  return Color.fromRGBO(r ~/ n, g ~/ n, b ~/ n, 1);
}
