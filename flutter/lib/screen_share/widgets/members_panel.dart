import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/modal.dart';
import '../../widgets/paper.dart';
import '../room_models.dart';
import '../screen_share_controller.dart';
import '../screen_share_theme.dart';

/// 成员列表。主持人可以踢人。
Future<void> showMembersPanel(
  BuildContext context,
  ScreenShareController controller,
) {
  return showCitroSheet(
    context: context,
    backgroundColor: shareColors.surface,
    builder: (_) => ShareTheme(child: _MembersPanel(controller: controller)),
  );
}

class _MembersPanel extends StatelessWidget {
  const _MembersPanel({required this.controller});

  final ScreenShareController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  child: Row(
                    children: [
                      Text(
                        '成员',
                        style: context.heading(
                          size: CitroType.subtitle,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x1),
                      Text(
                        '${controller.members.where((m) => m.online).length} 人在线',
                        style: context.body(
                          size: CitroType.caption,
                          color: c.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                _CloseButton(onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final members = [...controller.members];
              members.sort((a, b) {
                if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
                if (a.online != b.online) return a.online ? -1 : 1;
                return a.displayName.compareTo(b.displayName);
              });
              if (members.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.x4),
                  child: Center(
                    child: Text(
                      '房间里还没有人',
                      style: context.body(
                        size: CitroType.meta,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                );
              }
              return Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
                  itemCount: members.length,
                  itemBuilder: (context, i) {
                    final m = members[i];
                    return _MemberRow(
                      member: m,
                      canKick: controller.isHost && !m.isHost && !m.self,
                      onKick: () => _confirmKick(context, controller, m),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.x2),
        ],
      ),
    );
  }
}

/// 踢人必须先确认：误触一下就把人赶出去，是最容易得罪人的交互。
Future<void> _confirmKick(
  BuildContext context,
  ScreenShareController controller,
  RoomMember member,
) async {
  final ok = await showCitroDialog<bool>(
    context,
    builder: (ctx) => ShareTheme(
      child: PaperDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '移出一起看？',
              style: ctx.heading(size: CitroType.subtitle, color: ctx.c.ink),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              '把「${member.displayName}」移出房间，他可以凭房间号再进来。',
              style: ctx.body(size: CitroType.meta, color: ctx.c.inkSoft),
            ),
            const SizedBox(height: AppSpacing.x3),
            CitroButton(
              label: '移出',
              style: CitroButtonStyle.danger,
              expanded: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: AppSpacing.x1),
            CitroButton(
              label: '取消',
              style: CitroButtonStyle.ghost,
              expanded: true,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok == true) await controller.kickMember(member.uid);
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.canKick,
    required this.onKick,
  });

  final RoomMember member;
  final bool canKick;
  final VoidCallback onKick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final name = member.displayName;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: 6,
      ),
      child: Row(
        children: [
          CitroAvatar(
            text: name.isEmpty ? '?' : name.characters.first,
            size: 36,
          ),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.self ? '$name（我）' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(
                          size: CitroType.label,
                          weight: CitroType.medium,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (member.isHost) ...[
                      const SizedBox(width: 6),
                      _Badge(text: '主持人', mint: true),
                    ],
                    if (member.hasScreen) ...[
                      const SizedBox(width: 4),
                      _Badge(text: '放映中'),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (member.hasMic)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: AppIcon(AppIcons.mic, size: 12, color: c.mint),
                      ),
                    Text(
                      member.online
                          ? (member.hasScreen
                              ? '正在一起看'
                              : (member.hasMic ? '开着麦' : '在线'))
                          : '离线',
                      style: context.body(
                        size: CitroType.caption,
                        color: c.inkSoft,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (canKick)
            Pressable(
              onTap: onKick,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.dangerSoft,
                  borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                  border: Border.all(color: c.danger.withValues(alpha: .3)),
                ),
                child: Text(
                  '移出',
                  style: context.body(size: CitroType.caption, color: c.danger),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.mint = false});

  final String text;
  final bool mint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: mint ? c.mintSoft : c.accentLt,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(
          color: mint ? c.mintLine : c.accent.withValues(alpha: .3),
        ),
      ),
      child: Text(
        text,
        style: context.body(
          size: CitroType.micro,
          weight: CitroType.medium,
          color: mint ? c.mintInk : c.accentInk,
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