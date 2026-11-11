import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';

/// 页面背景。纯色或极轻的垂直渐变，没有网格纸。
///
/// 旧版 PaperBackground 的 24px 网格 + 暖光已删除；需要分区底色时用 [CitroBackground.tint]。
class CitroBackground extends StatelessWidget {
  final Widget child;
  final Color? color;
  final CitroTint? tint;
  final bool gradient;

  const CitroBackground({
    super.key,
    required this.child,
    this.color,
    this.tint,
    this.gradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = color ?? (tint != null ? c.tint(tint!) : c.bg);
    if (!gradient) {
      return ColoredBox(color: base, child: child);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [base, Color.lerp(base, c.surface, .6)!],
        ),
      ),
      child: child,
    );
  }
}

/// 卡片：大圆角 + 柔和阴影 + 可选整卡按压。
///
/// 这是全站容器的唯一基座：没有描边、没有胶带、没有折角、没有旋转。
class CitroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final List<BoxShadow>? shadow;
  final Border? border;
  final Clip clip;

  /// 用液态玻璃代替实色表面。为空时看 [GlassCardsScope] 的开关，
  /// 首页 Bento 就是把整格卡片放进这个 scope，统一切成玻璃。
  final bool? glass;

  const CitroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
    this.radius = 0,
    this.onTap,
    this.onLongPress,
    this.shadow,
    this.border,
    this.clip = Clip.none,
    this.glass,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = radius == 0 ? CitroColors.radii.card : radius;
    final br = BorderRadius.circular(r);
    // 统一实色表面：玻璃已全线取消，卡片就是奶青底上的浅卡 + 描边 + 投影。
    Widget box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: br,
        border: border,
        boxShadow: shadow ?? CitroColors.shadows.card(c),
      ),
      child: clip == Clip.none
          ? child
          : ClipRRect(borderRadius: br, child: child),
    );
    if (onTap != null || onLongPress != null) {
      box = Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
        scale: .98,
        borderRadius: br,
        child: box,
      );
    }
    if (margin != null) return Padding(padding: margin!, child: box);
    return box;
  }
}

/// 打开后，子树里所有 [CitroCard] 都改用液态玻璃表面。
///
/// 玻璃已全线取消，这里保留成空操作，避免各处调用点报错。
class GlassCardsScope extends InheritedWidget {
  final bool glass;

  const GlassCardsScope({super.key, this.glass = true, required super.child});

  static bool maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassCardsScope>()?.glass ??
      false;

  @override
  bool updateShouldNotify(GlassCardsScope oldWidget) =>
      oldWidget.glass != glass;
}

/// 胶囊按钮。主按钮是近黑（深色主题近白），品牌橙只做强调变体。
class CitroButton extends StatelessWidget {
  final String label;
  final Widget? icon;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final CitroButtonStyle style;
  final double height;
  final double? width;
  final bool expanded;
  final bool busy;

