import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/motion.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/motion_widgets.dart';
import 'package:citro/widgets/tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'motion-test'
      ..guestName = '动效测试';
  });

  Widget host(Widget child, {bool reduce = false}) => AppScope(
    state: AppState.instance,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCitroTheme(CitroColors.light),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: inner ?? const SizedBox.shrink(),
      ),
      home: Scaffold(body: SizedBox(width: 390, height: 844, child: child)),
    ),
  );

  testWidgets('stagger settles to the final state without leftover opacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const CitroStagger(children: [Text('一'), Text('二'), Text('三')])),
    );
    await tester.pump();
    expect(find.text('一'), findsOneWidget);
    expect(find.text('三'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    // 动画结束后不再包 Opacity，列表项回到普通渲染路径。
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('reduced motion shows content immediately', (tester) async {
    await tester.pumpWidget(
      host(const CitroStagger(children: [Text('一'), Text('二')]), reduce: true),
    );
    await tester.pump();
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('tab bar exposes four tabs and the CICI entry', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setter) {
            return Stack(
              children: [
                CitroTabBar(
                  index: index,
                  onChanged: (i) => setter(() => index = i),
                  onCiciTap: () {},
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pump();

    // 四格目的地 + CICI 头像按钮，全部通过 Semantics 暴露。
    for (final label in ['首页', '计划', '游戏', '社区', 'CICI 智能助手']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.bySemanticsLabel('计划'));
    await tester.pump();
    expect(index, 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet motion is shared and honours reduced motion', (
    tester,
  ) async {
    late AnimationStyle style;
    late AnimationStyle reducedStyle;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            style = CitroMotion.sheetStyle(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(style.curve, CitroMotion.drawer);
    expect(style.duration, CitroMotion.sheet);
    expect(style.reverseCurve, CitroMotion.exit);
    expect(style.reverseDuration, CitroMotion.sheetReverse);

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            reducedStyle = CitroMotion.sheetStyle(context);
            return const SizedBox.shrink();
          },
        ),
        reduce: true,
      ),
    );
    expect(reducedStyle.duration, Duration.zero);
    expect(reducedStyle.reverseDuration, Duration.zero);
  });

  testWidgets('tab switching duration is shorter on desktop-like targets', (
    tester,
  ) async {
    expect(CitroMotion.tab.inMilliseconds, lessThanOrEqualTo(300));
    expect(
      CitroMotion.tabDesktop.inMilliseconds,
      lessThan(CitroMotion.tab.inMilliseconds),
    );
    expect(
      CitroMotion.modalReverse.inMilliseconds,
      lessThan(CitroMotion.modal.inMilliseconds),
    );
    expect(
      CitroMotion.pageTouchReverse.inMilliseconds,
      lessThan(CitroMotion.pageTouch.inMilliseconds),
    );
  });
}
