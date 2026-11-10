import 'package:flutter/material.dart';

import '../data/resources.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'in_app_web.dart';

/// Shared by the original mobile resource list, desktop scrapbook and search.
/// Keeping confirmation/version selection here prevents the three UIs drifting.
Future<void> openCitroResource(
  BuildContext context,
  String title,
  String url, {
  String? warn,
  List<ResourceVersion> versions = const [],
  bool download = false,
}) async {
  ResourceVersion? chosen;
  final isDownload =
      download ||
      RegExp(
        r'\.(exe|zip|7z|apk|msi)(\?|$)',
        caseSensitive: false,
      ).hasMatch(url);
  final ok = await showCitroDialog<bool>(
    context,
    builder: (ctx) => PaperDialog(
      showClose: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            versions.isNotEmpty ? '选择版本' : (isDownload ? '确认下载' : '打开页面'),
            style: ctx.heading(size: 20),
          ),
          const SizedBox(height: AppSpacing.x1),
          if (warn != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ctx.c.dangerSoft,
                borderRadius: BorderRadius.circular(CitroColors.radii.small),
              ),
              child: Row(
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.info, width: 2),
                    size: 14,
                    color: ctx.c.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warn,
                      style: ctx.body(size: CitroType.caption, color: ctx.c.danger),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: ctx.body(size: CitroType.meta, color: ctx.c.inkSoft),
          ),
          if (versions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x2),
            for (final v in versions)
              GestureDetector(
                onTap: () {
                  chosen = v;
                  Navigator.pop(ctx, true);
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.x1),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ctx.c.surface2,
                    borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                    border: Border.all(color: ctx.c.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    v.name,
                                    style: ctx.body(
                                      size: CitroType.body,
                                      weight: CitroType.medium,
                                      color: ctx.c.ink,
                                    ),
                                  ),
                                ),
                                if (v.recommended) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ctx.c.accentLt,
                                      borderRadius: BorderRadius.circular(
                                        CitroColors.radii.chip,
                                      ),
                                    ),
                                    child: Text(
                                      '推荐',
                                      style: ctx.body(
                                        size: CitroType.micro,
                                        weight: CitroType.medium,
                                        color: ctx.c.accentInk,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              v.desc,
                              style: ctx.body(
                                size: CitroType.small,
                                color: ctx.c.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x1),
                      AppIcon(
                        strokeSvg(AppIcons.arrowUpRight, width: 2),
                        size: 14,
                        color: ctx.c.inkSoft,
                      ),
                    ],
                  ),
                ),
              ),
          ] else
            Text(
              url,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ctx.body(size: CitroType.micro, color: ctx.c.inkSoft),
            ),
          const SizedBox(height: AppSpacing.x2),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  text: '取消',
                  outlined: true,
                  onTap: () => Navigator.pop(ctx, false),
                ),
              ),
              const SizedBox(width: AppSpacing.x1),
              Expanded(
                child: AccentButton(
                  text: isDownload || versions.isNotEmpty ? '下载' : '打开',
                  onTap: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  await openCitroPage(
    context,
    chosen?.url ?? url,
    title: title,
    download: isDownload,
  );
}

void openCitroTool(BuildContext context, ToolItem tool) {
  if (tool.hash != null) {
    Navigator.of(context).pushNamed(tool.hash!.replaceFirst('#', ''));
  } else if (tool.url != null) {
    openCitroResource(
      context,
      tool.name,
      tool.url!,
      warn: tool.warn,
      versions: tool.versions,
    );
  }
}
