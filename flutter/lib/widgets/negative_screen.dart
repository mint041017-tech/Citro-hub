import 'package:flutter/material.dart';

import '../data/resources.dart';
import '../overlays/notes_modal.dart';
import '../overlays/pomodoro_sheet.dart';
import '../pages/web_resource_actions.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'paper.dart';

/// 首页下拉「负一屏」：只放 6 个真正常用的快捷入口。
///
/// 资源库（Mod / 驱动）已经从首页撤掉，这里也不再重复；
/// 需要下载资源时去游戏页的「资源库」或「我的」页面。
class NegativeScreen extends StatelessWidget {
  final VoidCallback onClose;

  const NegativeScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ColoredBox(
      color: c.bg2,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x3,
                  AppSpacing.x2,
                  AppSpacing.x3,
                  AppSpacing.x2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '快捷工具',
                            style: context.heading(size: CitroType.titleLg),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '上滑推回 · 点右上角关闭',
                            style: context.body(
                              size: CitroType.small,
                              color: c.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Pressable(
                      onTap: onClose,
                      hoverLift: 0,
                      hoverShadow: false,
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.line),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.close, width: 2.2),
                            size: 17,
                            color: c.ink2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
                child: _QuickGrid(items: _buildItems(context)),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.x4)),
          ],
        ),
      ),
    );
  }

  /// 固定的 6 项：灵敏度 / 玩法抽签 / 视野live / 屏幕分享 / 便签 / 番茄钟。
  List<_QuickItem?> _buildItems(BuildContext context) {
    final byName = {for (final t in kTools) t.name: t};
    return [
      _item(context, byName['灵敏度'], AppIcons.clock),
      _item(context, byName['玩法抽签'], AppIcons.sparkle),
      _item(context, byName['视野live'], AppIcons.eye),
      _item(context, byName['屏幕分享'], AppIcons.monitor),
      _QuickItem(
        name: '便签',
        desc: '随手记点什么',
        icon: AppIcons.note,
        onTap: () => showNotesModal(context),
      ),
      _QuickItem(
        name: '番茄钟',
        desc: '专注计时与休息提醒',
        icon: AppIcons.target,
        onTap: () => showPomodoroOverlay(context),
      ),
    ];
  }

  _QuickItem? _item(
    BuildContext context,
    ToolItem? tool,
    String fallbackIcon,
  ) {
    if (tool == null) return null;
    return _QuickItem(
      name: tool.name,
      desc: tool.desc,
      icon: tool.icon.isEmpty ? fallbackIcon : tool.icon,
      onTap: () => openCitroTool(context, tool),
    );
  }
}

class _QuickItem {
  final String name;
  final String desc;
  final String icon;
  final VoidCallback onTap;

  const _QuickItem({
    required this.name,
    required this.desc,
    required this.icon,
    required this.onTap,
  });
}

class _QuickGrid extends StatelessWidget {
  final List<_QuickItem?> items;

  const _QuickGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final tiles = items.whereType<_QuickItem>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          Row(
            children: [
              Expanded(child: _QuickTile(item: tiles[i])),
              if (i + 1 < tiles.length) ...[
                const SizedBox(width: AppSpacing.x2),
                Expanded(child: _QuickTile(item: tiles[i + 1])),
              ],
            ],
          ),
          if (i + 2 < tiles.length) const SizedBox(height: AppSpacing.x2),
        ],
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  final _QuickItem item;

  const _QuickTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: item.onTap,
      hoverLift: 0,
      hoverShadow: false,
      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x2),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.tintYellow,
                borderRadius: BorderRadius.circular(CitroColors.radii.small),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(item.icon, width: 2),
                  size: 19,
                  color: c.accentInk,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.heading(size: CitroType.label),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(size: CitroType.micro, color: c.inkSoft),
                  ),
                ],
              ),
            ),
            AppIcon(
              strokeSvg(AppIcons.arrowUpRight, width: 2.2),
              size: 15,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}
