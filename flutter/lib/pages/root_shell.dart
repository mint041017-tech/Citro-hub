import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../overlays/card_draw.dart';
import '../overlays/update_dialog.dart';
import '../perf_probe.dart';
import '../services/notifications.dart';
import '../services/orientation.dart';
import '../services/platform.dart' as platform;
import '../services/web_route.dart';
import '../state/app_state.dart';
import '../theme/breakpoints.dart';
import '../theme/motion.dart';
import '../widgets/tab_bar.dart';
import '../games/gbrake_web.dart';
import '../widgets/tablet_shell.dart';
import 'home_page.dart';
import 'games_page.dart';
import 'community_page.dart';
import 'me_page.dart';
import 'res_page.dart';

class RootShell extends StatefulWidget {
  final int initialIndex;
  const RootShell({super.key, this.initialIndex = 0});

  @override
  State<RootShell> createState() => RootShellState();
}

class RootShellState extends State<RootShell> with TickerProviderStateMixin {
  static const double _sidebarWidth = 208;
  static RootShellState? instance;
  int index = 0;
  // 首帧只构建当前页；其余页首次切到时才挂载，避免社区页在后台拉动态/起轮询。
  late final List<bool> _visited;
  late final AnimationController _tabAnim;
  double _dir = 1;
  Timer? _updateTimer;
  Timer? _cardPromptTimer;
  double _swipeDx = 0;

  /// Windows 多一个「资源」槽位，其余端（手机 / Web）是四格：
  /// 首页、游戏、社区、我的。「我的」始终在最后一个。
  static bool get _showResources => !kIsWeb && platform.isWindows;
  static int get _tabCount => _showResources ? 5 : 4;

