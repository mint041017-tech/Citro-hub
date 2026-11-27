import 'package:flutter/material.dart';

import '../overlays/ai_chat.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
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

  /// 状态点颜色，缺省用选中色（听隅暂停时是灰色、运行时是绿色）。
  final Color? dotColor;

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
    this.dotColor,
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

  /// 键盘弹起时收起来（保留原来的隐藏逻辑，附带下滑 + 淡出）。
  final bool visible;

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
    this.visible = true,
    this.colors,
    this.tabsBuilder,
    this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors ?? context.c;
    final reduce = CitroMotion.reduced(context);
    const double barHeight = 62;
    const double ciciSize = 62;
    // 与主导航一致：选中强调色，未选中半透明墨色。
    final active = activeColor ?? c.accentInk;
    final inactive =
        inactiveColor ?? c.ink.withValues(alpha: c.dark ? .58 : .52);

    Widget bar(BuildContext context) {
      final tabs = tabsBuilder?.call(context) ?? this.tabs;
      // 与主导航一致：按内容收窄、居中，每格固定 68 宽。
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CitroDock(
            height: barHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: CitroTabStrip(
                index: index,
                itemWidth: 70,
                height: barHeight,
                items: [
                  for (var i = 0; i < tabs.length; i++)
                    _slot(context, tabs[i], i, active, inactive, reduce, c),
                ],
              ),
            ),
          ),
          if (showCici) ...[
            const SizedBox(width: 10),
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
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.5),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
        curve: CitroMotion.easeOut,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !visible,
            // 子树统一补上 CitroSkin：听隅的 Theme 没有这个扩展，
            // 里面的 Pressable / CiciAvatarButton 都依赖 context.c。
            child: Theme(
              data: Theme.of(context).copyWith(extensions: [CitroSkin(c)]),
              child: RepaintBoundary(
                // Builder 保证 bar 拿到的是 Theme 之下的 context（听隅子树没有
                // CitroSkin，slot 里的 context.body / context.c 都依赖它）。
                child: Builder(
                  builder: (context) => listenable == null
                      ? bar(context)
                      : ListenableBuilder(
                          listenable: listenable!,
                          builder: (context, _) => bar(context),
                        ),
                ),
              ),
            ),
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
    // 选中态：强调色图标 + 文字，底下垫一枚浅胶囊。
    final fg = isActive ? active : inactive;
    final icon = tab.svg != null
        ? AppIcon(strokeSvg(tab.svg!, width: isActive ? 2.3 : 2), size: 22, color: fg)
        : tab.icon != null
        ? Icon(tab.icon, size: 22, color: fg)
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
        // 选中项垫一枚强调色浅胶囊（iOS 26 标签栏的选中态）。
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : CitroMotion.hover,
          curve: CitroMotion.easeColor,
          height: 50,
          // 选中底由 CitroTabStrip 的滑动指示器画。
          decoration: const BoxDecoration(),
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
                            size: 10.5,
                            weight: isActive
                                ? CitroType.strong
                                : CitroType.medium,
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
                          // 圆形角标：直径随字数长，始终是正圆（不再是胶囊）。
                          width: _badgeSide(tab.badge),
                          height: _badgeSide(tab.badge),
                          decoration: BoxDecoration(
                            color: c.danger,
                            shape: BoxShape.circle,
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
                        color: tab.dotColor ?? active,
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

/// 角标直径：1 位数 15，2 位数 21，3 位（99+）27 —— 保证正圆。
double _badgeSide(int badge) => badge > 99 ? 27 : (badge > 9 ? 21.0 : 15.0);
