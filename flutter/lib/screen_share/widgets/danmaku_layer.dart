import 'dart:async';

import 'package:flutter/material.dart';

import '../room_models.dart';
import '../screen_share_controller.dart';

/// 弹幕文字样式：纯白字 + 黑色柔影，压在任何画面上都可读；不带气泡底。
/// 测量（[_DanmakuLayerState._spawn]）和渲染（[_DanmakuBubble]）必须共用
/// 这一份，飞行宽度才和实际画出来的宽度一致。
const TextStyle _danmakuStyle = TextStyle(
  color: Colors.white,
  fontSize: 14,
  fontWeight: FontWeight.w600,
  shadows: <Shadow>[Shadow(blurRadius: 4, color: Colors.black54)],
);

/// 舞台上的弹幕层。
///
/// 聊天消息除了进聊天面板，还会从右向左从画面上飘过 —— 房间页不强制
/// 打开面板，观众也能看到别人说了什么。只播「进房之后新到」的消息，
/// 进房时的历史记录不补播，否则一进来会糊满整块屏幕。
///
/// 这一层永远不吃指针事件，底下的播放器 / 切换条不受影响。
class DanmakuLayer extends StatefulWidget {
  const DanmakuLayer({super.key, required this.controller});

  final ScreenShareController controller;

  @override
  State<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _Flight {
  _Flight({
    required this.animation,
    required this.lane,
    required this.width,
    required this.message,
  });

  final AnimationController animation;
  final int lane;
  final double width;
  final ChatMessage message;
}

class _DanmakuLayerState extends State<DanmakuLayer>
    with TickerProviderStateMixin {
  final Set<String> _seen = <String>{};
  final List<_Flight> _flights = <_Flight>[];
  int _laneCursor = 0;
  int _laneCount = 4;
  double _layerWidth = 600;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    // 历史消息只记为已读，不生成弹幕。
    for (final m in widget.controller.chat) {
      _seen.add(_key(m));
    }
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    for (final f in _flights) {
      f.animation.dispose();
    }
    _flights.clear();
    super.dispose();
  }

  String _key(ChatMessage m) =>
      m.id.isNotEmpty ? m.id : '${m.uid}|${m.at}|${m.text}';

  void _onControllerChanged() {
    if (_scheduled) return;
    _scheduled = true;
    // 不能用 addPostFrameCallback：它不会主动排帧，聊天事件如果是这一帧
    // 唯一的状态变化，下一帧就永远不会来（测试里直接卡死，线上则要等
    // 别的原因触发重绘才补播弹幕）。microtask 里 setState 能立刻排下一帧，
    // 同一批通知也只会合并成一次。
    scheduleMicrotask(() {
      _scheduled = false;
      if (mounted) _drain();
    });
  }

  void _drain() {
    var added = false;
    for (final m in widget.controller.chat) {
      if (!_seen.add(_key(m))) continue;
      if (m.text.trim().isEmpty) continue;
      _spawn(m);
      added = true;
    }
    if (added) setState(() {});
  }

  void _spawn(ChatMessage m) {
    final span = TextSpan(
      children: <TextSpan>[
        TextSpan(text: '${m.name}：', style: _danmakuStyle),
        TextSpan(text: m.text, style: _danmakuStyle),
      ],
    );
    final painter = TextPainter(
      text: span,
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: 516);

    final animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 14000),
    );
    final flight = _Flight(
      animation: animation,
      lane: _laneCursor++ % _laneCount,
      width: painter.width + 26,
      message: m,
    );
    _flights.add(flight);
    animation.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() => _flights.remove(flight));
      animation.dispose();
    });
    animation.forward();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _layerWidth = constraints.maxWidth;
        _laneCount = (constraints.maxHeight / 42).floor().clamp(2, 6);
        return ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              for (final f in _flights)
                Positioned(
                  left: 0,
                  top: 14 + f.lane * 40,
                  child: AnimatedBuilder(
                    animation: f.animation,
                    builder: (context, child) {
                      final x =
                          _layerWidth -
                          (_layerWidth + f.width + 16) * f.animation.value;
                      return Transform.translate(
                        offset: Offset(x, 0),
                        child: child,
                      );
                    },
                    child: _DanmakuBubble(message: f.message),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DanmakuBubble extends StatelessWidget {
  const _DanmakuBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: <TextSpan>[
          TextSpan(text: '${message.name}：', style: _danmakuStyle),
          TextSpan(text: message.text, style: _danmakuStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
