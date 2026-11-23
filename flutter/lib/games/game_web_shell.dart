import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'game_ui.dart'
    show GameActionButton, GameIdentityScope, GameScorePill;

/// WebView 小游戏（极限刹车 / 咕噜果冻铺）的平台无关壳层。
///
/// 这里只放两端共用的概念：加载动画、启动失败提示、宽高比/尺寸折算、
/// 桥接消息里的纯成绩解析、HUD 状态机。平台边界（InAppWebView 控制器/设置/
/// JS handler、dart:js_interop + ui_web 的 iframe 注册/销毁）仍留在各自
/// `*_native.dart` / `*_web.dart` 里，本文件不引用任何一端的平台控件。

// ---------------------------------------------------------------------------
// 启动状态（加载 / 失败 / 重试复位）
// ---------------------------------------------------------------------------

/// 页面启动状态机的平台无关部分：是否加载中、是否启动失败、失败文案。
///
/// 各端仍自行决定「重试」具体重载什么（重拼内嵌 HTML / 重新 loadData /
/// 刷新 iframe），这里只负责状态字段与状态迁移。
mixin WebBootState<T extends StatefulWidget> on State<T> {
  bool _loading = true;
  String? _bootError;

  bool get loading => _loading;
  String? get bootError => _bootError;

  /// 资源/页面就绪，撤掉加载与错误态。
  void markBootReady() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _bootError = null;
    });
  }

  /// 启动失败：撤掉加载动画，记录错误文案。
  /// [keepLoading] 为 true 时保留加载态（错误浮层优先于加载动画展示）。
  void markBootFailed(Object error, {bool keepLoading = false}) {
    if (!mounted) return;
    setState(() {
      _bootError = '$error';
      if (!keepLoading) _loading = false;
    });
  }

  /// 重试前复位：清错误、回到加载态。
  void resetBoot() {
    if (!mounted) return;
    setState(() {
      _bootError = null;
      _loading = true;
    });
  }
}

// ---------------------------------------------------------------------------
// 加载动画
// ---------------------------------------------------------------------------

/// 身份色线性进度加载屏（Web iframe 刹车版 + 果冻铺两端共用）。
///
/// 浅色端底 + 主色细进度条 + 深色端阶段文案，替代白底转圈。
class GameWebLinearBoot extends StatelessWidget {
  const GameWebLinearBoot({
    super.key,
    required this.label,
    required this.subtitle,
  });

  /// 主阶段文案。
  final String label;