  @override
  void initState() {
    super.initState();
    instance = this;
    index = widget.initialIndex.clamp(0, _tabCount - 1);
    _visited = List<bool>.generate(5, (i) => i == index);
    AppState.instance.cardPromptTick.addListener(_onCardPrompt);
    _tabAnim = AnimationController(
      vsync: this,
      duration: CitroMotion.tab,
      value: 1,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmAssets());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PerfProbe.homeReady(switchTo),
    );
    // 让启动路径先跑完，避免更新检查与首帧、权限申请抢带宽/主线程。
    _updateTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) unawaited(checkForUpdates(context, manual: false));
    });
  }

  /// 启动完成、网络请求也让出主线程之后，再预解码常用小图。
  /// 这样打开星象 / AI 对话时不会在首帧临时解码 9 张猫图。
  Future<void> _warmAssets() async {
    if (kIsWeb) return;
    await Future<void>.delayed(
      Duration(milliseconds: !kIsWeb && platform.isWindows ? 5000 : 2200),
    );
    if (!mounted) return;
    final warm = <String>[
      'assets/images/logo.webp',
      for (var i = 23757; i <= 23765; i++) 'assets/images/cats/$i.webp',
    ];
    for (final asset in warm) {
      if (!mounted) return;
      try {
        await precacheImage(
          ResizeImage(
            AssetImage(asset),
            width: asset.contains('/cats/') ? 288 : 420,
          ),
          context,
        );
      } catch (_) {}
    }
    // 极限刹车是内嵌原版（约 800KB 内联 HTML）：空闲时先拼好，
    // 首次打开不再现场读包 + 拼接。
    unawaited(prewarmBrakeBundle());
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    await AppState.instance.refreshWeatherWithLocation(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    await Notifications.ensureInit();
    final enabled = await Notifications.areEnabled();
    if (!enabled) await AppState.instance.setNotificationsEnabled(false);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _cardPromptTimer?.cancel();
    AppState.instance.cardPromptTick.removeListener(_onCardPrompt);
    _tabAnim.dispose();
    if (instance == this) instance = null;
    super.dispose();
  }

  void _onCardPrompt() {
    _cardPromptTimer?.cancel();
    _cardPromptTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final state = AppState.instance;
      if (state.cardCredits <= 0 || state.popupActive) return;
      unawaited(showCardDrawPrompt(context, credits: state.cardCredits));
    });
  }

  Widget _withSwipe(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _swipeDx = 0,
      onHorizontalDragUpdate: (details) => _swipeDx += details.delta.dx,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (_swipeDx <= -46 || v < -380) {
          switchTo(index + 1);
        } else if (_swipeDx >= 46 || v > 380) {
          switchTo(index - 1);
        }
        _swipeDx = 0;
      },
      child: child,
    );
  }

  void switchTo(int i) => unawaited(_switchTab(i));

  /// 壳内 Tab 切换：新旧两页同时在场，旧页反向让位、新页推入。
  ///
  /// 四端共一套节奏（仅时长/位移按端缩放），Web 也不再整页 push，
  /// 导航栏和页面壳不会跟着重挂载，切换因此连贯不割裂。
  Future<void> _switchTab(int i) async {
    if (i == index || i < 0 || i >= _tabCount) return;
    if (!kIsWeb && (platform.isAndroid || platform.isIOS)) {
      HapticFeedback.selectionClick();
    }
    // 可中断：上一段还没走完就收尾，再从当前位置开始新的一段。
    if (_tabAnim.isAnimating) _tabAnim.value = 1;
    _dir = i > index ? 1.0 : -1.0;
    final reduce = CitroMotion.reduced(context);
    PerfProbe.beginFrameCollection();
    setState(() {
      _visited[i] = true;
      index = i;
    });
    if (kIsWeb) {
      syncWebRoute(const ['/home', '/games', '/trash', '/me'][i]);
    }
    if (reduce) {
      _tabAnim.value = 1;
      PerfProbe.endFrameCollection('tab_$i');
      return;
    }
    _tabAnim.duration = CitroMotion.tabLength;
    await _tabAnim.forward(from: 0);
    if (!mounted) return;
    if (PerfProbe.enabled) {
      // FrameTiming 在帧结束后才批量回传，给采样回调留一帧时间。
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    PerfProbe.endFrameCollection('tab_$i');
  }

  Widget _pageStack() {
    return AnimatedBuilder(
      animation: _tabAnim,
      builder: (context, _) {
        final t = CitroMotion.easeOut.transform(_tabAnim.value);
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            for (var i = 0; i < 5; i++)
              _visited[i] ? _pageLayer(i, t) : const SizedBox.shrink(),
          ],
        );
      },
    );
  }

  Widget _pageLayer(int i, double t) {
    final active = i == index;
    // 旧页立即撤下：屏幕上永远只出现当前页，不会残留上一页的一条。
    // 新页只做 10px 归位 + 轻微淡入——足够表达"切换发生了"，
    // 又不会出现两页并存、残影或空白条。
    final settling = active && t < 1;
    final dx = settling ? _dir * 8 * (1 - t) : 0.0;
    final dy = settling ? 6 * (1 - t) : 0.0;
    final scale = settling ? .992 + .008 * t : 1.0;
    final opacity = settling ? .82 + .18 * t : 1.0;
    // 关键：隐藏页和显示页必须返回同一棵 widget 结构，否则 Flutter 会整页重建，
    // 每次切 Tab 都重放入场动画并闪一下。
    return Positioned.fill(
      child: Offstage(
        offstage: !active,
        child: IgnorePointer(
          ignoring: !active,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Transform.translate(
                offset: Offset(dx, dy),
                child: RepaintBoundary(
                  child: TickerMode(enabled: active, child: _pageAt(i)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageAt(int i) {
    switch (i) {
      case 1:
        return const GamesPage();
      case 2:
        return const CommunityPage();
      case 3:
        return _showResources
            ? const ResPage(embedded: true)
            : const MePage(embedded: true);
      case 4:
        return const MePage(embedded: true);
      default:
        return HomePage(onSwitchTab: switchTo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: kIsWeb || index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!kIsWeb && !didPop && index != 0) switchTo(0);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          unawaited(CitroOrientation.sync(size));
          final desktop = kIsWeb && size.width >= 1025;
          final duo =
              !kIsWeb && (CitroOrientation.isDuo || CitroForm.duoDevice(size));
          if (duo) {
            final media = MediaQuery.of(context);
            final railWidth = media.padding.right > 84
                ? media.padding.right
                : 84.0;
            final contentMedia = media.copyWith(
              padding: media.padding.copyWith(right: 0),
              viewPadding: media.viewPadding.copyWith(right: 0),
            );
            return Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: MediaQuery(
                      data: contentMedia,
                      child: CitroLayoutScope(
                        contentWidth: size.width - railWidth,
                        tabletNav: true,
                        duo: true,
                        child: _pageStack(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: railWidth,
                    child: CitroDuoRightRail(
                      index: index,
                      onChanged: switchTo,
                      topInset: CitroForm.duoRailTopInset(size),
                    ),
                  ),
                ],
              ),
            );
          }
          final tablet = !desktop && !kIsWeb && CitroForm.tabletNav(size);
          if (tablet) {
            return Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _sidebarWidth,
                    child: CitroTabletSidebar(
                      index: index,
                      showResources: platform.isWindows,
                      onChanged: switchTo,
                    ),
                  ),
                  Expanded(
                    child: CitroLayoutScope(
                      contentWidth: constraints.maxWidth - _sidebarWidth,
                      tabletNav: true,
                      duo: duo,
                      child: _pageStack(),
                    ),
                  ),
                ],
              ),
            );
          }
          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: CitroLayoutScope(
                    contentWidth: constraints.maxWidth,
                    tabletNav: false,
                    duo: duo,
                    child: _withSwipe(_pageStack()),
                  ),
                ),
                if (!desktop && !keyboardOpen)
                  CitroTabBar(index: index, onChanged: switchTo),
              ],
            ),
          );
        },
      ),
    );
  }
}
