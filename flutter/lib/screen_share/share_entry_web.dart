import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Web 端没有 flutter_webrtc（1.6.3 的 pubspec 没声明 web 平台），
/// 只能落在网页观众页。
Future<void> openScreenShare(
  BuildContext context, {
  String? roomCode,
}) async {
  final code = (roomCode ?? '').trim();
  final uri = Uri.parse(
    code.isEmpty
        ? 'https://share.mint1017.cn/'
        : 'https://share.mint1017.cn/?room=$code',
  );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
