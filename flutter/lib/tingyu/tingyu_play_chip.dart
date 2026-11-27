import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'tingyu_controller.dart';
import 'tingyu_page.dart' show tingyuAccent, tingyuOnAccent;

/// 离开听隅后的统一播放入口：声音仍在播放时，把听隅入口换成可暂停的胶囊。
class TingyuPlayChip extends StatelessWidget {
  const TingyuPlayChip({super.key, this.height = 46, this.maxTitleWidth = 96});

  final double height;
  final double maxTitleWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final accent = tingyuAccent(c);
    final onAccent = tingyuOnAccent(c);
    final player = NookController.instance;
    return Semantics(
      button: true,
      label: '听隅正在播放 ${player.title}，点击进入',
      child: Pressable(
        onTap: () => Navigator.of(context).pushNamed('/tingyu'),
        hoverLift: 0,
        hoverShadow: false,
        hoverColor: accent.withAlpha(24),
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        child: Container(
          height: height,
          padding: const EdgeInsets.only(left: 14, right: 5),
          decoration: BoxDecoration(
            color: c.surface2.withValues(alpha: c.surface2.a * (220) / 255),
            borderRadius: BorderRadius.circular(CitroColors.radii.chip),
            border: Border.all(color: c.line),
            boxShadow: CitroColors.shadows.card(c),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                strokeSvg(AppIcons.wave, width: 2),
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTitleWidth),
                child: Text(
                  player.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: CitroType.meta,
                    weight: CitroType.strong,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Semantics(
                button: true,
                label: '暂停播放',
                child: Pressable(
                  onTap: () => unawaited(player.send('pause')),
                  scale: .9,
                  hoverColor: accent.withAlpha(24),
                  borderRadius: BorderRadius.circular(CitroColors.radii.avatar),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.pause_rounded,
                      size: 18,
                      color: onAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
