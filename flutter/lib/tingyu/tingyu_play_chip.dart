import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'tingyu_controller.dart';

/// 离开听隅后的统一播放入口：声音仍在播放时，把听隅入口换成可暂停的胶囊。
class TingyuPlayChip extends StatelessWidget {
  const TingyuPlayChip({super.key, this.height = 46, this.maxTitleWidth = 96});

  final double height;
  final double maxTitleWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final player = NookController.instance;
    return Semantics(
      button: true,
      label: '听隅正在播放 ${player.title}，点击进入',
      child: Pressable(
        onTap: () => Navigator.of(context).pushNamed('/tingyu'),
        hoverLift: 0,
        hoverShadow: false,
        hoverColor: c.hl.withAlpha(55),
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: height,
          padding: const EdgeInsets.only(left: 14, right: 5),
          decoration: BoxDecoration(
            color: c.surface2.withAlpha(220),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: c.line),
            boxShadow: CitroColors.shadows.paper(c),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                strokeSvg(AppIcons.wave, width: 2),
                size: 17,
                color: c.accentInk,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTitleWidth),
                child: Text(
                  player.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: 13,
                    weight: FontWeight.w600,
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
                  hoverColor: c.hl.withAlpha(55),
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.hl,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.pause_rounded,
                      size: 18,
                      color: c.accentInk,
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
