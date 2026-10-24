import 'package:citro/main.dart';
import 'package:citro/pages/community_page.dart';
import 'package:citro/pages/home_page.dart';
import 'package:citro/services/models.dart';
import 'package:citro/services/orientation.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/breakpoints.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/corner_guard.dart';
import 'package:citro/widgets/tablet_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'duo-layout-test'
      ..guestName = '游客·Duo'
      ..user = const User(name: 'Duo 布局测试', profileDone: true);
  });

  group('Duo form detection', () {
    test('inner screens use the foldable layout', () {
      expect(CitroForm.duoInner(const Size(626, 890)), isTrue);
      expect(CitroForm.duoInner(const Size(669, 951)), isTrue);
      expect(CitroForm.duoInner(const Size(951, 669)), isTrue);
      expect(CitroForm.duoLandscape(const Size(951, 669)), isTrue);
      expect(CitroForm.duoLandscape(const Size(669, 951)), isFalse);
      expect(CitroForm.duoLandscape(const Size(626, 890)), isFalse);
    });

    test('Duo outer and inner are detected as one device', () {
      expect(CitroForm.duoDevice(const Size(466, 678)), isTrue);
      expect(CitroForm.duoDevice(const Size(669, 951)), isTrue);
      expect(CitroForm.duoDevice(const Size(951, 669)), isTrue);
      expect(CitroForm.duoDevice(const Size(440, 956)), isFalse);
      expect(CitroForm.duoDevice(const Size(744, 1133)), isFalse);
    });

    test('outer phone and iPad are not mistaken for the inner screen', () {
      expect(CitroForm.duoInner(const Size(466, 678)), isFalse);
      expect(CitroForm.duoInner(const Size(440, 956)), isFalse);
      expect(CitroForm.duoInner(const Size(744, 1133)), isFalse);
      expect(CitroForm.duoInner(const Size(1024, 1366)), isFalse);
    });

    test('tablet navigation only for tablets and Duo landscape', () {
      expect(CitroForm.tabletNav(const Size(890, 626)), isTrue);
      expect(CitroForm.tabletNav(const Size(951, 669)), isTrue);
      expect(CitroForm.tabletNav(const Size(669, 951)), isFalse);
      expect(CitroForm.tabletNav(const Size(626, 890)), isFalse);
      expect(CitroForm.tabletNav(const Size(466, 678)), isFalse);
      expect(CitroForm.tabletNav(const Size(956, 440)), isFalse);
      expect(CitroForm.tabletNav(const Size(1024, 1366)), isTrue);
      expect(CitroForm.tabletNav(const Size(678, 1024)), isFalse);
    });

    test('only the Duo inner screen unlocks landscape on iPhone', () {
      expect(
        CitroOrientation.preferredFor(isPad: false, size: const Size(626, 890)),
        [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
      expect(
        CitroOrientation.preferredFor(isPad: false, size: const Size(669, 951)),
        [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
      expect(
        CitroOrientation.preferredFor(isPad: false, size: const Size(466, 678)),
        [DeviceOrientation.portraitUp],
      );
      expect(
        CitroOrientation.preferredFor(isPad: false, size: const Size(440, 956)),
        [DeviceOrientation.portraitUp],
      );
      expect(
        CitroOrientation.preferredFor(
          isPad: true,
          size: const Size(1024, 1366),
        ),
        isNull,
      );
    });
  });

  Widget host(Widget child) => AppScope(
    state: AppState.instance,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCitroTheme(CitroColors.light),
      home: child,
    ),
  );

  testWidgets('duo landscape keeps the two-column home dashboard', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      host(
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 208,
              child: CitroTabletSidebar(index: 0, onChanged: (_) {}),
            ),
            const Expanded(
              child: CitroLayoutScope(
                contentWidth: 743,
                tabletNav: true,
                duo: true,
                child: HomePage(onSwitchTab: _noop),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    final fish = tester.getTopLeft(find.byType(FishCard));
    final zodiac = tester.getTopLeft(find.byType(ZodiacCard));
    expect(zodiac.dx, greaterThan(fish.dx));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('duo inner community uses the masonry branch', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(669, 951);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      host(
        const CitroLayoutScope(
          contentWidth: 669,
          tabletNav: false,
          duo: true,
          child: CommunityPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CustomScrollView), findsWidgets);
    expect(find.byType(ListView), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('duo closed community keeps the phone feed branch', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      host(
        const CitroLayoutScope(
          contentWidth: 466,
          tabletNav: false,
          child: CommunityPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(ListView), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('duo right rail exposes the navigation', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    var selected = 0;
    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 88,
            height: 669,
            child: CitroDuoRightRail(index: 0, onChanged: (i) => selected = i),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    for (final label in ['首页', '游戏', '社区', '食谱', 'CiCi']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('我的'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('duo-rail-avatar'))),
      const Size(44, 44),
    );
    expect(find.text('D'), findsOneWidget);
    await tester.tap(find.text('游戏'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(selected, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('duo back rail shows only for pushed pages', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    final depth = ValueNotifier<int>(1);
    final popups = ValueNotifier<int>(0);
    final name = ValueNotifier<String?>(null);
    var backed = 0;
    await tester.pumpWidget(
      host(
        CitroDuoBackRailOverlay(
          pageDepth: depth,
          popupDepth: popups,
          pageName: name,
          onBack: () => backed++,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('返回'), findsNothing);

    depth.value = 2;
    name.value = 'me';
    await tester.pump();
    expect(find.text('返回'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pump();
    expect(backed, 1);

    popups.value = 1;
    await tester.pump();
    expect(find.text('返回'), findsNothing);

    popups.value = 0;
    name.value = 'cook';
    await tester.pump();
    expect(find.text('返回'), findsNothing);

    depth.value = 1;
    name.value = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('route observer tracks pushed page depth and name', (
    tester,
  ) async {
    final observer = CitroRouteObserver();
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      AppScope(
        state: AppState.instance,
        child: MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [observer],
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pump();
    expect(observer.pageDepth.value, 1);

    navKey.currentState!.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'me'),
        builder: (_) => const Scaffold(body: Text('me')),
      ),
    );
    await tester.pumpAndSettle();
    expect(observer.pageDepth.value, 2);
    expect(observer.pageName.value, 'me');

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.pageDepth.value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duo outer rail keeps every tab reachable', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(466, 678);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(466, 678),
            padding: EdgeInsets.only(right: 84, bottom: 34),
          ),
          child: CitroDuoCornerGuard(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 84,
                height: 678,
                child: CitroDuoRightRail(
                  index: 0,
                  onChanged: (_) {},
                  topInset: CitroForm.duoRailTopInset(const Size(466, 678)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    for (final label in ['首页', '游戏', '社区', '食谱', 'CiCi']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('我的'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('duo corner guard pads top, left and bottom content', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      host(
        CitroDuoCornerGuard(
          child: SafeArea(child: Container(key: const Key('guarded'))),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const Key('guarded'))),
      const Rect.fromLTRB(16, 16, 951, 653),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('duo portrait keeps the single-column phone dashboard', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(669, 951);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      host(
        const CitroLayoutScope(
          contentWidth: 669,
          tabletNav: false,
          duo: true,
          child: HomePage(onSwitchTab: _noop),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    final fish = tester.getTopLeft(find.byType(FishCard));
    final zodiac = tester.getTopLeft(find.byType(ZodiacCard));
    expect(zodiac.dy, greaterThan(fish.dy));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

void _noop(int _) {}
