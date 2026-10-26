import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../overlays/update_dialog.dart';
import '../perf_probe.dart';
import '../services/notifications.dart';
import '../services/orientation.dart';
import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/breakpoints.dart';
import '../widgets/tab_bar.dart';
import '../games/gbrake_web.dart';
import '../widgets/tablet_shell.dart';
import 'home_page.dart';
import 'games_page.dart';
import 'community_page.dart';
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
  late final AnimationController _fade;
  late final AnimationController _slide;
  // 平移方向与距离：切 Tab 时旧页向反方向滑出、新页从行进方向滑入。
  Tween<Offset> _slideTween = Tween<Offset>(
    begin: Offset.zero,
    end: Offset.zero,
  );
  bool _switching = false;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    instance = this;
    index = widget.initialIndex.clamp(0, 3);
    _visited = List<bool>.generate(4, (i) => i == index);
    _fade = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 90),
    );
    _slide = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 90),
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
    await Future<void>.delayed(const Duration(milliseconds: 2200));
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
    _fade.dispose();
    _slide.dispose();
    if (instance == this) instance = null;
    super.dispose();
  }

  void switchTo(int i) => unawaited(_switchTab(i));

  Future<void> _switchTab(int i) async {
    if (i == index || _switching || i < 0 || i > 3) return;
    if (kIsWeb && i == 3) return;
    if (kIsWeb) {
      const routes = ['/home', '/games', '/trash', '/res'];
      await Navigator.of(context).pushNamed(routes[i]);
      return;
    }
    _switching = true;
    final dir = i > index ? 1.0 : -1.0;
    PerfProbe.beginFrameCollection();
    // 单程动画：立即换页，新页用 90ms 滑入+轻微淡入，总耗时控制在 100ms 内。
    setState(() {
      _visited[i] = true;
      index = i;
      _slideTween = Tween(begin: Offset(dir * 36, 0), end: Offset.zero);
    });
    _fade.value = .55;
    await Future.wait([_fade.forward(), _slide.forward(from: 0)]);
    if (PerfProbe.enabled) {
      // FrameTiming 在帧结束后才批量回传，给采样回调留一帧时间。
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    PerfProbe.endFrameCollection('tab_$i');
    if (mounted) _switching = false;
  }

  Widget _pageStack() {
    return AnimatedBuilder(
      animation: Listenable.merge([_fade, _slide]),
      builder: (context, child) {
        return Transform.translate(
          offset: _slideTween.evaluate(_slide),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
            child: child,
          ),
        );
      },
      child: RepaintBoundary(
        child: IndexedStack(
          index: index,
          children: [
            TickerMode(
              enabled: index == 0,
              child: HomePage(onSwitchTab: switchTo),
            ),
            _visited[1]
                ? TickerMode(enabled: index == 1, child: const GamesPage())
                : const SizedBox.shrink(),
            _visited[2]
                ? TickerMode(enabled: index == 2, child: const CommunityPage())
                : const SizedBox.shrink(),
            _visited[3] && !kIsWeb
                ? TickerMode(
                    enabled: index == 3,
                    child: const ResPage(embedded: true),
                  )
                : const SizedBox.shrink(),
          ],
        ),
      ),
    );
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
                    child: _pageStack(),
                  ),
                ),
                if (!desktop &&
                    !keyboardOpen &&
                    (index != 3 || platform.isWindows))
                  CitroTabBar(index: index, onChanged: switchTo),
              ],
            ),
          );
        },
      ),
    );
  }
}
