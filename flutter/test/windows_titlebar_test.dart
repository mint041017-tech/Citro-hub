import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/windows_title_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('window controls float at the top-right without a title bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCitroTheme(CitroColors.darkColors),
        builder: (context, child) => Stack(
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            const Positioned(
              top: 4,
              right: 10,
              child: Material(
                type: MaterialType.transparency,
                child: CitroWindowControls(),
              ),
            ),
          ],
        ),
        home: const Scaffold(backgroundColor: Colors.black),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 原来的整条标题栏已移除，品牌字不再出现在窗口顶部。
    expect(find.text('Citro'), findsNothing);
    for (final label in ['最小化', '最大化', '关闭']) {
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label,
        ),
        findsOneWidget,
        reason: label,
      );
    }

    // 三键悬浮在右上角，且只占一枚按钮的高度，不占整条标题栏。
    final rect = tester.getRect(find.byType(CitroWindowControls));
    expect(rect.top, 4);
    expect(rect.right, 1190);
    expect(rect.height, lessThanOrEqualTo(34));
    expect(tester.takeException(), isNull);
  });
}
