import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'ledger_models.dart';
import 'ledger_theme.dart';

/// 分类 iconKey → 线条图标。分类数据只存 key，换图标不用改模型。
String ledgerCategoryIcon(String key) => switch (key) {
  'fork' => AppIcons.fork,
  'location' => AppIcons.location,
  'cart' => AppIcons.cart,
  'home' => AppIcons.home,
  'games' => AppIcons.games,
  'heart' => AppIcons.heart,
  'book' => AppIcons.book,
  'users' => AppIcons.users,
  'note' => AppIcons.note,
  'trophy' => AppIcons.trophy,
  'board' => AppIcons.board,
  'clock' => AppIcons.clock,
  'wallet' => AppIcons.wallet,
  'trendUp' => AppIcons.trendUp,
  _ => AppIcons.flag,
};

class LedgerIconTile extends StatelessWidget {
  final String iconKey;
  final Color tint;
  final double size;
  final bool active;
  final bool filled;

  const LedgerIconTile({
    super.key,
    required this.iconKey,
    required this.tint,
    this.size = 42,
    this.active = false,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled
            ? tint.withAlpha(active ? 54 : 28)
            : (active ? tint.withAlpha(48) : c.surface2),
        borderRadius: BorderRadius.circular(CitroColors.radii.small),
        border: Border.all(
          color: active ? tint.withAlpha(150) : c.line,
          width: active ? 1.3 : 1,
        ),
      ),
      child: Center(
        child: AppIcon(
          strokeSvg(ledgerCategoryIcon(iconKey), width: 1.9),
          size: size * .46,
          color: active ? tint : c.ink2,
        ),
      ),
    );
  }
}

/// 支出 / 收入分段选择。选中块用语义色软底，和全局标签语言一致。
class LedgerKindToggle extends StatelessWidget {
  final LedgerKind value;
  final ValueChanged<LedgerKind> onChanged;
  final bool compact;

