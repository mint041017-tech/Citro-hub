import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/custom_tab.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'liquid_glass.dart';
import 'modal.dart';
import 'motion_widgets.dart';
import 'paper.dart';

/// 底部导航：左边四格成一体（首页 / 游戏 / 社区 / 自定义），
/// 右边单独一颗 CICI 圆形头像按钮——全 App 唯一的 AI 入口。
class CitroTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final CustomTabModule customModule;
  final VoidCallback onCustomTabLongPress;
  final VoidCallback onCiciTap;

  const CitroTabBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.customModule,
    required this.onCustomTabLongPress,
    required this.onCiciTap,
  });

  @override
  Widget build(BuildContext context) {
    final unread = context.app.unread;
    const double barHeight = 56;
    const double ciciSize = 54;

    final specs = <_TabSpec>[
      const _TabSpec('首页', AppIcons.home),
      const _TabSpec('游戏', AppIcons.games),
      _TabSpec('社区', AppIcons.community, badge: unread),
      _TabSpec(customModule.label, customModule.icon),
    ];

    return Positioned(
      left: AppSpacing.x1,
      right: AppSpacing.x1,
      bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.x1,
      child: RepaintBoundary(
        child: Row(
          children: [
            // 四格一组：玻璃只包这一个整体，右侧 CICI 不在这层玻璃里。
            Expanded(
              child: CitroLiquidGlass(
                height: barHeight,
                radius: barHeight / 2,
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    for (var i = 0; i < specs.length; i++)
                      Expanded(child: _tabSlot(context, specs[i], i)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            CiciAvatarButton(size: ciciSize, onTap: onCiciTap),
          ],
        ),
      ),
    );
  }

  Widget _tabSlot(BuildContext context, _TabSpec spec, int slot) {
    final active = index == slot;
    final isCustom = slot == 3;
    return Semantics(
      button: true,
      selected: active,
      label: spec.label,
      child: Pressable(
        onTap: () => onChanged(slot),
        onLongPress: isCustom ? onCustomTabLongPress : null,
        hoverLift: 0,
        hoverShadow: false,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        child: _TabContent(
          label: spec.label,
          icon: spec.icon,
          badge: spec.badge,
          active: active,
        ),
      ),
    );
  }
}

class _TabSpec {
  final String label;
  final String icon;
  final int badge;

  const _TabSpec(this.label, this.icon, {this.badge = 0});
}

class _TabContent extends StatelessWidget {
  final String label;
  final String icon;
  final int badge;
  final bool active;

  const _TabContent({
    required this.label,
    required this.icon,
    required this.badge,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    // 选中态只用颜色区分（和 iOS 26 玻璃导航一致）：
    // 实色墨 vs 灰，不压瓷实底，玻璃的通透感才留得住。
    final fg = active ? c.ink : c.inkSoft;
    return SizedBox(
      height: 44,
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedScale(
              scale: active ? 1 : .94,
              duration: reduce ? Duration.zero : CitroMotion.press,
              curve: CitroMotion.easeOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(strokeSvg(icon, width: 2), size: 20, color: fg),
                  const SizedBox(height: 2),
                  // 文字不再自带语义：外面已经用 Semantics(label:) 报了 Tab 名，
                  // 否则读屏会把「首页 首页」念两遍。
                  ExcludeSemantics(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: CitroType.micro,
                        weight: active ? CitroType.medium : CitroType.regular,
                        color: fg,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (badge > 0)
              Positioned(
                right: -2,
                top: -2,
                child: CitroPop(
                  child: ExcludeSemantics(
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 15,
                        minHeight: 15,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: c.danger,
                        borderRadius: BorderRadius.circular(
                          CitroColors.radii.chip,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: context.body(
                          size: 8,
                          weight: CitroType.strong,
                          color: c.bg,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// CICI 的圆形头像按钮：整个 App 唯一的 AI 入口。
///
/// 头像是 CICI 自己的（`assets/images/cici_avatar.webp`），不是登录用户的，
/// 这样它在任何账号下都是同一个助手形象。
class CiciAvatarButton extends StatelessWidget {
  final double size;
  final VoidCallback onTap;

  const CiciAvatarButton({super.key, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: 'CICI 智能助手',
      child: Pressable(
        onTap: onTap,
        scale: .94,
        hoverLift: 0,
        hoverShadow: false,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface,
            border: Border.all(color: c.accent, width: 2),
            boxShadow: CitroColors.shadows.float(c),
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/cici_avatar.webp',
              fit: BoxFit.cover,
              cacheWidth: (size * 2).round(),
              errorBuilder: (_, _, _) => Center(
                child: AppIcon(
                  strokeSvg(AppIcons.sparkle, width: 2),
                  size: size * .38,
                  color: c.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 长按自定义 Tab 的选择面板。
Future<void> showCustomTabPicker(BuildContext context) async {
  final c = context.c;
  await showCitroSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x3,
          AppSpacing.x2,
          AppSpacing.x3,
          AppSpacing.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('自定义这一格', style: ctx.heading(size: CitroType.title)),
            const SizedBox(height: 4),
            Text(
              '长按 Tab 可随时切换',
              style: ctx.body(size: CitroType.meta, color: c.inkSoft),
            ),
            const SizedBox(height: AppSpacing.x2),
            for (final m in CustomTabModule.values) ...[
              _moduleTile(ctx, m),
              if (m != CustomTabModule.values.last)
                const SizedBox(height: AppSpacing.x1),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _moduleTile(BuildContext context, CustomTabModule module) {
  final c = context.c;
  final app = context.app;
  final selected = app.customTabModule == module;
  return Pressable(
    onTap: () async {
      await app.setCustomTabModule(module);
      if (context.mounted) Navigator.of(context).maybePop();
    },
    hoverLift: 0,
    hoverShadow: false,
    borderRadius: BorderRadius.circular(CitroColors.radii.inner),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? c.tintYellow : c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: selected ? c.accent : c.line),
      ),
      child: Row(
        children: [
          AppIcon(
            strokeSvg(module.icon, width: 2),
            size: 20,
            color: selected ? c.accent : c.ink2,
          ),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Text(
              module.label,
              style: context.body(
                size: CitroType.label,
                weight: selected ? CitroType.medium : CitroType.regular,
                color: selected ? c.ink : c.ink2,
              ),
            ),
          ),
          if (selected)
            AppIcon(strokeSvg(AppIcons.check, width: 2.4), size: 18, color: c.accent),
        ],
      ),
    ),
  );
}
