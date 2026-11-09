import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import 'paper.dart';

Future<T?> showCitroDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  Color? barrier,
}) {
  final reduce = CitroMotion.reduced(context);
  return Navigator.of(context, rootNavigator: true).push<T>(
    _CitroDialogRoute<T>(
      page: builder,
      dismissible: dismissible,
      barrierColor: barrier ?? const Color(0xB223211C),
      reduce: reduce,
    ),
  );
}

/// 四端统一的弹窗路由：进场慢一点、退场快一点，居中缩放而不是从触发器展开。
class _CitroDialogRoute<T> extends PopupRoute<T> {
  final WidgetBuilder page;
  final bool dismissible;
  final Color _barrier;
  final bool reduce;

  _CitroDialogRoute({
    required this.page,
    required this.dismissible,
    required Color barrierColor,
    required this.reduce,
  }) : _barrier = barrierColor;

  @override
  Duration get transitionDuration => reduce ? Duration.zero : CitroMotion.modal;

  @override
  Duration get reverseTransitionDuration =>
      reduce ? Duration.zero : CitroMotion.modalReverse;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Color? get barrierColor => _barrier;

  @override
  String? get barrierLabel => '关闭';

  @override
  bool get opaque => false;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => page(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: CitroMotion.easeOut,
      reverseCurve: CitroMotion.exit,
    );
    if (reduce) return FadeTransition(opacity: curved, child: child);
    // 弹窗是居中的独立物件：保持 transform-origin 居中，只做轻微放大 + 上浮。
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: .965, end: 1).animate(curved),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .022),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

/// 底部弹层统一入口：四端同一套抽屉曲线与非对称时长。
///
/// 直接调用 `showModalBottomSheet` 会落到 Flutter 默认的 250ms ease，
/// 与本产品的节奏不一致；所有弹层走这里即可保持连贯。
Future<T?> showCitroSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  bool showDragHandle = false,
  Color? backgroundColor,
  Color? barrierColor,
  BoxConstraints? constraints,
  RouteSettings? routeSettings,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    backgroundColor: backgroundColor,
    barrierColor: barrierColor,
    constraints: constraints,
    routeSettings: routeSettings,
    sheetAnimationStyle: CitroMotion.sheetStyle(context),
  );
}

class PaperDialog extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final Color? tapeColor;
  final bool showClose;
  final VoidCallback? onClose;
  final bool scrollable;
  final bool alignTop;

  const PaperDialog({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 40, 24, 24),
    this.maxWidth = 376,
    this.tapeColor,
    this.showClose = true,
    this.onClose,
    this.scrollable = true,
    this.alignTop = false,
  });

  @override
  State<PaperDialog> createState() => _PaperDialogState();
}

class _PaperDialogState extends State<PaperDialog> {
  final GlobalKey _cardKey = GlobalKey();
  Offset? _downAt;

