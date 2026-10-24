import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'paper.dart';

Future<T?> showCitroDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  Color? barrier,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: '关闭',
    barrierColor: barrier ?? const Color(0xB223211C),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, sec) => builder(ctx),
    transitionBuilder: (ctx, anim, sec, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: .96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
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
    this.padding = const EdgeInsets.fromLTRB(24, 42, 24, 24),
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
    final card = Container(
      width: double.infinity,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(16),
        boxShadow: CitroColors.shadows.lg(c),
      ),
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
            top: 8,
            right: 8,
            child: Pressable(
              onTap: widget.onClose ?? () => Navigator.of(context).maybePop(),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.ink.withAlpha(8),
                  border: Border.all(color: c.line.withAlpha(120)),
                ),
                child: Center(
                  child: AppIcon(
                    strokeSvg(AppIcons.close, width: 2),
                    color: c.inkSoft,
                    size: 15,
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
          style: context.body(
            size: 11.5,
            weight: FontWeight.w700,
            color: c.inkSoft,
            letterSpacing: .46,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          maxLength: maxLength,
          maxLines: maxLines,
          enabled: enabled,
          focusNode: focusNode,
          onChanged: onChanged,
          style: context.body(size: 14, color: c.ink),
          cursorColor: c.accent,
          decoration: InputDecoration(
            counterText: '',
            hintText: hint,
            hintStyle: context.body(
              size: 13.5,
              color: c.inkSoft.withAlpha(210),
            ),
            filled: true,
            fillColor: c.surface2,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 12 : 0,
            ),
            constraints: BoxConstraints(minHeight: maxLines > 1 ? 92 : 44),
            suffixIcon: suffix,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.line2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.accent, width: 1),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
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
    this.height = 46,
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
      onTap: loading ? null : onTap,
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: outlined
              ? Colors.transparent
              : (onTap == null ? fill.withAlpha(120) : fill),
          borderRadius: BorderRadius.circular(999),
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
                  style: context.body(
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
