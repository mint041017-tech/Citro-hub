// 游戏页公共 UI —— 1:1 复刻 web 版游戏页。
// 基准：styles/citro-games.css + styles/citro-scrapbook.css + styles/citro-core.css，
// 390×844 light 实测（_tmp/ref/css/*.json 计算样式 + _tmp/ref/games/*-m-l.png 截图）。
//
// 版式（390×844）：
//   .page-g     全屏纸面 #FBF7EC + 24px 方格 + 双光斑
//   .g-head     56 高，左右 14；返回圆钮 38 / 居中「游戏空间」ZCOOL 15 / 账号圆钮 38
//   .g-body     纵向 flex 居中；padding 上 clamp(8,1.8vh,16) 下 12，左右 14
//   h1          ZCOOL clamp(25,6.6vw,34)，400 字重，letter-spacing .06em（手机端无荧光笔）
//   分数 pill   高 56.6，minWidth 62，padding 6/10，橙描边 1px，圆角 999，纸底 #FFFDF8
//   操作按钮     高 42，padding 0 22，圆角 999，普通纸底 .72 / 主按钮 135° 橙渐变
//   g-live      底部横条：margin 0 14 12，padding 8/10，圆角 14，纸底 + line 描边
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/refresh_rate.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/paper.dart';
import 'game_common.dart'
    show GameTabletRankRail, showGameAccount, showGameLeaderboard;

/// 版式常量（web 游戏页 390×844 实测）
class GameMetrics {
  const GameMetrics._();
  static const double headHeight = 56;
  static const double sidePad = 14;
  static const double bodyBottom = 12;
  static const double hudGap = 9;
  static const double actionGap = 8;

  /// .g-body padding-top: clamp(8px, 1.8vh, 16px)
  static double bodyTop(double viewportHeight) =>
      (viewportHeight * 0.018).clamp(8.0, 16.0);

  /// h1 font-size: clamp(25px, 6.6vw, 34px)
  static double titleSize(double width) => (width * 0.066).clamp(25.0, 34.0);
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
/// v1.6.4：文字游戏录入时列表要跟着最新一条走。
class KeyboardObserver with WidgetsBindingObserver {
  KeyboardObserver(this.onMetricsChanged);

  final VoidCallback onMetricsChanged;

  @override
  void didChangeMetrics() => onMetricsChanged();
}

/// 游戏页骨架：纸面 + 顶栏 + 居中内容 + 底部「正在玩」条
class GameScaffold extends StatefulWidget {
  const GameScaffold({
    super.key,
    required this.gameKey,
    required this.title,
    this.above = const [],
    this.pills = const [],
    this.actions = const [],
    this.hud,
    this.board,
    this.boardGap = 18,
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
  });

  final String gameKey;
  final String title;

  /// HUD 上方的整行控件（难度分段器等），每项独占一行
  final List<Widget> above;
  final List<Widget> pills;
  final List<Widget> actions;

  /// 自定义 HUD（如 gjump 的「pill + 按钮」单行 stretch 布局）；非空时忽略 pills/actions
  final Widget? hud;
  final Widget? board;
  final double boardGap;
  final ValueNotifier<String>? liveProgress;
  final bool showLive;

  /// true = live 条放进滚动内容（web 中页面内容高于视口时整页滚动的行为）
  final bool liveInScroll;
  final double? titleSize;
  final VoidCallback? onBack;
  final List<Widget> extraHeadActions;

  /// iPad 横屏侧栏排行榜使用的游戏 key；缺省按 gameKey 推导。
  final String? rankGame;
  final List<(String, String)> rankDifficulties;
  final String rankInitial;
  final bool rankAiSplit;

  /// 测试时关掉轮询（golden 渲染用）
  static bool liveEnabled = true;

