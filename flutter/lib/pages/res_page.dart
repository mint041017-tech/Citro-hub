import 'package:flutter/material.dart';

import '../data/resources.dart';
import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/paper.dart';
import '../widgets/tablet_shell.dart';
import 'in_app_web.dart';
import 'web_resource_actions.dart';

class ResPage extends StatefulWidget {
  final bool embedded;

  const ResPage({super.key, this.embedded = false});
  @override
  State<ResPage> createState() => _ResPageState();
}

const _gamesMovedTools = {'玩法抽签', '瞬投', '屏幕分享', '视野live'};

class _ResPageState extends State<ResPage> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final layout = CitroLayoutScope.maybeOf(context);
    final contentWidth =
        layout?.contentWidth ?? MediaQuery.sizeOf(context).width;
    final wide = (layout?.tabletNav ?? false) && contentWidth >= 940;
    final maxWidth = wide ? 1120.0 : 840.0;
    final tabBar = widget.embedded && !(layout?.tabletNav ?? false);
    final q = query.trim().toLowerCase();
    final mods = q.isEmpty
        ? kMods
        : kMods
              .where(
                (m) => '${m.name}${m.desc}${m.tag}'.toLowerCase().contains(q),
              )
              .toList();
    final sourceTools = (platform.isAndroid || platform.isIOS)
        ? kTools.where((t) => !_gamesMovedTools.contains(t.name)).toList()
        : kTools;
    final tools = q.isEmpty
        ? sourceTools
        : sourceTools
              .where(
                (t) =>
                    '${t.name}${t.desc}${t.section}'.toLowerCase().contains(q),
              )
              .toList();
    final drivers = q.isEmpty
        ? [...kDriversWeb, ...kDriversClient]
        : [
            ...kDriversWeb,
            ...kDriversClient,
          ].where((d) => d.name.toLowerCase().contains(q)).toList();
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
                  8,
                  tabBar ? 110 : 30,
                ),
                child: CitroStagger(
                  step: const Duration(milliseconds: 28),
                  children: [
                    Row(
                      children: [
                        Pressable(
                          onTap: () => popOrHome(context),
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius:
                                  BorderRadius.circular(CitroColors.radii.chip),
                              border: Border.all(color: c.line),
                              boxShadow: CitroColors.shadows.card(c),
                            ),
                            child: Row(
                              children: [
                                AppIcon(
                                  strokeSvg(AppIcons.arrowLeft, width: 2.2),
                                  size: 16,
                                  color: c.ink2,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  widget.embedded ? '首页' : '返回',
                                  style: context.body(
                                    size: CitroType.label,
                                    weight: CitroType.medium,
                                    color: c.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.x2),
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
                    Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius:
                            BorderRadius.circular(CitroColors.radii.field),
                        border: Border.all(color: c.line2),
                      ),
                      child: Row(
                        children: [
                          AppIcon(
                            strokeSvg(AppIcons.search, width: 2),
                            size: 20,
                            color: c.inkSoft,
                          ),
                          const SizedBox(width: AppSpacing.x2),
                          Expanded(
                            child: TextField(
                              controller: search,
                              textAlign: TextAlign.left,
                              onChanged: (v) => setState(() => query = v),
                              onSubmitted: (v) async {
                                if (v.trim().isEmpty) return;
                                final hasLocal =
                                    mods.isNotEmpty ||
                                    tools.isNotEmpty ||
                                    drivers.isNotEmpty;
                                if (!hasLocal) {
                                  await openCitroPage(
                                    context,
                                    'https://www.bing.com/search?q=${Uri.encodeQueryComponent(v)}',
                                    title: '必应 · $v',
                                  );
                                }
                              },
                              style: context.body(
                                size: CitroType.body,
                                color: c.ink,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: '搜索功能 / Mod / 工具，回车必应',
                                hintStyle: context.body(
                                  size: CitroType.meta,
                                  color: c.inkSoft,
                                ),
                              ),
                            ),
                          ),
                          if (query.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                search.clear();
                                setState(() => query = '');
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: AppIcon(
                                  strokeSvg(AppIcons.close, width: 2),
                                  size: 16,
                                  color: c.inkSoft,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (query.isNotEmpty &&
                        mods.isEmpty &&
                        tools.isEmpty &&
                        drivers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Text('没有找到本地资源', style: context.heading(size: 18)),
                            const SizedBox(height: 5),
                            Text(
                              '按回车去必应搜索「${query.trim()}」',
                              style: context.body(
                                size: CitroType.caption,
                                color: c.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    if (drivers.isNotEmpty) ...[
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
