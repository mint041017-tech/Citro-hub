import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_keys.dart';
import 'ledger/ledger_intake.dart';
import 'overlays/pomodoro_sheet.dart';
import 'overlays/profile_modal.dart';
import 'overlays/timer_overlay.dart';
import 'pages/login_page.dart';
import 'pages/root_shell.dart';
import 'perf_probe.dart';
import 'routes.dart';
import 'services/image_store.dart';
import 'services/orientation.dart';
import 'services/platform.dart' as platform;
import 'services/prefs.dart';
import 'services/refresh_rate.dart';
import 'services/web_route.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/breakpoints.dart';
import 'theme/motion.dart';
import 'theme/scroll_behavior.dart';
import 'theme/tokens.dart';
import 'widgets/corner_guard.dart';
import 'widgets/desktop_shell.dart';
import 'widgets/home_background.dart';
import 'widgets/paper.dart';
import 'widgets/tablet_shell.dart';

Future<void> main() async {
  PerfProbe.start();
  WidgetsFlutterBinding.ensureInitialized();
  // 全局请求屏幕最高刷新率：HyperOS 的 LTPO 屏在静态画面会降到 60Hz，
  // 常驻一个 lease，滚动/动画时系统才会升到 120Hz。游戏页的 acquire 会
  // 叠加在同一个计数器上，退出游戏后不会把全局请求释放掉。
  RefreshRate.acquire();
  await CitroDesktopShell.init();
  // 预热液态玻璃的着色器：只在启动时做一次异步磁盘读取，
  // 免得首帧才编译导致玻璃表面闪白。失败也不阻塞启动。
  try {
    await LiquidGlassWidgets.initialize().timeout(const Duration(seconds: 3));
  } catch (_) {}
  // 图片缓存是这类图文 App 最容易吃满内存的地方：限制总量，低内存时整块清掉。
  // 桌面端内存更宽裕，放宽缓存避免大图反复解码，帧时间更稳定。
  final desktopCache = !kIsWeb && platform.isDesktop;
  PaintingBinding.instance.imageCache
    ..maximumSize = kIsWeb ? 80 : (desktopCache ? 180 : 120)
    ..maximumSizeBytes = (kIsWeb ? 32 : (desktopCache ? 96 : 48)) << 20;
  ErrorWidget.builder = (details) => _FriendlyError(details: details);
  // iPhone 默认锁竖屏，只有 Duo 内屏解锁横屏；iPad 交给 Info.plist。
  if (!kIsWeb && !platform.isIOS && !platform.isDesktop) {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    } catch (_) {}
  }
  runApp(
    // 玻璃材质要跟着 MaterialApp 的 ThemeMode 走，否则深色模式下
    // 阴影和描边会按系统亮度算，和 App 实际主题对不上。
    // ios27() 是包按 Apple glassEffect(.regular) 校准好的材质，
    // 亮 / 暗两套自动切换，全站玻璃共用。
    LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      theme: const GlassThemeData.ios27(),
      child: const CitroApp(),
    ),
  );
  // 系统分享 / iOS 快捷指令可能冷启动 App：首帧后注册原生通道并消费待处理截图。
  LedgerIntake.instance.attach();
  // 方向同步不再阻塞首帧；RootShell 布局时也会按实际窗口再同步一次。
  if (!kIsWeb && platform.isIOS) {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view != null) {
      unawaited(
        CitroOrientation.sync(view.physicalSize / view.devicePixelRatio),
      );
    }
  }
}

final CitroRouteObserver _citroRouteObserver = CitroRouteObserver();

class CitroRouteObserver extends NavigatorObserver {
  int _popups = 0;
  final ValueNotifier<int> pageDepth = ValueNotifier<int>(0);
  final ValueNotifier<int> popupDepth = ValueNotifier<int>(0);
  final ValueNotifier<String?> pageName = ValueNotifier<String?>(null);

  void _sync() => AppState.instance.setPopupActive(_popups > 0);

  void _setPage(String? name) {
    pageName.value = name;
    citroActiveRoute.value = name;
  }

