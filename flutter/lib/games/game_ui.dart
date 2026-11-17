// 游戏页公共 UI —— 14 个游戏共用的一套舞台。
//
// 版式（竖屏，从上到下）：
//   浮动顶栏    返回圆钮 · 游戏名（带身份色标记）· 排行榜圆钮
//   HUD 条      分数 / 计时 / 最佳，棋盘正上方，一眼可读
//   舞台        棋盘居中，占掉剩余高度；页面底色带一层游戏身份色的微光
//   操作行      新游戏 / 撤销 / 重开，居中成排，主按钮用身份色
//   正在玩      底部横条，身份色小圆点
//
// 手机竖屏（宽 ≤ 600 且竖放）不同：游戏名左靠，只读读数收进顶栏右侧，
// 棋盘上方的 HUD 卡整块消失，把高度让给棋盘。宽度不够（长标题 / 大字号 /
// 多位数）时自动折成标题下方的一行小字，仍不挤占游戏名。平板、桌面和横屏
// 维持上面的老版式。
//
// 颜色只来自 [GameIdentity]（每个游戏固定），不读 `CitroColors.accent`：
// 主题在亮 / 暗之间切换时，游戏页的强调色不变，玩家靠颜色就能认出游戏。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/play_log.dart';
import '../services/refresh_rate.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/desktop_shell.dart';
import '../widgets/paper.dart';
import '../widgets/shared_element.dart';
import 'game_common.dart'
    show GameTabletRankRail, sameLiveList, showGameAccount, showGameLeaderboard;
import 'game_identity.dart';

/// 游戏身份作用域。
///
/// [GameScaffold] 在页顶注入，页内所有共享组件（按钮、HUD、分段器、正在玩）
/// 直接从这里取身份色，不必一层层往下传。
class GameIdentityScope extends InheritedWidget {
  const GameIdentityScope({
    super.key,
    required this.identity,
    required super.child,
  });

  final GameIdentity identity;

  /// 取当前游戏身份；页面外使用（弹层、测试）回落到中性身份，不会炸。
  static GameIdentity of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GameIdentityScope>();
    return scope?.identity ?? identityOf('');
  }

  @override
  bool updateShouldNotify(GameIdentityScope oldWidget) =>
      oldWidget.identity != identity;
}

/// 版式常量。
class GameMetrics {
  const GameMetrics._();
  static const double headHeight = 64;
  static const double sidePad = 14;
  static const double bodyBottom = 12;
  static const double hudGap = 9;
  static const double actionGap = 8;
  static const double hudPad = 10;

  /// 棋盘上方控件与棋盘之间的留白。
  static const double boardGap = 18;

  /// 内容区左右内边距（棋盘 / HUD / 操作行共用）。
  static const double gutter = 16;
}

/// 顶栏只读读数：手机竖屏把统计收进顶栏时用的数据。
///
/// 只承载文字，不是按钮；桌面 / 竖屏平板仍走 [GameScorePill] 卡片。
@immutable
class GameHudStat {
  const GameHudStat(this.label, this.value, {this.accent = false});

  final String label;
  final String value;

  /// true = 数值用游戏身份色（分数刷新时的 bump 语义）。
  final bool accent;
}

/// 游戏页图标（取自 index.html 游戏页内联 svg，lucide 路径）
class GameIcons {
  const GameIcons._();
  static const arrowLeft = '<path d="M19 12H5"/><path d="M12 19l-7-7 7-7"/>';
  static const undo =
      '<polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>';
  static const reset = '<path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/>';
  static const refresh =
      '<path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 3v6h-6"/>';
  static const trophy =
      '<path d="M8 21h8"/><path d="M12 17v4"/><path d="M6 3h12v6a6 6 0 0 1-12 0z"/><path d="M18 5h2a2 2 0 0 1 0 6h-2"/><path d="M6 5H4a2 2 0 0 0 0 6h2"/>';
  static const trophySimple =
      '<path d="M8 21h8"/><path d="M12 17v4"/><path d="M6 3h12v6a6 6 0 0 1-12 0z"/>';
  static const pause =
      '<rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/>';
  static const play = '<path d="M5 12l10-8v16z"/>';
  static const close = '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>';
  static const eraser =
      '<path d="M20 20H7L3 16a2 2 0 0 1 0-2.8l9-9a2 2 0 0 1 2.8 0l5 5a2 2 0 0 1 0 2.8L13 20"/><path d="M9 11l4 4"/>';
  static const pencil =
      '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>';
  static const lightbulb =
      '<path d="M9 18h6"/><path d="M10 22h4"/><path d="M12 2a7 7 0 0 0-4 12.7c.6.5 1 1.3 1 2.1V18h6v-1.2c0-.8.4-1.6 1-2.1A7 7 0 0 0 12 2Z"/>';
  static const trash =
      '<path d="M4 7h16"/><path d="M9 7v-3h6v3"/><path d="M6 7l1 13h10l1-13"/>';
  static const arrowUp = '<path d="M12 5l8 10H4z"/>';
  static const arrowLeftSolid = '<path d="M5 12l10-8v16z"/>';
  static const arrowRightSolid = '<path d="M19 12l-10-8v16z"/>';
  static const arrowDown = '<path d="M12 19l8-10H4z"/>';
  static const sparkle =
      '<path d="M12 3l1.9 5.8a2 2 0 0 0 1.3 1.3L21 12l-5.8 1.9a2 2 0 0 0-1.3 1.3L12 21l-1.9-5.8a2 2 0 0 0-1.3-1.3L3 12l5.8-1.9a2 2 0 0 0 1.3-1.3L12 3z"/>';
}

