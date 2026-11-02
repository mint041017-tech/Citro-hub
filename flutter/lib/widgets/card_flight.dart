import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// 没有共享元素可用的卡片：用 Overlay 做一个"悬浮替身"。
///
/// 打开阶段：快照从卡片位置抬起并快速淡出，在面板完全展开前就撤掉，
/// 不会出现"详情已经打开、卡片还在慢慢消失"的尾段。
/// 关闭阶段：重新插入替身，从面板方向淡入并缩回卡片原矩形——从哪来回哪去。
class CitroCardFlight {
  CitroCardFlight._();

  /// 抬起替身只负责"交棒"，时长要明显短于面板展开。
  static const Duration _handOff = Duration(milliseconds: 140);
  static const Duration _returnHome = Duration(milliseconds: 240);

  /// 卡片在屏幕上的矩形（由卡片自己在 onTap 里计算）。
  static Rect rectOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return Rect.zero;
  }

  /// 截取卡片自身的那一块：外层 RepaintBoundary 可能包着一整行卡片
  /// （例如首页天气 + 食谱），必须按卡片矩形裁切，否则抬起的是整行。
  static Future<ui.Image?> snapshotOf(
    BuildContext context,
    Rect cardRect,
  ) async {
    RenderObject? node = context.findRenderObject();
    while (node != null && node is! RenderRepaintBoundary) {
      node = node.parent;
    }
    if (node is! RenderRepaintBoundary) return null;
    RenderRepaintBoundary boundary = node;
    const ratio = 2.0;
    try {
      final full = await boundary.toImage(pixelRatio: ratio);
      final origin = boundary.localToGlobal(Offset.zero);
      final local = Rect.fromLTWH(
        (cardRect.left - origin.dx) * ratio,
        (cardRect.top - origin.dy) * ratio,
        cardRect.width * ratio,
        cardRect.height * ratio,
      );
      final clipped = local.intersect(
        Rect.fromLTWH(0, 0, full.width.toDouble(), full.height.toDouble()),
      );
      if (clipped.isEmpty || clipped.width < 2 || clipped.height < 2) {
        full.dispose();
        return null;
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        full,
        clipped,
        Rect.fromLTWH(0, 0, clipped.width, clipped.height),
        Paint(),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        clipped.width.round(),
        clipped.height.round(),
      );
      picture.dispose();
      full.dispose();
      return image;
    } catch (_) {
      return null;
    }
  }

  static Widget _standIn({
    required Animation<double> animation,
    required Rect rect,
    required ui.Image? image,
    required Color fallback,
  }) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = CitroMotion.easeInOut.transform(animation.value);
          final r = Rect.lerp(rect, rect.translate(0, -18), t)!;
          final opacity = (1 - t).clamp(0.0, 1.0);
          final radius = ui.lerpDouble(14, 18, t) ?? 14;
          return Stack(
            children: [
              Positioned.fromRect(
                rect: r.inflate(6 * t),
                child: Opacity(
                  opacity: opacity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x33000000),
                          blurRadius: 26 * t + 8,
                          offset: Offset(0, 8 * t + 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: image != null
                          ? RawImage(image: image, fit: BoxFit.fill)
                          : ColoredBox(
                              color: fallback,
                              child: const SizedBox.expand(),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 播放"抬起 → 交棒 → 返回"的替身动画。面板/弹窗结束时自动返回。
  static Future<void> run(
    BuildContext context, {
    required Future<void> Function() open,
    Rect? source,
  }) async {
    final rect = source ?? rectOf(context);
    if (rect.isEmpty || CitroMotion.reduced(context)) {
      await open();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final image = await snapshotOf(context, rect);
    final theme = context.c;

    final vsync = _TickerProvider();

    // 1. 抬起：只负责交棒，140ms 内淡出，避免详情出现后还残留卡片消失的尾段。
    final lift = AnimationController(vsync: vsync, duration: _handOff);
    final entry = OverlayEntry(
      builder: (_) => _standIn(
        animation: lift,
        rect: rect,
        image: image,
        fallback: theme.surface2,
      ),
    );
    overlay.insert(entry);
    final lifting = lift.forward();
    final opened = open();
    // 面板展开需要 ~300ms，替身在 150ms 时撤掉，绝不会在详情打开后继续可见。
    await Future.any([
      lifting,
      Future<void>.delayed(const Duration(milliseconds: 150)),
    ]);
    entry.remove();

    // 2. 关闭后返回：从"抬手位"淡入，缩回卡片原矩形。
    await opened;
    final back = AnimationController(
      vsync: vsync,
      duration: _returnHome,
      value: 1,
    );
    final backEntry = OverlayEntry(
      builder: (_) => _standIn(
        animation: back,
        rect: rect,
        image: image,
        fallback: theme.surface2,
      ),
    );
    overlay.insert(backEntry);
    await back.reverse();
    backEntry.remove();
    back.dispose();
    lift.dispose();
    vsync.disposeTicker();
    // 最后一帧可能还在绘制替身，延后释放，避免 clone 到已 dispose 的图片。
    if (image != null) {
      Future<void>.delayed(const Duration(milliseconds: 150), image.dispose);
    }
  }
}

/// 脱离 widget 树的 TickerProvider：OverlayEntry 里没有 State 可用。
class _TickerProvider implements TickerProvider {
  Ticker? _ticker;

  @override
  Ticker createTicker(TickerCallback onTick) {
    _ticker = Ticker(onTick);
    return _ticker!;
  }

  void disposeTicker() {
    _ticker?.dispose();
    _ticker = null;
  }
}
