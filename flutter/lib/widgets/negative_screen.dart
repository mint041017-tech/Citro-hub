import 'package:flutter/material.dart';

import '../data/resources.dart';
import '../overlays/extra_sheets.dart';
import '../overlays/notes_modal.dart';
import '../pages/in_app_web.dart';
import '../pages/web_resource_actions.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'paper.dart';

/// 首页下拉「负一屏」：资源库（Mod / 小工具 / 外设驱动）+ 小工具。
///
/// 从首页顶部继续下拉即可展开；点右上角收起。
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
                            '资源库 · 小工具',
                            style: context.heading(size: CitroType.titleLg),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '上滑推回 · 点右上角关闭',
                            style: context.body(size: CitroType.small, color: c.inkSoft),
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
                            strokeSvg(AppIcons.chevronDown, width: 2.2),
                            size: 18,
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
                child: _ResourceSection(),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: AppSpacing.x3)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
                child: _QuickToolsSection(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.x4)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? hint;

  const _SectionHeader(this.title, {this.hint});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x2),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(CitroColors.radii.xs),
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
          Text(title, style: context.heading(size: CitroType.title)),
          if (hint != null) ...[
            const SizedBox(width: AppSpacing.x1),
            Expanded(
              child: Text(
                hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResourceSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('游戏 Mod', hint: '点卡片跳转下载'),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kMods.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.x2),
            itemBuilder: (_, i) => _ModCard(item: kMods[i]),
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        const _SectionHeader('小工具'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: AppSpacing.x2,
            mainAxisSpacing: AppSpacing.x2,
            childAspectRatio: 2.5,
          ),
          itemCount: kTools.length,
          itemBuilder: (_, i) => _ToolTile(item: kTools[i]),
        ),
        const SizedBox(height: AppSpacing.x4),
        const _SectionHeader('外设驱动'),
        for (final d in kDriversClient) _DriverRow(item: d),
        for (final d in kDriversWeb) _DriverRow(item: d),
      ],
    );
  }
}

class _ModCard extends StatelessWidget {
  final ModItem item;
  const _ModCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => openCitroPage(context, item.url, title: item.name),
      hoverLift: 0,
      hoverShadow: false,
      borderRadius: BorderRadius.circular(CitroColors.radii.card),
      child: CitroCard(
        padding: const EdgeInsets.all(12),
        radius: CitroColors.radii.card,
        child: SizedBox(
          width: 132,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: c.tintBlue,
                    borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: item.image.isEmpty
                      ? Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.library, width: 2),
                            size: 26,
                            color: c.inkSoft,
                          ),
                        )
                      : Image.asset(item.image, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(item.name, style: context.heading(size: CitroType.bodyLg)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.tintYellow,
                      borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                    ),
                    child: Text(
                      item.tag,
                      style: context.body(
                        size: CitroType.micro,
                        weight: CitroType.medium,
                        color: c.accentInk,
                        height: 1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  AppIcon(
                    strokeSvg(AppIcons.download, width: 2),
                    size: 14,
                    color: c.inkSoft,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final ToolItem item;
  const _ToolTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => openCitroTool(context, item),
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
            AppIcon(
              strokeSvg(item.icon, width: 2),
              size: 20,
              color: c.accent,
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
                  Text(
                    item.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(size: CitroType.micro, color: c.inkSoft),
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

class _DriverRow extends StatelessWidget {
  final DriverItem item;
  const _DriverRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x1),
      child: Pressable(
        onTap: () => openCitroPage(
          context,
          item.url,
          title: item.name,
          download: item.client,
        ),
        hoverLift: 0,
        hoverShadow: false,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              AppIcon(
                strokeSvg(
                  item.client ? AppIcons.monitor : AppIcons.download,
                  width: 2,
                ),
                size: 18,
                color: c.ink2,
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: CitroType.label, color: c.ink),
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
      ),
    );
  }
}

class _QuickToolsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('小工具'),
        Row(
          children: [
            Expanded(child: _QuickTile(
              icon: AppIcons.sun,
              label: '天气',
              onTap: () => showWeatherSheet(context),
            )),
            const SizedBox(width: AppSpacing.x2),
            Expanded(child: _QuickTile(
              icon: AppIcons.calendar,
              label: '摸鱼日历',
              onTap: () => showFishSheet(context),
            )),
          ],
        ),
        const SizedBox(height: AppSpacing.x2),
        Row(
          children: [
            Expanded(child: _QuickTile(
              icon: AppIcons.note,
              label: '便签',
              onTap: () => showNotesModal(context),
            )),
            const SizedBox(width: AppSpacing.x2),
            Expanded(child: _QuickTile(
              icon: AppIcons.clock,
              label: '番茄钟',
              onTap: () => Navigator.of(context).pushNamed('/calendar'),
            )),
          ],
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _QuickTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      hoverLift: 0,
      hoverShadow: false,
      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.x2),
            AppIcon(strokeSvg(icon, width: 2), size: 20, color: c.accent),
            const SizedBox(width: AppSpacing.x2),
            Text(
              label,
              style: context.body(size: CitroType.label, color: c.ink),
            ),
          ],
        ),
      ),
    );
  }
}
