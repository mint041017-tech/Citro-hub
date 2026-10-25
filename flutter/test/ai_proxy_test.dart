import 'dart:convert';

import 'package:citro/services/ai.dart';
import 'package:citro/services/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'completion uses the Citro proxy without a provider credential',
    () async {
      final client = MockClient((request) async {
        expect(request.url, Uri.parse('${Api.base}/api/ai'));
        expect(request.headers['Authorization'], isNull);
        final payload = jsonDecode(request.body) as Map;
        expect(payload['stream'], isFalse);
        expect((payload['messages'] as List).last['content'], '合成连接检查');
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '测试回复'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await http.runWithClient(
        () => AiService.complete(prompt: '合成连接检查'),
        () => client,
      );
      expect(result, '测试回复');
    },
  );

  test(
    'proxy chat decodes split UTF-8 SSE content and ignores reasoning',
    () async {
      final client = MockClient.streaming((request, body) async {
        expect(request.url, Uri.parse('${Api.base}/api/ai'));
        expect(request.headers['Authorization'], isNull);
        final payload = jsonDecode(await body.bytesToString()) as Map;
        expect(payload['stream'], isTrue);
        final events = [
          'data: {"choices":[{"delta":{"reasoning_content":"推理"}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"你好"}}]}\n\n',
          'data: [DONE]\n\n',
        ].join();
        return http.StreamedResponse(
          Stream.fromIterable(utf8.encode(events).map((byte) => [byte])),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final result = await http.runWithClient(
        () => AiService.streamChat([
          {'role': 'user', 'content': '合成连接检查'},
        ]).join(),
        () => client,
      );
      expect(result, '你好');
    },
  );

  test(
    'proxy service errors are shown without exposing a raw JSON body',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'err': 'AI 服务暂未配置'}),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );

      await expectLater(
        http.runWithClient(
          () => AiService.complete(prompt: '合成连接检查'),
          () => client,
        ),
        throwsA(
          isA<AiException>().having(
            (error) => error.message,
            'message',
            'AI 服务暂未配置',
          ),
        ),
      );
    },
  );
}
