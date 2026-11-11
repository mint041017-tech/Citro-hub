import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../data/quotes.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_page.dart';
import '../calendar/calendar_store.dart';
import '../services/api.dart';
import '../services/fish.dart';
import '../services/haptics.dart';
import '../overlays/appreciation_sheet.dart';
import '../overlays/card_collection.dart';
import '../overlays/extra_sheets.dart';
import '../overlays/lantern_sheet.dart';
import '../overlays/zodiac_modal.dart';
import '../services/lantern_api.dart';
import '../services/models.dart';
import '../state/app_state.dart';
import '../state/negative_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/lunar.dart';
import '../widgets/card_flight.dart';
import '../widgets/card_morph.dart';
import '../widgets/home_background.dart';
import '../widgets/home_bento.dart';
import '../widgets/home_entries.dart';
import '../widgets/home_layout.dart';
import '../widgets/negative_screen.dart';
import '../widgets/paper.dart';
import '../widgets/todo_home_card.dart';
import '../widgets/mood_home_card.dart';
import '../widgets/ledger_home_card.dart';
import '../widgets/tablet_shell.dart';
import 'cook_page.dart';
import 'me_page.dart';
import 'web_home.dart';

String _weekdayLabel(DateTime d) {
  const names = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  return names[d.weekday - 1];
}

class HomePage extends StatefulWidget {
  final ValueChanged<int> onSwitchTab;
  const HomePage({super.key, required this.onSwitchTab});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();

  /// 负一屏展开进度（0..1）。
  ///
  /// 用 [ValueNotifier] 而不是 `setState`：拖拽每帧只重建那一层 Transform，
  /// 不重建整棵首页（否则卡片、背景、栅格每帧都要重新 layout，必然掉帧）。
  final ValueNotifier<double> _negProgress = ValueNotifier(0);

  /// 下拉行程 = 负一屏面板高度（在 build 里按屏高算）。
  double _negThreshold = 300;

  /// 本次下拉累计的拖拽距离。
  double _negPull = 0;

  /// 阻尼系数：抽屉行程走手指的 95%，几乎跟手但略带重量。
  static const double _negDamping = 0.95;

  /// 到达这个开度就自动弹开（不用再松手）——很低，轻轻一拖就开。
  static const double _negOpenAt = 0.35;

  /// 松手时超过这个开度就吸开，否则立刻吸回（不停顿）。
  static const double _negSnapAt = 0.3;

