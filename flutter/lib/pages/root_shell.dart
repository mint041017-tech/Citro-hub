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
import '../todo/todo_store.dart';
import '../ledger/ledger_store.dart';
import '../calendar/calendar_store.dart';
import '../widgets/home_layout.dart';
import '../widgets/tab_bar.dart';
import '../state/negative_screen.dart';
import '../games/gbrake_web.dart';
import '../widgets/tablet_shell.dart';
import '../overlays/ai_chat.dart';
import 'plan_page.dart';
import 'home_page.dart';
import 'games_page.dart';
import 'community_page.dart';

class RootShell extends StatefulWidget {
  final int initialIndex;
  const RootShell({super.key, this.initialIndex = 0});

  @override
  State<RootShell> createState() => RootShellState();
}

class RootShellState extends State<RootShell> with TickerProviderStateMixin {
  static const double _sidebarWidth = 208;
  static RootShellState? instance;

  /// 登录页完成后才挂载壳：登录那一刻壳还没在，需要补一次云端对齐。
  /// 由 SplashGate 在登录成功时置位，壳挂载后读取并清零。
  static bool syncOnNextMount = false;
  int index = 0;
  // 首帧只构建当前页；其余页首次切到时才挂载，避免社区页在后台拉动态/起轮询。
  late final List<bool> _visited;
  late final List<Widget> _pages;
  late final AnimationController _tabAnim;
  double _dir = 1;

  /// 切页动画期间仍留在 Stack 里的上一页，动画结束后移除。
  ///
  /// 旧页在同一帧直接 Offstage 时，交接的那一帧上新旧两页都不在，
  /// 会露出 Scaffold 底色（首页有背景图时尤其明显）。留着它交叉淡入，
  /// 切换才有「从这里到那里」的连续感。
  int? _prevIndex;
  Timer? _updateTimer;
  final List<Timer> _warmTimers = <Timer>[];
  Timer? _cardPromptTimer;
  double _swipeDx = 0;
  bool _wasLoggedIn = false;
  Size? _orientationSize;

  /// 四格导航：首页、游戏、社区、自定义（默认待办，长按可切模块）。
  /// 资源库收进首页下拉负一屏与「我的」，不再占独立 Tab。
  static int get _tabCount => 4;

  /// 当前页是否自己渲染左侧 rail。计划页把待办/记账/日历竖排在一页里，
  /// 不带 rail，所以恒为 false。
  bool get _pageOwnsRail => false;

