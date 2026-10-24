import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/paper.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clickable cards lift and scale on pointer hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCitroTheme(CitroColors.light),
        home: Scaffold(
          body: Center(
            child: Pressable(
              onTap: () {},
              borderRadius: BorderRadius.circular(14),
              child: const SizedBox(
                key: Key('hover-target'),
                width: 120,
                height: 80,
              ),
            ),
          ),
        ),
      ),
    );

    AnimatedScale scale() => tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(Pressable),
        matching: find.byType(AnimatedScale),
      ),
    );
    List<BoxShadow> shadows() {
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (container.decoration! as BoxDecoration).boxShadow!;
    }

    expect(scale().scale, 1);
    expect(shadows(), hasLength(1));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('hover-target'))));
    await tester.pumpAndSettle();

    expect(scale().scale, greaterThan(1));
    expect(shadows(), hasLength(1));
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(Pressable),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(container.transform, isNotNull);
  });
}
