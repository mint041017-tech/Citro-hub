import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';

/// 待办模块的左侧导航（与听隅侧栏同款），待办页和专注页共用。
class TodoRail extends StatelessWidget {
  /// 'todo' / 'data' / 'focus' / 'cici'
  final String active;
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;

  const TodoRail({
    super.key,
    required this.active,
    required this.onSelect,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const items = <(String, String, String)>[
      ('todo', '待办', AppIcons.check),
      ('data', '数据', AppIcons.board),
      ('focus', '专注', AppIcons.target),
      ('cici', 'CiCi', AppIcons.sparkle),
    ];
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
              borderRadius: BorderRadius.circular(99),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.line),
                  boxShadow: CitroColors.shadows.paper(c),
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
              switch (active) {
                'data' => '数据',
                'focus' => '专注',
                'cici' => 'CiCi',
                _ => '待办',
              },
              style: context.ui(
                size: CitroType.heading,
                weight: CitroType.strong,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _dateLine(DateTime.now()),
              style: context.ui(size: CitroType.caption, color: c.inkSoft),
            ),
            const SizedBox(height: 20),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Pressable(
                  onTap: () => onSelect(item.$1),
                  borderRadius: BorderRadius.circular(13),
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
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        AppIcon(
                          strokeSvg(item.$3, width: 1.9),
                          size: 20,
                          color: active == item.$1 ? c.accent : c.inkSoft,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          item.$2,
                          style: context.ui(
                            size: CitroType.title,
                            weight: active == item.$1
                                ? CitroType.strong
                                : CitroType.regular,
                            color: active == item.$1 ? c.accent : c.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Text(
              '日程 · 复盘 · 专注',
              style: context.ui(size: CitroType.caption, color: c.inkSoft),
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
