import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// 卡片 → 详情 的容器形变（Container Transform）。
///
/// Flutter 的 Hero 需要目标页面里存在一个对应的视觉元素，而很多卡片打开的是
/// 整页/面板，没有可复用的元素。这里用"卡片纸面长成整页"的方式实现同一种体感：
/// 卡片自身的圆角纸面从它的屏幕矩形扩展到目标矩形，内容随后淡入。
///
/// - 只在 PageRoute 上使用（Dialog/Sheet 路由不会参与 Navigator 的 Hero/转场联动）；
/// - 减少动态时直接返回普通页面，不做形变。
class CitroCardMorph {
  CitroCardMorph._();

  /// 卡片被点击时的全局矩形；由卡片在 onTap 里记录。
  static Rect? pendingRect;

  static void capture(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      pendingRect = box.localToGlobal(Offset.zero) & box.size;
    }
  }

  static Rect? take() {
    final rect = pendingRect;
    pendingRect = null;
    return rect;
  }

  /// 打开一个"从卡片长出来"的整页。
  static Future<T?> pushPage<T>(
    BuildContext context, {
    required Rect source,
    required WidgetBuilder builder,
    RouteSettings? settings,
    Color? barrier,
    Future<ui.Image?>? snapshot,
  }) async {
    final reduce = CitroMotion.reduced(context);
    final image = reduce ? null : await snapshot;
    final result = await Navigator.of(context, rootNavigator: true).push<T>(
      PageRouteBuilder<T>(
        settings: settings,
        opaque: false,
        barrierColor: barrier ?? const Color(0xB223211C),
        barrierDismissible: false,
        transitionDuration: reduce ? Duration.zero : CitroMotion.pageTouch,
        reverseTransitionDuration: reduce
            ? Duration.zero
            : CitroMotion.pageTouchReverse,
        pageBuilder: (ctx, animation, secondary) => builder(ctx),
        transitionsBuilder: (ctx, animation, secondary, child) {
          if (reduce) return child;
          return _CardMorphTransition(
            source: source,
            animation: animation,
            snapshot: image,
            child: child,
          );
        },
      ),
    );
    // 退场的最后一帧仍在用这张快照，立刻释放会让 RenderImage 在下一帧
    // clone 到已 dispose 的图片（Bad state: Cannot clone a disposed image）。
    if (image != null) {
      Future<void>.delayed(const Duration(milliseconds: 800), image.dispose);
    }
    return result;
  }

  /// 打开一个"卡片放大预览"（用于本身没有详情的卡片）。
  /// 纸页升起：适合食谱日记 / 听隅这类内容页。
  ///
  /// 页面从第一帧就存在，以轻微下沉 + 缩放淡入，卡片快照快速抬起淡出，
  /// 背景纸张同时铺满，不做「空白卡片先展开再淡入」的那一段。
  static Future<T?> pushPageSoft<T>(
    BuildContext context, {
    required Rect source,
    required WidgetBuilder builder,
    RouteSettings? settings,
    Future<ui.Image?>? snapshot,
  }) async {
    final reduce = CitroMotion.reduced(context);
    final image = reduce ? null : await snapshot;
    final result = await Navigator.of(context, rootNavigator: true).push<T>(
      PageRouteBuilder<T>(
        settings: settings,
        opaque: false,
        barrierColor: Colors.transparent,
        barrierDismissible: false,
        transitionDuration: reduce
            ? Duration.zero
            : const Duration(milliseconds: 380),
        reverseTransitionDuration: reduce
            ? Duration.zero
            : const Duration(milliseconds: 260),
        pageBuilder: (ctx, animation, secondary) => builder(ctx),
        transitionsBuilder: (ctx, animation, secondary, child) {
          if (reduce) return child;
          return _SoftPageTransition(
            source: source,
            animation: animation,
            snapshot: image,
            child: child,
          );
        },
      ),
    );
    if (image != null) {
      Future<void>.delayed(const Duration(milliseconds: 800), image.dispose);
    }
    return result;
  }

  static Future<void> showPreview(
    BuildContext context, {
    required Rect source,
    required WidgetBuilder builder,
    Color barrier = const Color(0x8A23211C),
  }) {
    final reduce = CitroMotion.reduced(context);
    final media = MediaQuery.sizeOf(context);
    final target = Rect.fromCenter(
      center: media.center(Offset.zero),
      width: media.width * .88,
      height: media.height * .72,
    );
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: barrier,
        barrierDismissible: true,
        transitionDuration: reduce ? Duration.zero : CitroMotion.modal,
        reverseTransitionDuration: reduce
            ? Duration.zero
            : CitroMotion.modalReverse,
        pageBuilder: (ctx, animation, secondary) => GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Center(
            child: SizedBox(
              width: target.width,
              height: target.height,
              child: builder(ctx),
            ),
          ),
        ),
        transitionsBuilder: (ctx, animation, secondary, child) {
          if (reduce) return child;
          return _CardMorphTransition(
            source: source,
            animation: animation,
            target: target,
            child: child,
          );
        },
      ),
    );
  }
}

