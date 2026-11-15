import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/paper.dart';

/// 画面显示区：把一路 renderer 铺满，并在没有画面时给出占位说明。
///
/// [highlighted] 用于主持人自己正在共享时描红边 —— 误共享是这类功能
/// 最容易出的安全事故，视觉上必须一直能看出来。
class RemoteView extends StatelessWidget {
  const RemoteView({
    super.key,
    required this.renderer,
    required this.placeholder,
    this.highlighted = false,
    this.live = false,
    this.label,
    this.sublabel,
    this.onTap,
  });

  /// 为 null 时只显示 [placeholder]，不创建 renderer。
  ///
  /// 「等待共享」这种状态还没有任何 track，没必要为了占位去初始化一个
  /// 真 renderer（它会去申请解码器）。
  final RTCVideoRenderer? renderer;

  /// 没有画面时显示的居中文案（例如「等待主持人开始共享」）。
  final String placeholder;

  final bool highlighted;

  /// 正在放映别人的画面：右上角挂「正在一起看」角标。
  final bool live;

  /// 左上角的小标签，比如发布者名字。
  final String? label;
  final String? sublabel;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = renderer;
    return Pressable(
      onTap: onTap,
      scale: 1,
      child: Container(
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: BorderRadius.circular(CitroColors.radii.card),
          border: Border.all(
            color: highlighted ? c.danger : c.line,
            width: highlighted ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (r != null)
              RTCVideoView(
                r,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                // 首帧未到时 placeholderBuilder 会显示（renderer 已挂流但
                // 视频还没渲染出来）——这正是「加载动画」该出现的状态。
                placeholderBuilder: (_) =>
                    _Placeholder(text: placeholder, loading: true),
              )
            else
              _Placeholder(text: placeholder),
            if (label != null)
              Positioned(
                left: AppSpacing.x2,
                top: AppSpacing.x2,
                child: _Tag(text: label!, sublabel: sublabel),
              ),
            if (highlighted || live)
              Positioned(
                right: AppSpacing.x2,
                top: AppSpacing.x2,
                child: const _LiveTag(),
              ),
          ],
        ),
      ),
    );
  }
}

/// 占位/加载态。静态文案（等主持人开播）与呼吸圆点（首帧加载中）共用。
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text, this.loading = false});

  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              const _LoadingDots(),
              const SizedBox(height: AppSpacing.x1),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: c.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// 三颗呼吸圆点：上下浮动 + 透明度呼吸，相位错开。
/// 自绘 + 单个 AnimationController 带三个相位，比三个独立动画便宜。
class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget dot(int i) {
      // 三颗点相位差 0.18s（与 Web 端 .slot-loading 的 delay 一致）。
      final t = Curves.easeInOut.transform(
        ((_c.value - i * 0.16) % 1.0).abs() * 2,
      );
      final lift = (1.0 - t).clamp(0.0, 1.0);
      return Opacity(
        opacity: 0.45 + 0.55 * lift,
        child: Transform.translate(
          offset: Offset(0, -7 * lift),
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: c.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) dot(i),
      ]
          .map(
            (w) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.5),
              child: w,
            ),
          )
          .toList(),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.sublabel});

  final String text;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x9B000000),
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: context.body(
              size: CitroType.meta,
              weight: CitroType.medium,
              color: Colors.white,
            ),
          ),
          if (sublabel != null)
            Text(
              sublabel!,
              style: context.body(size: CitroType.micro, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}

/// 右上角「正在一起看」角标。
class _LiveTag extends StatelessWidget {
  const _LiveTag();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: c.onAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '正在一起看',
            style: context.body(
              size: CitroType.micro,
              weight: CitroType.medium,
              color: c.onAccent,
            ),
          ),
        ],
      ),
    );
  }
}
