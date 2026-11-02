import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../overlays/ai_chat.dart';
import '../services/api.dart';
import '../pages/me_page.dart';
import '../services/orientation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/motion.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import 'motion_widgets.dart';
import 'paper.dart';
import 'shared_element.dart';

class CitroLayoutScope extends InheritedWidget {
  final double contentWidth;
  final bool tabletNav;
  final bool duo;

  const CitroLayoutScope({
    super.key,
    required this.contentWidth,
    required this.tabletNav,
    this.duo = false,
    required super.child,
  });

  static CitroLayoutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CitroLayoutScope>();

  static double widthOf(BuildContext context) =>
      maybeOf(context)?.contentWidth ?? MediaQuery.sizeOf(context).width;

  @override
  bool updateShouldNotify(CitroLayoutScope oldWidget) =>
      contentWidth != oldWidget.contentWidth ||
      tabletNav != oldWidget.tabletNav ||
      duo != oldWidget.duo;
}

class CitroTabletSidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final bool showResources;

  const CitroTabletSidebar({
    super.key,
    required this.index,
    required this.onChanged,
    this.showResources = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = context.app;
    final avatarUrl = Api.imageUrl(app.user?.av);
    return DecoratedBox(
      decoration: BoxDecoration(
        // iPad / Windows 的侧栏用 1 物理像素的发丝分隔，和系统分栏一致。
        border: Border(
          right: BorderSide(
            color: c.glassBorder,
            width: CitroNative.hairline(context),
          ),
        ),
      ),
      child: PaperBackground(
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Pressable(
                  onTap: () => onChanged(0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 14),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/images/logo.webp',
                            width: 44,
                            height: 44,
                            cacheWidth: 132,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Citro',
                                style: context.display(
                                  size: 25,
                                  weight: FontWeight.w700,
                                  color: c.ink,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '今天也要开心',
                                style: context.hand(
                                  size: 12.5,
                                  color: c.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DashedLine(color: c.line2.withAlpha(150)),
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '逛一逛',
                          // 分栏标题用系统字体 + 负字距，像 macOS/iPadOS 的 section header。
                          style: context.ui(
                            size: 11,
                            weight: FontWeight.w600,
                            color: c.inkSoft,
                            letterSpacing: .8,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        _SidebarNav(
                          index: index,
                          showResources: showResources,
                          items: [
                            _SidebarItem(
                              label: '首页',
                              icon: AppIcons.home,
                              active: index == 0,
                              showHighlight: false,
                              onTap: () => onChanged(0),
                            ),
                            _SidebarItem(
                              label: '游戏',
                              icon: AppIcons.games,
                              active: index == 1,
                              showHighlight: false,
                              onTap: () => onChanged(1),
                            ),
                            _SidebarItem(
                              label: '社区',
                              icon: AppIcons.community,
                              active: index == 2,
                              showHighlight: false,
                              badge: app.unread,
                              onTap: () => onChanged(2),
                            ),
                            if (showResources)
                              _SidebarItem(
                                label: '资源库',
                                icon: AppIcons.library,
                                active: index == 3,
                                showHighlight: false,
                                onTap: () => onChanged(3),
                              ),
                          ],
                        ),
                        _SidebarItem(
                          label: '全站搜索',
                          icon: AppIcons.search,
                          active: false,
                          onTap: () =>
                              Navigator.of(context).pushNamed('/search'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '我的 Citro',
                          style: context.ui(
                            size: 11,
                            weight: FontWeight.w600,
                            color: c.inkSoft,
                            letterSpacing: .8,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        _SidebarItem(
                          label: '食谱日记',
                          icon: AppIcons.fork,
                          active: false,
                          onTap: () => Navigator.of(context).pushNamed('/cook'),
                        ),
                        _SidebarItem(
                          label: 'CiCi AI',
                          icon: AppIcons.sparkle,
                          active: false,
                          onTap: () => showAiChat(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Pressable(
                  onTap: () => openMePage(context),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.x1 + 4),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(
                        CitroColors.radii.card,
                      ),
                      border: Border.all(color: c.line),
                      boxShadow: CitroColors.shadows.paper(c),
                    ),
                    child: Row(
                      children: [
                        CitroHero(
                          tag: CitroHero.tagOf('profile', 'me'),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: SizedBox(
                              width: 38,
                              height: 38,
                              child: avatarUrl.isEmpty
                                  ? ColoredBox(
                                      color: app.loggedIn ? c.hl : c.surface,
                                      child: Center(
                                        child: app.loggedIn
                                            ? Text(
                                                app.user!.name.isEmpty
                                                    ? '友'
                                                    : app.user!.name[0],
                                                style: context.display(
                                                  size: 16,
                                                  weight: FontWeight.w700,
                                                  color: c.accentInk,
                                                ),
                                              )
                                            : AppIcon(
                                                strokeSvg(
                                                  AppIcons.user,
                                                  width: 2,
                                                ),
                                                size: 18,
                                                color: c.ink2,
                                              ),
                                      ),
                                    )
                                  : Image.network(
                                      avatarUrl,
                                      fit: BoxFit.cover,
                                      cacheWidth: 114,
                                      errorBuilder: (_, _, _) => ColoredBox(
                                        color: c.surface,
                                        child: Center(
                                          child: AppIcon(
                                            strokeSvg(AppIcons.user, width: 2),
                                            size: 18,
                                            color: c.ink2,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.loggedIn ? app.displayName : '游客漫游中',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.heading(size: 14, color: c.ink),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                app.loggedIn ? '账号已同步' : '登录后同步社区与排行',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.body(
                                  size: 10.5,
                                  color: c.inkSoft,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

class CitroDuoRightRail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final double topInset;

  const CitroDuoRightRail({
    super.key,
    required this.index,
    required this.onChanged,
    this.topInset = 12,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = context.app;
    final avatarUrl = Api.imageUrl(app.user?.av);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: PaperBackground(
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, topInset, 12, 24),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.asset(
                  'assets/images/logo.webp',
                  width: 36,
                  height: 36,
                  cacheWidth: 108,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      CitroDuoRailItem(
                        label: '首页',
                        icon: AppIcons.home,
                        active: index == 0,
                        onTap: () => onChanged(0),
                      ),
                      CitroDuoRailItem(
                        label: '游戏',
                        icon: AppIcons.games,
                        active: index == 1,
                        onTap: () => onChanged(1),
                      ),
                      CitroDuoRailItem(
                        label: '社区',
                        icon: AppIcons.community,
                        active: index == 2,
                        badge: app.unread,
                        onTap: () => onChanged(2),
                      ),
                      const SizedBox(height: 6),
                      DashedLine(color: c.line2.withAlpha(150)),
                      const SizedBox(height: 6),
                      CitroDuoRailItem(
                        label: '食谱',
                        icon: AppIcons.fork,
                        onTap: () => Navigator.of(context).pushNamed('/cook'),
                      ),
                      CitroDuoRailItem(
                        label: 'CiCi',
                        icon: AppIcons.sparkle,
                        onTap: () => showAiChat(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Pressable(
                onTap: () => Navigator.of(context).pushNamed('/me'),
                child: CitroHero(
                  tag: CitroHero.tagOf('profile', 'me'),
                  child: Container(
                    key: const Key('duo-rail-avatar'),
                    width: 44,
                    height: 44,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: app.loggedIn ? c.hl : c.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.line),
                    ),
                    child: avatarUrl.isEmpty
                        ? Center(
                            child: app.loggedIn
                                ? Text(
                                    app.user!.name.isNotEmpty
                                        ? app.user!.name[0]
                                        : '友',
                                    style: context.display(
                                      size: 18,
                                      weight: FontWeight.w700,
                                      color: c.accentInk,
                                    ),
                                  )
                                : AppIcon(
                                    strokeSvg(AppIcons.user, width: 2),
                                    size: 20,
                                    color: c.ink2,
                                  ),
                          )
                        : Image.network(
                            avatarUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            cacheWidth: 132,
                            errorBuilder: (_, _, _) => Center(
                              child: Text(
                                app.loggedIn && app.user!.name.isNotEmpty
                                    ? app.user!.name[0]
                                    : '友',
                                style: context.display(
                                  size: 18,
                                  weight: FontWeight.w700,
                                  color: c.accentInk,
                                ),
                              ),
                            ),
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

class CitroDuoCookRail extends StatelessWidget {
  final List<(String, String, String)> items;
  final String activeKey;
  final bool foodActive;
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;
  final double topInset;

  const CitroDuoCookRail({
    super.key,
    required this.items,
    required this.activeKey,
    required this.foodActive,
    required this.onSelect,
    required this.onBack,
    required this.topInset,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: PaperBackground(
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, topInset, 12, 24),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                CitroDuoRailItem(
                  label: '返回',
                  icon: AppIcons.arrowLeft,
                  onTap: onBack,
                ),
                const SizedBox(height: 6),
                DashedLine(color: c.line2.withAlpha(150)),
                const SizedBox(height: 6),
                for (final item in items)
                  CitroDuoRailItem(
                    label: item.$2,
                    icon: item.$3,
                    active: item.$1 == 'food'
                        ? foodActive
                        : activeKey == item.$1,
                    onTap: () => onSelect(item.$1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CitroDuoBackRail extends StatelessWidget {
  final VoidCallback onBack;
  final double topInset;

  const CitroDuoBackRail({
    super.key,
    required this.onBack,
    required this.topInset,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: PaperBackground(
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, topInset, 12, 8),
          child: Column(
            children: [
              CitroDuoRailItem(
                label: '返回',
                icon: AppIcons.arrowLeft,
                onTap: onBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CitroDuoBackRailOverlay extends StatelessWidget {
  final Widget child;
  final ValueListenable<int> pageDepth;
  final ValueListenable<int> popupDepth;
  final ValueListenable<String?> pageName;
  final VoidCallback onBack;

  const CitroDuoBackRailOverlay({
    super.key,
    required this.child,
    required this.pageDepth,
    required this.popupDepth,
    required this.pageName,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned.fill(
          child: ValueListenableBuilder<int>(
            valueListenable: pageDepth,
            builder: (context, depth, _) {
              if (depth <= 1) return const SizedBox.shrink();
              return ValueListenableBuilder<int>(
                valueListenable: popupDepth,
                builder: (context, popups, _) {
                  if (popups > 0) return const SizedBox.shrink();
                  return ValueListenableBuilder<String?>(
                    valueListenable: pageName,
                    builder: (context, name, _) {
                      if (name == 'cook') return const SizedBox.shrink();
                      final media = MediaQuery.of(context);
                      final railWidth = media.padding.right > 84
                          ? media.padding.right
                          : 84.0;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: railWidth,
                            child: CitroDuoBackRail(
                              onBack: onBack,
                              topInset: CitroForm.duoRailTopInset(media.size),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class CitroDuoRailItem extends StatelessWidget {
  final String label;
  final String icon;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  const CitroDuoRailItem({
    super.key,
    required this.label,
    required this.icon,
    this.active = false,
    this.badge = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Pressable(
        onTap: onTap,
        hoverLift: 0,
        child: SizedBox(
          height: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: reduce
                        ? Duration.zero
                        : CitroMotion.indicatorLength,
                    curve: CitroMotion.emphasized,
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: active ? c.hl : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active
                            ? c.accent.withAlpha(110)
                            : Colors.transparent,
                      ),
                    ),
                    child: Center(
                      child: AnimatedScale(
                        scale: active ? 1.06 : 1,
                        duration: reduce ? Duration.zero : CitroMotion.press,
                        curve: CitroMotion.easeOut,
                        child: AppIcon(
                          strokeSvg(icon, width: 2),
                          size: 22,
                          color: active ? c.accentInk : c.ink2,
                        ),
                      ),
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -9,
                      top: -5,
                      child: CitroPop(
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 14,
                            minHeight: 14,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Center(
                            child: Text(
                              badge > 99 ? '99+' : '$badge',
                              style: context.body(
                                size: 8,
                                weight: FontWeight.w800,
                                color: const Color(0xFF2E2C22),
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: reduce ? Duration.zero : CitroMotion.hover,
                curve: CitroMotion.easeColor,
                style: context.hand(
                  size: 11.5,
                  color: active ? c.accentInk : c.ink2,
                  height: 1.1,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarNav extends StatelessWidget {
  final int index;
  final bool showResources;
  final List<Widget> items;

  /// 与 `_SidebarItem` 的高度一致：48 + 8 间距（8pt 栅格）。
  static const double _itemExtent = AppSpacing.x6 + AppSpacing.x1;

  const _SidebarNav({
    required this.index,
    required this.showResources,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final count = showResources ? 4 : 3;
    final active = index.clamp(0, count - 1);
    final reduce = CitroMotion.reduced(context);
    return Stack(
      children: [
        // 共享高亮：整块纸片在导航项之间滑动，取代逐项背景渐变。
        AnimatedPositioned(
          left: 0,
          right: 0,
          top: active * _itemExtent,
          height: AppSpacing.x6,
          duration: reduce ? Duration.zero : CitroMotion.indicatorLength,
          curve: CitroMotion.emphasized,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.hl,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.accent.withAlpha(110)),
              ),
            ),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final String icon;
  final bool active;
  final int badge;
  final VoidCallback onTap;
  final bool showHighlight;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.badge = 0,
    this.showHighlight = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final large = CitroOrientation.padSize(MediaQuery.sizeOf(context));
    final reduce = CitroMotion.reduced(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x1),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : CitroMotion.indicatorLength,
          curve: CitroMotion.emphasized,
          height: AppSpacing.x6,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1 + 4),
          decoration: showHighlight
              ? BoxDecoration(
                  color: active ? c.hl : Colors.transparent,
                  borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                  border: Border.all(
                    color: active
                        ? c.accent.withAlpha(110)
                        : Colors.transparent,
                  ),
                )
              : null,
          child: Row(
            children: [
              AnimatedContainer(
                duration: reduce ? Duration.zero : CitroMotion.hover,
                curve: CitroMotion.easeColor,
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: active ? c.accent : c.surface2,
                  borderRadius: BorderRadius.circular(AppSpacing.x1),
                  border: Border.all(
                    color: active ? c.accent : c.line.withAlpha(180),
                  ),
                ),
                child: Center(
                  child: AnimatedScale(
                    scale: active ? 1.06 : 1,
                    duration: reduce ? Duration.zero : CitroMotion.press,
                    curve: CitroMotion.easeOut,
                    child: AppIcon(
                      strokeSvg(icon, width: 2),
                      size: 17,
                      color: active ? const Color(0xFF2E2C22) : c.ink2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x1 + 4),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: reduce ? Duration.zero : CitroMotion.hover,
                  curve: CitroMotion.easeColor,
                  style: context.hand(
                    size: large ? 17 : 16,
                    color: active ? c.accentInk : c.ink,
                  ),
                  child: Text(label),
                ),
              ),
              if (badge > 0)
                CitroPop(
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: context.ui(
                        size: 10,
                        weight: FontWeight.w600,
                        color: const Color(0xFF2E2C22),
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                )
              else
                AnimatedScale(
                  scale: active ? 1 : .55,
                  duration: reduce ? Duration.zero : CitroMotion.press,
                  curve: CitroMotion.settle,
                  child: AnimatedOpacity(
                    opacity: active ? 1 : 0,
                    duration: reduce ? Duration.zero : CitroMotion.press,
                    curve: CitroMotion.easeColor,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
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