  void _onPointerUp(PointerUpEvent event) {
    final down = _downAt;
    _downAt = null;
    if (down == null) return;
    if ((event.position - down).distance > 14) return;
    final box = _cardKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.contains(event.position)) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // 原生弹层：iOS 上是系统材质的玻璃，其他端退化成半透明纸面 + 发丝边，
    // 但圆角、描边宽度、内高光四端一致。
    final card = CitroGlass(
      width: double.infinity,
      padding: widget.padding,
      borderRadius: BorderRadius.circular(CitroColors.radii.modal),
      tint: c.glassTintStrong,
      shadow: CitroColors.shadows.lg(c),
      child: widget.child,
    );
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -11,
          left: 0,
          right: 0,
          child: Center(
            child: Transform.rotate(
              angle: -2 * math.pi / 180,
              child: ClipPath(
                clipper: _TapeClip(),
                child: Container(
                  width: 86,
                  height: 24,
                  decoration: BoxDecoration(
                    color: widget.tapeColor ?? c.tape,
                    boxShadow: [
                      BoxShadow(
                        color: c.tapeLine,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.showClose)
          Positioned(
            top: AppSpacing.x1,
            right: AppSpacing.x1,
            child: Pressable(
              onTap: widget.onClose ?? () => Navigator.of(context).maybePop(),
              // 视觉 32pt，命中区补到 iOS 标准的 44pt。
              child: SizedBox(
                width: AppSpacing.touch,
                height: AppSpacing.touch,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.ink.withAlpha(10),
                      border: Border.all(
                        color: c.glassBorder,
                        width: CitroNative.hairline(context),
                      ),
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(AppIcons.close, width: 2),
                        color: c.inkSoft,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return Material(
      color: Colors.transparent,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _downAt = e.position,
        onPointerUp: _onPointerUp,
        child: SizedBox.expand(
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    vertical: widget.alignTop ? 16 : 32,
                    horizontal: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: widget.maxWidth),
                    child: KeyedSubtree(key: _cardKey, child: content),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TapeClip extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .02, 0)
    ..lineTo(size.width * .98, size.height * .03)
    ..lineTo(size.width, size.height * .95)
    ..lineTo(size.width * .04, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

class CitroField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int maxLines;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool enabled;

  const CitroField({
    super.key,
    required this.label,
    required this.hint,
    this.controller,
    this.obscure = false,
    this.keyboardType,
    this.maxLength,
    this.maxLines = 1,
    this.suffix,
    this.onChanged,
    this.focusNode,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.ui(
            size: 12,
            weight: FontWeight.w700,
            color: c.inkSoft,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          maxLength: maxLength,
          maxLines: maxLines,
          enabled: enabled,
          focusNode: focusNode,
          onChanged: onChanged,
          style: context.ui(size: 15, color: c.ink),
          cursorColor: c.accent,
          decoration: InputDecoration(
            counterText: '',
            hintText: hint,
            hintStyle: context.ui(size: 14, color: c.inkSoft),
            filled: true,
            fillColor: c.surface2,
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.x2,
              vertical: maxLines > 1 ? AppSpacing.x1 + 4 : 0,
            ),
            constraints: BoxConstraints(
              minHeight: maxLines > 1 ? 96 : AppSpacing.touch,
            ),
            suffixIcon: suffix,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CitroColors.radii.field),
              borderSide: BorderSide(color: c.line2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CitroColors.radii.field),
              borderSide: BorderSide(color: c.accent, width: 1),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CitroColors.radii.field),
              borderSide: BorderSide(color: c.line),
            ),
          ),
        ),
      ],
    );
  }
}

class AccentButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool loading;
  final double height;
  final double? width;
  final bool outlined;
  final bool danger;

  const AccentButton({
    super.key,
    required this.text,
    this.onTap,
    this.loading = false,
    this.height = 48,
    this.width,
    this.outlined = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fill = danger ? c.stamp : c.accent;
    final fg = outlined
        ? (danger ? c.stamp : c.ink2)
        : (danger ? Colors.white : const Color(0xFF2E2C22));
    return Pressable(
      onTap: (loading || onTap == null)
          ? null
          : () {
              // 主操作给一次轻触感，四端一致；Web 没有震动硬件。
              if (!kIsWeb) HapticFeedback.lightImpact();
              onTap?.call();
            },
      child: Container(
        width: width ?? double.infinity,
        // 任何传入高度都不得低于 44pt 的 iOS 可点击标准。
        height: math.max(height, AppSpacing.touch),
        decoration: BoxDecoration(
          color: outlined
              ? Colors.transparent
              : (onTap == null ? fill.withAlpha(120) : fill),
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: outlined
              ? Border.all(color: danger ? c.stamp : c.line2)
              : null,
          boxShadow: outlined ? null : CitroColors.shadows.note(c),
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Text(
                  text,
                  style: context.ui(
                    size: 15,
                    weight: FontWeight.w700,
                    color: fg,
                  ),
                ),
        ),
      ),
    );
  }
}
