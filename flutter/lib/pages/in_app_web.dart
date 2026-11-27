import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/links.dart';
import 'in_app_web_native.dart' if (dart.library.html) 'in_app_web_web.dart';

export 'in_app_web_native.dart' if (dart.library.html) 'in_app_web_web.dart';

/// 视野live：工具页里停留最久的网页，退场走完整淡出。
bool _isLiveHost(String host) =>
    host == 'shijiao.xingpaste.com' || host == 'shijiao.xingpaste.com.';

/// 下载类链接交给系统，其余网页都在应用内打开。
Future<void> openCitroPage(
  BuildContext context,
  String url, {
  String? title,
  bool download = false,
}) async {
  final normalized = normalizeWebUrl(url);
  if (normalized == null) return;
  if (download || isDownloadLink(normalized)) {
    await launchUrl(
      Uri.parse(normalized),
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  if (!context.mounted) return;
  final uri = Uri.tryParse(normalized);
  await openInAppPage(
    context,
    normalized,
    title: title,
    crispExit: uri != null && _isLiveHost(uri.host.toLowerCase()),
  );
}
