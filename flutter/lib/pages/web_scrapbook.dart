import 'dart:async';

import 'package:flutter/material.dart';

import '../overlays/ai_chat.dart';
import '../overlays/coin_sheet.dart';
import '../overlays/lantern_sheet.dart';
import '../overlays/pomodoro_sheet.dart';
import '../services/lantern_api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../tingyu/tingyu_controller.dart';
import '../tingyu/tingyu_play_chip.dart';
import '../utils/navigation.dart';
import '../widgets/paper.dart';
import '../widgets/tab_bar.dart';
import 'me_page.dart';

/// Web 桌面（>=1025）的干净仪表盘：中性底 + 白色大圆角内容面。
///
/// 旧版的暖色桌面渐变与纸质内框已删除，只保留 12 栏网格算法。
class WebDesktopPaper extends StatelessWidget {
  final Widget child;

  const WebDesktopPaper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.bg2,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(CitroColors.radii.page),
              boxShadow: CitroColors.shadows.card(c),
            ),
            clipBehavior: Clip.antiAlias,
            child: CitroBackground(
              color: c.surface,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class WebGridCell {
  final int column;
  final int row;
  final int columnSpan;
  final int rowSpan;
  final Widget child;

  const WebGridCell(
    this.column,
    this.row,
    this.columnSpan,
    this.rowSpan,
    this.child,
  );
}

class WebDesktopGrid extends StatelessWidget {
  final int rows;
  final List<WebGridCell> children;

  const WebDesktopGrid({super.key, required this.rows, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        const headerHeight = 64.0;
        final bodyRows = rows - 1;
        final bodyHeight = constraints.maxHeight - headerHeight - gap * rows;
        final rowHeight = bodyHeight / bodyRows;
        final columnWidth = (constraints.maxWidth - gap * 11) / 12;
        double left(int column) => (column - 1) * (columnWidth + gap);
        double top(int row) =>
            row == 1 ? 0 : headerHeight + gap + (row - 2) * (rowHeight + gap);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final cell in children)
              Positioned(
                left: left(cell.column),
                top: top(cell.row),
                width:
                    columnWidth * cell.columnSpan + gap * (cell.columnSpan - 1),
                height: cell.row == 1
                    ? headerHeight
                    : rowHeight * cell.rowSpan + gap * (cell.rowSpan - 1),
                child: RepaintBoundary(child: cell.child),
              ),
          ],
        );
      },
    );
  }
}

class WebDesktopHeader extends StatelessWidget {
  final VoidCallback onHome;

  const WebDesktopHeader({super.key, required this.onHome});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  List<WebGridCell> cells(BuildContext context) => [
    WebGridCell(1, 1, 3, 1, _Brand(onTap: onHome)),
    const WebGridCell(3, 1, 5, 1, WebDesktopClock()),
    WebGridCell(
      8,
      1,
      5,
      1,
      Align(
        alignment: Alignment.centerRight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: ListenableBuilder(
            listenable: NookController.instance,
            builder: (context, _) {
              final playing = NookController.instance.playing;
              final reduce = CitroMotion.reduced(context);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (LanternApi.currentWindow() != null) ...[
                    _LanternNavButton(onTap: () => showLanternSheet(context)),
                    const SizedBox(width: 10),
                  ],
                  AnimatedSize(
                    duration: reduce ? Duration.zero : CitroMotion.size,
                    curve: CitroMotion.easeOut,
                    alignment: Alignment.centerRight,
                    child: AnimatedSwitcher(
                      duration: reduce ? Duration.zero : CitroMotion.popover,
                      switchInCurve: CitroMotion.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        final fade = FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                        if (reduce) return fade;
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: .96,
                              end: 1,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: playing
                          ? const Padding(
                              key: ValueKey('web-tingyu-chip'),
                              padding: EdgeInsets.only(left: 10),
                              child: TingyuPlayChip(),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('web-tingyu-chip-idle'),
                            ),
                    ),
                  ),
                  const WebThemeMenu(),
                  const SizedBox(width: 8),
                  const _HeaderAvatar(),
                ],
              );
            },
          ),
        ),
      ),
    ),
  ];
}

