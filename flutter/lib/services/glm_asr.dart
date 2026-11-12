import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 直连智谱语音转写。
///
/// 正常路径应该走服务端 `/api/asr`（key 不出端），只有在服务端还没部署
/// 或未配置 GLM key 时，才退回这里，保证语音功能不至于整条不可用。
///
/// 注意：key 不写进仓库、不进安装包，只能用 `--dart-define` 注入，
/// 否则密钥会随 APK 一起泄露。
class GlmAsr {
  GlmAsr._();

  /// 直连 key 只由 `--dart-define=GLM_ASR_KEY=...` 注入，**不写进仓库、不进安装包**。
  /// 正常路径是服务端 `/api/asr`（key 不出端），这里只是服务端没配 key 时的兜底。
  static const String _key = String.fromEnvironment('GLM_ASR_KEY');

  static const String _endpoint =
      'https://open.bigmodel.cn/api/paas/v4/audio/transcriptions';

  static Future<String> transcribe(String base64Audio) async {
    if (_key.isEmpty) {
      throw Exception('未配置 GLM_ASR_KEY');
    }
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