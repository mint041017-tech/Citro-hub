import 'package:flutter/material.dart';

import '../overlays/ai_chat.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'liquid_glass.dart';
import 'motion_widgets.dart';
import 'paper.dart';
import 'tab_bar.dart';

/// 玻璃导航里的一格：图标 + 文字，可选未读角标 / 状态点。
///
/// 图标二选一：[svg] 走全站统一的 [AppIcon]，[icon] 走 Material 图标
/// （听隅的图标体系是 Material，不强行换成 SVG）。
class GlassTab {
  final String label;
  final String? svg;
  final IconData? icon;

  /// 未读数，0 表示不显示角标。
  final int badge;

  /// 状态点（听隅专注倒计时时用），和角标互不影响。
  final bool dot;

  /// 读屏用语，缺省用 [label]（听隅专注页要播「专注 25:00」而不是只念时间）。
  final String? semanticsLabel;

  /// 给格子挂 key，方便测试定位（记账页沿用旧的 ledger-tab-N）。
  final Key? key;

  const GlassTab({
    required this.label,
    this.svg,
    this.icon,
    this.badge = 0,
    this.dot = false,
    this.semanticsLabel,
    this.key,
  });
}

/// 模块页自带的底部导航：和首页 [CitroTabBar] 同一套液态玻璃材质。
///
/// 左边几格平分剩余宽度，[showCici] 时最右侧挂一颗 CICI 圆形按钮；
/// 整条浮在内容之上，贴屏幕底部、左右各留 8pt、避开安全区。
///
/// 选中态用调用方给的 [activeColor]（缺省取 `context.c.accentInk`），
/// 未选中用 [inactiveColor]（缺省 `context.c.inkSoft`）。
class GlassTabBar extends StatelessWidget {
  final List<GlassTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  final bool showCici;
  final VoidCallback? onCiciTap;
  final Color? activeColor;
  final Color? inactiveColor;

  /// 直接给颜色，绕开 `context.c`（听隅子树没有 CitroSkin 扩展时用）。
  final CitroColors? colors;

  /// 可选：跟随 [listenable] 重建 tabs（听隅的专注倒计时需要跟着番茄钟走）。
  final List<GlassTab> Function(BuildContext context)? tabsBuilder;
  final Listenable? listenable;

  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.showCici = false,
    this.onCiciTap,
    this.activeColor,
    this.inactiveColor,
    this.colors,
    this.tabsBuilder,
    this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors ?? context.c;
    final reduce = CitroMotion.reduced(context);
    const double barHeight = 56;
    const double ciciSize = 54;
    final active = activeColor ?? c.accentInk;
    final inactive = inactiveColor ?? c.inkSoft;

    Widget bar(BuildContext context) {
      final tabs = tabsBuilder?.call(context) ?? this.tabs;
      return Row(
        children: [
          // 几格一组：玻璃只包这一个整体，右侧 CICI 不在这层玻璃里。
          Expanded(
            child: CitroLiquidGlass(
              height: barHeight,
              radius: barHeight / 2,
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _slot(
                        context,
                        tabs[i],
                        i,
                        active,
                        inactive,
                        reduce,
                        c,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (showCici) ...[
            const SizedBox(width: AppSpacing.x2),
            CiciAvatarButton(
              size: ciciSize,
              onTap: onCiciTap ?? () => showAiChat(context),
            ),
          ],
        ],
      );
    }

    return Positioned(
      left: AppSpacing.x1,
      right: AppSpacing.x1,
      bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.x1,
      // 子树统一补上 CitroSkin：听隅的 Theme 没有这个扩展，
      // 里面的 Pressable / CiciAvatarButton 都依赖 context.c。
      child: Theme(
        data: Theme.of(context).copyWith(extensions: [CitroSkin(c)]),
        child: RepaintBoundary(
          child: listenable == null
              ? bar(context)
              : ListenableBuilder(
                  listenable: listenable!,
                  builder: (context, _) => bar(context),
                ),
        ),
      ),
    );
  }

  Widget _slot(
    BuildContext context,
    GlassTab tab,
    int slot,
    Color active,
    Color inactive,
    bool reduce,
    CitroColors c,
  ) {
    final isActive = index == slot;
    // 选中态只用颜色区分（和首页玻璃导航一致）：实色墨 vs 灰，
    // 不压瓷实底，玻璃的通透感才留得住。
    final fg = isActive ? active : inactive;
    final icon = tab.svg != null
        ? AppIcon(strokeSvg(tab.svg!, width: 2), size: 20, color: fg)
        : tab.icon != null
        ? Icon(tab.icon, size: 20, color: fg)
        : const SizedBox.shrink();
    return Semantics(
      button: true,
      selected: isActive,
      label: tab.semanticsLabel ?? tab.label,
      child: Pressable(
        key: tab.key,
        onTap: () => onChanged(slot),
        hoverLift: 0,
        hoverShadow: false,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        child: SizedBox(
          height: 44,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedScale(
                  scale: isActive ? 1 : .94,
                  duration: reduce ? Duration.zero : CitroMotion.press,
                  curve: CitroMotion.easeOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      icon,
                      const SizedBox(height: 2),
                      // 文字不再自带语义：外面已经用 Semantics(label:) 报了 Tab 名。
                      ExcludeSemantics(
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.body(
                            size: CitroType.micro,
                            weight: isActive
                                ? CitroType.medium
                                : CitroType.regular,
                            color: fg,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (tab.badge > 0)
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
                            tab.badge > 99 ? '99+' : '${tab.badge}',
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
                if (tab.dot)
                  Positioned(
                    right: -4,
                    top: -2,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
