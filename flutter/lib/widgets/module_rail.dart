import 'package:flutter/material.dart';

import '../overlays/ai_chat.dart';
import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'paper.dart';

/// 侧栏条目：(路由 key, 文案, 图标)。
typedef RailItem = (String, String, String);

/// 侧栏文本样式：(字号, 字重, 前景色) -> TextStyle。
typedef RailTextStyle = TextStyle Function(double, FontWeight, Color);

/// 左侧导航的共享实现：记账、待办、专注共用同一套纸页侧栏。
///
/// 两个模块只在标题、条目、选中前景色和字号档位上不同；排版、返回键、
/// Windows 下的 CiCi 入口与页脚由这里统一维护。
class ModuleRail extends StatelessWidget {
  final String title;
  final List<RailItem> items;
  final String active;
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;
  final String footer;
  final Color selectedFg;
  final RailTextStyle textStyle;

  const ModuleRail({
    super.key,
    required this.title,
    required this.items,
    required this.active,
    required this.onSelect,
    required this.onBack,
    required this.footer,
    required this.selectedFg,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    return Container(
      width: 194,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 26, 14, 20),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Pressable(
              onTap: onBack,
              scale: .92,
              borderRadius: BorderRadius.circular(CitroColors.radii.avatar),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.line),
                  boxShadow: CitroColors.shadows.card(c),
                ),
                child: Center(
                  child: AppIcon(
                    strokeSvg(AppIcons.arrowLeft, width: 2.2),
                    size: 17,
                    color: c.ink2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: textStyle(CitroType.heading, CitroType.strong, c.ink),
            ),
            const SizedBox(height: 4),
            Text(
              _dateLine(DateTime.now()),
              style: textStyle(CitroType.caption, CitroType.regular, c.inkSoft),
            ),
            const SizedBox(height: 20),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Pressable(
                  onTap: () => onSelect(item.$1),
                  borderRadius: BorderRadius.circular(CitroColors.radii.small),
                  child: AnimatedContainer(
                    duration: reduce ? Duration.zero : CitroMotion.hover,
                    curve: CitroMotion.easeColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: active == item.$1
                          ? c.accent.withAlpha(30)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        CitroColors.radii.small,
                      ),
                    ),
                    child: Row(
                      children: [
                        AppIcon(
                          strokeSvg(item.$3, width: 1.9),
                          size: 20,
                          color: active == item.$1 ? selectedFg : c.inkSoft,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          item.$2,
                          style: textStyle(
                            CitroType.title,
                            active == item.$1
                                ? CitroType.strong
                                : CitroType.regular,
                            active == item.$1 ? selectedFg : c.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Windows 宽屏没有底部 tab 栏（CiCi 入口在那里），补一个在侧栏。
            if (platform.isWindows) ...[
              const SizedBox(height: 6),
              Pressable(
                onTap: () => showAiChat(context),
                borderRadius: BorderRadius.circular(CitroColors.radii.small),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        strokeSvg(AppIcons.sparkle, width: 1.9),
                        size: 20,
                        color: c.accentInk,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'CiCi',
                        style: textStyle(
                          CitroType.title,
                          CitroType.strong,
                          c.accentInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              footer,
              style: textStyle(CitroType.caption, CitroType.regular, c.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  static String _dateLine(DateTime d) {
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    return '${d.month} 月 ${d.day} 日 · 周${week[d.weekday - 1]}';
  }
}
