import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_keys.dart';
import 'overlays/timer_overlay.dart';
import 'perf_probe.dart';
import 'routes.dart';
import 'services/orientation.dart';
import 'services/platform.dart' as platform;
import 'services/web_route.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/breakpoints.dart';
import 'theme/scroll_behavior.dart';
import 'theme/tokens.dart';
import 'widgets/corner_guard.dart';
import 'widgets/desktop_shell.dart';
import 'widgets/tablet_shell.dart';

Future<void> main() async {
  PerfProbe.start();
  WidgetsFlutterBinding.ensureInitialized();
  await CitroDesktopShell.init();
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
  runApp(const CitroApp());
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
      pageName.value = route.settings.name;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _setPopup(_popups - 1);
    } else {
      if (pageDepth.value > 0) pageDepth.value -= 1;
      pageName.value = previousRoute?.settings.name;
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _setPopup(_popups - 1);
    } else {
      if (pageDepth.value > 0) pageDepth.value -= 1;
      pageName.value = previousRoute?.settings.name;
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
      pageName.value = newRoute?.settings.name;
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

  @override
  void initState() {
    super.initState();
    // AppState 还会为天气 / 未读 / 弹层状态等发通知。只关心主题，
    // 避免每次 notifyListeners 都重建整个 MaterialApp（弹层开合时尤其明显）。
    _state.addListener(_syncTheme);
  }

  void _syncTheme() {
    final mode = _state.themeMode;
    if (mode != _themeMode) setState(() => _themeMode = mode);
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
              data: theme.copyWith(bottomSheetTheme: sheetTheme),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                  statusBarBrightness: isDark
                      ? Brightness.dark
                      : Brightness.light,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                  systemNavigationBarDividerColor: Colors.transparent,
                ),
                child: MediaQuery.withClampedTextScaling(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.15,
                  child: Stack(
                    children: [
                      child ?? const SizedBox.shrink(),
                      const TimerCapsuleOverlay(),
                    ],
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

class SplashGate extends StatefulWidget {
  final String initialRoute;
  const SplashGate({super.key, this.initialRoute = CitroRoutes.home});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _ready = false;
  bool _booted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
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
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: !_ready
          ? const SplashScreen(key: ValueKey('splash'))
          : (_booted
                ? KeyedSubtree(
                    key: const ValueKey('shell'),
                    child: CitroRoutes.pageFor(widget.initialRoute),
                  )
                : _BootError(
                    error: _error,
                    onRetry: _boot,
                    key: const ValueKey('boot-error'),
                  )),
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
      backgroundColor: const Color(0xFFFBF7EC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🍊', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                const Text(
                  'Citro 启动失败',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF23211C),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error ?? '未知错误',
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6E6858),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF2A43C),
                    foregroundColor: const Color(0xFF2E2C22),
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

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: const Color(0xFFFBF7EC),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo.webp',
                width: 112,
                height: 112,
                cacheWidth: 224,
              ),
              const SizedBox(height: 18),
              const SizedBox(
                width: 88,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: Color(0xFFF2A43C),
                  backgroundColor: Color(0x22F2A43C),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final size = MediaQuery.sizeOf(context);
    // iPad 固定使用横版启动图，与原生 LaunchImage 的 iPad 资源保持一致；
    // iPhone/Duo 仍按当前窗口方向选择。
    final isPad = size.shortestSide >= 700;
    final landscape = isPad || size.width > size.height;
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7EC),
      body: Image.asset(
        landscape ? 'assets/splash_landscape.jpg' : 'assets/splash_image.jpg',
        key: ValueKey(landscape ? 'splash-landscape' : 'splash-portrait'),
        fit: BoxFit.cover,
        alignment: landscape ? Alignment.center : Alignment.topCenter,
        cacheWidth: landscape ? 2000 : 1080,
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
      color: const Color(0xFFFBF7EC),
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🍊', style: TextStyle(fontSize: 34)),
            const SizedBox(height: 8),
            const Text(
              '页面加载出了点问题',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF23211C),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              details.exceptionAsString(),
              textAlign: TextAlign.center,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF6E6858),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