  void _setPopup(int value) {
    _popups = value < 0 ? 0 : value;
    popupDepth.value = _popups;
    _sync();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _setPopup(_popups + 1);
    } else {
      pageDepth.value += 1;
      _setPage(route.settings.name);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _setPopup(_popups - 1);
    } else {
      if (pageDepth.value > 0) pageDepth.value -= 1;
      _setPage(previousRoute?.settings.name);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _setPopup(_popups - 1);
    } else {
      if (pageDepth.value > 0) pageDepth.value -= 1;
      _setPage(previousRoute?.settings.name);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PopupRoute && oldRoute is! PopupRoute) {
      _setPopup(_popups + 1);
    } else if (newRoute is! PopupRoute && oldRoute is PopupRoute) {
      _setPopup(_popups - 1);
    } else {
      _sync();
    }
    if (newRoute is! PopupRoute) {
      _setPage(newRoute?.settings.name);
    }
  }
}

class _MemoryGuard extends StatefulWidget {
  final Widget child;
  const _MemoryGuard({required this.child});

  @override
  State<_MemoryGuard> createState() => _MemoryGuardState();
}

class _MemoryGuardState extends State<_MemoryGuard>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.chimu.crew/memory');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'trim') _trim();
      return null;
    });
  }

  void _trim() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    // HyperOS / MIUI 的 onTrimMemory 来得频繁，连同自建的内存图片缓存一起释放，
    // 否则 Flutter 画布缓存清了、原图字节还占着几十 MB。
    ImageStore.clearMemory();
    CitroBlendImage.clearMemory();
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() => _trim();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // HyperOS / MIUI 的后台限制较严：退后台暂停轮询，回前台立即补一次。
    AppState.instance.setForeground(state == AppLifecycleState.resumed);
    // 退到后台时清掉不在屏幕上的解码图，避免系统回收进程后回来直接重启。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      PaintingBinding.instance.imageCache.clear();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class CitroApp extends StatefulWidget {
  const CitroApp({super.key});

  @override
  State<CitroApp> createState() => _CitroAppState();
}

class _CitroAppState extends State<CitroApp> {
  final AppState _state = AppState.instance;
  late ThemeMode _themeMode = _state.themeMode;
  late bool _reduceMotion = _state.reduceMotion;

  @override
  void initState() {
    super.initState();
    // AppState 还会为天气 / 未读 / 弹层状态等发通知。只关心主题，
    // 避免每次 notifyListeners 都重建整个 MaterialApp（弹层开合时尤其明显）。
    _state.addListener(_syncTheme);
  }

  void _syncTheme() {
    final mode = _state.themeMode;
    final reduce = _state.reduceMotion;
    if (mode != _themeMode || reduce != _reduceMotion) {
      setState(() {
        _themeMode = mode;
        _reduceMotion = reduce;
      });
    }
  }

