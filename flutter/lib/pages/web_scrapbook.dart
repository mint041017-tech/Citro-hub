import 'dart:async';

import 'package:flutter/material.dart';

import '../overlays/ai_chat.dart';
import '../overlays/coin_sheet.dart';
import '../overlays/lantern_sheet.dart';
import '../overlays/pomodoro_sheet.dart';
import '../services/lantern_api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/paper.dart';

/// The desktop page is a 12-column sheet on a warm desk, matching index.html.
class WebDesktopPaper extends StatelessWidget {
  final Widget child;

  const WebDesktopPaper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: c.dark
              ? const [Color(0xFF111113), Color(0xFF08080A)]
              : const [Color(0xFFE9DCC6), Color(0xFFDCCAB0)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: c.dark ? Colors.black54 : const Color(0x553C301A),
                  blurRadius: 42,
                  offset: const Offset(0, 20),
                  spreadRadius: -20,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: PaperBackground(
              color: c.surface,
              child: Padding(padding: const EdgeInsets.all(4), child: child),
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
        const gap = 12.0;
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
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }

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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (LanternApi.currentWindow() != null) ...[
                _LanternNavButton(onTap: () => showLanternSheet(context)),
                const SizedBox(width: 9),
              ],
              const WebThemeMenu(),
            ],
          ),
        ),
      ),
    ),
  ];
}

class _Brand extends StatelessWidget {
  final VoidCallback onTap;

  const _Brand({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
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
                      width: 56,
                      height: 56,
                      fit: BoxFit.contain,
                      cacheWidth: 168,
                    ),
                    const SizedBox(width: 9),
                    HighlightedText(
                      'Citro',
                      style: context.display(size: 34, color: c.ink),
                      highlight: c.hl,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Pressable(
                onTap: () => showAiChat(context),
                hoverLift: 0,
                hoverShadow: false,
                hoverColor: c.hl.withAlpha(55),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: c.surface2.withAlpha(210),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.line),
                    boxShadow: CitroColors.shadows.paper(c),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        strokeSvg(AppIcons.sparkle, width: 2),
                        size: 18,
                        color: c.accentInk,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'CiCi',
                        style: context.body(
                          size: 15,
                          weight: FontWeight.w700,
                          color: c.accentInk,
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
          color: c.surface2.withAlpha(220),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌕', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text('灯谜', style: context.heading(size: 15, color: c.ink)),
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
      color: c.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shadowColor: c.ink.withAlpha(50),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      menuPadding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 224, maxWidth: 250),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
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
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: c.inkSoft,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                'APPEARANCE',
                style: context.hand(size: 11, color: c.inkSoft),
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
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: c.surface2.withAlpha(220),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('主题', style: context.display(size: 13, color: c.inkSoft)),
            const SizedBox(width: 7),
            AppIcon(strokeSvg(icon), size: 25, color: c.accentInk),
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
          color: selected ? c.hl.withAlpha(105) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? c.accent.withAlpha(110) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? c.accent : c.hl.withAlpha(90),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(icon),
                  size: 16,
                  color: selected ? const Color(0xFF2E2C22) : c.accentInk,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: context.body(
                  size: 14,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
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
                style: context.body(size: 14, color: c.inkSoft),
              ),
              const SizedBox(width: 10),
              Text(
                weeks[_now.weekday % 7],
                style: context.body(size: 15, color: c.inkSoft),
              ),
              const SizedBox(width: 10),
              Text(
                '${two(_now.hour)}:${two(_now.minute)}',
                style: context.display(
                  size: 48,
                  weight: FontWeight.w600,
                  color: c.ink,
                  height: 1,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                two(_now.second),
                style: context.display(size: 24, color: c.accentInk),
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
    return HighlightedText(
      text,
      style: context.heading(size: size, color: context.c.ink),
      highlight: context.c.hl,
    );
  }
}

/// 网页宽屏的「返回首页」纸质胶囊。
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
      hoverColor: c.hl.withAlpha(55),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface2.withAlpha(235),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
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
                size: 12.5,
                weight: FontWeight.w600,
                color: c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
