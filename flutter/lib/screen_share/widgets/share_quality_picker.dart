import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/modal.dart';
import '../../widgets/paper.dart';
import '../screen_share_theme.dart';
import '../share_quality.dart';

/// 画质选择行：点开是一个底部弹层，列出 720p / 1080p / 2K × 30 / 60fps。
///
/// 档位是「目标值」而不是保证值：采集分辨率由系统决定（Android 永远给
/// 物理分辨率、固定 30fps），真正的收敛发生在编码侧。
class ShareQualityPicker extends StatelessWidget {
  const ShareQualityPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.label = '画质',
  });

  final ShareQuality value;
  final ValueChanged<ShareQuality> onChanged;
  final bool enabled;
  final String label;

  Future<void> _open(BuildContext context) async {
    final picked = await showCitroSheet<ShareQuality>(
      context: context,
      // 弹层走根路由，不会继承房间页的暖黑主题，背景和内容都要显式套。
      backgroundColor: shareColors.surface,
      builder: (ctx) => ShareTheme(child: _QualitySheet(current: value)),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: enabled ? () => _open(context) : null,
      child: Container(
        height: AppSpacing.touch,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.field),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Text(label, style: context.body(size: CitroType.meta, color: c.ink2)),
            const Spacer(),
            Text(
              value.label,
              style: context.body(size: CitroType.label, weight: CitroType.medium),
            ),
            const SizedBox(width: 4),
            AppIcon(AppIcons.chevronDown, size: 16, color: c.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _QualitySheet extends StatelessWidget {
  const _QualitySheet({required this.current});

  final ShareQuality current;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      // 用小屏手机（或系统字体放大）时，6 个档位可能超过弹层给的高度，
      // 包一层滚动，别让最后两档被裁掉。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                AppSpacing.x2,
                AppSpacing.x3,
                0,
              ),
              child: Text('选择画质', style: context.heading(size: CitroType.title)),
            ),
            const SizedBox(height: AppSpacing.x2),
            for (final q in ShareQuality.presets)
              Pressable(
                onTap: () => Navigator.of(context).pop(q),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x3,
                    vertical: AppSpacing.x2,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.label,
                              style: context.body(
                                size: CitroType.body,
                                weight: CitroType.medium,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${(q.maxBitrate / 1000000).toStringAsFixed(1)} Mbps 上限',
                              style: context.body(size: CitroType.meta, color: c.inkSoft),
                            ),
                          ],
                        ),
                      ),
                      if (q == current)
                        AppIcon(AppIcons.check, size: 18, color: c.accent),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.x2),
          ],
        ),
      ),
    );
  }
}
