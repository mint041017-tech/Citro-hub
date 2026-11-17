import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screen_share/share_entry.dart';
import '../utils/links.dart';
import 'in_app_web_native.dart' if (dart.library.html) 'in_app_web_web.dart';

export 'in_app_web_native.dart' if (dart.library.html) 'in_app_web_web.dart';

/// 一起看域名：原生端开自己的房间页，Web 端落网页观众页。
bool _isScreenShareHost(String host) =>
    host == 'share.mint1017.cn' || host == 'share.mint1017.cn.';

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

  // 一起看是原生页面优先：WebView 里做不了 getDisplayMedia，
  // 而且媒体走 Cloudflare SFU，不经过本站。
  final uri = Uri.tryParse(normalized);
  if (uri != null && _isScreenShareHost(uri.host.toLowerCase())) {
    await openScreenShare(
      context,
      roomCode: uri.queryParameters['room'],
    );
    return;
  }

  if (!context.mounted) return;
  await openInAppPage(
    context,
    normalized,
    title: title,
    crispExit: uri != null && _isLiveHost(uri.host.toLowerCase()),
  );
}