class _CardMorphTransition extends StatelessWidget {
  const _CardMorphTransition({
    required this.source,
    required this.animation,
    required this.child,
    this.target,
    this.snapshot,
  });

  final Rect source;
  final Animation<double> animation;
  final Widget child;
  final Rect? target;
  final ui.Image? snapshot;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final media = MediaQuery.sizeOf(context);
    final end = target ?? (Offset.zero & media);
    final curved = CurvedAnimation(
      parent: animation,
      curve: CitroMotion.easeInOut,
      reverseCurve: CitroMotion.exit,
    );
    final rect = RectTween(begin: source, end: end);
    final radius = Tween<double>(begin: 14, end: target == null ? 0 : 20);
    // 内容在纸面长到 55% 后才淡入，避免布局在飞行中被压缩变形。
    final contentOpacity = CurvedAnimation(
      parent: animation,
      curve: const Interval(.32, 1, curve: CitroMotion.easeOut),
      reverseCurve: CitroMotion.exit,
    );
    final contentScale = Tween<double>(begin: .988, end: 1).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(.32, 1, curve: CitroMotion.easeOut),
        reverseCurve: CitroMotion.exit,
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: contentOpacity,
            child: ScaleTransition(scale: contentScale, child: child),
          ),
        ),
        AnimatedBuilder(
          animation: curved,
          builder: (context, _) {
            final r = rect.evaluate(curved) ?? end;
            return Positioned.fromRect(
              rect: r,
              child: IgnorePointer(
                child: Opacity(
                  // 纸面在最后 22% 里淡出，把页面交还出来。
                  opacity: (1 - ((curved.value - .78) / .22).clamp(0, 1)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(
                        radius.evaluate(curved),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x33000000),
                          blurRadius: 24 * curved.value,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: snapshot == null
                        ? null
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(
                              radius.evaluate(curved),
                            ),
                            child: RawImage(image: snapshot, fit: BoxFit.cover),
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SoftPageTransition extends StatelessWidget {
  final Rect source;
  final Animation<double> animation;
  final ui.Image? snapshot;
  final Widget child;

  const _SoftPageTransition({
    required this.source,
    required this.animation,
    required this.snapshot,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final curved = CurvedAnimation(
      parent: animation,
      curve: CitroMotion.emphasized,
      reverseCurve: CitroMotion.exit,
    );
    final pageFade = CurvedAnimation(
      parent: animation,
      curve: const Interval(.12, 1, curve: CitroMotion.easeOut),
      reverseCurve: const Interval(0, .6, curve: Curves.easeIn),
    );
    final pageSlide = Tween<Offset>(
      begin: const Offset(0, .045),
      end: Offset.zero,
    ).animate(curved);
    final pageScale = Tween<double>(begin: .984, end: 1).animate(curved);
    final backgroundFade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, .5, curve: CitroMotion.easeOut),
      reverseCurve: const Interval(0, .55, curve: Curves.easeIn),
    );
    final snapshotFade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, .34, curve: CitroMotion.easeOut),
      reverseCurve: const Interval(.45, 1, curve: CitroMotion.easeOut),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: backgroundFade,
            child: ColoredBox(color: c.surface),
          ),
        ),
        Positioned.fill(
          child: FadeTransition(
            opacity: pageFade,
            child: SlideTransition(
              position: pageSlide,
              child: ScaleTransition(scale: pageScale, child: child),
            ),
          ),
        ),
        if (snapshot != null)
          AnimatedBuilder(
            animation: snapshotFade,
            builder: (context, _) {
              final lift = 6 * snapshotFade.value;
              return Positioned.fromRect(
                rect: source.inflate(lift),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (1 - snapshotFade.value).clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14 + lift * .3),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x2E000000),
                            blurRadius: 18 + lift * 2,
                            offset: Offset(0, 6 + lift * .4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14 + lift * .3),
                        child: RawImage(
                          image: snapshot,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
