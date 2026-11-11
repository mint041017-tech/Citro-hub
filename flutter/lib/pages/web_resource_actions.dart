import 'package:flutter/material.dart';

import '../data/resources.dart';
import 'in_app_web.dart';

/// 直接打开资源 / 下载，不再弹「打开页面 / 确认下载 / 选择版本」确认框。
/// 有多个版本时默认走推荐版（没有推荐就第一个）。
Future<void> openCitroResource(
  BuildContext context,
  String title,
  String url, {
  String? warn,
  List<ResourceVersion> versions = const [],
  bool download = false,
}) async {
  final isDownload = download ||
      RegExp(
        r'\.(exe|zip|7z|apk|msi)(\?|$)',
        caseSensitive: false,
      ).hasMatch(url);
  final chosen = versions.isEmpty
      ? null
      : versions.firstWhere((v) => v.recommended, orElse: () => versions.first);
  await openCitroPage(
    context,
    chosen?.url ?? url,
    title: title,
    download: isDownload,
  );
}

void openCitroTool(BuildContext context, ToolItem tool) {
  if (tool.hash != null) {
    Navigator.of(context).pushNamed(tool.hash!.replaceFirst('#', ''));
  } else if (tool.url != null) {
    openCitroResource(
      context,
      tool.name,
      tool.url!,
      warn: tool.warn,
      versions: tool.versions,
    );
  }
}