  const LedgerKindToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    final selectedColor = value == LedgerKind.expense
        ? c.stamp.withAlpha(c.dark ? 70 : 34)
        : c.mintSoft;
    return Container(
      height: compact ? 38 : AppSpacing.touch,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          for (final kind in LedgerKind.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(kind),
                child: AnimatedContainer(
                  duration: reduce ? Duration.zero : CitroMotion.indicator,
                  curve: CitroMotion.easeColor,
                  decoration: BoxDecoration(
                    color: value == kind
                        ? (kind == LedgerKind.expense
                              ? selectedColor
                              : c.mintSoft)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                  ),
                  child: Center(
                    child: Text(
                      kind.label,
                      style: context.lui(
                        size: compact ? CitroType.label : CitroType.body,
                        weight: CitroType.strong,
                        color: value == kind
                            ? (kind == LedgerKind.expense ? c.stamp : c.mintInk)
                            : c.inkSoft,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LedgerMonthSwitcher extends StatelessWidget {
  final String monthKey;
  final ValueChanged<String> onChanged;
  final bool showBackToNow;

  const LedgerMonthSwitcher({
    super.key,
    required this.monthKey,
    required this.onChanged,
    this.showBackToNow = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final nowKey = LedgerDates.monthKey(DateTime.now());
    final isNow = monthKey == nowKey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MonthArrow(
          icon: AppIcons.chevronLeft,
          label: '上个月',
          onTap: () => onChanged(LedgerDates.monthKeyOfOffset(monthKey, -1)),
        ),
        const SizedBox(width: 6),
        Pressable(
          onTap: showBackToNow && !isNow ? () => onChanged(nowKey) : null,
          scale: .96,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              // 当前月用 accent 软底，深浅色下都保持同一套语义。
              color: isNow ? c.accent.withAlpha(24) : c.surface2,
              borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              border: Border.all(
                color: isNow ? c.accent.withAlpha(90) : c.line,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  strokeSvg(AppIcons.calendar, width: 1.9),
                  size: 13,
                  color: c.accentInk,
                ),
                const SizedBox(width: 5),
                Text(
                  LedgerDates.monthLabel(monthKey),
                  style: context.lui(
                    size: CitroType.meta,
                    weight: CitroType.strong,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _MonthArrow(
          icon: AppIcons.chevronRight,
          label: '下个月',
          onTap: () => onChanged(LedgerDates.monthKeyOfOffset(monthKey, 1)),
        ),
      ],
    );
  }
}

class _MonthArrow extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _MonthArrow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        scale: .9,
        hoverLift: 0,
        borderRadius: BorderRadius.circular(CitroColors.radii.avatar),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: c.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: c.line),
          ),
          child: Center(
            child: AppIcon(strokeSvg(icon, width: 2), size: 15, color: c.ink2),
          ),
        ),
      ),
    );
  }
}

/// 预算进度条：胶囊轨道 + 纯色填充，超支变成朱砂红。
class LedgerProgress extends StatelessWidget {
  final double value;
  final Color color;
  final Color? secondColor;
  final double height;
  final bool over;

  const LedgerProgress({
    super.key,
    required this.value,
    required this.color,
    this.secondColor,
    this.height = 7,
    this.over = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final clamped = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(CitroColors.radii.chip),
      child: Container(
        height: height,
        color: c.line.withAlpha(120),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: clamped,
          child: Container(
            decoration: BoxDecoration(
              color: over ? c.stamp : color,
              borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              gradient: over
                  ? null
                  : LinearGradient(
                      colors: [color.withAlpha(210), secondColor ?? color],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 概览里的一个数字块：小标签 + 等宽大数字。
class LedgerStat extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final Color? color;

  const LedgerStat({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: context.lui(
            size: CitroType.caption,
            color: c.inkSoft,
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: context.lhand(
              size: CitroType.titleLg,
              weight: CitroType.strong,
              color: color ?? c.ink,
              height: 1,
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 3),
          Text(
            hint!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.lui(size: CitroType.small, color: c.inkSoft),
          ),
        ],
      ],
    );
  }
}

class LedgerSectionTitle extends StatelessWidget {
  final String title;
  final String? hint;
  final Widget? trailing;

  const LedgerSectionTitle({
    super.key,
    required this.title,
    this.hint,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: CitroType.title * .72,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(CitroColors.radii.xs),
                    ),
                  ),
                  Text(
                    title,
                    style: context.lheading(
                      size: CitroType.title,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
              if (hint != null) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    hint!,
                    style: context.lui(
                      size: CitroType.caption,
                      color: c.inkSoft,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// 账单行：左侧分类色块，右侧等宽金额与时间。
class LedgerEntryRow extends StatelessWidget {
  final LedgerEntry entry;
  final LedgerCategory category;
  final VoidCallback? onTap;
  final bool dense;

  const LedgerEntryRow({
    super.key,
    required this.entry,
    required this.category,
    this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final expense = entry.kind == LedgerKind.expense;
    // 支出用近黑，红色只留给删除 / 逾期 / 错误；收入继续用薄荷绿。
    final amountColor = expense ? c.ink : c.mintInk;
    final title = entry.note.trim().isEmpty ? category.name : entry.note.trim();
    return Pressable(
      onTap: onTap,
      scale: .985,
      hoverLift: 0,
      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: dense ? 7 : 9),
        child: Row(
          children: [
            LedgerIconTile(
              iconKey: category.iconKey,
              tint: category.tint,
              size: dense ? 34 : 38,
              filled: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.lui(
                      size: dense ? CitroType.meta : CitroType.body,
                      weight: CitroType.strong,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${category.name} · ${entry.occurredAt.month}月${entry.occurredAt.day}日 ${LedgerDates.timeLabel(entry.occurredAt)}'
                    '${entry.source == LedgerSource.manual ? '' : ' · ${entry.source.label}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.lui(size: CitroType.small, color: c.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${expense ? '-' : '+'}${ledgerMoney(entry.amountCents)}',
              style: context.lhand(
                size: dense ? CitroType.meta : CitroType.bodyLg,
                weight: CitroType.strong,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空状态：图标 + 一句引导，保持留白。
class LedgerEmptyState extends StatelessWidget {
  final String title;
  final String hint;
  final String? action;
  final VoidCallback? onAction;
  final String icon;

  const LedgerEmptyState({
    super.key,
    required this.title,
    required this.hint,
    this.action,
    this.onAction,
    this.icon = AppIcons.wallet,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              LedgerIconTile(iconKey: 'wallet', tint: c.accent, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: context.lheading(size: CitroType.title, color: c.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hint,
            style: context.lui(
              size: CitroType.meta,
              color: c.inkSoft,
              height: 1.5,
            ),
          ),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 12),
            Pressable(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                ),
                child: Text(
                  action!,
                  style: context.lui(
                    size: CitroType.meta,
                    weight: CitroType.strong,
                    color: c.onAccent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 数字键盘：大圆角按键，等宽数字。
class LedgerNumberPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onDone;
  final String doneLabel;
  final bool enabled;

  const LedgerNumberPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onDone,
    this.doneLabel = '完成',
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', '⌫'],
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth < 340 ? 6.0 : AppSpacing.x1;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in keys)
              Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: Row(
                  children: [
                    for (var i = 0; i < row.length; i++) ...[
                      if (i > 0) SizedBox(width: gap),
                      Expanded(
                        child: _PadKey(
                          label: row[i],
                          enabled: enabled,
                          isBackspace: row[i] == '⌫',
                          onTap: row[i] == '⌫'
                              ? onBackspace
                              : () => onDigit(row[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (onDone != null)
              SizedBox(
                width: double.infinity,
                height: AppSpacing.touch,
                child: Pressable(
                  onTap: enabled ? onDone : null,
                  borderRadius: BorderRadius.circular(CitroColors.radii.button),
                  child: Container(
                    decoration: BoxDecoration(
                      color: enabled ? context.c.accent : context.c.line,
                      borderRadius: BorderRadius.circular(
                        CitroColors.radii.button,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        doneLabel,
                        style: context.lui(
                          size: CitroType.bodyLg,
                          weight: CitroType.strong,
                          color: context.c.onAccent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PadKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isBackspace;
  final bool enabled;

  const _PadKey({
    required this.label,
    required this.onTap,
    this.isBackspace = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: enabled ? onTap : null,
      scale: .94,
      hoverLift: 0,
      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      child: Container(
        height: AppSpacing.touch + 8,
        decoration: BoxDecoration(
          color: isBackspace ? c.surface : c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          border: Border.all(color: c.line),
        ),
        child: Center(
          child: isBackspace
              ? AppIcon(
                  strokeSvg(AppIcons.close, width: 2),
                  size: 17,
                  color: c.inkSoft,
                )
              : Text(
                  label,
                  style: context.lhand(
                    size: CitroType.titleLg,
                    weight: CitroType.strong,
                    color: c.ink,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 分类选择格：4 列铺开，选中后底色变成分类色。
class LedgerCategoryPicker extends StatelessWidget {
  final List<LedgerCategory> categories;
  final String selectedId;
  final ValueChanged<LedgerCategory> onSelected;
  final bool compact;

  const LedgerCategoryPicker({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520
            ? 6
            : (constraints.maxWidth >= 360 ? 4 : 3);
        final gap = compact ? 6.0 : AppSpacing.x1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final category in categories)
              SizedBox(
                width: width,
                child: _CategoryCell(
                  category: category,
                  selected: category.id == selectedId,
                  onTap: () => onSelected(category),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryCell extends StatelessWidget {
  final LedgerCategory category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryCell({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: .94,
      hoverLift: 0,
      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      child: AnimatedContainer(
        duration: CitroMotion.reduced(context)
            ? Duration.zero
            : CitroMotion.hover,
        curve: CitroMotion.easeColor,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? category.tint.withAlpha(38) : c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          border: Border.all(
            color: selected ? category.tint.withAlpha(160) : c.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LedgerIconTile(
              iconKey: category.iconKey,
              tint: category.tint,
              size: 34,
              active: selected,
              filled: true,
            ),
            const SizedBox(height: 5),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.lui(
                size: CitroType.caption,
                weight: selected ? CitroType.strong : CitroType.regular,
                color: selected ? category.tint : c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 小标签：预算、来源、分类预算等。
class LedgerChip extends StatelessWidget {
  final String text;
  final Color? color;
  final String? icon;
  final VoidCallback? onTap;
  final bool filled;

  const LedgerChip({
    super.key,
    required this.text,
    this.color,
    this.icon,
    this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = color ?? c.accentInk;
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? tint.withAlpha(30) : Colors.transparent,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(color: tint.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(strokeSvg(icon!, width: 2), size: 11, color: tint),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: context.lui(
              size: CitroType.small,
              weight: CitroType.strong,
              color: tint,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Pressable(onTap: onTap, scale: .95, hoverLift: 0, child: content);
  }
}

/// 同步状态小圆点：已登录用薄荷绿，避免用户误以为数据只存在本机。
class LedgerSyncBadge extends StatelessWidget {
  final bool signedIn;
  final bool syncing;

  const LedgerSyncBadge({
    super.key,
    required this.signedIn,
    this.syncing = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = signedIn ? c.mint : c.inkSoft;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (syncing)
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
          )
        else
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 4),
        Text(
          signedIn ? '已同步' : '仅本机',
          style: context.lui(size: CitroType.small, color: c.inkSoft),
        ),
      ],
    );
  }
}

/// 金额输入展示：¥ 符号固定，数字用大号等宽字体。
class LedgerAmountDisplay extends StatelessWidget {
  final String value;
  final String hint;
  final bool focused;

  const LedgerAmountDisplay({
    super.key,
    required this.value,
    this.hint = '0.00',
    this.focused = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = value.isEmpty ? hint : value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '¥',
            style: context.lhand(
              size: CitroType.titleLg,
              weight: CitroType.strong,
              color: c.inkSoft,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  text,
                  maxLines: 1,
                  style: context.lhand(
                    size: CitroType.poster,
                    weight: CitroType.strong,
                    color: value.isEmpty ? c.inkSoft.withAlpha(120) : c.ink,
                    height: 1,
                  ),
                ),
                if (focused && value.isNotEmpty)
                  Container(
                    width: 2,
                    height: 34,
                    margin: const EdgeInsets.only(left: 3, bottom: 4),
                    color: c.accent,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 后台统一的轻提示，保持和 App 其他页面一致。
void ledgerToast(BuildContext context, String text) {
  AppToast.show(context, text);
}
