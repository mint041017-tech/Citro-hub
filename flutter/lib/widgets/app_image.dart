import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/image_store.dart';

/// 带本地磁盘缓存的网络图片。
///
/// 原生端（Android / iOS / Windows）首次下载后落盘，之后启动直接读文件；
/// Web 端不额外存一份，直接走浏览器 HTTP 缓存。
class AppImage extends StatefulWidget {
  const AppImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.fadeDuration = const Duration(milliseconds: 200),
    this.placeholder,
    this.errorBuilder,
  });

  final String url;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final int? cacheWidth;
  final Duration fadeDuration;
  final Widget? placeholder;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// 预热一批图片：磁盘/网络 + 解码一次，列表打开时不再逐张闪白。
  static Future<void> precache(
    BuildContext context,
    Iterable<String> urls, {
    int width = 540,
  }) async {
    final list = urls.where((u) => u.isNotEmpty).toList();
    if (list.isEmpty) return;
    if (kIsWeb) {
      for (final url in list) {
        if (!context.mounted) return;
        try {
          await precacheImage(
            ResizeImage(NetworkImage(url), width: width),
            context,
          );
        } catch (_) {}
      }
      return;
    }
    // 先并发取盘/取网，再逐张解码，避免串行下载把首图拖慢。
    final bytes = await Future.wait(list.map(ImageStore.load));
    for (var i = 0; i < list.length; i++) {
      if (!context.mounted) return;
      final data = bytes[i];
      if (data == null) continue;
      try {
        await precacheImage(
          ResizeImage(MemoryImage(data), width: width),
          context,
        );
      } catch (_) {}
    }
  }

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _future = ImageStore.load(widget.url);
  }

  @override
  void didUpdateWidget(covariant AppImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && !kIsWeb) {
      _future = ImageStore.load(widget.url);
    }
  }

  Widget _network() {
    return Image.network(
      widget.url,
      fit: widget.fit,
      alignment: widget.alignment,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
      frameBuilder: _frame,
      errorBuilder: widget.errorBuilder ?? (_, _, _) => const SizedBox.shrink(),
    );
  }

  Widget _frame(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: widget.fadeDuration,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) {
      return widget.errorBuilder?.call(context, 'empty', null) ??
          const SizedBox.shrink();
    }
    if (kIsWeb) return _network();
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes != null) {
          return Image.memory(
            bytes,
            fit: widget.fit,
            alignment: widget.alignment,
            cacheWidth: widget.cacheWidth,
            gaplessPlayback: true,
            frameBuilder: _frame,
            errorBuilder:
                widget.errorBuilder ?? (_, _, _) => const SizedBox.shrink(),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return widget.placeholder ?? const SizedBox.shrink();
        }
        // 本地缓存失败时退回 Flutter 自带网络图，至少还有一次重试机会。
        return _network();
      },
    );
  }
}
