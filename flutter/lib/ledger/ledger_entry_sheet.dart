import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'ledger_date_picker.dart';
import 'ledger_models.dart';
import 'ledger_store.dart';
import 'ledger_theme.dart';
import 'ledger_widgets.dart';

/// 已入账账单的编辑 / 删除弹层。首页最近账单点进来即可改。
Future<void> showLedgerEntrySheet(
  BuildContext context, {
  required LedgerEntry entry,
}) {
  return showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => LedgerScope(child: _LedgerEntrySheet(entry: entry)),
  );
}

class _LedgerEntrySheet extends StatefulWidget {
  final LedgerEntry entry;

  const _LedgerEntrySheet({required this.entry});

  @override
  State<_LedgerEntrySheet> createState() => _LedgerEntrySheetState();
}

class _LedgerEntrySheetState extends State<_LedgerEntrySheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.entry.amountCents % 100 == 0
        ? '${widget.entry.amountCents ~/ 100}'
        : (widget.entry.amountCents / 100).toStringAsFixed(2),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.entry.note,
  );
  late LedgerKind _kind = widget.entry.kind;
  late String _categoryId = widget.entry.categoryId;
  late DateTime _at = widget.entry.occurredAt;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final cents = ledgerParseAmount(_amount.text) ?? 0;
    if (cents <= 0) {
      ledgerToast(context, '金额需要大于 0');
      return;
    }
    LedgerStore.instance.updateEntry(
      widget.entry.copyWith(
        kind: _kind,
        amountCents: cents,
        categoryId: _categoryId,
        note: _note.text.trim(),
        occurredAt: _at,
      ),
    );
    Navigator.of(context).pop();
    ledgerToast(context, '账单已更新');
  }

  Future<void> _delete() async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        maxWidth: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '删除这笔账单？',
              style: ctx.lheading(size: CitroType.subtitle, color: ctx.c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.entry.kind.label} ${ledgerMoney(widget.entry.amountCents)}'
              '，删除后本月统计会立即变化。',
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
    LedgerStore.instance.removeEntry(widget.entry.id);
    Navigator.of(context).pop();
    ledgerToast(context, '已删除这笔账单');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    child: Text(
                      '编辑账单',
                      style: context.lheading(
                        size: CitroType.subtitle,
                        color: c.ink,
                      ),
                    ),
                  ),
                  Pressable(
                    onTap: _delete,
                    scale: .94,
                    hoverLift: 0,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: c.stamp.withAlpha(24),
                        shape: BoxShape.circle,
                        border: Border.all(color: c.stamp.withAlpha(80)),
                      ),
                      child: Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.trash, width: 1.9),
                          size: 16,
                          color: c.stamp,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LedgerKindToggle(
                value: _kind,
                onChanged: (value) {
                  final list = LedgerStore.instance.categoriesFor(value);
                  setState(() {
                    _kind = value;
                    if (list.isNotEmpty) _categoryId = list.first.id;
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: context.ldisplay(
                        size: 34,
                        weight: FontWeight.w700,
                        color: c.ink,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        prefixText: '¥ ',
                        prefixStyle: context.ldisplay(
                          size: 20,
                          weight: FontWeight.w700,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ),
                  Pressable(
                    onTap: () async {
                      final picked = await showLedgerDateTimePicker(
                        context,
                        initial: _at,
                      );
                      if (picked == null) return;
                      setState(() => _at = picked);
                    },
                    scale: .96,
                    hoverLift: 0,
                    child: LedgerChip(
                      text:
                          '${_at.month}月${_at.day}日 ${LedgerDates.timeLabel(_at)}',
                      icon: AppIcons.clock,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LedgerCategoryPicker(
                categories: LedgerStore.instance.categoriesFor(_kind),
                selectedId: _categoryId,
                onSelected: (category) =>
                    setState(() => _categoryId = category.id),
                compact: true,
              ),
              const SizedBox(height: 12),
              CitroField(
                label: '备注',
                hint: '写点什么，之后更好找',
                controller: _note,
                maxLength: 40,
              ),
              const SizedBox(height: 16),
              AccentButton(text: '保存修改', onTap: _save),
            ],
          ),
        ),
      ),
    );
  }
}
