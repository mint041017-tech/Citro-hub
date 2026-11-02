import 'dart:convert';
import 'dart:typed_data';

import 'package:citro/services/image_store.dart';
import 'package:citro/widgets/app_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const url = 'cache-test://community/one';
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  test('memory cache returns the same bytes without another lookup', () async {
    await ImageStore.put(url, Uint8List.fromList(png));
    final cached = ImageStore.peek(url);
    expect(cached, isNotNull);
    expect(identical(cached, ImageStore.peek(url)), isTrue);
  });

  testWidgets('AppImage paints cached bytes on the first frame', (tester) async {
    await tester.runAsync(() async {
      await ImageStore.put(url, Uint8List.fromList(png));
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppImage(url))),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}