import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import 'paper.dart';

/// 盖在内容之上的子树（弹窗 / 底部面板）：把半透明的 [CitroColors.surface]
/// 换成不透明的 [CitroSurfaceX.sheet]，弹层里沿用 `c.surface` 的代码
/// 不会透出底下的页面。其余配色不变，仍随背景取色。
Widget citroOpaqueSurface(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  final c = context.c;
  // 已经是不透明配色（嵌套弹层）就不再包一层。
  if (c.surface.a >= .999) return child;
  final sheet = c.sheet;
  // 分区底（tint*）在沉浸式里是半透明的，铺在弹层大面积底上会透出
  // 后面的页面；这里统一预先叠到不透明的 sheet 上。
  Color solid(Color x) => Color.alphaBlend(x, sheet);
  return Theme(
    data: theme.copyWith(
      extensions: [
        for (final e in theme.extensions.values)
          if (e is! CitroSkin) e,
        CitroSkin(
          c.copyWith(
            bg: sheet,
            surface: sheet,
            tintYellow: solid(c.tintYellow),
            tintPink: solid(c.tintPink),
            tintBlue: solid(c.tintBlue),
            tintGreen: solid(c.tintGreen),
            tintNeutral: solid(c.tintNeutral),
          ),
        ),
      ],
    ),
    child: child,
  );
}

Future<T?> showCitroDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  Color? barrier,
}) {
  final reduce = CitroMotion.reduced(context);
  return Navigator.of(context, rootNavigator: true).push<T>(
    _CitroDialogRoute<T>(
      page: (ctx) => citroOpaqueSurface(ctx, builder(ctx)),
      dismissible: dismissible,
      barrierColor: barrier ?? context.c.scrim,
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

/// 居中 / 自定义转场弹层的统一入口，替掉 `showGeneralDialog`。
///
/// Flutter 的 `RawDialogRoute` 没有 `reverseTransitionDuration`，退场只能和
/// 进场一样长，做不到「回得比去得快」。这里改用自绘 [PopupRoute] 补上，
/// 转场写法与 `showGeneralDialog` 完全一致（pageBuilder + transitionBuilder），
/// 只是退场固定比进场短。
Future<T?> showCitroGeneralDialog<T>({
  required BuildContext context,
  required RoutePageBuilder pageBuilder,
  required RouteTransitionsBuilder transitionBuilder,
  bool barrierDismissible = true,
  String? barrierLabel,
  Color barrierColor = const Color(0x8A000000),
  Duration transitionDuration = CitroMotion.modal,
  Duration reverseTransitionDuration = CitroMotion.modalReverse,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final reduce = CitroMotion.reduced(context);
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _CitroGeneralDialogRoute<T>(
      pageBuilder: (ctx, a, b) =>
          citroOpaqueSurface(ctx, pageBuilder(ctx, a, b)),
      // 有的弹层（今日一签、卡面收藏）把内容画在 transitionBuilder 里，
      // 这里也要换成不透明配色，否则卡面会透出底下的页面。
      transitionBuilder: (ctx, a, b, child) =>
          citroOpaqueSurface(ctx, transitionBuilder(ctx, a, b, child)),
      dismissible: barrierDismissible,
      label: barrierLabel ?? '关闭',
      barrier: barrierColor,
      duration: transitionDuration,
      reverseDuration: reverseTransitionDuration,
      reduce: reduce,
      settings: routeSettings,
    ),
  );
}

class _CitroGeneralDialogRoute<T> extends PopupRoute<T> {
  _CitroGeneralDialogRoute({
    required this.pageBuilder,
    required this.transitionBuilder,
    required this.dismissible,
    required this.label,
    required this.barrier,
    required this.duration,
    required this.reverseDuration,
    required this.reduce,
    super.settings,
  });

  final RoutePageBuilder pageBuilder;
  final RouteTransitionsBuilder transitionBuilder;
  final bool dismissible;
  final String label;
  final Color barrier;
  final Duration duration;
  final Duration reverseDuration;
  final bool reduce;

  @override
  Duration get transitionDuration => reduce ? Duration.zero : duration;

  @override
  Duration get reverseTransitionDuration =>
      reduce ? Duration.zero : reverseDuration;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Color? get barrierColor => barrier;

  @override
  String? get barrierLabel => label;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => pageBuilder(context, animation, secondaryAnimation);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => transitionBuilder(context, animation, secondaryAnimation, child);
}

/// 日期选择器：统一套 Citro 主题。
///
/// 不套 builder 的原生日期选择器是 Material 默认配色，和整站没关系；
/// 这里只改配色与圆角，不动交互。
Future<DateTime?> showCitroDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  String? helpText,
}) {
  final c = context.c;
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    currentDate: currentDate,
    helpText: helpText,
    builder: (ctx, child) => Theme(
      data: Theme.of(ctx).copyWith(
        datePickerTheme: DatePickerThemeData(
          backgroundColor: c.sheet,
          headerBackgroundColor: c.accentLt,
          headerForegroundColor: c.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          ),
        ),
      ),
      child: child!,
    ),
  );
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
    builder: (ctx) => citroOpaqueSurface(ctx, builder(ctx)),
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
  final bool showClose;
  final VoidCallback? onClose;
  final bool scrollable;
  final bool alignTop;
  final double? blurSigma;
  final Color? tint;

  const PaperDialog({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 40, 24, 24),
    this.maxWidth = 376,
    this.showClose = true,
    this.onClose,
    this.scrollable = true,
    this.alignTop = false,
    this.blurSigma = 36,
    this.tint,
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
      tint:
          widget.tint ?? (c.dark ? const Color(0x42FFFFFF) : c.glassTintStrong),
      sigma: widget.blurSigma,
      shadow: CitroColors.shadows.lg(c),
      child: widget.child,
    );
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        card,
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
    // iOS 式主操作：背景取色派生的强调色实心胶囊；危险操作保持红色。
    final fill = danger ? c.danger : c.accent2;
    final fg = outlined
        ? (danger ? c.danger : c.accentInk)
        : (danger ? const Color(0xFFFFFFFF) : c.onAccent);
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
              ? Border.all(color: danger ? c.danger : c.line2)
              : null,
          boxShadow: outlined || onTap == null
              ? null
              : (danger
                    ? CitroColors.shadows.sm(c)
                    : CitroColors.shadows.glow(c)),
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