/// Web 桌面的账号入口：首页网格里的打卡已经改成卡片，
/// 头像收进顶栏，点一下仍然打开「我的」。
class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = context.c;
    final user = app.user;
    return Semantics(
      button: true,
      label: '我的',
      child: Pressable(
        onTap: () => openMePage(context),
        scale: .94,
        hoverLift: 0,
        hoverShadow: false,
        borderRadius: BorderRadius.circular(CitroColors.radii.avatar),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: c.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Center(
            child: user == null || user.name.isEmpty
                ? AppIcon(
                    strokeSvg(AppIcons.user, width: 2),
                    size: 18,
                    color: c.ink2,
                  )
                : Text(
                    user.name[0],
                    style: context.heading(
                      size: CitroType.meta,
                      color: c.ink,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final VoidCallback onTap;

  const _Brand({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => showCoinSheet(context),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Pressable(
                onTap: onTap,
                hoverLift: 0,
                hoverShadow: false,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo.webp',
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      cacheWidth: 120,
                    ),
                    const SizedBox(width: 10),
                    Text('Citro', style: context.heading(size: 28)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 宽桌面没有 Tab 栏，CICI 由顶栏这颗头像按钮担当，
              // 与手机 Tab 栏右侧的按钮是同一个组件。
              CiciAvatarButton(size: 42, onTap: () => showAiChat(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanternNavButton extends StatelessWidget {
  final VoidCallback onTap;

  const _LanternNavButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              strokeSvg(AppIcons.moon, width: 2),
              size: 18,
              color: c.accentInk,
            ),
            const SizedBox(width: 6),
            Text('灯谜', style: context.heading(size: CitroType.bodyLg)),
          ],
        ),
      ),
    );
  }
}

class WebThemeMenu extends StatelessWidget {
  const WebThemeMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = context.app;
    final icon = switch (state.themeMode) {
      ThemeMode.light => AppIcons.sun,
      ThemeMode.dark => AppIcons.moon,
      ThemeMode.system => AppIcons.monitor,
    };
    return PopupMenuButton<ThemeMode>(
      tooltip: '主题模式',
      initialValue: state.themeMode,
      onSelected: state.setThemeMode,
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shadowColor: c.scrim,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      menuPadding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 224, maxWidth: 250),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
        side: BorderSide(color: c.line),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<ThemeMode>(
          enabled: false,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Text(
                '外观主题',
                style: context.body(
                  size: CitroType.small,
                  weight: CitroType.medium,
                  color: c.inkSoft,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                'APPEARANCE',
                style: context.body(
                  size: CitroType.micro,
                  weight: CitroType.medium,
                  color: c.inkSoft,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        PopupMenuDivider(height: 10, color: c.line),
        _themeItem(context, ThemeMode.light, '浅色模式', AppIcons.sun),
        _themeItem(context, ThemeMode.dark, '深色模式', AppIcons.moon),
        _themeItem(context, ThemeMode.system, '跟随系统', AppIcons.monitor),
      ],
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '主题',
              style: context.body(
                size: CitroType.meta,
                color: c.inkSoft,
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            AppIcon(strokeSvg(icon), size: 22, color: c.accentInk),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<ThemeMode> _themeItem(
    BuildContext context,
    ThemeMode mode,
    String label,
    String icon,
  ) {
    final c = context.c;
    final selected = context.app.themeMode == mode;
    return PopupMenuItem(
      value: mode,
      height: 52,
      padding: EdgeInsets.zero,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? c.accentLt.withAlpha(140) : Colors.transparent,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? c.accent : c.surface2,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(icon),
                  size: 16,
                  color: selected ? c.onAccent : c.ink2,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                label,
                style: context.body(
                  size: CitroType.body,
                  weight: selected ? CitroType.medium : CitroType.regular,
                  color: selected ? c.accentInk : c.ink,
                ),
              ),
            ),
            if (selected)
              AppIcon(
                strokeSvg('<path d="M20 6 9 17l-5-5"/>', width: 2.4),
                size: 16,
                color: c.accentInk,
              ),
          ],
        ),
      ),
    );
  }
}

class WebDesktopClock extends StatefulWidget {
  const WebDesktopClock({super.key});

  @override
  State<WebDesktopClock> createState() => _WebDesktopClockState();
}

class _WebDesktopClockState extends State<WebDesktopClock> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const weeks = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    String two(int value) => value.toString().padLeft(2, '0');
    return Pressable(
      onTap: () => showPomodoroOverlay(context),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${_now.month}.${two(_now.day)}',
                style: context.body(size: CitroType.meta, color: c.inkSoft),
              ),
              const SizedBox(width: 10),
              Text(
                weeks[_now.weekday % 7],
                style: context.body(size: CitroType.body, color: c.inkSoft),
              ),
              const SizedBox(width: 10),
              Text(
                '${two(_now.hour)}:${two(_now.minute)}',
                style: context.hand(
                  size: 40,
                  weight: CitroType.strong,
                  color: c.ink,
                  height: 1,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                two(_now.second),
                style: context.hand(
                  size: CitroType.titleLg,
                  weight: CitroType.medium,
                  color: c.accentInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WebSectionTitle extends StatelessWidget {
  final String text;
  final double size;

  const WebSectionTitle(this.text, {super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: context.heading(size: size, color: context.c.ink));
  }
}

/// 网页宽屏的「返回首页」胶囊。
class WebHomeBackPill extends StatelessWidget {
  final String label;

  const WebHomeBackPill({super.key, this.label = '返回首页'});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => popOrHome(context),
      hoverLift: 0,
      hoverShadow: false,
      hoverColor: c.surface2,
      borderRadius: BorderRadius.circular(CitroColors.radii.chip),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              strokeSvg(AppIcons.arrowLeft, width: 2.2),
              size: 15,
              color: c.accentInk,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.body(
                size: CitroType.meta,
                weight: CitroType.medium,
                color: c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