  @override
  void dispose() {
    _state.removeListener(_syncTheme);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MemoryGuard(
      child: AppScope(
        state: _state,
        child: MaterialApp(
          title: 'Citro',
          navigatorKey: citroNavigatorKey,
          navigatorObservers: [_citroRouteObserver],
          debugShowCheckedModeBanner: false,
          themeMode: _themeMode,
          theme: buildCitroTheme(CitroColors.light),
          darkTheme: buildCitroTheme(CitroColors.darkColors),
          themeAnimationCurve: CitroMotion.easeOut,
          themeAnimationDuration: _reduceMotion
              ? Duration.zero
              : CitroMotion.modal,
          scrollBehavior: const CitroScrollBehavior(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          initialRoute: CitroRoutes.normalize(currentWebRoute()),
          onGenerateRoute: CitroRoutes.onGenerateRoute,
          onGenerateInitialRoutes: (initialRoute) {
            final route = CitroRoutes.normalize(
              currentWebRoute() ?? initialRoute,
            );
            return [
              MaterialPageRoute<dynamic>(
                settings: RouteSettings(name: route),
                builder: (_) => SplashGate(initialRoute: route),
              ),
            ];
          },
          builder: (context, child) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final duo =
                !kIsWeb && CitroForm.duoDevice(MediaQuery.sizeOf(context));
            final sheetTheme = duo
                ? theme.bottomSheetTheme.copyWith(
                    constraints: const BoxConstraints(
                      maxWidth: double.infinity,
                    ),
                  )
                : theme.bottomSheetTheme;
            final content = Theme(
              data: theme.copyWith(
                bottomSheetTheme: sheetTheme,
                pageTransitionsTheme: _reduceMotion
                    ? const PageTransitionsTheme(
                        builders: {
                          TargetPlatform.android: _NoPageTransitions(),
                          TargetPlatform.iOS: _NoPageTransitions(),
                          TargetPlatform.windows: _NoPageTransitions(),
                          TargetPlatform.macOS: _NoPageTransitions(),
                          TargetPlatform.linux: _NoPageTransitions(),
                          TargetPlatform.fuchsia: _NoPageTransitions(),
                        },
                      )
                    : theme.pageTransitionsTheme,
              ),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                  statusBarBrightness: isDark
                      ? Brightness.dark
                      : Brightness.light,
                  // 系统不再给状态栏/导航栏加对比蒙层，纸感背景能一直铺到屏幕边缘。
                  systemStatusBarContrastEnforced: false,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                  systemNavigationBarDividerColor: Colors.transparent,
                  systemNavigationBarContrastEnforced: false,
                ),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations:
                        MediaQuery.of(context).disableAnimations ||
                        _reduceMotion,
                  ),
                  child: MediaQuery.withClampedTextScaling(
                    minScaleFactor: 0.9,
                    maxScaleFactor: 1.15,
                    child: Stack(
                      children: [
                        child ?? const SizedBox.shrink(),
                        const TimerCapsuleOverlay(),
                        const PomodoroDoneWatcher(),
                      ],
                    ),
                  ),
                ),
              ),
            );
            if (!duo) {
              return CitroDesktopShell.wrap(context, content);
            }
            return CitroDesktopShell.wrap(
              context,
              CitroDuoBackRailOverlay(
                pageDepth: _citroRouteObserver.pageDepth,
                popupDepth: _citroRouteObserver.popupDepth,
                pageName: _citroRouteObserver.pageName,
                onBack: () => citroNavigatorKey.currentState?.maybePop(),
                child: CitroDuoCornerGuard(child: content),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NoPageTransitions extends PageTransitionsBuilder {
  const _NoPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class SplashGate extends StatefulWidget {
  final String initialRoute;
  const SplashGate({super.key, this.initialRoute = CitroRoutes.home});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _ready = false;
  bool _booted = false;
  bool _enterMain = false;
  bool _pendingProfilePrompt = false;
  String? _error;
  Future<void>? _enterFuture;
  bool _wasLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _wasLoggedIn = AppState.instance.loggedIn;
    AppState.instance.addListener(_onAuthChanged);
    unawaited(_boot());
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<void> _boot() async {
    final startedAt = DateTime.now();
    if (mounted) {
      setState(() {
        _ready = false;
        _error = null;
      });
    }
    try {
      await AppState.instance.init().timeout(const Duration(seconds: 10));
      _booted = true;
    } catch (e) {
      _booted = false;
      _error = '$e';
    }
    // 背景预载：登录页和主界面共用这一张，越早开始越好。
    unawaited(CitroAmbientBackground.prepare());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(CitroAmbientBackground.prepare(context: context));
    });
    // 会话恢复（有本地 token / Web 的 httpOnly Cookie）与最长启动展示
    // 并行等：不让登录页闪一帧，也不把启动时间无意义地拉长。
    final needSessionWait = _booted &&
        ((Prefs.getString(PrefKeys.token) ?? '').isNotEmpty || kIsWeb);
    final waitSession = needSessionWait
        ? _waitForSession(const Duration(milliseconds: 1000))
        : Future<void>.value();
    // Windows 与 iPad 一样先完整展示启动插画，避免秒开时只闪一帧；
    // 安卓原生冷启动窗口没有插画，同样补足展示时间，否则一闪而过。
    final minSplash = !kIsWeb && (platform.isWindows || platform.isAndroid)
        ? const Duration(milliseconds: 1000)
        : Duration.zero;
    final splashRemaining = minSplash - DateTime.now().difference(startedAt);
    try {
      await Future.wait<void>([
        waitSession,
        if (splashRemaining > Duration.zero)
          Future<void>.delayed(splashRemaining),
      ]);
    } catch (_) {}
    if (!mounted) return;
    _wasLoggedIn = AppState.instance.loggedIn;
    setState(() => _ready = true);
    if (_wasLoggedIn) unawaited(_enterMainFlow());
  }

  /// 会话恢复是异步的：有 token 但还没拿到用户时，短暂等一下，
  /// 免得登录页闪一帧。超时也没关系，恢复完成后会走 late-restore 分支。
  Future<void> _waitForSession(Duration limit) async {
    final deadline = DateTime.now().add(limit);
    while (AppState.instance.user == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final loggedIn = AppState.instance.loggedIn;
    if (!_ready) {
      // 启动期间可能收到会话恢复通知；只记状态，等 boot 收尾统一放行。
      _wasLoggedIn = loggedIn;
      return;
    }
    if (loggedIn && !_wasLoggedIn) {
      // 登录页完成后才挂载壳：登录那一刻壳还没在，标记一次云端对齐。
      RootShellState.syncOnNextMount = true;
      unawaited(_enterMainFlow());
    } else if (!loggedIn && _wasLoggedIn) {
      // 登出 / 会话失效：回到登录页，必须重新登录才能进主界面。
      _enterFuture = null;
      _pendingProfilePrompt = false;
      setState(() => _enterMain = false);
    }
    _wasLoggedIn = loggedIn;
  }

  /// 登录页在背景预载完成后回调：带上「这次登录是否要补资料」的信号。
  void _handleAuthenticated(bool needProfilePrompt) {
    _pendingProfilePrompt = needProfilePrompt;
    if (_enterMain) {
      _maybePromptProfile();
    } else {
      unawaited(_enterMainFlow());
    }
  }

  Future<void> _enterMainFlow() {
    final existing = _enterFuture;
    if (existing != null) return existing;
    final future = _doEnterMain();
    _enterFuture = future;
    return future;
  }

  /// 进入主界面前一定等背景就绪；超时也放行，不能把人卡在外面。
  Future<void> _doEnterMain() async {
    try {
      await CitroAmbientBackground.prepare(context: context).timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _enterMain = true);
    _maybePromptProfile();
  }

  /// 新注册 / 新登录且资料没填完时，沿用原来的资料完善弹层。
  void _maybePromptProfile() {
    if (!_pendingProfilePrompt) return;
    _pendingProfilePrompt = false;
    final user = AppState.instance.user;
    if (user == null || user.profileDone) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showProfileModal(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (!_ready) {
      child = const SplashScreen(key: ValueKey('splash'));
    } else if (!_booted) {
      child = _BootError(
        error: _error,
        onRetry: _boot,
        key: const ValueKey('boot-error'),
      );
    } else if (!_enterMain && !AppState.instance.loggedIn) {
      child = CitroLoginPage(
        key: const ValueKey('login'),
        onAuthenticated: _handleAuthenticated,
      );
    } else if (_enterMain) {
      child = KeyedSubtree(
        key: const ValueKey('shell'),
        child: CitroRoutes.pageFor(widget.initialRoute),
      );
    } else {
      child = const _EnteringHome(key: ValueKey('entering'));
    }
    return AnimatedSwitcher(
      duration: CitroMotion.popover,
      switchInCurve: CitroMotion.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

class _BootError extends StatelessWidget {
  final String? error;
  final VoidCallback onRetry;
  const _BootError({super.key, this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🍊', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                Text(
                  'Citro 启动失败',
                  style: context.heading(
                    size: CitroType.subtitle,
                    color: context.c.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error ?? '未知错误',
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: CitroType.caption,
                    color: context.c.inkSoft,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.c.ink,
                    foregroundColor: context.c.bg,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 0,
  );
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
    value: .5,
  );
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (CitroMotion.reduced(context)) {
      _enter.value = 1;
      return;
    }
    unawaited(_enter.forward());
    unawaited(_breath.repeat(reverse: true));
    unawaited(_dots.repeat());
  }

  @override
  void dispose() {
    _enter.dispose();
    _breath.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // 奶米底 + 青瓷柔光 + 两侧粉彩：手账感的干净版本。
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -.35),
                  radius: 1.25,
                  colors: [c.tintYellow.withAlpha(160), c.bg],
                  stops: const [0, .78],
                ),
              ),
            ),
          ),
          Positioned(
            left: -72,
            top: size.height * .14,
            child: _Blob(color: c.tintBlue, size: 240, alpha: 50),
          ),
          Positioned(
            right: -64,
            top: size.height * .42,
            child: _Blob(color: c.tintPink, size: 200, alpha: 45),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: Listenable.merge([_enter, _breath]),
                      builder: (context, _) {
                        final t = CitroMotion.easeOut.transform(_enter.value);
                        final breath = Curves.easeInOut.transform(_breath.value);
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 16 * (1 - t)),
                            child: SizedBox(
                              width: 176,
                              height: 176,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // 呼吸的墨色柔光：启动页的「仪式感」来源。
                                  Container(
                                    width: 148 + 24 * breath,
                                    height: 148 + 24 * breath,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          c.accentLt.withAlpha(
                                            (70 + 55 * breath).round(),
                                          ),
                                          c.accentLt.withAlpha(0),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Transform.scale(
                                    scale: .94 + .06 * t,
                                    // logo 直接上屏：不套圆角框/描边/底卡，
                                    // 原图是透明底的，直接压在青瓷柔光上。
                                    child: Image.asset(
                                      'assets/images/logo.webp',
                                      width: 148,
                                      height: 148,
                                      fit: BoxFit.contain,
                                      cacheWidth: 360,
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 12,
                                    child: Opacity(
                                      opacity: .35 + .45 * breath,
                                      child: AppIcon(
                                        strokeSvg(AppIcons.sparkle, width: 2),
                                        size: 18,
                                        color: c.accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _enter,
                        curve: CitroMotion.easeOut,
                      ),
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .12),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: _enter,
                            curve: CitroMotion.easeOut,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Citro',
                                  style: context.heading(
                                    size: 34,
                                    weight: CitroType.strong,
                                    color: c.ink,
                                    letterSpacing: .5,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: c.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '今天也要开心',
                              style: context.body(
                                size: CitroType.bodyLg,
                                color: c.inkSoft,
                                letterSpacing: 3,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: c.accentLt.withAlpha(c.dark ? 70 : 120),
                                borderRadius: BorderRadius.circular(
                                  CitroColors.radii.chip,
                                ),
                                border: Border.all(color: c.accent.withAlpha(60)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: c.accent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '记录 · 收藏 · 陪伴',
                                    style: context.body(
                                      size: CitroType.small,
                                      weight: CitroType.medium,
                                      color: c.accentInk,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 34,
            child: Column(
              children: [
                _LoadingDots(controller: _dots, color: c.accent),
                const SizedBox(height: 12),
                Text(
                  '© 2026 chimu',
                  style: context.body(
                    size: CitroType.micro,
                    color: c.inkSoft,
                    letterSpacing: 1.2,
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

/// 启动页两侧的柔光斑：给奶米底一点层次，不抢 logo。
class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  final int alpha;
  const _Blob({required this.color, required this.size, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withAlpha(alpha), color.withAlpha(0)],
        ),
      ),
    );
  }
}

/// 底部三点依次呼吸的加载指示。
class _LoadingDots extends StatelessWidget {
  final Animation<double> controller;
  final Color color;
  const _LoadingDots({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (controller.value - i * .18) % 1.0;
            final wave = math.sin(t * math.pi);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color.withAlpha((70 + 160 * wave).round()),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

/// 已登录但背景还在预载时的过渡页：避免直接闪出半加载的主界面。
class _EnteringHome extends StatelessWidget {
  const _EnteringHome({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.line),
                boxShadow: CitroColors.shadows.float(c),
              ),
              child: Image.asset('assets/images/logo.webp', cacheWidth: 140),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
            ),
            const SizedBox(height: 14),
            Text(
              '正在进入…',
              style: context.body(size: CitroType.caption, color: c.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendlyError extends StatelessWidget {
  final FlutterErrorDetails details;
  const _FriendlyError({required this.details});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.c.bg,
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🍊', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 8),
            Text(
              '页面加载出了点问题',
              style: context.heading(
                size: CitroType.titleLg,
                color: context.c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              details.exceptionAsString(),
              textAlign: TextAlign.center,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: context.body(
                size: CitroType.small,
                color: context.c.inkSoft,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
