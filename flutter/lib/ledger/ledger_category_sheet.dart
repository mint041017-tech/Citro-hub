import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'ledger_models.dart';
import 'ledger_store.dart';
import 'ledger_theme.dart';
import 'ledger_widgets.dart';

/// 分类管理：内置分类可改名/换图标/隐藏，自定义分类可新增与删除。
Future<void> showLedgerCategorySheet(BuildContext context) {
  return showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => LedgerScope(child: const _CategorySheet()),
  );
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet();

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  Future<void> _create(LedgerKind kind) async {
    final result = await _showCategoryEditor(context, kind: kind);
    if (result == null || !mounted) return;
    LedgerStore.instance.addCategory(
      name: result.name,
      kind: result.kind,
      color: result.color,
      iconKey: result.icon,
    );
    setState(() {});
    ledgerToast(context, '已新增分类「${result.name}」');
  }

  Future<void> _edit(LedgerCategory category) async {
    final result = await _showCategoryEditor(context, existing: category);
    if (result == null || !mounted) return;
    LedgerStore.instance.updateCategory(
      category.copyWith(
        name: result.name,
        color: result.color,
        iconKey: result.icon,
        active: true,
      ),
    );
    setState(() {});
    ledgerToast(context, '分类已更新');
  }

  Future<void> _remove(LedgerCategory category) async {
    if (category.builtIn) {
      LedgerStore.instance.removeCategory(category.id);
      setState(() {});
      ledgerToast(context, '已隐藏「${category.name}」，可在下方恢复');
      return;
    }
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        maxWidth: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '删除分类？',
              style: ctx.lheading(size: CitroType.subtitle, color: ctx.c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              '「${category.name}」下已有的账单会迁移到「其他」，不会丢失。',
              style: ctx.lui(
                size: CitroType.meta,
                color: ctx.c.inkSoft,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '取消',
                    outlined: true,
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AccentButton(
                    text: '删除',
                    danger: true,
                    onTap: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    LedgerStore.instance.removeCategory(category.id);
    setState(() {});
    ledgerToast(context, '分类已删除');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = LedgerStore.instance;
    final expense = store.expenseCategories;
    final income = store.incomeCategories;
    final hidden = store.categories.where((c) => !c.active).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .82,
          minChildSize: .5,
          maxChildSize: .95,
          builder: (context, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.line2,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '分类管理',
                            style: context.lheading(
                              size: CitroType.subtitle,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '内置分类可隐藏，自定义分类可删除',
                            style: context.lui(
                              size: CitroType.caption,
                              color: c.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _group(context, '支出分类', expense, LedgerKind.expense),
                const SizedBox(height: 12),
                _group(context, '收入分类', income, LedgerKind.income),
                if (hidden.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  LedgerSectionTitle(title: '已隐藏', hint: '点「恢复」重新放回选择器'),
                  const SizedBox(height: 6),
                  for (final category in hidden)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: c.bg2.withAlpha(c.dark ? 100 : 70),
                          borderRadius: BorderRadius.circular(
                            CitroColors.radii.inner,
                          ),
                          border: Border.all(color: c.line),
                        ),
                        child: Row(
                          children: [
                            LedgerIconTile(
                              iconKey: category.iconKey,
                              tint: category.tint,
                              size: 30,
                              filled: true,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${category.name} · ${category.kind.label}',
                                style: context.lui(
                                  size: CitroType.meta,
                                  color: c.inkSoft,
                                ),
                              ),
                            ),
                            LedgerChip(
                              text: '恢复',
                              onTap: () {
                                LedgerStore.instance.updateCategory(
                                  category.copyWith(active: true),
                                );
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _group(
    BuildContext context,
    String title,
    List<LedgerCategory> categories,
    LedgerKind kind,
  ) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LedgerSectionTitle(
          title: title,
          trailing: LedgerChip(
            text: '新增',
            icon: AppIcons.plus,
            onTap: () => _create(kind),
          ),
        ),
        const SizedBox(height: 6),
        for (final category in categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: [
                  Tooltip(
                    message: '编辑分类',
                    child: Semantics(
                      button: true,
                      label: '编辑「${category.name}」',
                      child: Pressable(
                        onTap: () => _edit(category),
                        scale: .9,
                        hoverLift: 0,
                        borderRadius: BorderRadius.circular(10),
                        child: LedgerIconTile(
                          iconKey: category.iconKey,
                          tint: category.tint,
                          size: 34,
                          filled: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.lui(
                              size: CitroType.body,
                              weight: CitroType.strong,
                              color: c.ink,
                            ),
                          ),
                        ),
                        if (category.builtIn) ...[
                          const SizedBox(width: 6),
                          LedgerChip(text: '内置', color: c.inkSoft),
                        ],
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: () => _remove(category),
                    scale: .9,
                    hoverLift: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: AppIcon(
                        strokeSvg(
                          category.builtIn ? AppIcons.eye : AppIcons.trash,
                          width: 1.9,
                        ),
                        size: 15,
                        color: category.builtIn ? c.inkSoft : c.stamp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

typedef _CategoryResult = ({
  String name,
  LedgerKind kind,
  int color,
  String icon,
});

Future<_CategoryResult?> _showCategoryEditor(
  BuildContext context, {
  LedgerCategory? existing,
  LedgerKind kind = LedgerKind.expense,
}) {
  return showCitroDialog<_CategoryResult>(
    context,
    builder: (ctx) => LedgerScope(
      child: _CategoryEditorDialog(existing: existing, kind: kind),
    ),
  );
}

class _CategoryEditorDialog extends StatefulWidget {
  final LedgerCategory? existing;
  final LedgerKind kind;

  const _CategoryEditorDialog({this.existing, required this.kind});

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late LedgerKind _kind = widget.existing?.kind ?? widget.kind;
  late int _color = widget.existing?.color ?? _palette.first;
  late String _icon = widget.existing?.iconKey ?? 'flag';

  static const _palette = [
    0xFFC08A4A,
    0xFF6F8CA8,
    0xFFB5717A,
    0xFF6E9A78,
    0xFF9A8FA6,
    0xFFC4855D,
    0xFF8FA6BE,
    0xFFA79E8C,
  ];
  static const _icons = [
    'fork',
    'cart',
    'location',
    'home',
    'games',
    'heart',
    'book',
    'users',
    'note',
    'trophy',
    'board',
    'clock',
    'wallet',
    'flag',
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ledgerToast(context, '给分类起个名字');
      return;
    }
    Navigator.of(context).pop<_CategoryResult>((
      name: name,
      kind: _kind,
      color: _color,
      icon: _icon,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      maxWidth: 400,
      padding: const EdgeInsets.fromLTRB(22, 36, 22, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? '新增分类' : '编辑分类',
            style: context.lheading(size: CitroType.subtitle, color: c.ink),
          ),
          const SizedBox(height: 12),
          CitroField(
            label: '名称',
            hint: '例如：宠物、旅行、副业',
            controller: _name,
            maxLength: 8,
          ),
          const SizedBox(height: 10),
          if (widget.existing == null) ...[
            LedgerKindToggle(
              value: _kind,
              onChanged: (value) => setState(() => _kind = value),
              compact: true,
            ),
            const SizedBox(height: 12),
          ],
          Text(
            '颜色',
            style: context.lui(
              size: CitroType.caption,
              weight: CitroType.strong,
              color: c.inkSoft,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _palette)
                GestureDetector(
                  onTap: () => setState(() => _color = color),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == color ? c.ink : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: _color == color
                        ? const Center(
                            child: Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '图标',
            style: context.lui(
              size: CitroType.caption,
              weight: CitroType.strong,
              color: c.inkSoft,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final icon in _icons)
                Pressable(
                  onTap: () => setState(() => _icon = icon),
                  scale: .9,
                  hoverLift: 0,
                  child: LedgerIconTile(
                    iconKey: icon,
                    tint: Color(_color),
                    size: 40,
                    active: _icon == icon,
                    filled: true,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          AccentButton(text: '保存', onTap: _save),
        ],
      ),
    );
  }
}
