import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

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
import '../pages/res_page.dart';
import '../widgets/tab_bar.dart';
import '../games/gbrake_web.dart';
import '../widgets/tablet_shell.dart';
import '../overlays/ai_chat.dart';
import 'plan_page.dart';
import 'home_page.dart';
import 'me_page.dart';
import 'games_page.dart';
import 'community_page.dart';
import '../widgets/paper.dart';

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

  /// 五格导航：首页、计划、游戏、社区、资源库（资源库由 Windows / iPad 侧栏到达）。
  static int get _tabCount => 5;

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
      // 这里补一次云端对齐，否则待办 / 记账 / 日历都不同步。
      syncOnNextMount = false;
      unawaited(TodoStore.instance.syncFromAccount(force: true));
      unawaited(LedgerStore.instance.syncFromAccount(force: true));
      unawaited(CalendarStore.instance.syncFromAccount(force: true));
    }
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
  /// 这样打开 AI 对话时不会在首帧临时解码 9 张猫图。
  Future<void> _warmAssets() async {
    // 测试环境没有解码器 / 插件，预解码只会留下一个等不到头的延时。
    if (kIsWeb || platform.isTest) return;
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
    // widget 测试里没有定位 / 通知插件，等定位超时只会给测试留下一个
    // 20 秒的 pending timer。启动预热与滚动这类测试不需要它。
    if (kIsWeb || platform.isTest) return;
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
    _tabAnim.dispose();
    if (instance == this) instance = null;
    super.dispose();
  }

  void _onAuthChanged() {
    final loggedIn = AppState.instance.loggedIn;
    if (loggedIn && !_wasLoggedIn) {
      // 登录完成后立即对齐云端：待办数据。
      unawaited(TodoStore.instance.syncFromAccount(force: true));
      unawaited(LedgerStore.instance.syncFromAccount(force: true));
      unawaited(CalendarStore.instance.syncFromAccount(force: true));
    } else if (!loggedIn && _wasLoggedIn) {
      // 登出 / 会话失效：账本属于账号数据，本机副本一并清掉。
      unawaited(LedgerStore.instance.clearLocal());
    }
    _wasLoggedIn = loggedIn;
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

  /// 原生手机：横滑切 Tab。
  bool get _nativeTouch => !kIsWeb && (platform.isAndroid || platform.isIOS);

  Widget _withSwipe(Widget child, {bool switchTabs = true}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // 只认手指 / 触控笔：桌面鼠标拖动是文本选择、横向滚动，不能被吃掉。
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      },
      onHorizontalDragStart: (_) => _swipeDx = 0,
      onHorizontalDragUpdate: (details) => _swipeDx += details.delta.dx,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        final left = _swipeDx <= -46 || v < -380;
        final right = _swipeDx >= 46 || v > 380;
        _swipeDx = 0;
        if (right && index == 0) {
          // 首页右滑：从左边呼出「我的」侧栏（首页左边没有 Tab 可切）。
          unawaited(showMeSidebar(context));
        } else if (switchTabs && _nativeTouch && left) {
          switchTo(index + 1);
        } else if (switchTabs && _nativeTouch && right) {
          switchTo(index - 1);
        }
      },
      child: child,
    );
  }

  /// 原生手机：横滑切 Tab，首页右滑呼出「我的」侧栏。
  /// 其他端（Web 触屏 / 平板 / 触屏笔记本）只保留首页右滑呼出侧栏；
  /// 鼠标拖动一律不响应，避免和文本选择、横向滚动冲突。
  Widget _swipeable(Widget child) => _withSwipe(child);

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
    _tabAnim.duration = CitroMotion.desktopLike
        ? CitroMotion.tabSlideDesktop
        : CitroMotion.tabSlide;
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
      child: TickerMode(enabled: active || leaving, child: _pages[i]),
    );
    return Positioned.fill(
      // 稳定的 key 不能省：Stack 里页面的先后顺序会随「预热其余 Tab」
      // 和切页动画变化。没有 key 时，同类型的 Positioned 会按位置复用，
      // 首页前面一插入计划页，后面的首页 Element 就被整棵替换重建 ——
      // 滚动位置、负一屏开度全部丢光（表现就是「刚打开几秒内怎么滑都
      // 被拉回原位」）。加了 key 之后 Flutter 才能按 key 搬运同一个页。
      key: ValueKey<String>('citro-page-$i'),
      child: Offstage(
        offstage: !active && !leaving,
        child: IgnorePointer(
          ignoring: !active,
          // 页面作为 child 传入，动画期间只更新外面这层包装，不重建页面本身。
          // 后台页不监听切页动画（用常量动画占位），结构保持一致，
          // 因此切 Tab 时既不会重挂 Element，也不会逐帧重建后台长页面。
          child: AnimatedBuilder(
            // 当前页和正在离开的页都要跟着动画逐帧更新位移；之前只有当前页
            // 监听 _tabAnim，离开的页只在切换那一帧按 t=0 算一次位置就再也
            // 不动了——新页从旁边滑进来时直接压在静止的旧页上，就是「重叠」。
            // 只有后台页才用常量动画占位、不逐帧重建。
            animation: (active || leaving)
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

  /// 切页包装：新旧两页整宽并排横移（见 [CitroMotion.tabSlide]）。
  Widget _settlePage(
    Widget child, {
    required bool active,
    required bool leaving,
  }) {
    // 整宽横移：页面底是透明的、背景由壳层统一铺在下面，所以两页并排
    // 一起滑过静止的背景——像翻相册。新页从行进方向那一侧整页滑入，旧页
    // 同步整页滑出，两页首尾相接：任何一帧都不重叠、也不留空白。
    // 不做透明度变化（半透明正是之前「叠字」的来源），只改合成层位移。
    // 所有页（当前 / 离开 / 后台）都返回同一种包装、只改位移：外层结构
    // 一旦在「页面」和「FractionalTranslation(页面)」之间切换，页面
    // Element 会被整棵重建，滚动位置和状态全丢。
    var dx = 0.0;
    if ((active || leaving) && !CitroMotion.reduced(context)) {
      final t = CitroMotion.tabSlideCurve.transform(_tabAnim.value);
      dx = active ? _dir * (1 - t) : -_dir * t;
    }
    return FractionalTranslation(translation: Offset(dx, 0), child: child);
  }

  Widget _pageAt(int i) {
    switch (i) {
      case 1:
        return const PlanPage();
      case 2:
        return const GamesPage();
      case 3:
        return const CommunityPage();
      case 4:
        // Windows / iPad 侧栏的「资源库」Tab。
        return const ResPage(embedded: true);
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
          // Web 横屏（浏览器窗口呈横向、且宽度够）直接沿用 Windows 桌面壳：
          // 左侧 208 侧栏 + 分栏首页，不再走网页专用的 WebHomePage。
          // 竖屏 / 手机上窗口（width < 900 或短边 < 600）保持原来的移动壳。
          final webLandscape =
              kIsWeb && size.width > size.height && CitroForm.tabletNav(size);
          final desktop = kIsWeb && !webLandscape && size.width >= 1025;
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
            return CitroBackground(
              // 整个壳只铺一张沉浸背景：侧栏、各 tab 页（透明底）共用同一张图，
              // 不会在侧栏和内容之间出现两块裁切不同的背景。
              child: Scaffold(
              backgroundColor: Colors.transparent,
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
                        child: _withSwipe(_pageStack(), switchTabs: false),
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
            ),
            );
          }
          final tablet =
              webLandscape ||
              (!desktop && !kIsWeb && CitroForm.tabletNav(size));
          if (tablet) {
            // 待办 / 记账 / 食谱自己就带左侧 rail：这时全局侧栏让位，
            // 由页面自己的 tab 接替左侧位置，右边的内容区保持不动。
            final ownsRail = _pageOwnsRail;
            return CitroBackground(
              // 整个壳只铺一张沉浸背景：侧栏、各 tab 页（透明底）共用同一张图，
              // 不会在侧栏和内容之间出现两块裁切不同的背景。
              child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!ownsRail)
                    SizedBox(
                      width: _sidebarWidth,
                      child: CitroTabletSidebar(
                        index: index,
                        onChanged: switchTo,
                        // 网页端已下线资源库（mods 包体也从 Web 产物里删掉了），
                        // 侧栏只保留四格；Windows / iPad 仍然是五格。
                        showLibrary: !kIsWeb,
                      ),
                    ),
                  Expanded(
                    child: CitroLayoutScope(
                      contentWidth: ownsRail
                          ? constraints.maxWidth
                          : constraints.maxWidth - _sidebarWidth,
                      tabletNav: true,
                      duo: duo,
                      // 桌面分栏排版（首页左栏背景 + 右栏卡片）：Windows 桌面壳、
                      // 平板横屏、以及 Web 横屏都开 —— 三端看起来是同一套桌面版。
                      splitHome:
                          webLandscape ||
                          (!kIsWeb &&
                              (platform.isWindows || size.width > size.height)),
                      child: _withSwipe(_pageStack(), switchTabs: false),
                    ),
                  ),
                ],
              ),
            ),
            );
          }
          return CitroBackground(
              // 整个壳只铺一张沉浸背景：侧栏、各 tab 页（透明底）共用同一张图，
              // 不会在侧栏和内容之间出现两块裁切不同的背景。
              child: Scaffold(
              backgroundColor: Colors.transparent,
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
          ),
            );
        },
      ),
    );
  }
}