  @override
  State<GameScaffold> createState() => _GameScaffoldState();
}

class _GameScaffoldState extends State<GameScaffold> {
  Timer? _timer;
  List<dynamic> _live = const [];
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
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
      if (mounted) setState(() => _live = list);
    } catch (_) {}
  }

  @override
  void dispose() {
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
        }[widget.gameKey] ??
        widget.gameKey;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final screen = MediaQuery.sizeOf(context);
    final ts = widget.titleSize ?? GameMetrics.titleSize(screen.width);
    final tabletLandscape =
        screen.width >= 1100 && screen.width > screen.height;
    final hudGroups = <Widget>[
      if (widget.hud != null)
        widget.hud!
      else ...[
        if (widget.pills.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: GameMetrics.hudGap,
            runSpacing: GameMetrics.hudGap,
            children: widget.pills,
          ),
        if (widget.actions.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: GameMetrics.actionGap,
            runSpacing: GameMetrics.actionGap,
            children: widget.actions,
          ),
      ],
    ];
    // 游戏页是按 390×844 逐像素复刻的定版式；系统字号放大（无障碍字体缩放）
    // 会把规则卡 / HUD pill / 菜单按钮的文字撑出布局（成语接龙、飞花令的
    // 「开始按钮与规则重叠」「最高分换行」都是它引起的），这里统一钳到 1.0，
    // 与 web 端 CSS px 不随系统缩放的行为一致。
    final mq = MediaQuery.of(context);
    final kbOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.zcool,
            fontFamilyFallback: AppFonts.fallback,
            fontSize: ts,
            fontWeight: FontWeight.w400,
            height: 1.65,
            letterSpacing: ts * 0.06,
            color: c.ink,
          ),
        ),
        ...widget.above,
        const SizedBox(height: 8),
        if (hudGroups.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < hudGroups.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      top: i == 0 ? 0 : GameMetrics.hudGap,
                    ),
                    child: hudGroups[i],
                  ),
              ],
            ),
          ),
        if (widget.board != null) ...[
          SizedBox(height: widget.boardGap),
          RepaintBoundary(child: widget.board!),
        ],
      ],
    );

    Widget normalBody() {
      return Column(
        children: [
          SafeArea(
            bottom: false,
            child: GameHead(
              extraActions: widget.extraHeadActions,
              onBack: widget.onBack ?? () => popOrHome(context),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, cons) {
                final top = GameMetrics.bodyTop(screen.height);
                // web：.g-body 与 .g-live 同在 .page-g 的滚动流里；内容高于视口时
                // 整页滚动（live 条只露出顶部）。liveInScroll 复刻该行为。
                if (widget.liveInScroll) {
                  final bodyAreaMax = math.max(
                    0.0,
                    cons.maxHeight - (kbOpen ? 0.0 : 56.7),
                  );
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(minHeight: bodyAreaMax),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              GameMetrics.sidePad,
                              top,
                              GameMetrics.sidePad,
                              GameMetrics.bodyBottom,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 760,
                                ),
                                child: content,
                              ),
                            ),
                          ),
                        ),
                        if (widget.showLive && !kbOpen)
                          GameLiveBar(list: _live),
                      ],
                    ),
                  );
                }
                final minH = math.max(
                  0.0,
                  cons.maxHeight - top - GameMetrics.bodyBottom,
                );
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    GameMetrics.sidePad,
                    top,
                    GameMetrics.sidePad,
                    GameMetrics.bodyBottom,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minH),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: content,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.showLive &&
              !widget.liveInScroll &&
              MediaQuery.viewInsetsOf(context).bottom <= 0)
            GameLiveBar(list: _live),
        ],
      );
    }

    Widget tabletBody() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 248, child: _tabletSidebar(context)),
          Expanded(
            child: SafeArea(
              bottom: false,
              left: false,
              right: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
          if (widget.showLive)
            SizedBox(width: 196, child: _tabletLiveRail(context)),
        ],
      );
    }

    Widget page = Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            isComplex: true,
            willChange: false,
            painter: _PageBgPainter(c),
          ),
        ),
        if (tabletLandscape) tabletBody() else normalBody(),
      ],
    );
    if (mq.textScaler.scale(10) != 10) {
      page = MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.noScaling),
        child: page,
      );
    }
    return Scaffold(backgroundColor: c.surface, body: page);
  }

  Widget _tabletSidebar(BuildContext context) {
    final c = context.c;
    final duo = CitroForm.duoDevice(MediaQuery.sizeOf(context));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface.withAlpha(238),
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        bottom: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (!duo)
                    _RoundIconButton(
                      onTap:
                          widget.onBack ??
                          () => Navigator.of(context).maybePop(),
                      size: 38,
                      child: gameIcon(
                        GameIcons.arrowLeft,
                        size: 18,
                        color: c.ink2,
                      ),
                    )
                  else
                    const SizedBox(width: 38),
                  const SizedBox(width: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.asset(
                      'assets/images/logo.webp',
                      width: 30,
                      height: 30,
                      cacheWidth: 90,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '游戏空间',
                    style: TextStyle(
                      fontFamily: AppFonts.zcool,
                      fontFamilyFallback: AppFonts.fallback,
                      fontSize: 14.5,
                      height: 1.4,
                      letterSpacing: 0.6,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: GameTabletRankRail(
                  game: _rankGameKey,
                  title: widget.title,
                  difficulties: widget.rankDifficulties,
                  initial: widget.rankInitial,
                  aiSplit: widget.rankAiSplit,
                  enabled: GameScaffold.liveEnabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabletLiveRail(BuildContext context) {
    final c = context.c;
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
                      color: c.mint,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '正在玩',
                    style: TextStyle(
                      fontFamily: AppFonts.zcool,
                      fontFamilyFallback: AppFonts.fallback,
                      fontSize: 16,
                      height: 1.4,
                      letterSpacing: 0.4,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _live.isEmpty
                    ? Center(
                        child: Text(
                          '还没有人在玩',
                          style: TextStyle(
                            fontFamily: AppFonts.noto,
                            fontFamilyFallback: AppFonts.bodyFallback,
                            fontSize: 11,
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
    final name = '${raw['name'] ?? '游客'}';
    final progress = '${raw['progress'] ?? ''}';
    final av = raw['av'];
    final hasAv = av != null && '$av'.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line.withAlpha(160)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: c.accent,
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
                    style: TextStyle(
                      fontFamily: AppFonts.kalam,
                      fontFamilyFallback: AppFonts.fallback,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2E2C22),
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
                  style: TextStyle(
                    fontFamily: AppFonts.noto,
                    fontFamilyFallback: AppFonts.bodyFallback,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                if (progress.isNotEmpty)
                  Text(
                    progress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontFamilyFallback: AppFonts.bodyFallback,
                      fontSize: 9.5,
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
// 背景：.page-g 纸面 + 24px 方格（光斑在 web 侧已被 background:none 关掉）
//   横向线来源 repeating-linear-gradient(0deg, ...) 从**底边**起算，
//   所以相位 = (height - 1) % 24；纵向线来自 90deg 渐变，从左边起算 = 0。
// ---------------------------------------------------------------------------

class _PageBgPainter extends CustomPainter {
  _PageBgPainter(this.c);
  final CitroColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = c.surface);

    final grid = Paint()
      ..color = c.grid
      ..strokeWidth = 1
      ..isAntiAlias = false;
    for (double x = 0; x <= size.width; x += 24) {
      canvas.drawLine(Offset(x + .5, 0), Offset(x + .5, size.height), grid);
    }
    final double phase = (size.height - 1) % 24;
    for (double y = phase; y <= size.height; y += 24) {
      canvas.drawLine(Offset(0, y + .5), Offset(size.width, y + .5), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _PageBgPainter old) =>
      old.c.surface != c.surface || old.c.grid != c.grid;
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
              style: TextStyle(
                fontFamily: AppFonts.zcool,
                fontFamilyFallback: AppFonts.fallback,
                fontSize: 15,
                height: 1.65,
                letterSpacing: 0.9,
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
    return Container(
      height: GameMetrics.headHeight,
      padding: const EdgeInsets.symmetric(horizontal: GameMetrics.sidePad),
      decoration: BoxDecoration(color: c.surface),
      child: Stack(
        children: [
          // web .g-head::before 的 inset 0 -1px line
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 1,
            child: ColoredBox(color: c.line),
          ),
          // web .g-head::after 的 16%..84% 渐隐线
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    c.line2.withValues(alpha: 0),
                    c.line2,
                    c.line2,
                    c.line2.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.16, 0.84, 1],
                ),
              ),
            ),
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
                const _MeButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.child, this.onTap, this.size = 38});
  final Widget child;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: c.line2),
        ),
        child: child,
      ),
    );
  }
}

class _MeButton extends StatelessWidget {
  const _MeButton();

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
              color: c.accent,
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
                    style: const TextStyle(
                      fontFamily: AppFonts.kalam,
                      fontFamilyFallback: AppFonts.fallback,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: Color(0xFF2E2C22),
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

/// 分数 / 计时 pill（web .g-pill）
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
    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 56.64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.accent, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.65,
              letterSpacing: 1.68,
              color: c.accentInk,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppFonts.kalam,
              fontFamilyFallback: AppFonts.fallback,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.15,
              letterSpacing: 0.38,
              color: bump ? c.accentInk : c.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 操作按钮（web .g-btn / .g-btn.primary）
class GameActionButton extends StatelessWidget {
  const GameActionButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.primary = false,
    this.enabled = true,
    this.height = 42,
  });

  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool primary;
  final bool enabled;

  /// web 手机端 .g-btn min-height 42；gjump 等单行 HUD 里按钮被 stretch 到 56.64
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? const Color(0xFF3B2A10) : const Color(0xFF4E4A40);
    final body = Stack(
      children: [
        // web 的 box-shadow 会被裁剪在 border-box 之外；Flutter 里半透明底色会让
        // 底层阴影透上来（button 变灰）。这里把阴影画在裁剪掉圆角矩形之外的层。
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _OuterShadowPainter(
                color: primary
                    ? const Color(0xA694530A)
                    : const Color(0x803C301A),
                blur: primary ? 22 : 12,
                spread: primary ? -12 : -8,
                offset: Offset(0, primary ? 11 : 4),
                radius: 999,
              ),
            ),
          ),
        ),
        Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: primary ? null : const Color(0xB8FFFCF4),
            gradient: primary
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF9C98C), Color(0xFFF0A85C)],
                  )
                : null,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: primary
                  ? const Color(0x2E94530A)
                  : const Color(0x294A3A22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                gameIcon(icon!, size: 14, color: fg),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppFonts.noto,
                  fontFamilyFallback: AppFonts.bodyFallback,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.24,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.34,
      child: Pressable(onTap: enabled ? onTap : null, child: body),
    );
  }
}

