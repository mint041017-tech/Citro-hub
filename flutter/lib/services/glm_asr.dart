import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 直连智谱语音转写。
///
/// 正常路径应该走服务端 `/api/asr`（key 不出端），只有在服务端还没部署
/// 或未配置 GLM key 时，才退回这里，保证语音功能不至于整条不可用。
class GlmAsr {
  GlmAsr._();

  static const String _key = String.fromEnvironment(
    'GLM_ASR_KEY',
    defaultValue: '9afd1948557345cab1940ba326792230.SYvdnKqsRZPJDVkn',
  );

  static const String _endpoint =
      'https://open.bigmodel.cn/api/paas/v4/audio/transcriptions';

  static Future<String> transcribe(String base64Audio) async {
    final res = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Authorization': 'Bearer $_key',
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'model': 'glm-asr-2512',
            'file_base64': base64Audio,
          }),
        )
        .timeout(const Duration(seconds: 45));
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = data?['error'] is Map
          ? '${(data!['error'] as Map)['message'] ?? ''}'
          : '';
      throw Exception(
        message.isEmpty ? '转写服务返回 ${res.statusCode}' : message,
      );
    }
    final text = data?['text'];
    return text is String ? text.trim() : '';
  }
}