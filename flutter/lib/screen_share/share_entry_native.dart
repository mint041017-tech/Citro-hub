import 'package:flutter/material.dart';

import '../theme/crisp_page_route.dart';
import 'screen_share_page.dart';

/// 原生端：直接开房间页。
///
/// [roomCode] 来自邀请链接（`https://share.mint1017.cn/?room=123456`），有就先填进输入框。
Future<void> openScreenShare(
  BuildContext context, {
  String? roomCode,
}) async {
  await Navigator.of(context).push(
    CitroCrispPageRoute<void>(
      builder: (_) => ScreenSharePage(initialCode: roomCode),
    ),
  );
}