/// 把投影画在「圆角矩形之外」（模拟 CSS 外阴影不被半透明背景透出的效果）
class _OuterShadowPainter extends CustomPainter {
  const _OuterShadowPainter({
    required this.color,
    required this.blur,
    required this.spread,
    required this.offset,
    required this.radius,
  });

  final Color color;
  final double blur;
  final double spread;
  final Offset offset;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    final inner = RRect.fromRectAndRadius(outer, Radius.circular(radius));
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(outer.inflate(blur * 2 + 40)),
        Path()..addRRect(inner),
      ),
    );
    final shadowRect = outer.inflate(spread).shift(offset);
    final shadowPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(shadowRect, Radius.circular(radius + spread)),
      );
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 0.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OuterShadowPainter old) =>
      old.color != color ||
      old.blur != blur ||
      old.spread != spread ||
      old.offset != offset ||
      old.radius != radius;
}

/// 难度 / 榜单分段切换（web .gmem-diff / .gs-tabs）
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 4 : 5,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final it in items)
            GestureDetector(
              onTap: () => onChanged(it.$1),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 10 : 13,
                  vertical: dense ? 5 : 6,
                ),
                decoration: BoxDecoration(
                  color: it.$1 == value ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  it.$2,
                  style: TextStyle(
                    fontFamily: AppFonts.noto,
                    fontFamilyFallback: AppFonts.bodyFallback,
                    fontSize: dense ? 11 : 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: it.$1 == value ? const Color(0xFF2E2C22) : c.ink2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 纸胶带（web 棋盘 ::before）
class GameTape extends StatelessWidget {
  const GameTape({
    super.key,
    this.width = 82,
    this.height = 24,
    this.color,
    this.angle = -2,
  });

  final double width;
  final double height;
  final Color? color;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Transform.rotate(
      angle: angle * math.pi / 180,
      child: CustomPaint(
        size: Size(width, height),
        painter: _TapePainter(color ?? c.tape),
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  _TapePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.02, 0)
      ..lineTo(size.width * 0.98, size.height * 0.03)
      ..lineTo(size.width, size.height * 0.95)
      ..lineTo(size.width * 0.04, size.height)
      ..close();
    canvas.drawShadow(path, const Color(0x1A786040), 1, false);
    canvas.drawPath(path, Paint()..color = color);
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width * 0.06, size.height * 0.12),
      Offset(size.width * 0.94, size.height * 0.16),
      edge,
    );
  }

  @override
  bool shouldRepaint(covariant _TapePainter old) => old.color != color;
}

