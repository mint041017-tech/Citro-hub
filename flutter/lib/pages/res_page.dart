import 'package:flutter/material.dart';

import '../data/resources.dart';
import '../overlays/notes_modal.dart';
import '../services/platform.dart' as platform;
import '../widgets/desktop_shell.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/paper.dart';
import '../widgets/tablet_shell.dart';
import 'web_resource_actions.dart';

class ResPage extends StatefulWidget {
  final bool embedded;

  const ResPage({super.key, this.embedded = false});
  @override
  State<ResPage> createState() => _ResPageState();
}

const _gamesMovedTools = {'玩法抽签', '瞬投', '屏幕分享', '视野live'};

/// 顶部快捷工具：这三项在下方列表里不再重复出现（「便签」不在 kTools 里）。
const _quickToolNames = {'屏幕分享', '玩法抽签', '视野live'};

class _QuickTool {
  final String name;
  final String desc;
  final String icon;
  final Color tint;
  final VoidCallback onTap;

  const _QuickTool({
    required this.name,
    required this.desc,
    required this.icon,
    required this.tint,
    required this.onTap,
  });
}

class _ResPageState extends State<ResPage> {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final layout = CitroLayoutScope.maybeOf(context);
    final contentWidth =
        layout?.contentWidth ?? MediaQuery.sizeOf(context).width;
    final wide = (layout?.tabletNav ?? false) && contentWidth >= 940;
    final maxWidth = wide ? 1120.0 : 840.0;
    final tabBar = widget.embedded && !(layout?.tabletNav ?? false);
    final mods = kMods;
    // 「屏幕分享」「玩法抽签」「视野live」已经提到顶部快捷工具里，
    // 下面不再重复显示。
    final tools = kTools
        .where(
          (t) =>
              !_quickToolNames.contains(t.name) &&
              (!(platform.isAndroid || platform.isIOS) ||
                  !_gamesMovedTools.contains(t.name)),
        )
        .toList();
    final drivers = [...kDriversWeb, ...kDriversClient];
    // iPad 上装不了 PC 外设驱动，整块不展示（用户要求）。
    final hideDrivers = platform.isIOS && (layout?.tabletNav ?? false);
    return Scaffold(
      body: CitroBackground(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  8,
                  AppSpacing.pageTop(contentWidth),
                  8 + CitroDesktopShell.windowControlsInset,
                  tabBar ? 110 : 30,
                ),
                child: CitroStagger(
                  step: const Duration(milliseconds: 28),
                  children: [
                    Row(
                      children: [
                        Text('资源库', style: context.heading(size: 28)),
                        const Spacer(),
                        Text(
                          '全部资源',
                          style: context.body(
                            size: CitroType.small,
                            color: c.inkSoft,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    _quickToolsRow(context, columns: wide ? 4 : 2),
                    if (mods.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x2),
                      CitroCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const CitroSectionHeader('游戏 Mod', size: 20),
                            const SizedBox(height: AppSpacing.x2),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final columns = wide ? 3 : 2;
                                final cellWidth =
                                    (constraints.maxWidth -
                                        10 * (columns - 1)) /
                                    columns;
                                // 封面固定 2:1，下方文字区高度固定，避免按比例撑出大片空白。
                                final extent = (cellWidth - 14) / 2 + 72;
                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                        mainAxisExtent: extent,
                                      ),
                                  itemCount: mods.length,
                                  itemBuilder: (_, i) =>
                                      _modCard(context, mods[i]),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (tools.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x2),
                      CitroCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const CitroSectionHeader('小工具', size: 20),
                            const SizedBox(height: AppSpacing.x2),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: wide ? 3 : 2,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 0,
                                    // 工具行内容高度固定，两列下不再用宽高比把卡片拉高。
                                    mainAxisExtent: 104,
                                  ),
                              itemCount: tools.length,
                              itemBuilder: (_, i) =>
                                  _toolCard(context, tools[i]),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (drivers.isNotEmpty && !hideDrivers) ...[
                      const SizedBox(height: AppSpacing.x2),
                      CitroCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const CitroSectionHeader('外设驱动', size: 20),
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              '网页驱动',
                              style: context.heading(
                                size: CitroType.bodyLg,
                                color: c.ink2,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x1),
                            _driverList(
                              context,
                              kDriversWeb.where((d) => drivers.contains(d)),
                            ),
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              '客户端驱动',
                              style: context.heading(
                                size: CitroType.bodyLg,
                                color: c.ink2,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x1),
                            _driverList(
                              context,
                              kDriversClient.where((d) => drivers.contains(d)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!platform.isWindows) ...[
                      const SizedBox(height: AppSpacing.x2),
                      CitroCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: c.surface2,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: AppIcon(
                                  strokeSvg(AppIcons.monitor, width: 2),
                                  size: 20,
                                  color: c.ink2,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '更多资源请移步 PC 版',
                                    style: context.heading(
                                      size: CitroType.bodyLg,
                                    ),
                                  ),
                                  Text(
                                    'chimu-claw.xyz',
                                    style: context.body(
                                      size: CitroType.caption,
                                      color: c.accentInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AppIcon(
                              strokeSvg(AppIcons.arrowUpRight, width: 2.2),
                              size: 16,
                              color: c.accentInk,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modCard(BuildContext context, ModItem m) {
    final c = context.c;
    return Pressable(
      onTap: () => openCitroResource(context, '《${m.name}》Mod', m.url),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          border: Border.all(color: c.line),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CitroColors.radii.small),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      m.image,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                      errorBuilder: (_, __, ___) =>
                          Container(color: c.tintGreen),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius:
                              BorderRadius.circular(CitroColors.radii.chip),
                          border: Border.all(color: c.line2),
                        ),
                        child: Text(
                          m.tag,
                          style: context.body(
                            size: CitroType.micro,
                            weight: CitroType.medium,
                            color: c.accentInk,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Expanded(
              child: Text(
                m.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.heading(size: CitroType.bodyLg),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.accentLt.withAlpha(c.dark ? 60 : 160),
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.download, width: 2),
                    size: 11,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '网盘下载',
                      style: context.body(
                        size: CitroType.small,
                        weight: CitroType.medium,
                        color: c.accentInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AppIcon(
                    strokeSvg(AppIcons.arrowUpRight, width: 2),
                    size: 10,
                    color: c.accentInk,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部一排快捷工具：四张卡用不同底色区分，点一下直接打开。
  /// 「屏幕分享」「玩法抽签」「视野live」在下方列表里不再重复。
  Widget _quickToolsRow(BuildContext context, {required int columns}) {
    final c = context.c;
    final byName = {for (final t in kTools) t.name: t};
    void open(String name) {
      final t = byName[name];
      if (t != null) openCitroTool(context, t);
    }

    final items = <_QuickTool>[
      _QuickTool(
        name: '屏幕分享',
        desc: byName['屏幕分享']?.desc ?? '网页屏幕共享与远程演示',
        icon: byName['屏幕分享']?.icon ?? AppIcons.monitor,
        tint: c.tintBlue,
        onTap: () => open('屏幕分享'),
      ),
      _QuickTool(
        name: '玩法抽签',
        desc: byName['玩法抽签']?.desc ?? '无畏契约整活玩法抽签',
        icon: byName['玩法抽签']?.icon ?? AppIcons.sparkle,
        tint: c.tintYellow,
        onTap: () => open('玩法抽签'),
      ),
      _QuickTool(
        name: '视野live',
        desc: byName['视野live']?.desc ?? '实时视野 · 在线直播',
        icon: byName['视野live']?.icon ?? AppIcons.eye,
        tint: c.tintGreen,
        onTap: () => open('视野live'),
      ),
      _QuickTool(
        name: '便签',
        desc: '随手记点什么',
        icon: AppIcons.note,
        tint: c.tintPink,
        onTap: () => showNotesModal(context),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i += columns) ...[
          if (i > 0) const SizedBox(height: AppSpacing.x2),
          Row(
            children: [
              for (var j = i; j < i + columns && j < items.length; j++) ...[
                if (j > i) const SizedBox(width: AppSpacing.x2),
                Expanded(child: _quickToolCard(context, items[j])),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _quickToolCard(BuildContext context, _QuickTool item) {
    final c = context.c;
    return Pressable(
      onTap: item.onTap,
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.surface2,
      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                color: item.tint,
                borderRadius: BorderRadius.circular(CitroColors.radii.small),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(item.icon, width: 2),
                  size: 19,
                  color: c.ink,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: CitroType.body,
                      weight: CitroType.medium,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(size: CitroType.small, color: c.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolCard(BuildContext context, ToolItem tool) {
    final c = context.c;
    return Pressable(
      onTap: () => openCitroTool(context, tool),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.surface2,
      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: c.line),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.surface2,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(tool.icon, width: 2),
                  size: 18,
                  color: c.ink2,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              tool.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(
                size: CitroType.body,
                weight: CitroType.medium,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tool.desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(
                size: CitroType.small,
                color: c.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _driverList(BuildContext context, Iterable<DriverItem> drivers) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 24.0;
        final columns = (constraints.maxWidth / 260).floor().clamp(1, 4);
        if (columns <= 1) {
          return Column(
            children: [for (final d in drivers) _driverRow(context, d)],
          );
        }
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 0,
          children: [
            for (final d in drivers)
              SizedBox(width: itemWidth, child: _driverRow(context, d)),
          ],
        );
      },
    );
  }

  Widget _driverRow(BuildContext context, DriverItem d) {
    final c = context.c;
    return Pressable(
      onTap: () => openCitroResource(
        context,
        d.name,
        d.url,
        download: d.client,
      ),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.surface2,
      borderRadius: BorderRadius.circular(CitroColors.radii.small),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                d.name,
                style: context.body(
                  size: CitroType.body,
                  weight: CitroType.medium,
                  color: c.ink,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                border: Border.all(color: c.line2),
              ),
              child: Text(
                d.client ? '客户端' : '网页',
                style: context.body(
                  size: CitroType.micro,
                  weight: CitroType.medium,
                  color: c.ink2,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            AppIcon(
              strokeSvg(AppIcons.arrowUpRight, width: 2),
              size: 14,
              color: c.accentInk,
            ),
          ],
        ),
      ),
    );
  }
}
