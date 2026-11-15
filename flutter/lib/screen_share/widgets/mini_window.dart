import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/paper.dart';

/// 应用内小窗：可拖动的悬浮画面，点一下放大回房间。
///
/// 初始位置离底边 108px，刚好停在悬浮控制条上方；旧版停在 96px，
/// 会被控制条压住一半。
///
/// 为什么先做应用内的小窗，而不是系统画中画：
///   - 系统 PiP 只有 Android 有成熟路径（`simple_pip_mode`），iOS 要额外
///     配广播扩展，Windows 没有系统级 PiP；
///   - 应用内小窗四端行为一致，且能直接复用同一个 renderer，不需要把
///     画面搬到系统层再拿回来。
/// 系统 PiP 作为 Android 的加成项另外接。
class ShareMiniWindow extends StatefulWidget {
  const ShareMiniWindow({
    super.key,
    required this.renderer,
    required this.label,
    required this.onExpand,
    required this.onClose,
  });

  final RTCVideoRenderer renderer;
  final String label;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  State<ShareMiniWindow> createState() => _ShareMiniWindowState();
}

class _ShareMiniWindowState extends State<ShareMiniWindow> {
  Offset? _offset;
  static const double _width = 148;
  static const double _height = 88;

  void _onDrag(DragUpdateDetails details, BoxConstraints constraints) {
    final size = constraints.biggest;
    setState(() {
      final base = _offset ?? Offset(size.width - _width - 16, size.height - _height - 108);
      final next = base + details.delta;
      _offset = Offset(
        next.dx.clamp(0.0, math.max(0.0, size.width - _width)),
        next.dy.clamp(0.0, math.max(0.0, size.height - _height)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final left = _offset?.dx ?? size.width - _width - 16;
        final top = _offset?.dy ?? size.height - _height - 108;
        return Positioned(
          left: left,
          top: top,
          child: GestureDetector(
            onPanUpdate: (d) => _onDrag(d, constraints),
            onTap: widget.onExpand,
            child: Container(
              width: _width,
              height: _height,
              decoration: BoxDecoration(
                color: c.bg2,
                borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                border: Border.all(color: c.accent, width: 1.5),
                boxShadow: CitroColors.shadows.card(c),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RTCVideoView(
                    widget.renderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: const Color(0x8A000000),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.body(
                                size: CitroType.micro,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Pressable(
                            onTap: widget.onClose,
                            scale: 1,
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: AppIcon(AppIcons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