  /// 副标（游戏名 · 玩法意象）。
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final identity = GameIdentityScope.of(context);
    return ColoredBox(
      color: identity.soft,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 132,
              height: 4,
              child: LinearProgressIndicator(
                minHeight: 4,
                color: identity.primary,
                backgroundColor: identity.primary.withAlpha(40),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: context.body(
                size: CitroType.body,
                weight: CitroType.strong,
                color: identity.deep,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: context.body(
                size: CitroType.small,
                color: identity.primaryInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 速度表意象的旋转进度弧 painter（刹车内嵌版加载动画）。
class GameWebArcPainter extends CustomPainter {
  const GameWebArcPainter({
    required this.t,
    required this.base,
    required this.arc,
    required this.tick,
  });

  final double t;
  final Color base;
  final Color arc;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: r);

    // 底线圆环
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = base,
    );

    // 旋转的进度弧（圆头）
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t * 6.28318);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(
      rect,
      -1.5708,
      3.14159,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..color = arc,
    );
    canvas.restore();

    // 刻度点（速度表意象）
    for (var i = 0; i < 12; i++) {
      final a = i * 0.5236 - 1.5708;
      final p1 = center + Offset(
        math.cos(a) * (r - 9),
        math.sin(a) * (r - 9),
      );
      final p2 = center + Offset(
        math.cos(a) * (r - 5),
        math.sin(a) * (r - 5),
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..strokeWidth = 1.4
          ..color = tick.withValues(
            alpha: .35 + .65 * (((i / 12) + t) % 1),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant GameWebArcPainter old) =>
      old.t != t || old.base != base || old.arc != arc || old.tick != tick;
}

/// 身份色旋转弧线加载屏（刹车内嵌版）：旋转主色弧 + 速度表图标 + 阶段文案。
class GameWebArcBoot extends StatefulWidget {
  const GameWebArcBoot({
    super.key,
    required this.stage,
    required this.labels,
    required this.subtitle,
    this.icon = Icons.speed_rounded,
  });

  /// 0 = 准备资源，1 = 初始化三维场景，2 = 就绪。
  final int stage;

  /// 按阶段索引取主文案；越界回落到最后一条。
  final List<String> labels;

  /// 副标（游戏名 · 玩法意象）。
  final String subtitle;

  final IconData icon;

  @override
  State<GameWebArcBoot> createState() => _GameWebArcBootState();
}

class _GameWebArcBootState extends State<GameWebArcBoot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _label {
    final i = widget.stage.clamp(0, widget.labels.length - 1);
    return widget.labels[i];
  }

  @override
  Widget build(BuildContext context) {
    final identity = GameIdentityScope.of(context);
    return ColoredBox(
      color: identity.soft,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 112,
              height: 112,
              child: AnimatedBuilder(
                animation: _c,
                builder: (ctx, _) => CustomPaint(
                  painter: GameWebArcPainter(
                    t: _c.value,
                    base: identity.deep.withAlpha(70),
                    arc: identity.primary,
                    tick: identity.deep,
                  ),
                  child: Center(
                    child: Opacity(
                      opacity:
                          0.75 + 0.25 * (1 - (_c.value - 0.5).abs() * 2),
                      child: Icon(
                        widget.icon,
                        size: 36,
                        color: identity.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _label,
              style: context.body(
                size: CitroType.body,
                weight: CitroType.strong,
                color: identity.deep,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.subtitle,
              style: context.body(
                size: CitroType.small,
                color: identity.primaryInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 启动失败提示
// ---------------------------------------------------------------------------

/// 启动失败屏：身份色浅底 + 标题 + 错误文案 + 重试按钮。
///
/// 两端文案、留白与行数约束由调用方传入，观感与原版保持一致。
class GameWebBootError extends StatelessWidget {
  const GameWebBootError({
    super.key,
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    this.padding = const EdgeInsets.all(24),
    this.messageMaxLines,
    this.titleGap = 6,
    this.buttonGap = 14,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  /// 整块内容的内边距。
  final EdgeInsetsGeometry padding;

  /// 错误文案最大行数；null 表示不限行。
  final int? messageMaxLines;

  /// 标题与错误文案间距。
  final double titleGap;

  /// 错误文案与重试按钮间距。
  final double buttonGap;

  @override
  Widget build(BuildContext context) {
    final identity = GameIdentityScope.of(context);
    return ColoredBox(
      color: identity.soft,
      child: Center(
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: context.heading(
                  size: CitroType.titleLg,
                  color: identity.deep,
                ),
              ),
              SizedBox(height: titleGap),
              Text(
                message,
                maxLines: messageMaxLines,
                overflow: messageMaxLines == null
                    ? TextOverflow.clip
                    : TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.body(
                  size: CitroType.caption,
                  color: identity.primaryInk,
                  height: 1.5,
                ),
              ),
              SizedBox(height: buttonGap),
              GameActionButton(
                label: retryLabel,
                primary: true,
                onTap: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 棋盘视口尺寸折算（极限刹车）
// ---------------------------------------------------------------------------

/// 刹车棋盘（内嵌网页视口）按内容区约束推导。
///
/// 内容区宽度有界、高度无界，所以高度按宽度折算：窄内容区（手机）给竖屏
/// 比例，宽内容区（桌面横屏）给接近 16:10 的驾驶视角。两个比例在阈值附近
/// 平滑过渡，避免内容宽跨过阈值时高度突变。
class BrakeBoardMetrics {
  const BrakeBoardMetrics._();

  static const double maxWidth = 900;
  static const double maxHeight = 640;
  static const double compactRatio = 1.35;
  static const double wideRatio = 0.62;
  static const double compactMaxWidth = 560;

  /// 比例过渡带半宽：在阈值前后各 90px 内从竖屏比例平滑插值到宽屏比例。
  static const double ratioBlend = 90;

  static Size boardSize(double maxWidth) {
    final w = math.min(maxWidth, BrakeBoardMetrics.maxWidth);
    // 阈值附近用 smoothstep 插值比例，高度随宽度连续变化（559 与 560 同高）。
    final t = ((w - BrakeBoardMetrics.compactMaxWidth) /
            BrakeBoardMetrics.ratioBlend)
        .clamp(0.0, 1.0)
        .toDouble();
    final ratio = BrakeBoardMetrics.compactRatio +
        (BrakeBoardMetrics.wideRatio - BrakeBoardMetrics.compactRatio) *
            (t * t * (3 - 2 * t));
    final h = (w * ratio).clamp(240.0, BrakeBoardMetrics.maxHeight).toDouble();
    return Size(w, h);
  }
}

// ---------------------------------------------------------------------------
// 刹车：桥接消息里的纯成绩 / 榜单解析（平台无关，传输层各自接 handler）
// ---------------------------------------------------------------------------

/// 刹车成绩上报：解析 v0 / stopTime / score，失败/空分流后落库。
///
/// 返回结构同时兼容原生 JS handler 与 iframe postMessage 的回包。
Future<Map<String, Object?>> submitBrakeScore(
  Map<String, Object?> body,
) async {
  final v0 = (body['v0'] as num?)?.toDouble() ?? 0;
  final stop = (body['stopTime'] as num?)?.toDouble() ?? 0;
  final reported = (body['score'] as num?)?.toInt() ?? 0;
  final computed = stop > 0 ? (v0 * v0 / stop).round() : 0;
  final score = reported > 0 ? reported : computed;
  if (body['failed'] == true) {
    await AppState.instance.noteGameRound();
    return {'ok': false, 'failed': true};
  }
  if (score <= 0) return {'ok': false, 'err': 'empty score'};
  final res = await AppState.instance.submitScore('brake', score);
  return {
    'ok': res['ok'] != false,
    'score': score,
    'best': res['best'] ?? score,
    'rank': res['rank'] ?? 0,
  };
}

/// 刹车榜单原始响应 → 页面需要的 entries 结构。
List<Map<String, Object?>> brakeBoardEntries(dynamic raw, int limit) {
  final out = <Map<String, Object?>>[];
  if (raw is List) {
    for (final e in raw.take(limit)) {
      if (e is! Map) continue;
      out.add({
        'nickname': '${e['name'] ?? e['nickname'] ?? '游客'}',
        'score':
            ((e['score'] ?? e['best'] ?? e['value'] ?? 0) as num).toInt(),
        'v0': e['v0'] ?? 0,
        'stopTime': e['stopTime'] ?? 0,
      });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// 果冻铺：HUD 状态机（原生内嵌 WebView 与 iframe 两端共用）
// ---------------------------------------------------------------------------

/// 果冻铺 WebView 两端共享的展示状态：分数 / 最高分 / 接下来队列 / 正在玩
/// 进度 / 提交去重。只持有展示状态与纯解析逻辑，不触碰任何平台控件。
mixin LiquidWebShellState<T extends StatefulWidget> on State<T> {
  bool _submitting = false;
  int _score = 0;
  int _best = 0;
  List<int> _next = const [];
  final ValueNotifier<String> _liveProgress = ValueNotifier('开局准备中');

  int get score => _score;
  int get best => _best;
  List<int> get next => _next;
  ValueNotifier<String> get liveProgress => _liveProgress;

  static int asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static bool sameInts(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 解析实时状态（progress / score / best / next）并刷新 HUD；
  /// 返回展示数据是否发生变化。
  bool applyLiveState(Map<dynamic, dynamic> data) {
    final progress = '${data['progress'] ?? ''}'.trim();
    if (progress.isNotEmpty && _liveProgress.value != progress) {
      _liveProgress.value = progress;
    }
    final s = asInt(data['score']);
    final b = asInt(data['best']);
    final rawNext = data['next'];
    final n = rawNext is List
        ? rawNext.map(asInt).where((v) => v > 0).toList(growable: false)
        : const <int>[];
    final changed = s != _score || b != _best || !sameInts(n, _next);
    if (changed && mounted) {
      setState(() {
        _score = s;
        _best = b;
        _next = n;
      });
    }
    return changed;
  }

  /// 提交成绩（带去重），成功后弹 toast。回包结构兼容两端传输层。
  Future<Map<String, Object?>> submitLiquidScore(int value) async {
    if (value <= 0) {
      unawaited(AppState.instance.noteGameRound());
      return {'ok': false};
    }
    if (_submitting) return {'ok': false};
    _submitting = true;
    try {
      final res = await AppState.instance.submitScore('liquid', value);
      if (mounted) {
        final rank = res['rank'];
        AppToast.show(
          context,
          rank is num && rank > 0
              ? '已计入排行榜 · 第 $rank 名'
              : '成绩已记录',
        );
      }
      return {'ok': res['ok'] != false, 'rank': res['rank'] ?? 0};
    } finally {
      _submitting = false;
    }
  }

  /// 标准三枚 HUD pill（分数 / 最高分 / 接下来）。
  List<Widget> liquidPills() => liquidPillsFor(
        score: '$_score',
        best: '${math.max(_best, _score)}',
        next: _next.isEmpty ? '—' : _next.join('·'),
      );

  /// 任意已格式化的展示值 → 同一组标准 pill（原生玩法页也复用这一组壳层）。
  static List<Widget> liquidPillsFor({
    required String score,
    required String best,
    required String next,
  }) {
    return [
      GameScorePill(label: '分数', value: score),
      GameScorePill(label: '最高分', value: best),
      GameScorePill(label: '接下来', value: next, minWidth: 96),
    ];
  }

  /// 在页面 dispose 里调用，释放进度监听。
  void disposeLiveProgress() => _liveProgress.dispose();
}