  /// 负一屏自身上滑时把它推回顶部（同样按增量）。
  bool _onNegativeScroll(ScrollNotification n) {
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final d = n.scrollDelta ?? 0;
      if (d > 0) {
        _setNegProgress(
          (_negProgress.value - d / _negThreshold).clamp(0.0, 1.0),
        );
      }
    } else if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll > 0) {
      _setNegProgress(
        (_negProgress.value - n.overscroll / _negThreshold).clamp(0.0, 1.0),
      );
    } else if (n is ScrollEndNotification &&
        _negProgress.value > 0 &&
        _negProgress.value < 1) {
      _animateNegTo(_negProgress.value > _negSnapAt ? 1.0 : 0.0);
    }
    return false;
  }

  /// 当前背景露出高度与卡片覆盖比例（驱动背景模糊）。
  double _bgHeight = 400;
  double _bgCover = 0;

  /// 外部请求展开负一屏时用的过渡动画（下拉驱动时不用它）。
  AnimationController? _negAuto;

  @override
  void initState() {
    super.initState();
    negativeScreenSignal.addListener(_onNegativeSignal);
    CitroBlendImage.bottomEdge.addListener(_onBgEdge);
    _scroll.addListener(_onScrollOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showLanternWelcomeIfNeeded(context);
      HomeLayoutStore.instance.syncFromAccount();
    });
  }

  /// 背景图解码完成后，卡片区起点跟着图的下边缘走。
  void _onBgEdge() {
    if (mounted) setState(() {});
  }

  void _onScrollOffset() {
    if (!_scroll.hasClients) return;
    final cover = (_scroll.offset / _bgHeight).clamp(0.0, 1.0);
    if ((cover - _bgCover).abs() > .01) {
      setState(() => _bgCover = cover);
    }
  }

  @override
  void dispose() {
    CitroBlendImage.bottomEdge.removeListener(_onBgEdge);
    _scroll.removeListener(_onScrollOffset);
    negativeScreenSignal.removeListener(_onNegativeSignal);
    _negAuto?.dispose();
    _negProgress.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 平滑把负一屏推进 / 推回（外部入口与关闭按钮用）。
  ///
  /// 用弹簧而不是定时曲线：弹簧带一点过冲再回落，回弹不生硬。
  void _animateNegTo(double target) {
    if (!mounted) return;
    _negAuto?.dispose();
    final from = _negProgress.value;
    if ((target - from).abs() < 0.001) return;
    final controller = AnimationController(vsync: this, value: from);
    _negAuto = controller;
    controller.addListener(() => _setNegProgress(controller.value));
    final simulation = SpringSimulation(
      // 回弹要快、要干脆：刚度大、阻尼略低于临界，几乎不停顿。
      SpringDescription(mass: 1, stiffness: 340, damping: 32),
      from,
      target,
      0,
    );
    controller.animateWith(simulation).whenComplete(() {
      if (identical(_negAuto, controller)) _negAuto = null;
      // 弹簧停在容差内，最后补一刀精确落到目标值。
      _setNegProgress(target);
      controller.dispose();
    });
  }

  /// 「我的 / 游戏页」的资源配置入口：平滑展开负一屏，而不是瞬间跳变。
  void _onNegativeSignal() => _animateNegTo(1);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1025) {
      return WebHomePage(onSwitchTab: widget.onSwitchTab);
    }
    final layout = CitroLayoutScope.maybeOf(context);
    final media = MediaQuery.sizeOf(context);
    final width = layout?.contentWidth ?? media.width;
    final duoWide = (layout?.duo ?? false) && media.width > media.height;
    final wide = width >= 780 || (duoWide && width >= 600);
    final maxWidth = wide ? 1120.0 : 760.0;
    final layoutKey = homeLayoutKeyFor(
      wide ? HomeForm.wide : HomeForm.compact,
      media.width > media.height,
    );
    final sideNav = layout?.tabletNav ?? false;
    final side = math.max(12.0, (width - maxWidth) / 2);

    // 顶栏（账号 + 日期）固定占位，卡片从它下缘开始滚，两者不重叠。
    final topBarReserved = MediaQuery.paddingOf(context).top + 56;
    // 卡片面板的顶边落在屏幕的这个高度上（默认约 2/3）；
    // 英雄区（背景 + 打招呼）= 这段高度减去顶栏。
    final heroBottom = wide
        ? math.min(480.0, media.height * .60)
        : (media.height * .68).clamp(440.0, 640.0);
    // 卡片面板的顶边：优先落在背景图的下边缘；图还没解码出来时先按默认英雄区。
    // 「抬高」= 卡片区往上提，所以上限比图低 24px，顶多占视口 60%。
    final bgEdge = CitroBlendImage.bottomEdge.value;
    final rawBg = bgEdge > 0
        ? math.max(120.0, bgEdge - topBarReserved)
        : math.max(120.0, heroBottom - topBarReserved);
    final bgHeight = math.min(rawBg, media.height * 0.45);
    _bgHeight = bgHeight;
    // 抽屉（负一屏）高度：够用就好，不要多余空白。
    final negHeight = (media.height * .52).clamp(300.0, 460.0);
    _negThreshold = negHeight;
    // 下拉行程 = 抽屉高度，手指拖多少首页就往下走多少。
    final travel = negHeight;

    return Stack(
      children: [
        // ── 1. 抽屉（负一屏）：固定在最底层，下拉时从首页下面露出来 ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: negHeight,
          child: ValueListenableBuilder<double>(
            valueListenable: _negProgress,
            builder: (context, progress, child) =>
                IgnorePointer(ignoring: progress < .95, child: child),
            child: NotificationListener<ScrollNotification>(
              onNotification: _onNegativeScroll,
              child: NegativeScreen(onClose: () => _animateNegTo(0)),
            ),
          ),
        ),

        // ── 2. 整个首页：下拉时一起往下走（抽屉） ──
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _negProgress,
            builder: (context, progress, child) => Transform.translate(
              key: const ValueKey('home-drawer-shift'),
              offset: Offset(0, progress * travel),
              child: child,
            ),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              // 单击抽屉以外的地方（首页内容）就收起抽屉。
              onPointerDown: (_) {
                if (_negProgress.value > 0.02) _animateNegTo(0);
              },
              child: Stack(
                children: [
                  // 背景层：铺满全屏，固定不动，只随下拉整体下移；
                  // 清晰度随卡片覆盖下降（卡片上滑盖住背景时背景变糊）。
                  // 首页英雄区是白字，强制深色罩面。
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CitroAmbientBackground(
                        blurred: true,
                        blurSigma: _bgCover * 16,
                        darkScrim: true,
                        // 深色主题下把背景图再压暗一点。
                        dim: 0.18,
                      ),
                    ),
                  ),
                  // 顶栏固定 + 下方整页滚动：卡片上滑时逐渐盖住背景图。
                  Positioned.fill(
                    child: Column(
                      children: [
                        _HomeTopBar(side: side),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _onScrollNotification,
                            child: SingleChildScrollView(
                              controller: _scroll,
                              // 去掉回弹：到底 / 到顶都硬停，不弹。
                              physics: const ClampingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: bgHeight,
                                    child: _HomeHeader(side: side),
                                  ),
                                  _CardsPanel(
                                    radiusTop: CitroColors.radii.card,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            side,
                                            8,
                                            side,
                                            sideNav ? 92 : 108,
                                          ),
                                          child: HomeBento(
                                            layoutKey: layoutKey,
                                            editing: false,
                                            scrollController: _scroll,
                                            builder: _cardFor,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        Center(
                                          child: Pressable(
                                            onTap: () =>
                                                showAppreciationSheet(context),
                                            child: Text(
                                              'Citro · 今天也要开心',
                                              style: context.body(
                                                size: CitroType.small,
                                                color: context.c.inkSoft,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 滚动通知偶尔会在帧内（布局/动画回调）派发，那时直接 setState 会触发
  /// 「Build scheduled during frame」。这种情况挂到帧末再更新。
  /// 直接写 [ValueNotifier]：只在帧末由 Flutter 统一重建监听它的那几层，
  /// 不像 `setState` 那样把整棵首页连同卡片栅格一起重新 layout。
  void _setNegProgress(double value) {
    if (_negProgress.value == value) return;
    _negProgress.value = value;
  }

  /// 把累计下拉距离换算成带阻尼的开度（0..1）。
  double _pullProgress() =>
      ((_negPull / _negThreshold) * _negDamping).clamp(0.0, 1.0);

  /// 顶部下拉 / 上滑驱动负一屏（对齐微信首页下拉小程序面板）。
  ///
  /// - 关着：列表到顶还继续下拉，首页跟手（带阻尼），走到 [_negOpenAt]
  ///   直接弹开，不用等松手。
  /// - 开着：任意位置上滑立刻收起。
  bool _onScrollNotification(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      _negPull = 0;
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      if (_negAuto != null) return false;
      final d = n.scrollDelta ?? 0;
      if (d < 0 && _scroll.hasClients && _scroll.offset <= 0.5) {
        _negPull += -d;
        final next = _pullProgress();
        if (_negProgress.value < _negOpenAt && next >= _negOpenAt) {
          unawaited(Haptics.breath());
          _animateNegTo(1);
          return false;
        }
        _setNegProgress(next);
      } else if (d > 0 && _negProgress.value > 0.02) {
        _animateNegTo(0);
      }
    } else if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll != 0 &&
        _scroll.hasClients &&
        _scroll.offset <= 0.5) {
      if (_negAuto != null) return false;
      if (n.overscroll < 0) {
        _negPull += -n.overscroll;
        final next = _pullProgress();
        if (_negProgress.value < _negOpenAt && next >= _negOpenAt) {
          unawaited(Haptics.breath());
          _animateNegTo(1);
          return false;
        }
        _setNegProgress(next);
      } else if (n.overscroll > 0 && _negProgress.value > 0.02) {
        _animateNegTo(0);
      }
    } else if (n is ScrollEndNotification) {
      // 松手吸附：超过吸合线弹开，否则立刻收回（不停顿）。
      if (_negProgress.value > 0 && _negAuto == null) {
        _animateNegTo(_negProgress.value > _negSnapAt ? 1.0 : 0.0);
      }
      _negPull = 0;
    }
    return false;
  }

  /// 首页卡片的内容映射：栅格只负责位置，卡片自身保持原来的交互与动效。
  Widget _cardFor(HomeSlot slot) => switch (slot.id) {
    HomeCardId.checkin => const CheckinCard(),
    HomeCardId.todo => const TodoHomeCard(),
    HomeCardId.mood => const MoodHomeCard(),
    HomeCardId.ledger => const LedgerHomeCard(),
    HomeCardId.tingyu => const TingyuCard(),
    HomeCardId.fish => const FishCard(),
    HomeCardId.weather => const WeatherCard(),
    HomeCardId.cook => const CookCard(),
    HomeCardId.calendar => const CalendarCard(),
    HomeCardId.zodiac => const ZodiacCard(),
    HomeCardId.quote => const QuoteCard(),
    HomeCardId.cardCollection => const CardCollectionEntry(compact: true),
    HomeCardId.game => HomeGameCard(gameKey: slot.item ?? ''),
    HomeCardId.res => HomeResCard(item: slot.item ?? ''),
  };
}

/// 固定的顶部栏：账号入口 + 日期。
///
/// 上滑时卡片会盖住打招呼，但账号和日期始终留在顶部，不用跟着滚走。
/// 背景由底层的固定背景层统一提供（铺满全屏），这里只画内容。
class _HomeTopBar extends StatelessWidget {
  final double side;

  const _HomeTopBar({required this.side});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = context.app;
    final now = DateTime.now();
    final user = app.user;
    // user.av 可能是相对路径，必须过 Api.imageUrl 拼成完整地址，
    // 否则 Image.network 直接失败、errorBuilder 返回空——整个圆就是空白。
    final avatarUrl = Api.imageUrl(user?.av);
    // 顶栏不单独加底色：直接压在全屏背景上，白字靠背景罩面读得清；
    // 卡片从它下缘开始滚，不会叠上来。
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(side, AppSpacing.x1, side, 0),
        child: Row(
          children: [
            Expanded(
              child: Pressable(
                onTap: () => openMePage(context),
                hoverLift: 0,
                hoverShadow: false,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white54),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: avatarUrl.isEmpty
                            ? Center(
                                child:
                                    app.loggedIn &&
                                        user != null &&
                                        user.name.isNotEmpty
                                    ? Text(
                                        user.name[0],
                                        style: context.heading(
                                          size: CitroType.label,
                                          color: c.ink,
                                        ),
                                      )
                                    : AppIcon(
                                        strokeSvg(AppIcons.user, width: 2),
                                        size: 16,
                                        color: c.ink2,
                                      ),
                              )
                            : Image.network(
                                avatarUrl,
                                fit: BoxFit.cover,
                                cacheWidth: 96,
                                errorBuilder: (_, _, _) => Center(
                                  child: AppIcon(
                                    strokeSvg(AppIcons.user, width: 2),
                                    size: 16,
                                    color: c.ink2,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: AppSpacing.x1),
                      Flexible(
                        child: Text(
                          app.loggedIn && user != null && user.name.isNotEmpty
                              ? user.name
                              : '点击进入我的',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.body(
                            size: CitroType.label,
                            weight: CitroType.medium,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      AppIcon(
                        strokeSvg(AppIcons.chevronRight, width: 2),
                        size: 15,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            if (LanternApi.currentWindow() != null) ...[
              const LanternEntry(),
              const SizedBox(width: AppSpacing.x1),
            ],
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(28),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Center(
                child: Text(
                  '${now.month} 月 ${now.day} 日 · ${_weekdayLabel(now)}',
                  style: context.body(
                    size: CitroType.micro,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 英雄区的打招呼：跟着滚动走，上滑时被卡片盖掉。
class _HomeHeader extends StatelessWidget {
  final double side;

  const _HomeHeader({required this.side});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 6
        ? '夜深了'
        : now.hour < 11
        ? '早上好'
        : now.hour < 14
        ? '中午好'
        : now.hour < 18
        ? '下午好'
        : '晚上好';
    // 第二句按「月 + 日」轮换，不会每天都一样。
    const lines = [
      '今天也要开心',
      '慢慢来，比较快',
      '记得好好吃饭',
      '喝杯水，歇一下',
      '你已经很棒了',
      '给自己一点时间',
      '别急，事情会一件件好起来',
      '今天也是适合努力的一天',
      '把今天过好就够了',
      '照顾好自己',
    ];
    final line = lines[(now.month + now.day) % lines.length];
    return Padding(
      padding: EdgeInsets.fromLTRB(side, AppSpacing.x1, side, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            '$greeting，',
            textAlign: TextAlign.left,
            style: context.display(
              size: CitroType.hero,
              color: Colors.white,
              height: 1.12,
            ),
          ),
          Text(
            line,
            textAlign: TextAlign.left,
            style: context.display(
              size: CitroType.hero,
              color: Colors.white,
              height: 1.12,
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
        ],
      ),
    );
  }
}

/// 下半部分的卡片面板：顶部圆角 + 一条模糊过渡带。
///
/// 过渡带是透明的，[BackdropFilter] 采到的是上半部分的背景图，
/// 于是卡片区像是从背景里「长」出来的，而不是一刀切上去。
class _CardsPanel extends StatelessWidget {
  final Widget child;
  final double radiusTop;

  const _CardsPanel({required this.child, required this.radiusTop});

  @override
  Widget build(BuildContext context) {
    // 卡片区的底就是奶米 #F9EDD7，和上方背景图没盖到的区域连成一整块。
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radiusTop)),
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: context.c.bg)),
          child,
        ],
      ),
    );
  }
}

class LanternEntry extends StatelessWidget {
  const LanternEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => showLanternSheet(context),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.sm(c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              strokeSvg(AppIcons.moon, width: 2),
              size: 17,
              color: c.accent,
            ),
            const SizedBox(width: 6),
            Text(
              '灯谜',
              style: context.body(
                size: CitroType.label,
                weight: CitroType.medium,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final c = context.c;
    final w = state.weather;
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      onTap: () => showWeatherSheet(context),
      // 小尺寸 bento 格里整体等比缩小，避免固定内容把卡片撑爆。
      child: LayoutBuilder(
        builder: (context, cons) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: cons.maxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.sun, width: 2),
                      size: 15,
                      color: c.accent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '天气',
                      style: context.body(
                        size: CitroType.meta,
                        weight: CitroType.medium,
                        color: c.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    AppIcon(
                      strokeSvg(AppIcons.location, width: 2),
                      size: 13,
                      color: c.inkSoft,
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        // 窄卡片上按屏宽收紧，避免和左上角标签重叠。
                        maxWidth: math.min(
                          96.0,
                          MediaQuery.sizeOf(context).width * .22,
                        ),
                      ),
                      child: Text(
                        w.city.isEmpty ? '定位中…' : w.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(
                          size: CitroType.meta,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x2),
                // 温度数字在窄格里可能比卡片宽，等比缩小而不是硬撑爆。
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        w.emoji,
                        style: const TextStyle(fontSize: 36, height: 1),
                      ),
                      const SizedBox(width: AppSpacing.x1),
                      Text(
                        '${w.temp.round()}°',
                        style: context.hand(
                          size: 50,
                          weight: CitroType.strong,
                          color: c.ink,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  w.desc,
                  textAlign: TextAlign.center,
                  style: context.heading(
                    size: CitroType.titleLg,
                    color: c.ink2,
                  ),
                ),
                const SizedBox(height: AppSpacing.x2),
                const CitroDivider(),
                const SizedBox(height: AppSpacing.x2),
                Row(
                  children: [
                    Expanded(child: CitroStat('体感', '${w.feels.round()}°')),
                    Container(width: 1, height: 28, color: c.line),
                    Expanded(child: CitroStat('湿度', '${w.humidity}%')),
                  ],
                ),
                const SizedBox(height: AppSpacing.x1),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${w.updated} 更新',
                    style: context.body(
                      size: CitroType.small,
                      color: c.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CookCard extends StatelessWidget {
  const CookCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CitroCard(
      padding: const EdgeInsets.all(16),
      onTap: () {
        final rect = CitroCardFlight.rectOf(context);
        if (rect.isEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              settings: const RouteSettings(name: 'cook'),
              builder: (_) => const CookPage(),
            ),
          );
          return;
        }
        CitroCardMorph.pushPageSoft(
          context,
          source: rect,
          settings: const RouteSettings(name: 'cook'),
          builder: (_) => const CookPage(),
          snapshot: CitroCardFlight.snapshotOf(context, rect),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 96),
        // 窄格子（小屏手机 / 双栏内屏）里图标 + 箭头会挤爆一行，
        // 这时改成竖排：图标在上，两行文字在下。
        child: LayoutBuilder(
          builder: (context, cons) {
            final icon = Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.tintYellow,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.fork, width: 2),
                  size: 28,
                  color: c.accentInk,
                ),
              ),
            );
            final text = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '食谱日记',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.heading(size: CitroType.titleLg, color: c.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  '记录今天吃了什么',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: CitroType.meta, color: c.inkSoft),
                ),
              ],
            );
            if (cons.maxWidth < 190) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.tintYellow,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.fork, width: 2),
                          size: 20,
                          color: c.accentInk,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  text,
                ],
              );
            }
            return Row(
              children: [
                icon,
                const SizedBox(width: AppSpacing.x2),
                Expanded(child: text),
                const SizedBox(width: AppSpacing.x1),
                AppIcon(
                  strokeSvg(AppIcons.arrowRight, width: 2),
                  size: 18,
                  color: c.inkSoft,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class FishCard extends StatelessWidget {
  const FishCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final infoText = FishStateView.chipText;
    // 把「距休息日 N 天」里的数字单独放大，避免小卡片缩放后数字看不清。
    final match = RegExp(r'^(.*?)(\d+)(\s*天.*)$').firstMatch(infoText);
    final lead = match == null ? '' : match.group(1)!.trimRight();
    final days = match?.group(2);
    final tail = match == null ? '' : match.group(3)!.trimLeft();
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () => showFishSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(
                strokeSvg(AppIcons.wave, width: 2),
                size: 14,
                color: c.accent,
              ),
              const SizedBox(width: 5),
              Text(
                '摸鱼日历',
                style: context.body(
                  size: CitroType.meta,
                  weight: CitroType.medium,
                  color: c.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (lead.isNotEmpty)
                  Text(
                    lead,
                    style: context.body(
                      size: CitroType.label,
                      weight: CitroType.medium,
                      color: c.ink2,
                    ),
                  ),
                if (lead.isNotEmpty) const SizedBox(width: 4),
                Text(
                  days ?? infoText,
                  style: context.hand(
                    size: 30,
                    weight: CitroType.strong,
                    color: c.accent,
                    height: 1,
                  ),
                ),
                if (tail.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    tail,
                    style: context.body(
                      size: CitroType.label,
                      weight: CitroType.medium,
                      color: c.ink2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CalendarCard extends StatefulWidget {
  /// 计划页只需要「今天」：大日期 + 星期 + 农历，不铺整月格子。
  final bool compact;

  const CalendarCard({super.key, this.compact = false});

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  int _monthOffset = 0;

  @override
  void initState() {
    super.initState();
    CalendarStore.instance.ensureInit();
  }

  void _open(BuildContext context) {
    final rect = CitroCardFlight.rectOf(context);
    if (rect.isEmpty) {
      Navigator.of(context).pushNamed('/calendar');
      return;
    }
    CitroCardMorph.pushPageSoft(
      context,
      source: rect,
      settings: const RouteSettings(name: '/calendar'),
      builder: (_) => const CalendarPage(),
      snapshot: CitroCardFlight.snapshotOf(context, rect),
    );
  }

  /// 日期上是否有倒数日 / 纪念日，供月历格显示小圆点。
  bool _hasMark(DateTime date) {
    for (final mark in CalendarStore.instance.marks) {
      if (CalendarDates.hits(mark, date)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final current = DateTime.now();
    final now = DateTime(current.year, current.month + _monthOffset, 1);
    final first = DateTime(now.year, now.month, 1);
    final startWd = first.weekday % 7;
    final days = DateTime(now.year, now.month + 1, 0).day;
    final prevDays = DateTime(now.year, now.month, 0).day;
    const wd = ['日', '一', '二', '三', '四', '五', '六'];
    final cells = <_CalCellData>[];
    for (var i = 0; i < 42; i++) {
      int day;
      int cy = now.year, cm = now.month;
      bool dim = false;
      if (i < startWd) {
        day = prevDays - startWd + 1 + i;
        dim = true;
        cm = now.month == 1 ? 12 : now.month - 1;
        if (now.month == 1) cy = now.year - 1;
      } else if (i >= startWd + days) {
        day = i - startWd - days + 1;
        dim = true;
        cm = now.month == 12 ? 1 : now.month + 1;
        if (now.month == 12) cy = now.year + 1;
      } else {
        day = i - startWd + 1;
      }
      final date = DateTime(cy, cm, day);
      final isToday =
          _monthOffset == 0 &&
          !dim &&
          day == current.day &&
          cy == current.year &&
          cm == current.month;
      cells.add(_CalCellData(day, date, dim, isToday));
    }
    return ListenableBuilder(
      listenable: CalendarStore.instance,
      builder: (context, _) => CitroCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        onTap: () => _open(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 3×3 起的小卡片只保留「今天」：大日期 + 星期 + 农历，
            // 不再铺整月日期格，避免小尺寸里 42 个日期挤成一团。
            final mini =
                widget.compact ||
                constraints.maxHeight < 210 ||
                constraints.maxWidth < 210;
            if (mini) return _todayOnly(context, current);
            final fill = constraints.hasBoundedHeight;
            // 迷你尺寸：收紧标题与字号，把空间留给 6 行日期。
            final dense =
                constraints.maxHeight < 260 || constraints.maxWidth < 240;
            Widget row(int r) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < 7; col++) ...[
                  if (col > 0) const SizedBox(width: 2),
                  Expanded(
                    child: _CalCell(
                      day: cells[r * 7 + col].day,
                      date: cells[r * 7 + col].date,
                      dim: cells[r * 7 + col].dim,
                      today: cells[r * 7 + col].today,
                      dot: _hasMark(cells[r * 7 + col].date),
                      fill: fill,
                      dense: dense,
                    ),
                  ),
                ],
              ],
            );
            final gridRows = <Widget>[
              for (var r = 0; r < 6; r++)
                if (fill)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: r == 0 ? 0 : 2),
                      child: row(r),
                    ),
                  )
                else
                  SizedBox(
                    height: 44,
                    child: Padding(
                      padding: EdgeInsets.only(top: r == 0 ? 0 : 2),
                      child: row(r),
                    ),
                  ),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '日历',
                      style: context.body(
                        size: dense ? CitroType.small : CitroType.meta,
                        weight: CitroType.medium,
                        color: c.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    Pressable(
                      onTap: () => setState(() => _monthOffset--),
                      hoverLift: 0,
                      hoverShadow: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.chevron_left_rounded,
                          size: dense ? 18 : 22,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                    Text(
                      dense ? '${now.month}月' : '${now.year}年${now.month}月',
                      style: context.hand(
                        size: dense ? CitroType.label : CitroType.bodyLg,
                        color: c.ink,
                      ),
                    ),
                    Pressable(
                      onTap: () => setState(() => _monthOffset++),
                      hoverLift: 0,
                      hoverShadow: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: dense ? 18 : 22,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x1),
                Row(
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: dense ? 2 : 4),
                          child: Text(
                            wd[i],
                            textAlign: TextAlign.center,
                            style: context.body(
                              size: dense ? CitroType.small : CitroType.label,
                              weight: CitroType.medium,
                              color: (i == 0 || i == 6) ? c.accent : c.inkSoft,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (fill)
                  Expanded(child: Column(children: gridRows))
                else
                  ...gridRows,
              ],
            );
          },
        ),
      ),
    );
  }

  /// 迷你卡片：参照系统日历小组件的排版，只显示今天。
  ///
  /// 顶部年月、左侧超大日期、底部事件卡；事件卡第一行放节日 / 节气 / 今日
  /// 标记，第二行补上公历日期与农历，保证小卡也看得见农历。
  Widget _todayOnly(BuildContext context, DateTime today) {
    final c = context.c;
    final lunar = lunarOf(today);
    final fid = festivalIdOf(today);
    final term = termToday(today);
    final marks = CalendarStore.instance.todayMarks(today);
    final headline = fid != null
        ? festivalName(fid)
        : (term ??
              (marks.isNotEmpty ? marks.first.title : weekdayChinese(today)));
    final lunarDay = lunar != null ? kLunarDayNames[lunar.day - 1] : '';
    String two(int value) => value.toString().padLeft(2, '0');
    final yearMonth =
        '${today.year}/${two(today.month)}'
        '${lunarDay.isEmpty ? '' : ' · $lunarDay'}';
    final dateLine = '${today.month}月${today.day}日';
    final markLabel = marks.isNotEmpty
        ? CalendarDates.labelFor(marks.first, today)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          yearMonth,
          style: context.body(size: CitroType.small, color: c.inkSoft),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${today.day}',
                style: context.hand(
                  size: CitroType.display,
                  weight: CitroType.strong,
                  color: c.ink,
                  height: .95,
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: CitroType.caption,
                        weight: CitroType.medium,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (markLabel != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      markLabel,
                      maxLines: 1,
                      style: context.body(
                        size: CitroType.micro,
                        color: c.stamp,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 1),
              Text(
                dateLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: CitroType.micro, color: c.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalCellData {
  final int day;
  final DateTime date;
  final bool dim;
  final bool today;
  const _CalCellData(this.day, this.date, this.dim, this.today);
}

class _CalCell extends StatelessWidget {
  final int day;
  final DateTime date;
  final bool dim;
  final bool today;
  final bool fill;

  /// 该日期是否有倒数日 / 纪念日，有则在日期右上角点一颗小圆点。
  final bool dot;

  /// 迷你日历：缩小日期与农历字号，隐藏次要标签。
  final bool dense;
  const _CalCell({
    required this.day,
    required this.date,
    required this.dim,
    required this.today,
    this.dot = false,
    this.fill = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    String? label;
    Color? labelColor;
    if (!dim) {
      final fid = festivalIdOf(date);
      final term = termToday(date);
      if (fid != null) {
        label = festivalName(fid);
        labelColor = c.accent;
      } else if (term != null) {
        label = term;
        labelColor = c.mintInk;
      } else {
        final lu = lunarOf(date);
        if (lu != null) {
          label = lu.day == 1
              ? lu.name
              : lu.name.substring(math.max(0, lu.name.length - 2));
        }
      }
    }
    final dayColor = today
        ? c.onAccent
        : (dim ? c.inkSoft.withAlpha(140) : c.ink);
    final subColor = today
        ? c.onAccent
        : (labelColor ?? c.inkSoft).withAlpha(dim ? 140 : 255);
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      // 日历格高度随卡片尺寸变化，用 scaleDown 兜底，避免字体
      // 行高在不同平台相差半像素时出现 RenderFlex 溢出。
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: context.hand(
                  size: dense
                      ? CitroType.body
                      : (fill ? CitroType.titleLg : CitroType.title),
                  color: dayColor,
                  height: 1.05,
                ),
              ),
              if (dot)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: today
                          ? c.onAccent
                          : (dim ? c.accent.withAlpha(140) : c.accent),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(
                  size: dense ? CitroType.micro : CitroType.small,
                  color: subColor,
                  height: 1.15,
                ),
              ),
            ),
        ],
      ),
    );
    return Container(
      height: fill ? null : 44,
      padding: EdgeInsets.only(top: fill ? 2 : 3, bottom: fill ? 2 : 2),
      decoration: today
          ? BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(fill ? 12 : 10),
            )
          : null,
      // 非本月日期在上面的颜色里已经压暗，不再额外套 Opacity，
      // 避免整个日期格多一层离屏合成。
      child: content,
    );
  }
}

class ZodiacCard extends StatelessWidget {
  const ZodiacCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final c = context.c;
    final tone = _ZodiacTone.of(c);
    final sign = zodiacById(state.zodiacSign);
    final f = state.zodiacFortune;
    final now = DateTime.now();
    final dateText =
        '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} ${weekdayChinese(now)}';
    return CitroCard(
      radius: CitroColors.radii.card,
      padding: EdgeInsets.zero,
      // 和全站卡片同一个表面，只留一层很淡的粉彩渐变交代「星象」的情绪。
      color: c.surface,
      border: Border.all(color: c.line),
      shadow: CitroColors.shadows.card(c),
      clip: Clip.antiAlias,
      onTap: () => showZodiacModal(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : 272.0;
          final maxW = constraints.maxWidth;
          // 232 太窄，320 以下（半宽卡片 / 小屏）就走紧凑头，
          // 否则「DAILY ZODIAC」+ 日期胶囊会把行撑爆。
          final micro = maxW < 320 || cardHeight < 240;
          final horizontal = maxW >= 316 && cardHeight >= 238;
          final tall = cardHeight >= 342;
          return SizedBox(
            width: constraints.maxWidth,
            height: cardHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            c.tintYellow.withAlpha(80),
                            c.surface,
                            c.tintBlue.withAlpha(60),
                          ],
                          stops: const [0, .5, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                if (sign != null)
                  Positioned(
                    right: -8,
                    top: 20,
                    child: IgnorePointer(
                      child: Text(
                        sign.symbol,
                        style: TextStyle(
                          fontFamily: AppFonts.rounded,
                          fontSize: micro ? 56 : 76,
                          height: 1,
                          color: tone.watermark,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    micro ? 12 : 14,
                    16,
                    micro ? 12 : 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(context, dateText, tone, micro: micro),
                      SizedBox(height: micro ? 6 : 8),
                      Expanded(
                        child: sign == null
                            ? _picker(context, tone, micro: micro)
                            : _body(
                                context,
                                state,
                                sign,
                                f,
                                tone,
                                micro: micro,
                                horizontal: horizontal,
                                tall: tall,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(
    BuildContext context,
    String dateText,
    _ZodiacTone tone, {
    required bool micro,
  }) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: tone.chipBg, shape: BoxShape.circle),
          child: Center(
            child: Text(
              '✦',
              style: TextStyle(fontSize: 9, height: 1, color: tone.accent),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '今日星象',
          style: context.heading(
            size: micro ? 11.5 : 12.5,
            color: tone.accentInk,
            letterSpacing: 1.1,
          ),
        ),
        if (!micro) ...[
          const SizedBox(width: 8),
          Text(
            'DAILY ZODIAC',
            style: context.body(
              size: 9,
              weight: FontWeight.w700,
              color: tone.inkSoft.withAlpha(180),
              letterSpacing: 1.4,
            ),
          ),
        ],
        const Spacer(),
        if (!micro)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: tone.chipBg,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: tone.chipLine),
            ),
            child: Text(
              dateText,
              style: context.body(
                size: 9,
                color: tone.inkSoft,
                letterSpacing: .3,
              ),
            ),
          ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    AppState state,
    ZodiacSign sign,
    ZodiacFortune? f,
    _ZodiacTone tone, {
    required bool micro,
    required bool horizontal,
    required bool tall,
  }) {
    final ringSize = micro
        ? 54.0
        : (tall ? (horizontal ? 96.0 : 88.0) : (horizontal ? 84.0 : 76.0));
    if (micro) {
      return Row(
        children: [
          _score(f, tone, size: ringSize),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sign.symbol} ${sign.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.heading(
                    size: 18,
                    color: tone.ink,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  f == null
                      ? (state.zodiacError != null ? '星语生成失败' : '星语生成中…')
                      : '✦ ${f.tag}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: 10,
                    color: f == null ? tone.inkSoft : tone.accentInk,
                  ),
                ),
                if (f != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${sign.range} · ${sign.element}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(size: 9, color: tone.inkSoft),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }
    if (horizontal) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: ringSize + 18,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _score(f, tone, size: ringSize),
                const SizedBox(height: 6),
                Text(
                  '综合运势',
                  style: context.body(
                    size: 9,
                    weight: FontWeight.w700,
                    color: tone.inkSoft,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${sign.symbol} ${sign.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.heading(
                    size: 20,
                    color: tone.ink,
                    height: 1.1,
                  ),
                ),
                Text(
                  '${sign.range} · ${sign.element}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: 10, color: tone.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, color: tone.line),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _tagPill(context, state, f, tone),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        f?.text ?? _pendingText(state),
                        maxLines: tall ? 6 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(
                          size: 13,
                          color: tone.ink2,
                          height: 1.62,
                        ),
                      ),
                    ),
                  ),
                ),
                if (tall && f != null) ...[
                  const SizedBox(height: 6),
                  _luckChips(f, tone),
                ],
                if (f != null) ...[
                  const SizedBox(height: 8),
                  _metrics(f, tone, compact: !tall),
                ],
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _score(f, tone, size: ringSize),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${sign.symbol} ${sign.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.heading(
                      size: 22,
                      color: tone.ink,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${sign.range} · ${sign.element}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(size: 10, color: tone.inkSoft),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _tagPill(context, state, f, tone),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (f != null) ...[
          Expanded(
            child: ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  f.text,
                  maxLines: tall ? 5 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: 13, color: tone.ink2, height: 1.62),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _metrics(f, tone, compact: !tall),
        ] else
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                _pendingText(state),
                style: context.body(
                  size: 12,
                  color: state.zodiacError != null ? tone.error : tone.inkSoft,
                  height: 1.55,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _pendingText(AppState state) =>
      state.zodiacError ?? (state.zodiacLoading ? '星语生成中…' : '点开卡片生成今日星语');

  Widget _score(ZodiacFortune? f, _ZodiacTone tone, {required double size}) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ZodiacScorePainter(
          score: f?.score,
          accent: tone.accent,
          track: tone.chipLine,
          halo: tone.glow,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (f != null) ...[
                Text(
                  '${f.score}',
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: size * .31,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: tone.accentInk,
                  ),
                ),
                Text(
                  '综合',
                  style: TextStyle(
                    fontFamily: AppFonts.rounded,
                    fontFamilyFallback: AppFonts.bodyFallback,
                    fontSize: math.max(7, size * .105),
                    height: 1.25,
                    letterSpacing: 1,
                    color: tone.inkSoft,
                  ),
                ),
              ] else
                Text(
                  '✦',
                  style: TextStyle(fontSize: size * .3, color: tone.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tagPill(
    BuildContext context,
    AppState state,
    ZodiacFortune? f,
    _ZodiacTone tone,
  ) {
    final text = f == null
        ? (state.zodiacError != null ? '星语生成失败' : '星语生成中…')
        : '✦ ${f.tag}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: tone.chipBg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tone.chipLine),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.body(
          size: 11,
          weight: FontWeight.w700,
          color: f == null ? tone.inkSoft : tone.accentInk,
          letterSpacing: .4,
        ),
      ),
    );
  }

  Widget _metrics(ZodiacFortune f, _ZodiacTone tone, {required bool compact}) {
    return Row(
      children: [
        _stat('爱情', f.love, compact, tone),
        _metricDivider(tone),
        _stat('事业', f.work, compact, tone),
        _metricDivider(tone),
        _stat('财运', f.wealth, compact, tone),
        _metricDivider(tone),
        _stat('健康', f.health, compact, tone),
      ],
    );
  }

  Widget _stat(String label, int value, bool compact, _ZodiacTone tone) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontFamily: AppFonts.kalam,
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: tone.accentInk,
                  ),
                ),
                Text(
                  '分',
                  style: TextStyle(
                    fontFamily: AppFonts.noto,
                    fontSize: 9,
                    height: 1,
                    color: tone.inkSoft,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 2 : 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontFamilyFallback: AppFonts.bodyFallback,
                fontSize: 9,
                height: 1.2,
                color: tone.inkSoft,
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: value.clamp(0, 100) / 100,
                  minHeight: 2.4,
                  backgroundColor: tone.accent.withAlpha(24),
                  valueColor: AlwaysStoppedAnimation(tone.accent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricDivider(_ZodiacTone tone) =>
      Container(width: 1, height: 18, color: tone.line);

  Widget _luckChips(ZodiacFortune f, _ZodiacTone tone) => Wrap(
    spacing: 5,
    runSpacing: 4,
    children: [
      _luckChip('幸运色', f.color, tone),
      _luckChip('幸运数', f.number, tone),
      _luckChip('幸运物', f.item, tone),
    ],
  );

  Widget _luckChip(String label, String value, _ZodiacTone tone) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: tone.chipBg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: tone.chipLine),
    ),
    child: Text(
      '$label $value',
      style: TextStyle(
        fontFamily: AppFonts.noto,
        fontFamilyFallback: AppFonts.bodyFallback,
        fontSize: 9,
        height: 1.2,
        color: tone.inkSoft,
      ),
    ),
  );

  Widget _picker(
    BuildContext context,
    _ZodiacTone tone, {
    required bool micro,
  }) {
    if (micro) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('还没有本命星座', style: context.body(size: 11, color: tone.inkSoft)),
            const SizedBox(height: 8),
            Pressable(
              onTap: () => showZodiacModal(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tone.chipBg,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: tone.chipLine),
                ),
                child: Text(
                  '选择星座 →',
                  style: context.body(
                    size: 11,
                    weight: FontWeight.w700,
                    color: tone.accentInk,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 290;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '选一个本命星座，解锁今日星象',
              style: context.body(
                size: compact ? 10.5 : 11.5,
                color: tone.inkSoft,
              ),
            ),
            SizedBox(height: compact ? 6 : 8),
            Wrap(
              spacing: compact ? 4 : 6,
              runSpacing: compact ? 4 : 6,
              alignment: WrapAlignment.center,
              children: [
                for (final z in kZodiacSigns)
                  Pressable(
                    onTap: () => showZodiacModal(context),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 8,
                        vertical: compact ? 4 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: tone.chipBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tone.chipLine),
                      ),
                      child: Text(
                        '${z.symbol} ${z.name}',
                        style: context.body(
                          size: compact ? 9.5 : 10.5,
                          color: tone.accentInk,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: compact ? 5 : 7),
            Text(
              '点击选择 →',
              style: context.body(
                size: CitroType.small,
                weight: CitroType.medium,
                color: tone.accentInk,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 星象卡的纸面配色：浅色跟随纸卡，深色跟随暗色主题，保持同一套占星符号。
class _ZodiacTone {
  const _ZodiacTone({
    required this.top,
    required this.mid,
    required this.bottom,
    required this.accent,
    required this.accentInk,
    required this.ink,
    required this.ink2,
    required this.inkSoft,
    required this.line,
    required this.chipBg,
    required this.chipLine,
    required this.watermark,
    required this.glow,
    required this.border,
    required this.error,
  });

  final Color top;
  final Color mid;
  final Color bottom;
  final Color accent;
  final Color accentInk;
  final Color ink;
  final Color ink2;
  final Color inkSoft;
  final Color line;
  final Color chipBg;
  final Color chipLine;
  final Color watermark;
  final Color glow;
  final Color border;
  final Color error;

  /// 星象卡不再自带一套彩色渐变，改为和全站卡片同表面 + 同 token。
  factory _ZodiacTone.of(CitroColors c) => _ZodiacTone(
    top: c.surface,
    mid: c.surface,
    bottom: c.surface,
    accent: c.accent,
    accentInk: c.accentInk,
    ink: c.ink,
    ink2: c.ink2,
    inkSoft: c.inkSoft,
    line: c.line,
    chipBg: c.tintYellow,
    chipLine: c.line,
    watermark: c.accent.withAlpha(16),
    glow: c.accent.withAlpha(18),
    border: c.line,
    error: c.stamp,
  );
}

/// 金色刻度环：12 格刻度 + 进度弧 + 中心光面。
class _ZodiacScorePainter extends CustomPainter {
  const _ZodiacScorePainter({
    this.score,
    required this.accent,
    required this.track,
    required this.halo,
  });

  final int? score;
  final Color accent;
  final Color track;
  final Color halo;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [halo, halo.withAlpha(0)],
        stops: const [.44, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius + 3));
    canvas.drawCircle(center, radius + 3, glow);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..color = track.withAlpha(70);
    canvas.drawCircle(center, radius - 1.6, trackPaint);

    final tick = Paint()
      ..strokeWidth = .9
      ..strokeCap = StrokeCap.round
      ..color = track.withAlpha(85);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6 - math.pi / 2;
      final inner = radius - 8;
      final outer = radius - 4;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * inner,
        center + Offset(math.cos(a), math.sin(a)) * outer,
        tick,
      );
    }

    final pct = (score ?? 0).clamp(0, 100) / 100;
    if (score != null) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round
        ..color = accent;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 1.6),
        -math.pi / 2,
        math.pi * 2 * pct,
        false,
        arc,
      );
    }

    canvas.drawCircle(
      center,
      radius - 9,
      Paint()..color = accent.withAlpha(12),
    );
    canvas.drawCircle(
      center,
      radius - 9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = track.withAlpha(70),
    );
  }

  @override
  bool shouldRepaint(covariant _ZodiacScorePainter oldDelegate) =>
      oldDelegate.score != score ||
      oldDelegate.accent != accent ||
      oldDelegate.track != track ||
      oldDelegate.halo != halo;
}

class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final q = kQuotes[dayOfYear % kQuotes.length];
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () =>
          copyText('${q.cn} — ${q.en}', context: context, tip: '已复制每日一言'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 112),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 250;
            final body = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.book, width: 2),
                      size: 13,
                      color: c.accent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '每日一言',
                      style: context.body(
                        size: CitroType.micro,
                        weight: CitroType.medium,
                        color: c.inkSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  '「${q.cn}」',
                  textAlign: TextAlign.center,
                  locale: const Locale('zh', 'CN'),
                  style: context.heading(
                    size: narrow ? CitroType.title : CitroType.titleLg,
                    color: c.ink,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  '— ${q.en}',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: CitroType.meta,
                    color: c.inkSoft,
                    height: 1.45,
                  ),
                ),
              ],
            );
            // 引文长短不一，整块等比缩小，宁可字小一点也不撑爆卡片。
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: body,
            );
          },
        ),
      ),
    );
  }
}
