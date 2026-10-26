import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Web 构建本身就在浏览器里，新标签页可避开第三方站点的 iframe 拦截。
Future<void> openInAppPage(
  BuildContext context,
  String url, {
  String? title,
}) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
