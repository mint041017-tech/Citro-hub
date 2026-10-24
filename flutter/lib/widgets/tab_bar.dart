import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../state/app_state.dart';
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
    final side = math.max(0.0, (MediaQuery.sizeOf(context).width - 520) / 2);
    return Positioned(
      left: 10 + side,
      right: 10 + side,
      bottom: bottom + 10,
      child: RepaintBoundary(
        child: SizedBox(
          height: 66,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 66,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: c.dark
                        ? [const Color(0xFF24242C), const Color(0xFF1C1C23)]
                        : [const Color(0xFFFFFDF6), const Color(0xFFFBF5E9)],
                  ),
                  border: Border.all(
                    color: c.dark ? c.line : c.line.withAlpha(242),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: c.dark
                          ? const Color(0x99000000)
                          : const Color(0x6B5A4A2C),
                      blurRadius: 22,
                      spreadRadius: -12,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    _TabBtn(
                      label: '首页',
                      icon: AppIcons.home,
                      active: index == 0,
                      onTap: () => onChanged(0),
                    ),
                    _TabBtn(
                      label: '游戏',
                      icon: AppIcons.games,
                      active: index == 1,
                      onTap: () => onChanged(1),
                    ),
                    _TabBtn(
                      label: '社区',
                      icon: AppIcons.users,
                      active: index == 2,
                      badge: unread,
                      onTap: () => onChanged(2),
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

class _TabBtn extends StatelessWidget {
  final String label;
  final String icon;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  const _TabBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget inner = Container(
      width: double.infinity,
      height: active ? 54 : 46,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? (c.dark ? c.hl : const Color(0x57FECE66))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AppIcon(
                strokeSvg(icon, width: 2),
                size: 20,
                color: active ? c.accentInk : c.inkSoft.withAlpha(184),
              ),
              if (badge > 0)
                Positioned(
                  right: -8,
                  top: -4,
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
                        '$badge',
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
          const SizedBox(height: 1),
          Text(
            label,
            style: active
                ? context.display(
                    size: 12,
                    weight: FontWeight.w700,
                    color: c.accentInk,
                    height: 1.1,
                  )
                : context.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: c.inkSoft,
                    height: 1.1,
                  ),
          ),
          if (active)
            Container(
              width: 15,
              height: 3,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            )
          else
            const SizedBox(height: 4),
        ],
      ),
    );
    if (active) {
      inner = ClipPath(
        clipper: _ActiveClipper(),
        child: Transform.rotate(angle: -1.2 * math.pi / 180, child: inner),
      );
    }
    return Expanded(
      child: Pressable(
        onTap: onTap,
        child: Center(child: inner),
      ),
    );
  }
}

class _ActiveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .04, size.height * .12)
    ..lineTo(size.width * .96, 0)
    ..lineTo(size.width, size.height * .86)
    ..lineTo(size.width * .06, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
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
