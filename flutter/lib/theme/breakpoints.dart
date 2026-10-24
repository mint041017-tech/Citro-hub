import 'dart:ui';

/// iPhone Duo：外屏 5.4"（1398×2034 @3x，约 466×678pt），内屏 7.6"
/// （2007×2853 @3x，约 669×951pt，长宽比 1.42）。
class CitroForm {
  const CitroForm._();

  static bool duoInner(Size size) {
    final short = size.shortestSide;
    final long = size.longestSide;
    return short >= 600 && short <= 700 && long / short < 1.47;
  }

  static bool duoLandscape(Size size) =>
      duoInner(size) && size.width > size.height;

  static bool duoOuter(Size size) {
    final short = size.shortestSide;
    final long = size.longestSide;
    return short >= 450 &&
        short <= 480 &&
        long >= 660 &&
        long <= 690 &&
        long / short < 1.5;
  }

  static bool duoDevice(Size size) => duoInner(size) || duoOuter(size);

  static double duoRailTopInset(Size size) => duoOuter(size) ? 168 : 112;

  static bool tabletNav(Size size) =>
      (size.width >= 900 && size.shortestSide >= 600) || duoLandscape(size);
}
