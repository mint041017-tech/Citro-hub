import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/resources.dart';
import '../theme/app_theme.dart';
import '../widgets/global_search.dart';
import '../widgets/paper.dart';
import 'web_resource_actions.dart';
import 'web_scrapbook.dart';

class WebResourcesPage extends StatelessWidget {
  const WebResourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final header = WebDesktopHeader(
      resources: true,
      onHome: () => Navigator.of(context).pushNamed('/home'),
      onResources: () {},
    );
    return WebDesktopPaper(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = math.max(820.0, constraints.maxHeight);
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              height: height,
              child: WebDesktopGrid(
                rows: 8,
                children: [
                  ...header.cells(context),
                  const WebGridCell(
                    1,
                    2,
                    12,
                    1,
                    Center(
                      child: SizedBox(
                        width: 560,
                        child: GlobalSearch(preferBelow: true),
                      ),
                    ),
                  ),
                  const WebGridCell(1, 3, 6, 6, _WebTools()),
                  const WebGridCell(7, 3, 6, 6, _WebDrivers()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WebTools extends StatelessWidget {
  const _WebTools();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -.3 * math.pi / 180,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WebSectionTitle('小工具', size: 27),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 18,
                    mainAxisExtent: constraints.maxHeight / 6,
                  ),
                  itemCount: kTools.length,
                  itemBuilder: (context, index) =>
                      _WebToolCard(tool: kTools[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebToolCard extends StatelessWidget {
  final ToolItem tool;

  const _WebToolCard({required this.tool});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => openCitroTool(context, tool),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.hl.withAlpha(50),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line2.withAlpha(110))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.hl.withAlpha(130),
                shape: BoxShape.circle,
                border: Border.all(color: c.accent.withAlpha(65)),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(tool.icon),
                  size: 16,
                  color: c.accentInk,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 16,
                      weight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tool.desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 12,
                      color: c.inkSoft,
                      height: 1.35,
                    ),
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

class _WebDrivers extends StatelessWidget {
  const _WebDrivers();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Transform.rotate(
      angle: .3 * math.pi / 180,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WebSectionTitle('外设驱动', size: 27),
            const SizedBox(height: 5),
            Text('网页驱动', style: context.heading(size: 17, color: c.accentInk)),
            const Expanded(
              flex: 8,
              child: _DriverGrid(drivers: kDriversWeb, rows: 8),
            ),
            Text('客户端驱动', style: context.heading(size: 17, color: c.accentInk)),
            const Expanded(
              flex: 2,
              child: _DriverGrid(drivers: kDriversClient, rows: 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverGrid extends StatelessWidget {
  final List<DriverItem> drivers;
  final int rows;

  const _DriverGrid({required this.drivers, required this.rows});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 20,
          mainAxisExtent: constraints.maxHeight / rows,
        ),
        itemCount: drivers.length,
        itemBuilder: (context, index) => _WebDriverRow(driver: drivers[index]),
      ),
    );
  }
}

class _WebDriverRow extends StatelessWidget {
  final DriverItem driver;

  const _WebDriverRow({required this.driver});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => openCitroResource(
        context,
        driver.name,
        driver.url,
        download: driver.client,
      ),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.hl.withAlpha(55),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line2.withAlpha(105))),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                driver.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(
                  size: 14,
                  weight: FontWeight.w600,
                  color: c.ink2,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: c.hl.withAlpha(170),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                driver.client ? '客户端' : '网页',
                style: context.body(size: 10, color: c.accentInk),
              ),
            ),
            const SizedBox(width: 4),
            AppIcon(
              strokeSvg(AppIcons.arrowUpRight),
              size: 11,
              color: c.inkSoft.withAlpha(150),
            ),
          ],
        ),
      ),
    );
  }
}