/// 底部「正在玩」条（web .g-live.on）
class GameLiveBar extends StatelessWidget {
  const GameLiveBar({super.key, required this.list});
  final List<dynamic> list;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 44.7,
      margin: const EdgeInsets.fromLTRB(
        GameMetrics.sidePad,
        0,
        GameMetrics.sidePad,
        12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.paper(c),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '正在玩',
            style: TextStyle(
              fontFamily: AppFonts.zcool,
              fontFamilyFallback: AppFonts.fallback,
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              height: 1.65,
              letterSpacing: 0.25,
              color: c.ink,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(
                      top: 2,
                      right: 2,
                      bottom: 3,
                      left: 7,
                    ),
                    child: Text(
                      '还没有人在玩',
                      style: TextStyle(
                        fontFamily: AppFonts.noto,
                        fontFamilyFallback: AppFonts.bodyFallback,
                        fontSize: 11.5,
                        height: 1.8,
                        color: const Color(0xFF575446),
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
    final name = '${raw['name'] ?? '游客'}';
    final progress = '${raw['progress'] ?? ''}';
    final initial = name.isEmpty ? '游' : name.substring(name.length - 1);
    // v1.6.0：web .gl-av 有头像显示头像图、.gl-row.you 高亮并加「你」标；
    // 旧实现只画昵称末字，用户看不到自己的头像。
    final av = raw['av'];
    final hasAv = av != null && '$av'.isNotEmpty;
    final you = raw['you'] == true || raw['you'] == 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 11, 4),
      decoration: BoxDecoration(
        color: you ? const Color(0x29FE923B) : c.line,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: you ? const Color(0x66FE923B) : c.line2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accent,
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
                    style: const TextStyle(
                      fontFamily: AppFonts.kalam,
                      fontFamilyFallback: AppFonts.fallback,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E2C22),
                    ),
                  ),
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          if (you) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                '你',
                style: TextStyle(
                  fontFamily: AppFonts.noto,
                  fontFamilyFallback: AppFonts.bodyFallback,
                  fontSize: 10,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8F4E05),
                ),
              ),
            ),
          ],
          if (progress.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(
              progress,
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontFamilyFallback: AppFonts.bodyFallback,
                fontSize: 11,
                color: c.inkSoft,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 排行榜入口（复用旧实现，后续按 web .g-sheet 精修）
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
