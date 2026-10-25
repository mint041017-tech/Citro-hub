import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../overlays/ai_chat.dart';
import '../services/api.dart';
import '../pages/me_page.dart';
import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import 'paper.dart';

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
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: PaperBackground(
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
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
                          style: context.body(
                            size: 10.5,
                            weight: FontWeight.w700,
                            color: c.inkSoft,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 7),
                        _SidebarItem(
                          label: '首页',
                          icon: AppIcons.home,
                          active: index == 0,
                          onTap: () => onChanged(0),
                        ),
                        _SidebarItem(
                          label: '游戏',
                          icon: AppIcons.games,
                          active: index == 1,
                          onTap: () => onChanged(1),
                        ),
                        _SidebarItem(
                          label: '社区',
                          icon: AppIcons.users,
                          active: index == 2,
                          badge: app.unread,
                          onTap: () => onChanged(2),
                        ),
                        if (showResources)
                          _SidebarItem(
                            label: '资源库',
                            icon: AppIcons.library,
                            active: index == 3,
                            onTap: () => onChanged(3),
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
                          style: context.body(
                            size: 10.5,
                            weight: FontWeight.w700,
                            color: c.inkSoft,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 7),
                        _SidebarItem(
                          label: '食谱日记',
                          icon: AppIcons.fork,
                          active: false,
                          onTap: () => Navigator.of(context).pushNamed('/cook'),
                        ),
                        _SidebarItem(
                          label: '我的',
                          icon: AppIcons.user,
                          active: false,
                          onTap: () {
                            if (platform.isWindows) {
                              showMeWindow(context);
                            } else {
                              Navigator.of(context).pushNamed('/me');
                            }
                          },
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
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line),
                    boxShadow: CitroColors.shadows.paper(c),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.loggedIn ? app.displayName : '游客漫游中',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.heading(size: 14, color: c.ink),
                      ),
                      const SizedBox(height: 3),
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
                        icon: AppIcons.users,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
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
                      child: AppIcon(
                        strokeSvg(icon, width: 2),
                        size: 22,
                        color: active ? c.accentInk : c.ink2,
                      ),
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -9,
                      top: -5,
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
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: active ? c.accentInk : c.ink2,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final String icon;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? c.hl : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? c.accent.withAlpha(110) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: active ? c.accent : c.surface2,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: active ? c.accent : c.line.withAlpha(180),
                  ),
                ),
                child: Center(
                  child: AppIcon(
                    strokeSvg(icon, width: 2),
                    size: 17,
                    color: active ? const Color(0xFF2E2C22) : c.ink2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: context.body(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: active ? c.accentInk : c.ink,
                  ),
                ),
              ),
              if (badge > 0)
                Container(
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
                    style: context.body(
                      size: 9,
                      weight: FontWeight.w800,
                      color: const Color(0xFF2E2C22),
                    ),
                  ),
                )
              else if (active)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
