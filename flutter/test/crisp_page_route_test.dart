import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/crisp_page_route.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('iOS 上保留左缘滑动返回手势', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCitroTheme(
          CitroColors.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey<String>('open'),
                onPressed: () => Navigator.of(context).push(
                  CitroCrispPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(
                        child: SizedBox(
                          key: ValueKey<String>('target'),
                          width: 160,
                          height: 160,
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open')));
    await tester.pumpAndSettle();

    final target = find.byKey(const ValueKey<String>('target'));
    final before = tester.getTopLeft(target).dx;

    // 从屏幕左缘往右拖：Cupertino 路由会跟手右移，自定义转场则会吞掉手势。
    final gesture = await tester.startGesture(const Offset(1, 420));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    final after = tester.getTopLeft(target).dx;
    expect(after - before, greaterThan(40));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('进场未完成时返回，透明度不会一帧闪灭', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late BuildContext pushedContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCitroTheme(CitroColors.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey<String>('open'),
                onPressed: () => Navigator.of(context).push(
                  CitroCrispPageRoute<void>(
                    builder: (ctx) {
                      pushedContext = ctx;
                      return const Scaffold(
                        body: Center(
                          child: SizedBox(
                            key: ValueKey<String>('target'),
                            width: 160,
                            height: 160,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open')));
    await tester.pump();
    // 进场 280ms 只走 120ms。
    await tester.pump(const Duration(milliseconds: 120));

    double pageOpacity() {
      final opacities = tester.widgetList<Opacity>(
        find.ancestor(
          of: find.byKey(const ValueKey<String>('target')),
          matching: find.byType(Opacity),
        ),
      );
      return opacities
          .map((widget) => widget.opacity)
          .firstWhere((value) => value < 1.0);
    }

    final before = pageOpacity();
    expect(before, greaterThan(0.6));

    Navigator.of(pushedContext).pop();
    await tester.pump();
    final after = pageOpacity();
    // 旧实现每帧重建 CurvedAnimation，这里会从约 0.9 直接掉到 0.1。
    expect(after, greaterThan(0.5));
    expect((before - after).abs(), lessThan(0.4));

    await tester.pumpAndSettle();
  });
}
