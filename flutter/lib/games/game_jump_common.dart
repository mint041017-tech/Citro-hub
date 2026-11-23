import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'game_identity.dart';
import 'game_ui.dart';

// ---------------------------------------------------------------------------
// 帧心跳（Ticker 驱动 + 节流时间戳 + 画布重绘计数器）
//
// 跳一跳 / 淘气小球两边的 Ticker 绑定、就绪标记、上一帧时间戳、重绘计数器
// 与重启/停表流程逐字相同；唯一差异是单帧物理步长上限（50ms / 60ms），
// 属于各自的手感调参，由 [GameFrameTicker.dtMs] 的调用方传入，这里不统一。
// ---------------------------------------------------------------------------

/// 小游戏共用的帧心跳宿主。
class GameFrameTicker {
  GameFrameTicker();

  late final Ticker ticker;
  bool ready = false;
  Duration lastElapsed = Duration.zero;
  final ValueNotifier<int> frame = ValueNotifier<int>(0);

  /// 绑定帧回调并启动（对应 State.initState 里的 `createTicker(..)..start()`）。
  void bind(TickerProvider provider, TickerCallback onTick) {
    ticker = provider.createTicker(onTick)..start();
    ready = true;
  }

  /// 距上一帧的毫秒数；[maxMs] 为本游戏允许的单帧步长上限。
  double dtMs(Duration elapsed, double maxMs) {
    var dt = (elapsed - lastElapsed).inMicroseconds / 1000.0;
    lastElapsed = elapsed;
    if (dt <= 0) dt = 16;
    return dt.clamp(1.0, maxMs);
  }

  /// 停表后清空节流时间戳，下次 start 从 0 起算。
  void resetElapsed() => lastElapsed = Duration.zero;

  /// 心跳已就绪且当前未运行时重启（新游戏从 ready 态恢复）。
  void restartIfNeeded() {
    if (ready && !ticker.isActive) {
      resetElapsed();
      ticker.start();
    }
  }

  void dispose() {
    ticker.dispose();
    frame.dispose();
  }
}

// ---------------------------------------------------------------------------
// 提示胶囊（棋盘外常驻：纸底 + 身份色描边 + 前置圆点）
// 文案与单行省略策略由各游戏传入，结构与样式两边一致。
// ---------------------------------------------------------------------------

class GameHintPill extends StatelessWidget {
  const GameHintPill({
    super.key,
    required this.identity,
    required this.active,
    required this.text,
    this.height = 34,
    this.overflow = TextOverflow.ellipsis,
  });

  final GameIdentity identity;
  final bool active;
  final String text;
  final double height;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: identity.primary.withAlpha(70)),
        borderRadius: BorderRadius.circular(CitroColors.radii.button),
        boxShadow: CitroColors.shadows.card(c),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? identity.primary : identity.deep.withAlpha(120),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              overflow: overflow,
              style: context.body(
                size: CitroType.caption,
                weight: CitroType.strong,
                color: c.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 结算遮罩壳（半透纸底 + 身份色描边 + 居中标题 / 正文 / 重试按钮）
// 标题与正文 spans 由各游戏按自身文案构造。
// ---------------------------------------------------------------------------

/// 遮罩正文里高亮数字的墨色：暗色主题用 onDark()，否则 primaryInk。
Color gameEndOverlayInk(BuildContext context, GameIdentity identity) =>
    context.c.dark ? identity.onDark() : identity.primaryInk;

class GameEndOverlay extends StatelessWidget {
  const GameEndOverlay({
    super.key,
    required this.title,
    required this.body,
    required this.identity,
    this.onRetry,
  });

  final String title;
  final List<TextSpan> body;
  final GameIdentity identity;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final id = identity;
    return Container(
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.96),
        border: Border.all(color: id.primary.withAlpha(70)),
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: context.heading(size: CitroType.subtitle, color: c.ink),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text.rich(
              TextSpan(children: body),
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: c.ink2),
            ),
          ),
          const SizedBox(height: 10),
          GameActionButton(label: '再来一局', primary: true, onTap: onRetry),
        ],
      ),
    );
  }
}
