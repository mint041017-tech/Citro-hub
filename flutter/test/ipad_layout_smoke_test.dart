import 'package:citro/games/game_registry.dart';
import 'package:citro/games/game_ui.dart';
import 'package:citro/overlays/ai_chat.dart';
import 'package:citro/overlays/auth_modal.dart';
import 'package:citro/overlays/composer_sheet.dart';
import 'package:citro/overlays/cook_editor.dart';
import 'package:citro/pages/community_page.dart';
import 'package:citro/pages/cook_page.dart';
import 'package:citro/pages/games_page.dart';
import 'package:citro/pages/home_page.dart';
import 'package:citro/pages/legal_page.dart';
import 'package:citro/pages/me_page.dart';
import 'package:citro/pages/play_page.dart';
import 'package:citro/pages/res_page.dart';
import 'package:citro/pages/sens_page.dart';
import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/breakpoints.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/corner_guard.dart';
import 'package:citro/widgets/tablet_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _noop(int _) {}

void main() {
  const sizes = <String, Size>{
    'iphone': Size(390, 844),
    'duo-outer': Size(466, 678),
    'duo-inner': Size(669, 951),
    'duo-inner-landscape': Size(951, 669),
    'ipad-portrait': Size(1024, 1366),
    'ipad-landscape': Size(1366, 1024),
    'ipad-half': Size(678, 1024),
    'ipad-third': Size(478, 1024),
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'ipad-layout-test'
      ..guestName = '游客·布局测试'
      ..user = const User(name: '用于验证布局的长昵称测试用户', profileDone: true);
    GameScaffold.liveEnabled = false;
  });

  Widget host(Widget child, {bool guard = false}) => AppScope(
    state: AppState.instance,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCitroTheme(CitroColors.light),
      darkTheme: buildCitroTheme(CitroColors.darkColors),
      builder: guard
          ? (context, child) =>
                CitroDuoCornerGuard(child: child ?? const SizedBox.shrink())
          : null,
      home: child,
    ),
  );

  Future<void> verifyPage(
    WidgetTester tester,
    String name,
    Size size,
    Widget page,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(host(page, guard: CitroForm.duoDevice(size)));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.takeException(),
      isNull,
      reason: '$name at ${size.width}x${size.height}',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('tablet rail and home dashboard', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1032, 1366);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      host(
        Row(
          children: [
            SizedBox(
              width: 208,
              child: CitroTabletSidebar(index: 0, onChanged: (_) {}),
            ),
            const Expanded(
              child: CitroLayoutScope(
                contentWidth: 824,
                tabletNav: true,
                child: HomePage(onSwitchTab: _noop),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('逛一逛'), findsOneWidget);
    expect(find.text('食谱日记'), findsOneWidget);
    expect(find.text('Citro · 今天也要开心'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('tablet games grid', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1032, 1366);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      host(
        const CitroLayoutScope(
          contentWidth: 824,
          tabletNav: true,
          child: GamesPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final entry in sizes.entries) {
    testWidgets('core pages ${entry.key}', (tester) async {
      addTearDown(tester.view.reset);
      final pages = <String, Widget>{
        'home': HomePage(onSwitchTab: (_) {}),
        'games': const GamesPage(),
        'community': const CommunityPage(),
        'me': const MePage(),
        'cook': const CookPage(),
        'resources': const ResPage(),
        'play': const PlayPage(),
        'sensitivity': const SensPage(),
        'privacy': const LegalPage(doc: LegalDoc.privacy),
        'terms': const LegalPage(doc: LegalDoc.terms),
      };
      for (final page in pages.entries) {
        await verifyPage(tester, page.key, entry.value, page.value);
      }
    });

    testWidgets('native games ${entry.key}', (tester) async {
      addTearDown(tester.view.reset);
      for (final game in kGameCards.where((game) => game.key != 'gbrake')) {
        await verifyPage(
          tester,
          game.title,
          entry.value,
          buildGamePage(game.key),
        );
      }
    });

    testWidgets('dialogs and sheets ${entry.key}', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      final overlays = <String, Future<void> Function(BuildContext)>{
        'register': (context) => showAuthModal(context, mode: 'register'),
        'ai': showAiChat,
        'composer': (context) async => await showComposerSheet(context),
        'cook-editor': (context) async => await showCookEditor(context, null),
      };
      for (final overlay in overlays.entries) {
        await tester.pumpWidget(
          host(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => overlay.value(context),
                  child: const Text('open'),
                ),
              ),
            ),
            guard: CitroForm.duoDevice(entry.value),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull, reason: overlay.key);
        if (overlay.key == 'ai') {
          final editable = tester.widget<EditableText>(
            find.byType(EditableText),
          );
          expect(editable.focusNode.hasFocus, isTrue);
          expect(tester.testTextInput.isVisible, isTrue);
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump(const Duration(milliseconds: 100));
        final fields = find.byType(TextField);
        if (fields.evaluate().isNotEmpty) {
          await tester.ensureVisible(fields.last);
          await tester.tap(fields.last);
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${overlay.key} keyboard at ${entry.value}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        tester.view.resetViewInsets();
      }
    });
  }
}