/// 游戏页内联图标（stroke 2，颜色随主题）
Widget gameIcon(String body, {double size = 14, Color? color}) =>
    AppIcon(strokeSvg(body, width: 2), size: size, color: color);

/// 键盘弹出/收起监听：视图 insets 变化（键盘升降）时回调。
class KeyboardObserver with WidgetsBindingObserver {
  KeyboardObserver(this.onMetricsChanged);

  final VoidCallback onMetricsChanged;

  @override
  void didChangeMetrics() => onMetricsChanged();
}

/// 游戏页骨架：身份色微光 + 浮动顶栏 + HUD + 舞台 + 操作 + 正在玩。
class GameScaffold extends StatefulWidget {
  const GameScaffold({
    super.key,
    required this.gameKey,
    required this.title,
    this.identity,
    this.above = const [],
    this.pills = const [],
    this.hudStats = const [],
    this.actions = const [],
    this.hud,
    this.board,
    this.boardGap = GameMetrics.boardGap,
    this.liveProgress,
    this.showLive = true,
    this.liveInScroll = false,
    this.titleSize,
    this.onBack,
    this.extraHeadActions = const [],
    this.rankGame,
    this.rankDifficulties = const [],
    this.rankInitial = '',
    this.rankAiSplit = false,
    this.showSidePanels = true,
    this.contentMaxWidth = 760,

    /// 键盘弹出时隐藏操作行（成语接龙 / 飞花令这类有文字录入的游戏用）：
    /// 键盘抬起时操作行会被顶到首屏外，用户反而点不到。
    this.hideActionsOnKeyboard = false,

    /// true = 操作行放进棋盘滚动内容末尾，不再钉在视口底部（仅手机竖屏）。
    ///
    /// 数独页内容最长，固定操作行会一直占住约一整行高度；放进滚动区后
    /// 页面底部只剩「正在玩」，下滑就能看到按钮。平板竖屏与桌面仍钉在
    /// 底部，版式不变。
    this.actionsInScroll = false,
  });

  final String gameKey;
  final String title;

  /// 覆盖游戏身份；缺省按 [gameKey] 查表。
  final GameIdentity? identity;

  /// 棋盘上方的整行控件（难度/模式分段器等），每项独占一行
  final List<Widget> above;
  final List<Widget> pills;

  /// 手机竖屏顶栏只读读数；为空时自动从 [pills] 里的 [GameScorePill] 提取。
  ///
  /// 淘气小球 / 跳一跳把 pill 包在自定义 [hud] 里，无法反推 label/value，
  /// 由页面显式再传一份；非手机布局仍用各自的 [hud] 原样画。
  final List<GameHudStat> hudStats;

  /// 棋盘下方的操作按钮（新游戏/撤销/排行榜等）
  final List<Widget> actions;

  /// 自定义 HUD 数据（仅只读数据，不含按钮）；非空时忽略 pills
  final Widget? hud;
  final Widget? board;
  final double boardGap;
  final ValueNotifier<String>? liveProgress;
  final bool showLive;

  /// true = live 条放进滚动内容（页面内容高于视口时整页滚动的行为）
  final bool liveInScroll;
  final double? titleSize;
  final VoidCallback? onBack;
  final List<Widget> extraHeadActions;

  /// iPad 横屏侧栏排行榜使用的游戏 key；缺省按 gameKey 推导。
  final String? rankGame;
  final List<(String, String)> rankDifficulties;
  final String rankInitial;
  final bool rankAiSplit;

  /// false = 横屏也不显示左右侧栏（模式选择等非对局页面）。
  final bool showSidePanels;

  /// 居中内容最大宽度；模式选择页可传更宽的值。
  final double contentMaxWidth;

  /// 键盘弹出时是否隐藏操作行。
  final bool hideActionsOnKeyboard;

  /// true = 操作行渲染在 [board] 之后的滚动内容里（仅手机竖屏生效）。
  final bool actionsInScroll;

  /// 测试时关掉轮询（golden 渲染用）
  static bool liveEnabled = true;

  @override
  State<GameScaffold> createState() => _GameScaffoldState();
}

class _GameScaffoldState extends State<GameScaffold> {
  Timer? _timer;
  List<dynamic> _live = const [];
  bool _leaving = false;
  DateTime? _entered;

  @override
  void initState() {
    super.initState();
    _entered = DateTime.now();
    RefreshRate.acquire();
    if (widget.showLive && GameScaffold.liveEnabled) _startLive();
  }

