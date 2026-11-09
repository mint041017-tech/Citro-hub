import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import 'motion_widgets.dart';
import 'paper.dart';

class CitroTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const CitroTabBar({super.key, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final unread = context.app.unread;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final barWidth = platform.isWindows ? 560.0 : 520.0;
    final side = math.max(
      0.0,
      (MediaQuery.sizeOf(context).width - barWidth) / 2,
    );
    final tabs = <_TabSpec>[
      const _TabSpec('首页', AppIcons.home),
      const _TabSpec('游戏', AppIcons.games),
      _TabSpec('社区', AppIcons.community, badge: unread),
      if (platform.isWindows) const _TabSpec('资源', AppIcons.library),
      // 「我的」固定在最后一个，手机端也是右侧最后一格。
      const _TabSpec('我的', AppIcons.user),
    ];
    final count = tabs.length;
    final reduce = CitroMotion.reduced(context);
    return Positioned(
      left: AppSpacing.x1 + side,
      right: AppSpacing.x1 + side,
      bottom: bottom + AppSpacing.x1,
      child: RepaintBoundary(
        child: SizedBox(
          height: AppSpacing.navBar,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // iOS / iPadOS 上是真实背景模糊，Android 是 tonal 表面，
              // Windows / Web 是半透明纸面——同一块导航，各端用各自的原生材质。
              CitroGlass(
                height: AppSpacing.navBar,
                borderRadius: BorderRadius.circular(CitroColors.radii.card),
                shadow: CitroColors.shadows.chrome(c),
                padding: const EdgeInsets.all(AppSpacing.x1),
                // 竖屏底部栏使用实色纸面，不透出背后的内容。
                blur: false,
                highlight: false,
                tint: c.surface,
                borderColor: c.line,
                child: Stack(
                  children: [
                    // 共享高亮：一颗胶囊在 Tab 之间滑过去，
                    // 比每个 Tab 各自渐变更连贯，也不会出现两个高亮同时存在。
                    // 位置按 Row 的等分宽度直接算（Align 的 alignment 是在
                    // 「剩余空间」里插值，会和 Tab 中心越走越偏）。
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final itemWidth = constraints.maxWidth / count;
                          // 图标模式：高亮收成一枚圆形胶囊，只包住当前图标。
                          final pill = math.min(itemWidth - 8, 54.0);
                          return Stack(
                            children: [
                              AnimatedPositioned(
                                duration: reduce
                                    ? Duration.zero
                                    : CitroMotion.indicatorLength,
                                curve: CitroMotion.emphasized,
                                left:
                                    itemWidth * index + (itemWidth - pill) / 2,
                                width: pill,
                                top: 3,
                                bottom: 3,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: c.dark
                                        ? c.hl
                                        : c.accent.withAlpha(120),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(
                            child: Pressable(
                              onTap: () => onChanged(i),
                              hoverLift: 0,
                              hoverShadow: false,
                              child: Center(
                                child: _TabBtn(
                                  label: tabs[i].label,
                                  icon: tabs[i].icon,
                                  active: index == i,
                                  badge: tabs[i].badge,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -9,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.rotate(
                    angle: -1.8 * math.pi / 180,
                    child: ClipPath(
                      clipper: _TapeClipper(),
                      child: Container(
                        width: 112,
                        height: 18,
                        decoration: BoxDecoration(
                          color: c.tape,
                          boxShadow: [
                            BoxShadow(
                              color: c.dark
                                  ? const Color(0x30000000)
                                  : const Color(0x735A4A2C),
                              blurRadius: 5,
                              spreadRadius: -3,
                              offset: const Offset(0, 2),
                            ),
                          ],
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

class _TabSpec {
  final String label;
  final String icon;
  final int badge;

  const _TabSpec(this.label, this.icon, {this.badge = 0});
}

class _TabBtn extends StatelessWidget {
  final String label;
  final String icon;
  final bool active;
  final int badge;

  const _TabBtn({
    required this.label,
    required this.icon,
    required this.active,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    final activeColor = c.accentInk;
    final idleColor = c.ink2.withAlpha(200);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: SizedBox(
        height: AppSpacing.touch,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: active ? 1 : 0),
                duration: reduce ? Duration.zero : CitroMotion.press,
                curve: CitroMotion.easeOut,
                builder: (context, t, _) {
                  return Transform.scale(
                    scale: 1 + .1 * t,
                    child: AppIcon(
                      strokeSvg(icon, width: 2),
                      size: 26,
                      color: Color.lerp(idleColor, activeColor, t)!,
                    ),
                  );
                },
              ),
              if (badge > 0)
                Positioned(
                  right: -8,
                  top: -4,
                  child: CitroPop(child: _Badge(count: badge)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
      ),
      child: Center(
        child: Text(
          '$count',
          style: context.ui(
            size: 9,
            weight: FontWeight.w700,
            color: const Color(0xFF2E2C22),
            height: 1,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _TapeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .02, 0)
    ..lineTo(size.width * .98, size.height * .06)
    ..lineTo(size.width, size.height * .92)
    ..lineTo(size.width * .03, size.height)
    ..lineTo(0, size.height * .26)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
