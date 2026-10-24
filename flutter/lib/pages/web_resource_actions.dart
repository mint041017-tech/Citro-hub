import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/resources.dart';
import '../theme/app_theme.dart';
import '../widgets/modal.dart';

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
            versions.isNotEmpty ? '选择版本' : (isDownload ? '确认下载' : '前往外部页面'),
            style: ctx.heading(size: 20),
          ),
          const SizedBox(height: 8),
          if (warn != null) ...[
            Text(
              '⚠ $warn',
              textAlign: TextAlign.center,
              style: ctx.body(size: 11, color: ctx.c.stamp),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: ctx.body(size: 12, color: ctx.c.inkSoft),
          ),
          if (versions.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final v in versions)
              GestureDetector(
                onTap: () {
                  chosen = v;
                  Navigator.pop(ctx, true);
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ctx.c.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ctx.c.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.name,
                        style: ctx.body(
                          size: 12.5,
                          weight: FontWeight.w700,
                          color: ctx.c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        v.desc,
                        style: ctx.body(size: 10.5, color: ctx.c.inkSoft),
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
              style: ctx.body(size: 10, color: ctx.c.inkSoft),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  text: '取消',
                  outlined: true,
                  onTap: () => Navigator.pop(ctx, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AccentButton(
                  text: isDownload || versions.isNotEmpty ? '下载' : '前往',
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
  await launchUrl(
    Uri.parse(chosen?.url ?? url),
    mode: LaunchMode.externalApplication,
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