  Future<void> _startLive() async {
    await _tick();
    _timer ??= Timer.periodic(const Duration(seconds: 4), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_leaving) return;
    try {
      final state = AppState.instance;
      final j = await Api.gameLive(
        widget.gameKey,
        progress: widget.liveProgress?.value ?? '',
        name: state.loggedIn ? null : state.guestName,
        gid: state.loggedIn ? null : state.gid,
      );
      final list = (j['list'] as List?) ?? const [];
      if (mounted && !sameLiveList(_live, list)) {
        setState(() => _live = list);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    final entered = _entered;
    if (entered != null) PlayLog.add(DateTime.now().difference(entered));
    RefreshRate.release();
    _leaving = true;
    _timer?.cancel();
    if (widget.showLive && GameScaffold.liveEnabled) {
      try {
        final state = AppState.instance;
        Api.gameLive(
          widget.gameKey,
          leave: true,
          name: state.loggedIn ? null : state.guestName,
          gid: state.loggedIn ? null : state.gid,
        ).catchError((_) => <String, dynamic>{});
      } catch (_) {}
    }
    super.dispose();
  }

  GameIdentity get _identity => widget.identity ?? identityOf(widget.gameKey);

  /// 手机竖屏：宽度 ≤ 600 且更窄的一边竖放。
  ///
  /// 只影响顶栏和 HUD 的排布，不动棋盘逻辑；平板、桌面和横屏继续用
  /// 「标题居中 + 棋盘上方 HUD 卡」的老版式。
  bool _compactChrome(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return screen.width <= 600 && screen.height > screen.width;
  }

  /// 顶栏要显示的只读读数。
  ///
  /// 常规页面直接复用 `pills` 里的 [GameScorePill]；自定义 `hud` 的页面
  /// 由 [GameScaffold.hudStats] 显式给出。没有读数时返回空表，顶栏只留标题。
  List<GameHudStat> get _compactStats {
    if (widget.hudStats.isNotEmpty) return widget.hudStats;
    return [
      for (final pill in widget.pills)
        if (pill is GameScorePill)
          GameHudStat(pill.label, pill.value, accent: pill.bump),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final screen = MediaQuery.sizeOf(context);
    final landscape = screen.width > screen.height;
    final identity = _identity;
    // 身份色只以极低的透明度铺在页面顶部，像舞台顶光：
    // 主题切换时底色仍是主题的，游戏识别色靠它透出来。
    final body = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            identity.primary.withAlpha(c.dark ? 34 : 30),
            c.bg,
          ],
          stops: const [0, 0.62],
        ),
      ),
      child: landscape && widget.showSidePanels
          ? _landscapeBody(context)
          : _portraitBody(context),
    );
    return GameIdentityScope(
      identity: identity,
      child: Scaffold(backgroundColor: c.bg, body: body),
    );
  }

  Widget _portraitBody(BuildContext context) {
    final kbOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compact = _compactChrome(context);
    // 操作行随内容滚动只给手机竖屏；iPad 竖屏与桌面窗口保持钉底版式。
    final actionsInScroll = widget.actionsInScroll && compact;
    // 只有真的拿到了读数才收起棋盘上方的 HUD 卡；自定义 hud 又没给
    // hudStats 的页面保持原样，避免统计凭空消失。
    final compactHud = compact && _compactStats.isNotEmpty;
    // 顶栏参与布局，不再浮动：浮动时它的高度随系统状态栏变化，
    // 而内容区写死 top:64，真机状态栏一高就压到 HUD / 棋盘上。
    return Column(
      children: [
        _floatingHeader(context, compact: compact),
        Expanded(
          child: Column(
            children: [
              // HUD 收进顶栏后，模式条和棋盘之间留一口气，别贴在一起。
              _hudStrip(
                context,
                showHud: !compactHud,
                belowGap: compactHud ? 16 : 0,
              ),
              Expanded(child: _boardArea(context, actionsInScroll)),
              if (!actionsInScroll) _actionsStrip(context),
              if (widget.showLive && !kbOpen)
                SafeArea(top: false, child: GameLiveBar(list: _live)),
            ],
          ),
        ),
      ],
    );
  }

  /// actions 里的排行榜入口：竖屏挪到顶部圆形按钮，横屏左栏已有。
  GameActionButton? get _rankButton {
    for (final item in widget.actions) {
      if (item is GameActionButton && item.label.contains('排行')) return item;
      if (item is GameRankAction && item.child is GameActionButton) {
        final child = item.child as GameActionButton;
        if (child.label.contains('排行')) return child;
      }
    }
    return null;
  }

  /// 浮动顶栏：返回 + 标题（带身份色标记）+ 排行榜。
  ///
  /// 手机竖屏（[compact]）标题左靠，只读读数收进顶栏：宽度够就单行
  /// （标题左、读数右），不够自动折成标题下一行小字，不会挤到游戏名。
  Widget _floatingHeader(BuildContext context, {required bool compact}) {
    final c = context.c;
    final rank = _rankButton;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: GameMetrics.sidePad,
          // 右侧避开 Windows 悬浮窗控（其他端 inset 为 0）。
          right: GameMetrics.sidePad + CitroDesktopShell.windowControlsInset,
          top: 6,
          bottom: 6,
        ),
          child: Row(
            children: [
              _RoundIconButton(
                onTap: widget.onBack ?? () => popOrHome(context),
                size: 40,
                child: gameIcon(GameIcons.arrowLeft, size: 18, color: c.ink2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: compact
                    ? _compactHeader(context)
                    : _centeredTitle(context),
              ),
              const SizedBox(width: 10),
              if (rank != null)
                _RoundIconButton(
                  key: rank.key,
                  onTap: rank.onTap,
                  size: 40,
                  child: gameIcon(
                    rank.icon ?? GameIcons.trophy,
                    size: 18,
                    color: c.ink2,
                  ),
                )
              else
                const SizedBox(width: 40),
            ],
          ),
        ),
    );
  }

  Widget _centeredTitle(BuildContext context) => CitroHero(
    tag: CitroHero.tagOf('game-title', widget.gameKey),
    child: _titleRow(context, compact: false),
  );

  /// 手机顶栏中段：单行放得下就标题左、读数右；否则读数折到标题下方。
  Widget _compactHeader(BuildContext context) {
    final stats = _compactStats;
    final title = CitroHero(
      tag: CitroHero.tagOf('game-title', widget.gameKey),
      child: _titleRow(context, compact: true),
    );
    if (stats.isEmpty) {
      return Align(alignment: Alignment.centerLeft, child: title);
    }
    return LayoutBuilder(
      builder: (context, box) {
        // 用真实文本宽度判断，而不是按屏幕宽度猜：长标题、6 位分数、
        // 系统大字号都会把单行顶爆，这时自动退回标题下的那一行。
        final single =
            !box.maxWidth.isFinite ||
            _titleRowWidth(context) +
                    24 +
                    _statsClusterWidth(context, stats) <=
                box.maxWidth;
        if (single) {
          return Row(
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: title),
              ),
              const SizedBox(width: 20),
              _CompactHudCluster(stats: stats),
            ],
          );
        }
        return _CompactHudTitleColumn(title: title, stats: stats);
      },
    );
  }

  /// 标题行（身份点 + 游戏名）。[compact] 时整体左靠，否则居中。
  Widget _titleRow(BuildContext context, {required bool compact}) {
    final c = context.c;
    final identity = _identity;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: compact
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: identity.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: identity.primary.withAlpha(120),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.left : TextAlign.center,
            style: context.heading(
              size: widget.titleSize ?? CitroType.bodyLg,
              color: c.ink,
            ),
          ),
        ),
      ],
    );
  }

  double _titleRowWidth(BuildContext context) {
    final c = context.c;
    final style = context.heading(
      size: widget.titleSize ?? CitroType.bodyLg,
      color: c.ink,
    );
    return 7 + 8 + _textWidth(context, widget.title, style);
  }

  /// 单行读数组的宽度：每组取标签/数值里较宽的一个，再算分隔线。
  double _statsClusterWidth(BuildContext context, List<GameHudStat> stats) {
    final c = context.c;
    final labelStyle = context.body(
      size: CitroType.micro,
      weight: CitroType.medium,
      color: c.inkSoft,
      letterSpacing: .5,
      height: 1,
    );
    final valueStyle = context.hand(
      size: 13,
      weight: CitroType.strong,
      color: c.ink,
      height: 1.08,
    );
    var width = 0.0;
    for (var i = 0; i < stats.length; i++) {
      if (i > 0) width += 21; // 分隔竖线 1 + 左右各 10
      width += math.max(
        _textWidth(context, stats[i].label, labelStyle),
        _textWidth(context, stats[i].value, valueStyle),
      );
    }
    return width;
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// 棋盘上方：above 槽位 + HUD 条。HUD 贴在棋盘之上，读分不用抬头。
  ///
  /// [belowGap] 给手机竖屏用：HUD 收进顶栏后，模式条和棋盘之间补一口气。
  Widget _hudStrip(
    BuildContext context, {
    bool showHud = true,
    double belowGap = 0,
  }) {
    final hasHud = showHud && (widget.hud != null || widget.pills.isNotEmpty);
    if (widget.above.isEmpty && !hasHud) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        GameMetrics.gutter,
        4,
        GameMetrics.gutter,
        belowGap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.above.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : GameMetrics.hudGap),
              child: widget.above[i],
            ),
          if (hasHud) ...[
            if (widget.above.isNotEmpty)
              const SizedBox(height: GameMetrics.hudGap),
            _hudBar(context),
          ],
        ],
      ),
    );
  }

  /// HUD 条：所有分数/计时共用一个浅卡槽，身份色描边。
  Widget _hudBar(BuildContext context) {
    final c = context.c;
    final identity = _identity;
    final inner = widget.hud ??
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: GameMetrics.hudGap,
          runSpacing: 4,
          children: widget.pills,
        );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GameMetrics.hudPad,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: c.surface.withAlpha(238),
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: identity.primary.withAlpha(46)),
        boxShadow: CitroColors.shadows.sm(c),
      ),
      child: inner,
    );
  }

  /// 棋盘区：占掉 HUD 与操作行之外的全部高度，棋盘居中。
  Widget _boardArea(BuildContext context, bool actionsInScroll) {
    final board = widget.board ?? const SizedBox.shrink();
    return LayoutBuilder(
      builder: (ctx, area) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            GameMetrics.gutter,
            8,
            GameMetrics.gutter,
            0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0.0, area.maxHeight - 8),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.contentMaxWidth),
                child: actionsInScroll
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [board, _actionsStrip(context)],
                      )
                    : board,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 操作行：居中成排，不撑满（[GameActionButton] 按内容宽度）。
  Widget _actionsStrip(BuildContext context) {
    final actions = _visibleActions();
    if (actions.isEmpty) return const SizedBox.shrink();
    // 键盘弹出时收起操作行：否则它会被顶到折叠线之外，用户点不到，
    // 看起来像按钮「消失」了（成语接龙 / 飞花令）。
    if (widget.hideActionsOnKeyboard &&
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        GameMetrics.gutter,
        widget.boardGap,
        GameMetrics.gutter,
        GameMetrics.bodyBottom,
      ),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: GameMetrics.actionGap,
          runSpacing: GameMetrics.actionGap,
          children: actions,
        ),
      ),
    );
  }

  List<Widget> _visibleActions() {
    // 排行榜在竖屏挪到顶部圆形按钮、横屏在左栏常驻，都不再出现在按钮行。
    return widget.actions
        .where(
          (item) =>
              item is! GameRankAction &&
              !(item is GameActionButton && item.label.contains('排行')),
        )
        .toList();
  }

  Widget _hudPanel(BuildContext context) {
    if (widget.hud != null) return widget.hud!;
    if (widget.pills.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: GameMetrics.hudGap,
      runSpacing: GameMetrics.hudGap,
      children: widget.pills,
    );
  }

  Widget _landscapeBody(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final kbOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final leftW = math.min(248.0, math.max(210.0, screen.width * 0.24));
    final rightW = math.min(340.0, math.max(270.0, screen.width * 0.24));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: leftW, child: _landscapeRankSidebar(context)),
        Expanded(
          child: SafeArea(
            bottom: false,
            left: false,
            right: false,
            child: _centerArea(context),
          ),
        ),
        SizedBox(
          width: rightW,
          child: _landscapeSidebar(
            context,
            showLive: widget.showLive && !kbOpen,
          ),
        ),
      ],
    );
  }

  /// Windows 横屏右栏是否有「数据看板」。
  ///
  /// 有看板时中间那份 HUD 就是重复的（同一个 hud / pills 画了两遍），
  /// 只隐藏中间这份，右栏的看板保留。
  bool get _sideDashboardVisible =>
      CitroDesktopShell.enabled &&
      widget.showSidePanels &&
      MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;

  /// 横屏：HUD 与操作行分别钉在上下两端，中间棋盘可滚。
  ///
  /// 旧版把 HUD、棋盘、操作全塞进一条滚动视图，棋盘一大就把操作行顶到
  /// 折叠线以下——「暂停 / 新游戏」这种必须够得着的按钮不该需要滚。
  Widget _centerArea(BuildContext context) {
    final actions = _visibleActions();
    return Column(
      children: [
        _hudStrip(context, showHud: !_sideDashboardVisible),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, area) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  GameMetrics.gutter,
                  8,
                  GameMetrics.gutter,
                  8,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0.0, area.maxHeight - 16),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.contentMaxWidth,
                      ),
                      child: widget.board ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GameMetrics.gutter,
              8,
              GameMetrics.gutter,
              GameMetrics.bodyBottom,
            ),
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: GameMetrics.actionGap,
                runSpacing: GameMetrics.actionGap,
                children: actions,
              ),
            ),
          ),
      ],
    );
  }

  Widget _landscapeRankSidebar(BuildContext context) {
    final c = context.c;
    final identity = _identity;
    final duo = CitroForm.duoDevice(MediaQuery.sizeOf(context));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface.withAlpha(242),
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (!duo)
                    _RoundIconButton(
                      onTap: widget.onBack ?? () => popOrHome(context),
                      size: 40,
                      child: gameIcon(
                        GameIcons.arrowLeft,
                        size: 18,
                        color: c.ink2,
                      ),
                    )
                  else
                    const SizedBox(width: 38),
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: identity.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '排行榜',
                      style: context.heading(size: 18, color: c.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: GameTabletRankRail(
                  game: _rankGameKey,
                  title: widget.title,
                  difficulties: widget.rankDifficulties,
                  initial: widget.rankInitial,
                  aiSplit: widget.rankAiSplit,
                  enabled: GameScaffold.liveEnabled,
                  showTitle: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _landscapeSidebar(BuildContext context, {required bool showLive}) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface.withAlpha(242),
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.heading(
                        size: widget.titleSize ?? CitroType.bodyLg,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '数据看板',
                    style: context.body(
                      size: CitroType.micro,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _hudPanel(context),
                ),
              ),
            ),
            const Divider(height: 1),
            if (showLive)
              Expanded(flex: 5, child: _tabletLiveRail(context))
            else
              const Spacer(),
          ],
        ),
      ),
    );
  }

  String get _rankGameKey {
    if (widget.rankGame != null) return widget.rankGame!;
    return const {
          'g2048': '2048',
          'gmem': 'memory',
          'gsudoku': 'sudoku',
          'gnono': 'nono',
          'gslide': 'slide',
          'gsnake': 'snake',
          'gsheep': 'sheep',
          'gjump': 'jump',
          'gpeng': 'peng',
          'gidiom': 'idiom',
          'gfeihua': 'feihua',
          'gbrake': 'brake',
          'gliquid': 'liquid',
          'gknockwater': 'knockwater',
        }[widget.gameKey] ??
        widget.gameKey;
  }

  Widget _tabletLiveRail(BuildContext context) {
    final c = context.c;
    final identity = _identity;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface.withAlpha(238),
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        bottom: false,
        left: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: identity.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '正在玩',
                    style: context.heading(size: CitroType.body, color: c.ink),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _live.isEmpty
                    ? Center(
                        child: Text(
                          '还没有人在玩',
                          style: context.body(
                            size: CitroType.small,
                            color: c.inkSoft,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _live.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) =>
                            _tabletLiveRow(context, _live[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabletLiveRow(BuildContext context, dynamic raw) {
    final c = context.c;
    final identity = _identity;
    final name = '${raw['name'] ?? '游客'}';
    final progress = '${raw['progress'] ?? ''}';
    final av = raw['av'];
    final hasAv = av != null && '$av'.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: identity.primary,
              shape: BoxShape.circle,
              image: hasAv
                  ? DecorationImage(
                      image: ResizeImage(
                        NetworkImage(Api.imageUrl('$av')),
                        width: 78,
                        height: 78,
                      ),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: hasAv
                ? null
                : Text(
                    name.isEmpty ? '游' : name.substring(name.length - 1),
                    style: context.body(
                      size: CitroType.small,
                      weight: CitroType.strong,
                      color: identity.onPrimary,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: CitroType.small,
                    weight: CitroType.strong,
                    color: c.ink,
                  ),
                ),
                if (progress.isNotEmpty)
                  Text(
                    progress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: CitroType.micro,
                      color: c.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 顶栏
// ---------------------------------------------------------------------------

/// 游戏页顶栏（back / 游戏空间 / 账号），可复用给全屏内嵌小游戏。
class GameHead extends StatelessWidget {
  const GameHead({
    super.key,
    this.extraActions = const [],
    required this.onBack,
    this.buttonSize = 38,
    this.iconSize = 18,
    this.centerBrand = false,
  });

  final List<Widget> extraActions;
  final VoidCallback onBack;

  /// 返回圆钮尺寸（内嵌游戏页会放大到 42，让返回键更好点）。
  final double buttonSize;
  final double iconSize;

  /// true = 品牌行相对整条顶栏绝对居中（内嵌游戏页没有右侧动作时用）。
  final bool centerBrand;

  Widget _brand(BuildContext context) {
    final c = context.c;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/logo.webp',
            width: 40,
            height: 40,
            cacheWidth: 120,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 8),
          Transform.translate(
            // web 品牌文字字形比 Skia 高 1px（bbox 190,22 vs 191,23）
            offset: const Offset(-1, -1),
            child: Text(
              '游戏空间',
              style: context.body(
                size: CitroType.label,
                weight: CitroType.medium,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final duo = CitroForm.duoDevice(MediaQuery.sizeOf(context));
    final identity = GameIdentityScope.of(context);
    return Container(
      height: GameMetrics.headHeight,
      padding: EdgeInsets.only(
        left: GameMetrics.sidePad,
        right: GameMetrics.sidePad + CitroDesktopShell.windowControlsInset,
      ),
      decoration: BoxDecoration(color: c.surface),
      child: Stack(
        children: [
          // 底部发丝分隔线
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 1,
            child: ColoredBox(color: c.line),
          ),
          if (centerBrand)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 58),
                  child: Center(child: _brand(context)),
                ),
              ),
            ),
          Positioned.fill(
            child: Row(
              children: [
                if (!duo)
                  _RoundIconButton(
                    onTap: onBack,
                    size: buttonSize,
                    child: gameIcon(
                      GameIcons.arrowLeft,
                      size: iconSize,
                      color: c.ink2,
                    ),
                  )
                else
                  SizedBox(width: buttonSize),
                const SizedBox(width: 12),
                Expanded(
                  child: centerBrand
                      ? const SizedBox.shrink()
                      : Center(child: _brand(context)),
                ),
                const SizedBox(width: 12),
                for (final action in extraActions) ...[
                  action,
                  const SizedBox(width: 8),
                ],
                _MeButton(identity: identity),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    super.key,
    required this.child,
    this.onTap,
    this.size = 38,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: identity.primary.withAlpha(60)),
        ),
        child: child,
      ),
    );
  }
}

class _MeButton extends StatelessWidget {
  const _MeButton({required this.identity});
  final GameIdentity identity;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    String initial = '游';
    try {
      final name = AppState.instance.displayName;
      if (name.isNotEmpty) initial = name.substring(name.length - 1);
    } catch (_) {}
    // web gamesRenderMe：登录用户顶栏圆钮显示真实头像（.gm-av img），
    // 未登录显示昵称末字；此前 App 端永远只画首字。
    final av = AppState.instance.user?.av;
    return GestureDetector(
      onTap: () => showGameAccount(context),
      child: SizedBox(
        width: 38,
        height: 38,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: identity.primary,
              shape: BoxShape.circle,
              border: Border.all(color: c.surface2, width: 2),
              image: av != null && av.isNotEmpty
                  ? DecorationImage(
                      image: ResizeImage(
                        NetworkImage(Api.imageUrl(av)),
                        width: 90,
                        height: 90,
                      ),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: av != null && av.isNotEmpty
                ? null
                : Text(
                    initial,
                    style: context.body(
                      size: CitroType.body,
                      weight: CitroType.strong,
                      color: identity.onPrimary,
                      height: 1.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HUD 组件
// ---------------------------------------------------------------------------

/// 分数 / 计时 pill。
///
/// 数字用身份色的可读深色，标签弱一档；外框只有一圈极淡的身份色描边，
/// 让一排 pill 看起来像同一组读出，而不是几个孤立的卡片。
class GameScorePill extends StatelessWidget {
  const GameScorePill({
    super.key,
    required this.label,
    required this.value,
    this.bump = false,
    this.minWidth = 62,
  });

  final String label;
  final String value;
  final bool bump;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: identity.primary.withAlpha(52)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: context.body(
              size: CitroType.micro,
              weight: CitroType.medium,
              color: c.inkSoft,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: context.hand(
              size: CitroType.titleLg,
              weight: CitroType.strong,
              color: bump ? identity.primaryInk : c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// 手机顶栏读数（单行）：标签在上、数值在下，组与组之间一条细竖线。
class _CompactHudCluster extends StatelessWidget {
  const _CompactHudCluster({required this.stats});

  final List<GameHudStat> stats;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    final children = <Widget>[];
    for (var i = 0; i < stats.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: c.line2,
          ),
        );
      }
      final stat = stats[i];
      children.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              stat.label,
              maxLines: 1,
              softWrap: false,
              style: context.body(
                size: CitroType.micro,
                weight: CitroType.medium,
                color: c.inkSoft,
                letterSpacing: .5,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              stat.value,
              maxLines: 1,
              softWrap: false,
              style: context.hand(
                size: 13,
                weight: CitroType.strong,
                // 身份色在暗色下要提亮，否则 bump 的深蓝在近黑底上读不清。
                color: stat.accent
                    ? (c.dark ? identity.onDark() : identity.primaryInk)
                    : c.ink,
                height: 1.08,
              ),
            ),
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

/// 手机顶栏读数（回退）：标题下一行小字，横向排；放不下自动换行。
class _CompactHudTitleColumn extends StatelessWidget {
  const _CompactHudTitleColumn({required this.title, required this.stats});

  final Widget title;
  final List<GameHudStat> stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 15),
          child: _CompactHudLine(stats: stats),
        ),
      ],
    );
  }
}

class _CompactHudLine extends StatelessWidget {
  const _CompactHudLine({required this.stats});

  final List<GameHudStat> stats;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final stat in stats)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stat.label,
                maxLines: 1,
                softWrap: false,
                style: context.body(
                  size: 10,
                  weight: CitroType.medium,
                  color: c.inkSoft,
                  height: 1,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                stat.value,
                maxLines: 1,
                softWrap: false,
                style: context.hand(
                  size: CitroType.small,
                  weight: CitroType.strong,
                  color: stat.accent
                      ? (c.dark ? identity.onDark() : identity.primaryInk)
                      : c.ink2,
                  height: 1,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 轻量悬停反馈：鼠标移入轻微抬升并放大，移出回落。
///
/// 给不走 [GameActionButton] 的自定义按钮、分段器和可点击卡片补上桌面端反馈；
/// 只负责视觉与指针光标，点击仍由外层 GestureDetector / Pressable 处理。
class GameHover extends StatefulWidget {
  const GameHover({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 1.02,
    this.lift = 1.5,
  });

  final Widget child;
  final bool enabled;
  final double scale;
  final double lift;

  @override
  State<GameHover> createState() => _GameHoverState();
}

class _GameHoverState extends State<GameHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled && _hover;
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        if (widget.enabled && !_hover) setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, on ? -widget.lift : 0, 0),
        child: AnimatedScale(
          scale: on ? widget.scale : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 标记「排行榜」入口：横屏左栏已有常驻榜单时，GameScaffold 从按钮行移除。
class GameRankAction extends StatelessWidget {
  const GameRankAction({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// 操作按钮。
///
/// 宽度按内容收（不能加 `alignment: center`：那会让它在有界宽度下
/// 撑满整行，操作行因此变成一列全宽按钮）。需要通栏时显式传 [expand]。
class GameActionButton extends StatelessWidget {
  const GameActionButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.width,
    this.primary = false,
    this.enabled = true,
    this.height = 44,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onTap;
  final String? icon;

  /// 固定宽度；[expand] 优先。
  final double? width;
  final bool primary;
  final bool enabled;

  /// 按钮高度。
  final double height;

  /// 弹窗里成对按钮需要等宽撑满；游戏 HUD 保持按内容宽度。
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    final bg = primary ? identity.primary : c.surface;
    final fg = primary ? identity.onPrimary : c.ink2;
    final border = primary ? identity.primary : c.line2;
    return Opacity(
      opacity: enabled ? 1 : 0.34,
      child: Pressable(
        onTap: enabled ? onTap : null,
        scale: .97,
        hoverLift: 1.5,
        borderRadius: BorderRadius.circular(CitroColors.radii.button),
        child: Container(
          width: expand ? double.infinity : width,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(CitroColors.radii.button),
            border: Border.all(color: border),
            boxShadow: primary
                ? CitroColors.shadows.float(c)
                : CitroColors.shadows.sm(c),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                gameIcon(icon!, size: 15, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: context.body(
                  size: CitroType.label,
                  weight: CitroType.strong,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 难度 / 榜单分段切换。选中态用身份色实底。
class GameSegTabs<T> extends StatelessWidget {
  const GameSegTabs({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 4 : 5,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.button),
        border: Border.all(color: c.line),
      ),
      // 用 Wrap 而不是 Row：窄侧栏（iPad 横屏）里段数多时换行，不溢出。
      child: Wrap(
        spacing: 0,
        runSpacing: 0,
        children: [
          for (final it in items)
            GestureDetector(
              onTap: () => onChanged(it.$1),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 10 : 14,
                  vertical: dense ? 5 : 6,
                ),
                decoration: BoxDecoration(
                  color: it.$1 == value ? identity.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(CitroColors.radii.button),
                ),
                child: Text(
                  it.$2,
                  style: context.body(
                    size: dense ? CitroType.small : CitroType.caption,
                    weight: CitroType.strong,
                    color: it.$1 == value ? identity.onPrimary : c.ink2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 底部「正在玩」条。
class GameLiveBar extends StatelessWidget {
  const GameLiveBar({super.key, required this.list});
  final List<dynamic> list;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    return Container(
      height: 48,
      margin: const EdgeInsets.fromLTRB(
        GameMetrics.gutter,
        0,
        GameMetrics.gutter,
        12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.card(c),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: identity.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '正在玩',
            style: context.body(
              size: CitroType.caption,
              weight: CitroType.medium,
              color: c.ink2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '还没有人在玩',
                      style: context.body(
                        size: CitroType.caption,
                        color: c.inkSoft,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final raw in list.take(6))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _LiveChip(raw: raw),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.raw});
  final dynamic raw;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    final name = '${raw['name'] ?? '游客'}';
    final progress = '${raw['progress'] ?? ''}';
    final initial = name.isEmpty ? '游' : name.substring(name.length - 1);
    final av = raw['av'];
    final hasAv = av != null && '$av'.isNotEmpty;
    final you = raw['you'] == true || raw['you'] == 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: you ? identity.primary.withAlpha(38) : c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(color: you ? identity.primary : c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: identity.primary,
              shape: BoxShape.circle,
              image: hasAv
                  ? DecorationImage(
                      image: ResizeImage(
                        NetworkImage(Api.imageUrl('$av')),
                        width: 72,
                        height: 72,
                      ),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasAv
                ? null
                : Text(
                    initial,
                    style: context.body(
                      size: CitroType.small,
                      weight: CitroType.strong,
                      color: identity.onPrimary,
                    ),
                  ),
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: context.body(
              size: CitroType.caption,
              weight: CitroType.strong,
              color: c.ink,
            ),
          ),
          if (you) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: identity.primary,
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              ),
              child: Text(
                '你',
                style: context.body(
                  size: CitroType.micro,
                  weight: CitroType.strong,
                  color: identity.onPrimary,
                ),
              ),
            ),
          ],
          if (progress.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(
              progress,
              style: context.body(size: CitroType.small, color: c.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

/// 排行榜入口（复用旧实现）
Future<void> showGameRank(
  BuildContext context, {
  required String game,
  required String title,
  List<(String, String)> difficulties = const [],
  String initial = '',
  bool aiSplit = false,
}) => showGameLeaderboard(
  context,
  game: game,
  title: title,
  difficulties: difficulties,
  initial: initial,
  aiSplit: aiSplit,
);

/// 时长格式 m:ss
String gameFmtDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// 一条 CSS `box-shadow` 描述（外阴影语义：绘制在圆角矩形之外）
class CssShadowSpec {
  const CssShadowSpec({
    required this.color,
    this.offset = Offset.zero,
    this.blur = 0,
    this.spread = 0,
  });

  final Color color;
  final Offset offset;
  final double blur;
  final double spread;
}

/// 复刻 CSS 外阴影：外阴影被裁剪在 border-box 之外，且 blur 半径 = 2σ。
/// 用 Stack 把阴影画在 child 下方（child 自身可以是半透明底）。
class CssShadowLayer extends StatelessWidget {
  const CssShadowLayer({
    super.key,
    required this.shadows,
    required this.radius,
    required this.child,
  });

  final List<CssShadowSpec> shadows;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CssShadowLayerPainter(shadows: shadows, radius: radius),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _CssShadowLayerPainter extends CustomPainter {
  const _CssShadowLayerPainter({required this.shadows, required this.radius});

  final List<CssShadowSpec> shadows;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(outer, Radius.circular(radius)));
    final clip = Path.combine(
      PathOperation.difference,
      Path()..addRect(outer.inflate(200)),
      inner,
    );
    canvas.save();
    canvas.clipPath(clip);
    for (final s in shadows) {
      final rect = outer.inflate(s.spread).shift(s.offset);
      final path = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular((radius + s.spread).clamp(0, 999)),
          ),
        );
      final paint = Paint()..color = s.color;
      if (s.blur > 0) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.blur * 0.5);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CssShadowLayerPainter old) =>
      old.radius != radius || old.shadows != shadows;
}