  @override
  void initState() {
    super.initState();
    instance = this;
    index = widget.initialIndex.clamp(0, _tabCount - 1);
    _visited = List<bool>.generate(_tabCount, (i) => i == index);
    // 页面 widget 只创建一次：切 Tab 时不再生成新的 HomePage/CommunityPage 实例，
    // 已挂载的页面不会因为父级 setState 而整棵 rebuild。
    _pages = List<Widget>.generate(_tabCount, _pageAt);
    AppState.instance.cardPromptTick.addListener(_onCardPrompt);
    _wasLoggedIn = AppState.instance.loggedIn;
    AppState.instance.addListener(_onAuthChanged);
    if (_wasLoggedIn && syncOnNextMount) {
      // 强制登录后，壳是登录成功才挂载的：登录那一刻壳还没在，
      // 这里补一次云端对齐，否则首页布局 / 待办 / 记账 / 日历都不同步。
      syncOnNextMount = false;
      unawaited(HomeLayoutStore.instance.syncFromAccount(force: true));
      unawaited(TodoStore.instance.syncFromAccount(force: true));
      unawaited(LedgerStore.instance.syncFromAccount(force: true));
      unawaited(CalendarStore.instance.syncFromAccount(force: true));
    }
    // 负一屏的展开信号：先回到首页，HomePage 自己会把负一屏展开。
    negativeScreenSignal.addListener(_onNegativeScreenRequest);
    _tabAnim = AnimationController(
      vsync: this,
      duration: CitroMotion.tab,
      value: 1,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
    // 首页的待办卡、心情卡要在还没进待办页时就能显示数据，所以这里先初始化一次。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(TodoStore.instance.ensureInit()),
    );
    // 首页记账卡要在没进记账页时就能显示本月数据。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(LedgerStore.instance.ensureInit()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmAssets());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PerfProbe.homeReady(switchTo),
    );
    // 空闲时按顺序预挂载其余 Tab（Offstage），首次切过去不再整页构建。
    // 错开时间，避免同一次 setState 里连续挂载多个页面。
    _warmPage(1, 1200); // 计划
    _warmPage(2, 2000); // 游戏
    _warmPage(3, 2800); // 社区（会顺带预取动态，游客不发请求）
    // 让启动路径先跑完，避免更新检查与首帧、权限申请抢带宽/主线程。
    _updateTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) unawaited(checkForUpdates(context, manual: false));
    });
  }

  void _warmPage(int i, int delayMs) {
    _warmTimers.add(
      Timer(Duration(milliseconds: delayMs), () {
        if (!mounted || _visited[i]) return;
        setState(() => _visited[i] = true);
      }),
    );
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
    // 启动时自动定位：用户手动选过城市的话，AppState 内部会直接跳过。
    await AppState.instance.refreshWeatherWithLocation();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    await Notifications.ensureInit();
    final enabled = await Notifications.areEnabled();
    if (!enabled) await AppState.instance.setNotificationsEnabled(false);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    for (final timer in _warmTimers) {
      timer.cancel();
    }
    _warmTimers.clear();
    _cardPromptTimer?.cancel();
    AppState.instance.cardPromptTick.removeListener(_onCardPrompt);
    AppState.instance.removeListener(_onAuthChanged);
    negativeScreenSignal.removeListener(_onNegativeScreenRequest);
    _tabAnim.dispose();
    if (instance == this) instance = null;
    super.dispose();
  }

  void _onAuthChanged() {
    final loggedIn = AppState.instance.loggedIn;
    if (loggedIn && !_wasLoggedIn) {
      // 登录完成后立即对齐云端：首页布局与待办数据。
      unawaited(HomeLayoutStore.instance.syncFromAccount(force: true));
      unawaited(TodoStore.instance.syncFromAccount(force: true));
      unawaited(LedgerStore.instance.syncFromAccount(force: true));
      unawaited(CalendarStore.instance.syncFromAccount(force: true));
    } else if (!loggedIn && _wasLoggedIn) {
      // 登出 / 会话失效：账本属于账号数据，本机副本一并清掉。
      unawaited(LedgerStore.instance.clearLocal());
    }
    _wasLoggedIn = loggedIn;
  }

  /// 「资源库」的唯一落点是首页负一屏：收到信号先切回首页，
  /// HomePage 自己监听同一个信号把负一屏展开。
  void _onNegativeScreenRequest() {
    if (mounted && index != 0) switchTo(0);
  }

  /// 长按自定义 Tab 改了模块：替换该页实例，让新模块立刻生效。

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

  /// 只有触屏手机响应横滑切 Tab；桌面 Web / Windows 会与文本选择、
  /// 横向滚动（日历、图表、游戏）冲突。
  Widget _swipeable(Widget child) {
    if (kIsWeb || !(platform.isAndroid || platform.isIOS)) return child;
    return _withSwipe(child);
  }

  void switchTo(int i) => unawaited(_switchTab(i));

  /// 壳内 Tab 切换：新旧两页同时在场，旧页反向让位、新页推入。
  ///
  /// 四端共一套节奏（仅时长/位移按端缩放），Web 也不再整页 push，
  /// 导航栏和页面壳不会跟着重挂载，切换因此连贯不割裂。
  Future<void> _switchTab(int i) async {
    if (i == index || i < 0 || i >= _tabCount) return;
    // 可中断：上一段还没走完就收尾，再从当前位置开始新的一段。
    if (_tabAnim.isAnimating) _tabAnim.value = 1;
    _dir = i > index ? 1.0 : -1.0;
    final reduce = CitroMotion.reduced(context);
    PerfProbe.beginFrameCollection();
    _tabAnim.duration = CitroMotion.tabContent;
    // 先把动画值归零，保证等待新页首帧时它就以 t=0 呈现；
    // 否则会先显示一帧 t=1 再跳回起点，出现闪动。
    _tabAnim.value = 0;
    setState(() {
      _prevIndex = index;
      _visited[i] = true;
      index = i;
    });
    if (kIsWeb) {
      const routes = ['/home', '/plan', '/games', '/trash'];
      syncWebRoute(i < routes.length ? routes[i] : '/plan');
    }
    if (reduce) {
      _tabAnim.value = 1;
      if (_prevIndex != null) _prevIndex = null;
      PerfProbe.endFrameCollection('tab_$i');
      return;
    }
    // 先让新页完成首帧 build/layout，再开始动画，避免“构建整页 + 动画”
    // 挤在同一帧（首次切到社区/我的时最容易掉帧）。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _tabAnim.forward(from: 0);
    if (!mounted) return;
    if (_prevIndex != null) {
      setState(() => _prevIndex = null);
    }
    if (PerfProbe.enabled) {
      // FrameTiming 在帧结束后才批量回传，给采样回调留一帧时间。
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    PerfProbe.endFrameCollection('tab_$i');
  }

  Widget _pageStack() {
    // 已挂载的页面保持原位；当前页与上一页（切页动画期间）同时在场。
    // 旧实现把整棵 Stack 放进 AnimatedBuilder，动画期间后台页也会逐帧重建；
    // 首页、社区这类长页面在每次切 Tab 时都要白白 build + layout 一遍。
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        for (var i = 0; i < _tabCount; i++)
          if (_visited[i] && i != index && i != _prevIndex)
            _pageLayer(i, active: false),
        if (_prevIndex != null && _visited[_prevIndex!])
          _pageLayer(_prevIndex!, active: false),
        _pageLayer(index, active: true),
      ],
    );
  }

  Widget _pageLayer(int i, {required bool active}) {
    final leaving = !active && i == _prevIndex;
    // 关键：隐藏页和显示页必须返回同一棵 widget 结构，否则 Flutter 会整页重建，
    // 每次切 Tab 都重放入场动画并闪一下。
    final page = RepaintBoundary(
      child: TickerMode(
        enabled: active || leaving,
        child: _pages[i],
      ),
    );
    return Positioned.fill(
      child: Offstage(
        offstage: !active && !leaving,
        child: IgnorePointer(
          ignoring: !active,
          // 页面作为 child 传入，动画期间只更新外面这层包装，不重建页面本身。
          // 后台页不监听切页动画（用常量动画占位），结构保持一致，
          // 因此切 Tab 时既不会重挂 Element，也不会逐帧重建后台长页面。
          child: AnimatedBuilder(
            animation: active
                ? _tabAnim
                : const AlwaysStoppedAnimation<double>(1),
            child: page,
            builder: (context, child) =>
                _settlePage(child!, active: active, leaving: leaving),
          ),
        ),
      ),
    );
  }

  /// 切页包装：新页从行进方向一侧进入并淡入，旧页反向让位。
  ///
  /// 位移用 [FractionalTranslation]（相对自身宽度），不需要知道画布有多宽；
  /// 5% 宽在 220ms 下能读出方向，又不会像整页横推那样「等页面」。
  Widget _settlePage(Widget child, {required bool active, required bool leaving}) {
    final reduce = CitroMotion.reduced(context);
    if (active) {
      final t = CitroMotion.easeOut.transform(_tabAnim.value);
      if (reduce) return child;
      return Opacity(
        opacity: .85 + .15 * t,
        child: FractionalTranslation(
          translation: Offset(-_dir * .05 * (1 - t), 0),
          child: child,
        ),
      );
    }
    if (!leaving || reduce) return child;
    // 旧页：朝相反方向让开一半，同时淡到 70%，把舞台让给新页。
    final out = CitroMotion.exit.transform(_tabAnim.value);
    return Opacity(
      opacity: 1 - .3 * out,
      child: FractionalTranslation(
        translation: Offset(_dir * .025 * out, 0),
        child: child,
      ),
    );
  }

  Widget _pageAt(int i) {
    switch (i) {
      case 1:
        return const PlanPage();
      case 2:
        return const GamesPage();
      case 3:
        return const CommunityPage();
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
          // 形态同步放到首帧后，且尺寸没变不重复触发平台通道。
          if (_orientationSize != size) {
            _orientationSize = size;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) CitroOrientation.sync(size);
            });
          }
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
            // 待办 / 记账 / 食谱自己就带左侧 rail：这时全局侧栏让位，
            // 由页面自己的 tab 接替左侧位置，右边的内容区保持不动。
            final ownsRail = _pageOwnsRail;
            return Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!ownsRail)
                    SizedBox(
                      width: _sidebarWidth,
                      child: CitroTabletSidebar(
                        index: index,
                        onChanged: switchTo,
                      ),
                    ),
                  Expanded(
                    child: CitroLayoutScope(
                      contentWidth: ownsRail
                          ? constraints.maxWidth
                          : constraints.maxWidth - _sidebarWidth,
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
                    child: _swipeable(_pageStack()),
                  ),
                ),
                if (!desktop && !keyboardOpen)
                  CitroTabBar(
                    index: index,
                    onChanged: switchTo,
                    onCiciTap: () => showAiChat(context),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
