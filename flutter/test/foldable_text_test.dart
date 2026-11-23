import 'package:citro/widgets/foldable_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(String text) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 220,
        child: FoldableText(
          text: text,
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('长文超过五行折叠，展开后可收起', (tester) async {
    final text = List.generate(
      10,
      (i) => '第${i + 1}行是一段足够长的社区正文，用来把宽度占满。',
    ).join('\n');
    await tester.pumpWidget(_host(text));
    expect(find.text('展开全文'), findsOneWidget);

    await tester.tap(find.text('展开全文'));
    await tester.pump();
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('短文不出现展开按钮', (tester) async {
    await tester.pumpWidget(_host('今天只写了两行。\n第二行也很短。'));
    expect(find.text('展开全文'), findsNothing);
  });
}
