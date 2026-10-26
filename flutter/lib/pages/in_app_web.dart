import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/links.dart';
import 'in_app_web_native.dart' if (dart.library.html) 'in_app_web_web.dart';

export 'in_app_web_native.dart' if (dart.library.html) 'in_app_web_web.dart';

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
  await openInAppPage(context, normalized, title: title);
}
