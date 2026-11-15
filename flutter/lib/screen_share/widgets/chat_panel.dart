import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/modal.dart';
import '../../widgets/paper.dart';
import '../room_models.dart';
import '../screen_share_controller.dart';
import '../screen_share_theme.dart';

/// 文字沟通面板。聊天走 WebSocket，不占媒体带宽。
Future<void> showChatPanel(
  BuildContext context,
  ScreenShareController controller,
) {
  return showCitroSheet(
    context: context,
    isScrollControlled: true,
    // 弹层走根路由，背景和内容都显式套上暖黑剧场主题。
    backgroundColor: shareColors.surface,
    builder: (_) => ShareTheme(child: _ChatPanel(controller: controller)),
  );
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({required this.controller});

  final ScreenShareController controller;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.controller.sendChat(text);
    _input.clear();
    // 自己刚发的消息要等服务端广播回来，这里只把列表滚到底。
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final controller = widget.controller;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                AppSpacing.x2,
                AppSpacing.x2,
                AppSpacing.x1,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '聊天',
                      style: context.heading(
                        size: CitroType.subtitle,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (!controller.wsConnected) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: c.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '连接断开',
                      style: context.body(
                        size: CitroType.caption,
                        color: c.danger,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x1),
                  ],
                  _CloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            Divider(height: 1, color: c.line),
            Flexible(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final messages = controller.chat;
                  if (messages.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.x4),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '还没有人说话',
                              style: context.body(
                                size: CitroType.body,
                                color: c.ink2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '发第一条消息，打个招呼吧',
                              style: context.body(
                                size: CitroType.caption,
                                color: c.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      return _MessageRow(
                        message: m,
                        self: controller.selfUid != null &&
                            m.uid == controller.selfUid,
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                AppSpacing.x1,
                AppSpacing.x2,
                AppSpacing.x2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CitroTextField(
                      controller: _input,
                      hint: '说点什么…',
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  CitroButton(
                    label: '发送',
                    style: CitroButtonStyle.accent,
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: 1,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: c.line),
        ),
        child: AppIcon(
          strokeSvg(AppIcons.close, width: 2),
          size: 15,
          color: c.ink2,
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, required this.self});

  final ChatMessage message;
  final bool self;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: 5,
      ),
      child: Column(
        crossAxisAlignment:
            self ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            self ? '${message.name}（我）' : message.name,
            style: context.body(size: CitroType.caption, color: c.inkSoft),
          ),
          const SizedBox(height: 3),
          Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: self ? c.accentLt : c.surface2,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(self ? 16 : 5),
                bottomRight: Radius.circular(self ? 5 : 16),
              ),
              border: Border.all(
                color: self ? c.accent.withValues(alpha: .32) : c.line,
              ),
            ),
            child: Text(
              message.text,
              style: context.body(size: CitroType.label, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}