  const CitroButton({
    super.key,
    required this.label,
    this.icon,
    this.trailing,
    required this.onPressed,
    this.style = CitroButtonStyle.primary,
    this.height = 48,
    this.width,
    this.expanded = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg, border) = switch (style) {
      CitroButtonStyle.primary => (c.ink, c.bg, Border.all(color: c.ink)),
      CitroButtonStyle.accent => (
        c.accent,
        c.onAccent,
        Border.all(color: c.accent),
      ),
      CitroButtonStyle.mint => (c.mint, c.onAccent, Border.all(color: c.mint)),
      CitroButtonStyle.danger => (
        c.danger,
        c.onAccent,
        Border.all(color: c.danger),
      ),
      CitroButtonStyle.outline => (
        Colors.transparent,
        c.ink,
        Border.all(color: c.line2),
      ),
      CitroButtonStyle.ghost => (
        Colors.transparent,
        c.ink2,
        Border.all(color: Colors.transparent),
      ),
      CitroButtonStyle.surface => (
        c.surface2,
        c.ink,
        Border.all(color: c.line),
      ),
    };
    final enabled = onPressed != null && !busy;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          IconTheme(
            data: IconThemeData(color: fg, size: 18),
            child: icon!,
          ),
        if (busy || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.body(
              size: CitroType.label,
              weight: CitroType.medium,
              color: fg,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
    Widget btn = Material(
      color: bg,
      borderRadius: BorderRadius.circular(CitroColors.radii.button),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(CitroColors.radii.button),
        child: Container(
          height: height,
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
    if (expanded) btn = SizedBox(width: double.infinity, child: btn);
    if (!enabled) {
      btn = Opacity(
        opacity: .45,
        child: IgnorePointer(ignoring: true, child: btn),
      );
    }
    return btn;
  }
}

enum CitroButtonStyle { primary, accent, mint, danger, outline, ghost, surface }

/// 胶囊标签。中性为主，语义色只作小面积点缀。
class CitroChip extends StatelessWidget {
  final String text;
  final Widget? icon;
  final Color? color;
  final Color? background;
  final Color? borderColor;
  final EdgeInsets padding;
  final double size;
  final FontWeight weight;

  const CitroChip(
    this.text, {
    super.key,
    this.icon,
    this.color,
    this.background,
    this.borderColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.size = CitroType.caption,
    this.weight = CitroType.medium,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(color: borderColor ?? c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            IconTheme(
              data: IconThemeData(color: color ?? c.ink2, size: size + 3),
              child: icon!,
            ),
          if (icon != null) const SizedBox(width: 4),
          Text(
            text,
            style: context.body(
              size: size,
              weight: weight,
              color: color ?? c.ink2,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 页面大标题：计划 / 游戏 / 社区共用，字号与首页打招呼一致。
class CitroPageTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const CitroPageTitle(this.title, this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.display(size: CitroType.hero, color: c.ink),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: context.body(size: CitroType.meta, color: c.inkSoft),
          ),
        ],
      ],
    );
  }
}

/// 分区标题：纯文字 + 可选右侧操作，没有荧光笔底纹和斜置短横。
class CitroSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry padding;
  final double size;

  const CitroSectionHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
    this.size = CitroType.title,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: size * .72,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.heading(size: size, color: c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.body(size: CitroType.meta, color: c.inkSoft),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

/// 输入框：大圆角、无下划线、聚焦时品牌橙描边。
class CitroTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final Widget? prefix;
  final Widget? suffix;
  final int maxLines;
  final int? minLines;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final Color? fillColor;

  const CitroTextField({
    super.key,
    this.controller,
    this.hint,
    this.prefix,
    this.suffix,
    this.maxLines = 1,
    this.minLines,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.focusNode,
    this.keyboardType,
    this.style,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(CitroColors.radii.field),
      borderSide: BorderSide(color: c.line),
      gapPadding: 8,
    );
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      obscureText: obscure,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      focusNode: focusNode,
      keyboardType: keyboardType,
      style: style ?? context.body(size: CitroType.body, color: c.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: context.body(size: CitroType.body, color: c.inkSoft),
        prefixIcon: prefix,
        suffixIcon: suffix,
        filled: true,
        fillColor: fillColor ?? c.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CitroColors.radii.field),
          borderSide: BorderSide(color: c.accent, width: 1.5),
          gapPadding: 8,
        ),
        border: border,
      ),
    );
  }
}

/// 指标块：小标签 + 大数字（等宽），用于营养/统计栅格。
class CitroStat extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? color;
  final bool center;

  const CitroStat(
    this.label,
    this.value, {
    super.key,
    this.unit,
    this.color,
    this.center = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final valueColor = color ?? c.ink;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.body(
            size: CitroType.small,
            color: c.inkSoft,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: context.hand(size: CitroType.bodyLg, color: valueColor),
            ),
            if (unit != null) ...[
              const SizedBox(width: 1),
              Text(
                unit!,
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 贴纸相框：白色圆角/圆形底 + 虚线描边，nosh 的「sticker」符号。
///
/// 只用在照片/插画上（菜谱图、头像、相册），不做大面积容器。
class StickerFrame extends StatelessWidget {
  final Widget child;
  final double size;
  final double radius;
  final bool circle;
  final Color? color;
  final Color? dashColor;
  final double dashWidth;

  const StickerFrame({
    super.key,
    required this.child,
    this.size = 96,
    this.radius = 24,
    this.circle = false,
    this.color,
    this.dashColor,
    this.dashWidth = 1.6,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final br = circle
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(radius);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: br,
        boxShadow: CitroColors.shadows.sm(c),
      ),
      child: CustomPaint(
        foregroundPainter: _DashPainter(
          color: dashColor ?? c.inkSoft.withAlpha(150),
          radius: br,
          width: dashWidth,
        ),
        child: ClipRRect(borderRadius: br, child: child),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  final BorderRadius radius;
  final double width;
  _DashPainter({
    required this.color,
    required this.radius,
    required this.width,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect(Offset.zero & size);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final path = Path()..addRRect(rrect.deflate(width / 2));
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      double d = 0;
      const dash = 5.0;
      const gap = 4.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) =>
      old.color != color || old.radius != radius || old.width != width;
}

/// 圆形头像 / 图标块。
class CitroAvatar extends StatelessWidget {
  final String? text;
  final Widget? child;
  final double size;
  final Color? color;

  const CitroAvatar({
    super.key,
    this.text,
    this.child,
    this.size = 40,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? c.surface2,
        shape: BoxShape.circle,
      ),
      child:
          child ??
          (text == null
              ? null
              : Text(
                  text!,
                  style: context.body(
                    size: size * .38,
                    weight: CitroType.strong,
                    color: c.ink2,
                  ),
                )),
    );
  }
}

/// 胶囊进度条。
class CitroProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  final Color? track;

  const CitroProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.track,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: [
          Container(height: height, color: track ?? c.surface2),
          FractionallySizedBox(
            widthFactor: v,
            child: Container(height: height, color: color ?? c.accent),
          ),
        ],
      ),
    );
  }
}

/// 发丝分隔线。
class CitroDivider extends StatelessWidget {
  final double height;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  const CitroDivider({super.key, this.height = 1, this.color, this.margin});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: margin,
      color: color ?? context.c.line,
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

/// 实心图标（点赞后的小红心等），颜色由 [AppIcon] 的 color 统一着色。
String fillSvg(String body, {String color = '#000000'}) =>
    '<svg viewBox="0 0 24 24" fill="$color" stroke="none">$body</svg>';

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
  static const phone =
      '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1 1 .4 2 .7 2.9a2 2 0 0 1-.5 2.1L8.1 9.9a16 16 0 0 0 6 6l1.2-1.2a2 2 0 0 1 2.1-.5c.9.3 1.9.6 2.9.7a2 2 0 0 1 1.7 2z"/>';
  static const mail =
      '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>';
  static const info =
      '<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 8h.01"/>';
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
  static const wave =
      '<path d="M3 12h2M19 12h2"/><path d="M7 8v8M11 5v14M15 8v8"/>';
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
  static const heartFilled =
      '<path d="M12 21.1 4.2 13.6a5.6 5.6 0 0 1 0-7.9 5.6 5.6 0 0 1 7.8 0 5.6 5.6 0 0 1 7.8 0 5.6 5.6 0 0 1 0 7.9z"/>';

  /// 社区：带一颗小爱心的对话框，比并排小人更贴合「社区」语义。
  static const community =
      '<path d="M21 11.5a8.4 8.4 0 0 1-9 8.4 9.9 9.9 0 0 1-4.1-.9L3 20l1-4.3A8.4 8.4 0 0 1 3 11.5a8.4 8.4 0 0 1 9-8.4 8.4 8.4 0 0 1 9 8.4z"/><path d="M12 14.2s-2.8-1.6-2.8-3.3a1.7 1.7 0 0 1 2.8-1.4 1.7 1.7 0 0 1 2.8 1.4c0 1.7-2.8 3.3-2.8 3.3z"/>';
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
  static const qr =
      '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3z"/><path d="M21 14v.01M14 21v.01M21 21v.01"/>';
  static const scan =
      '<path d="M3 8V5a2 2 0 0 1 2-2h3"/><path d="M16 3h3a2 2 0 0 1 2 2v3"/><path d="M21 16v3a2 2 0 0 1-2 2h-3"/><path d="M8 21H5a2 2 0 0 1-2-2v-3"/><circle cx="12" cy="12" r="3"/>';
  static const wallet =
      '<path d="M3 7a2 2 0 0 1 2-2h13a1 1 0 0 1 1 1v2"/><path d="M3 7v11a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V9a1 1 0 0 0-1-1H5"/><path d="M17 13h.01"/>';
  static const trendUp =
      '<path d="M3 17 9.5 10.5l4 4L21 7"/><path d="M15 7h6v6"/>';
  static const flash = '<path d="M13 2 3 14h7l-1 8 10-12h-7l1-8z"/>';
  static const check = '<path d="M20 6 9 17l-5-5"/>';
  static const list =
      '<path d="M9 6h12M9 12h12M9 18h12"/><circle cx="4" cy="6" r="1.3"/><circle cx="4" cy="12" r="1.3"/><circle cx="4" cy="18" r="1.3"/>';
  static const board =
      '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16M15 4v16"/>';
  static const smile =
      '<circle cx="12" cy="12" r="9"/><path d="M8.5 14.5a4.5 4.5 0 0 0 7 0M9 9.5h.01M15 9.5h.01"/>';
  static const flag = '<path d="M5 21V4"/><path d="M5 4h11l-2 4 2 4H5"/>';
  static const repeat =
      '<path d="M17 2l4 4-4 4"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><path d="M7 22l-4-4 4-4"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>';
  static const target =
      '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r="1"/>';
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
    this.scale = .96,
    this.borderRadius,
    this.hoverColor,
    this.hoverOverlayColor,
    this.hoverLift = 2,
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
    final reduce = CitroMotion.reduced(context);
    // Windows 上鼠标悬停会连续触发大半径阴影重绘，是掉帧的主要来源之一。
    // 这里保留同一条阴影、只缩小半径，四端都有稳定的悬停层次。
    final cheapHover = !kIsWeb && platform.isWindows;
    final hoverShadow = widget.hoverShadow ?? true;
    final lift = _hover && !_down && !reduce ? -widget.hoverLift : 0.0;
    final scale = _down && !reduce
        ? widget.scale
        : (_hover && !reduce ? 1.02 : (_focused && !reduce ? 1.02 : 1.0));
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
            duration: reduce ? Duration.zero : CitroMotion.press,
            curve: CitroMotion.easeOut,
            transform: Matrix4.translationValues(0, lift, 0),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: hoverShadow && widget.borderRadius != null
                  ? [
                      BoxShadow(
                        color: _hover && !_down
                            ? (c.dark
                                  ? const Color(0x66000000)
                                  : const Color(0x2E000000))
                            : Colors.transparent,
                        blurRadius: _hover && !_down
                            ? (cheapHover ? 12 : 22)
                            : 0,
                        spreadRadius: _hover && !_down ? -12 : 0,
                        offset: const Offset(0, 9),
                      ),
                    ]
                  : const [],
            ),
            child: AnimatedScale(
              scale: scale,
              duration: reduce ? Duration.zero : CitroMotion.press,
              curve: CitroMotion.easeOut,
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
                                curve: CitroMotion.easeColor,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: widget.hoverColor,
                                    borderRadius:
                                        widget.borderRadius ??
                                        BorderRadius.circular(16),
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
                                curve: CitroMotion.easeColor,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: widget.hoverOverlayColor,
                                    borderRadius:
                                        widget.borderRadius ??
                                        BorderRadius.circular(16),
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
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ToastBubble(
        message: message,
        hold: duration,
        onDismissed: () {
          if (identical(_entry, entry)) _entry = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _ToastBubble extends StatefulWidget {
  const _ToastBubble({
    required this.message,
    required this.hold,
    required this.onDismissed,
  });

  final String message;
  final Duration hold;
  final VoidCallback onDismissed;

  @override
  State<_ToastBubble> createState() => _ToastBubbleState();
}

class _ToastBubbleState extends State<_ToastBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CitroMotion.toast,
    reverseDuration: CitroMotion.toastReverse,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: CitroMotion.easeOut,
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, -.18),
    end: Offset.zero,
  ).animate(_opacity);
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _holdTimer = Timer(widget.hold, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    // 全局轻提示统一显示在屏幕上方（键盘弹出时不会被遮）。
    return Positioned(
      left: 24,
      right: 24,
      top: MediaQuery.paddingOf(context).top + 88,
      child: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: SlideTransition(
            position: reduce
                ? const AlwaysStoppedAnimation(Offset.zero)
                : _offset,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.ink.withAlpha(240),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: CitroColors.shadows.card(c),
                ),
                child: Text(
                  widget.message,
                  style: context.body(size: CitroType.meta, color: c.bg),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
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

// ---------------------------------------------------------------------------
// 弃用替身：保留旧类名，让尚未迁移的文件继续编译。新代码请用上面的新组件。
// 这些替身全部按新风格渲染（无网格 / 无胶带 / 无折角 / 大圆角）。
// ---------------------------------------------------------------------------

/// @deprecated 用 [CitroBackground]。
@Deprecated('用 CitroBackground 代替')
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
  Widget build(BuildContext context) =>
      CitroBackground(color: color, child: child);
}

/// @deprecated 用 [CitroCard]。
@Deprecated('用 CitroCard 代替')
class PaperCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final PaperShadow shadow;
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
    Widget box = Container(
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius:
            borderRadius ??
            BorderRadius.circular(
              radius == 14 ? CitroColors.radii.card : radius,
            ),
        border: borderColor == null ? null : Border.all(color: borderColor!),
        boxShadow: shadow == PaperShadow.none
            ? const []
            : CitroColors.shadows.card(c),
      ),
      child: clip
          ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child)
          : child,
    );
    if (onTap != null) {
      box = Pressable(
        onTap: onTap,
        scale: .98,
        borderRadius: BorderRadius.circular(radius),
        child: box,
      );
    }
    if (margin != null) return Padding(padding: margin!, child: box);
    return box;
  }
}

enum PaperShadow { paper, large, note, none }

/// @deprecated 用纸胶带做装饰的手账风已移除。
@Deprecated('纸胶带已移除')
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// @deprecated 用 [CitroSectionHeader]。
@Deprecated('用 CitroSectionHeader 代替')
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
  Widget build(BuildContext context) => CitroSectionHeader(
    text,
    size: size < 23 ? size : CitroType.title,
    padding: padding,
  );
}

/// @deprecated 用 [CitroChip]。
@Deprecated('用 CitroChip 代替')
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
  Widget build(BuildContext context) => CitroChip(
    text,
    color: color,
    background: bg,
    padding: padding,
    size: size,
    borderColor: border?.top.color,
  );
}

/// @deprecated 用 [CitroDivider]。
@Deprecated('用 CitroDivider 代替')
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
  Widget build(BuildContext context) =>
      CitroDivider(height: thickness, color: color);
}

/// @deprecated 荧光笔底纹已移除，直接用 Text。
@Deprecated('荧光笔底纹已移除，直接用 Text')
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
  Widget build(BuildContext context) =>
      Text(text, style: style, maxLines: 1, softWrap: false);
}
