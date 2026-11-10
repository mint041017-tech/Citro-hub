import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

Future<void> showBlockedUsersSheet(BuildContext context) {
  return showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BlockedUsersSheet(),
  );
}

class _BlockedUsersSheet extends StatelessWidget {
  const _BlockedUsersSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: MediaQuery.sizeOf(context).height * .62,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(CitroColors.radii.card)),
        border: Border.all(color: c.line),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: c.line2,
                borderRadius: BorderRadius.circular(CitroColors.radii.xs),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
              child: Row(
                children: [
                  Text('黑名单', style: context.heading(size: 18)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AppIcon(
                        strokeSvg(AppIcons.close, width: 2.2),
                        size: 18,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(
                '黑名单只保存在当前设备。被拉黑昵称的动态、评论和消息会从这里隐藏；匿名内容请使用举报处理。',
                style: context.body(size: CitroType.small, color: c.inkSoft, height: 1.6),
              ),
            ),
            CitroDivider(color: c.line2.withAlpha(140)),
            Expanded(
              child: AnimatedBuilder(
                animation: AppState.instance,
                builder: (context, _) {
                  final users = AppState.instance.blockedUsers.toList()..sort();
                  if (users.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🫧', style: TextStyle(fontSize: 36)),
                          const SizedBox(height: 8),
                          Text(
                            '还没有拉黑任何人',
                            style: context.body(size: CitroType.meta, color: c.inkSoft),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '在动态或评论的「…」里可以拉黑',
                            style: context.body(size: CitroType.small, color: c.inkSoft),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: CitroDivider(color: c.line2.withAlpha(110)),
                    ),
                    itemBuilder: (_, i) {
                      final nick = users[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: c.surface2,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.line2),
                              ),
                              child: Center(
                                child: Text(
                                  nick.isEmpty ? '?' : nick[0],
                                  style: context.heading(
                                    size: CitroType.bodyLg,
                                    color: c.accentInk,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                nick,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.body(
                                  size: CitroType.body,
                                  weight: CitroType.medium,
                                  color: c.ink,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                await AppState.instance.unblockUser(nick);
                                if (context.mounted) {
                                  AppToast.show(context, '已解除 $nick');
                                }
                              },
                              child: Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.surface2,
                                  borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                                  border: Border.all(color: c.line2),
                                ),
                                child: Text(
                                  '解除',
                                  style: context.body(
                                    size: CitroType.small,
                                    weight: CitroType.medium,
                                    color: c.accentInk,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
